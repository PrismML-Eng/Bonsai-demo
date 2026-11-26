/**
 * LM Studio generator plugin for Bonsai 2 27B's fork-only PQ2_0 / PTQ1_0 bands
 * (prism-ml/Ternary-Bonsai-2-27B-gguf).
 *
 * LM Studio's bundled llama.cpp engines cannot load PQ2_0 or PTQ1_0 GGUFs: those
 * tensor types and the Hadamard activation transform they need only exist in this
 * demo's llama.cpp fork (see `AGENTS.md`, "Do not run Bonsai 2 on stock llama.cpp",
 * and LMSTUDIO.md for the mainline `Q2_0` band, which upstream can now load
 * natively). So for PQ2_0/PTQ1_0 the model runs on this demo's llama-server
 * (scripts/start_llama_server.sh - see LMSTUDIO.md) and this generator makes that
 * server look like a model to LM Studio. Text, thinking and tool calls stream
 * straight through.
 *
 * It registers as "prism-ml/bonsai-2-27b" (owner and name come from manifest.json)
 * and shows up in LM Studio's chat model picker. It is chat-only: LM Studio does
 * not serve generator models from its Server tab or its REST API.
 *
 * Env overrides:
 *   BONSAI_BASE_URL  llama-server endpoint. Default http://127.0.0.1:8080/v1
 *                    (loopback-only by default); set this only to point at a
 *                    server on another host, which this plugin will then reach
 *                    over the network.
 *   BONSAI_MODEL_ID  model name sent to llama-server (it routes by server, not by
 *                    name, so any value works; this plugin's default matches the
 *                    value the request body carries)
 */

import { readFileSync } from "node:fs";

const BASE_URL = process.env.BONSAI_BASE_URL || "http://127.0.0.1:8080/v1";
const MODEL_ID = process.env.BONSAI_MODEL_ID || "bonsai-2-27b";

const MIME_BY_EXTENSION = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  webp: "image/webp",
  gif: "image/gif",
  bmp: "image/bmp",
};

/** Plugin entry point: LM Studio calls this once, we register a generator. */
export async function main(context) {
  context.withGenerator(generate);
}

/* -------------------------------------------------------------------------- */
/*                         LM Studio chat -> OpenAI                           */
/* -------------------------------------------------------------------------- */

/**
 * An attached image as an OpenAI image part. LM Studio hands plugins a file
 * handle with an absolute path for files picked from disk; images pasted into
 * the chat are stored in LM Studio's own base64 store and have no path, which
 * this plugin cannot read (getFilePath throws for those).
 */
async function toImagePart(file) {
  const extension = String(file.name).split(".").pop().toLowerCase();
  const mime = MIME_BY_EXTENSION[extension];
  if (mime === undefined) {
    throw new Error(`unsupported image extension ".${extension}"`);
  }
  const path = await file.getFilePath();
  const base64 = readFileSync(path).toString("base64");
  return { type: "image_url", image_url: { url: `data:${mime};base64,${base64}` } };
}

async function toOpenAIMessages(history, ctl) {
  const messages = [];

  for (const message of history) {
    const role = message.getRole();

    if (role === "system" || role === "user") {
      const parts = [];
      const text = message.getText();
      if (text !== "") {
        parts.push({ type: "text", text });
      }
      for (const file of message.getFiles(ctl.client)) {
        if (!file.isImage()) {
          continue;
        }
        try {
          const part = await toImagePart(file);
          if (part !== null) {
            parts.push(part);
          }
        } catch (error) {
          parts.push({
            type: "text",
            text: `[image "${file.name}" was not sent: ${error?.message ?? error}]`,
          });
        }
      }
      const content = parts.length === 1 && parts[0].type === "text" ? parts[0].text : parts;
      messages.push({ role, content });
      continue;
    }

    if (role === "assistant") {
      const toolCalls = message.getToolCallRequests().map(toolCall => ({
        id: toolCall.id ?? "",
        type: "function",
        function: {
          name: toolCall.name,
          arguments: JSON.stringify(toolCall.arguments ?? {}),
        },
      }));
      messages.push({
        role: "assistant",
        content: message.getText(),
        ...(toolCalls.length > 0 ? { tool_calls: toolCalls } : {}),
      });
      continue;
    }

    if (role === "tool") {
      for (const result of message.getToolCallResults()) {
        messages.push({
          role: "tool",
          tool_call_id: result.toolCallId ?? "",
          content: result.content,
        });
      }
    }
  }

  return messages;
}

/* -------------------------------------------------------------------------- */
/*                              Stream handling                               */
/* -------------------------------------------------------------------------- */

function closeReasoning(ctl, state) {
  if (state.inReasoning) {
    ctl.fragmentGenerated("", { reasoningType: "reasoningEndTag" });
    state.inReasoning = false;
  }
}

function handleDelta(ctl, state, chunk) {
  const choice = chunk.choices?.[0];
  if (choice === undefined) {
    return;
  }
  const delta = choice.delta ?? {};

  // llama-server with --jinja separates a <think> block into reasoning_content.
  if (typeof delta.reasoning_content === "string" && delta.reasoning_content !== "") {
    if (!state.inReasoning) {
      ctl.fragmentGenerated("", { reasoningType: "reasoningStartTag" });
      state.inReasoning = true;
    }
    ctl.fragmentGenerated(delta.reasoning_content, { reasoningType: "reasoning" });
  }

  if (typeof delta.content === "string" && delta.content !== "") {
    closeReasoning(ctl, state);
    ctl.fragmentGenerated(delta.content);
  }

  // OpenAI streams tool calls as deltas keyed by `index`; a single chunk can
  // carry fragments for several calls at once, and fragments for different
  // calls can interleave across chunks. Accumulate per index and only emit
  // them to LM Studio (in index order) once the stream is done, so an
  // in-progress call never gets another call's name/arguments attached.
  if ((delta.tool_calls ?? []).length > 0) {
    closeReasoning(ctl, state);
  }
  for (const toolCall of delta.tool_calls ?? []) {
    const index = toolCall.index ?? 0;
    let entry = state.toolCalls.get(index);
    if (entry === undefined) {
      entry = { id: null, name: null, arguments: "" };
      state.toolCalls.set(index, entry);
      state.toolCallOrder.push(index);
    }
    if (typeof toolCall.id === "string" && toolCall.id !== "") {
      entry.id = toolCall.id;
    }
    if (typeof toolCall.function?.name === "string" && toolCall.function.name !== "") {
      entry.name = (entry.name ?? "") + toolCall.function.name;
    }
    if (typeof toolCall.function?.arguments === "string" && toolCall.function.arguments !== "") {
      entry.arguments += toolCall.function.arguments;
    }
  }
}

/** Emit every accumulated tool call to LM Studio, in the order it first appeared. */
function flushToolCalls(ctl, state) {
  for (const index of state.toolCallOrder) {
    const toolCall = state.toolCalls.get(index);
    if (toolCall === undefined) {
      continue;
    }
    ctl.toolCallGenerationStarted();
    if (toolCall.name === null) {
      ctl.toolCallGenerationFailed(new Error("llama-server streamed a tool call without a name."));
      continue;
    }
    ctl.toolCallGenerationNameReceived(toolCall.name);
    let args;
    try {
      args = JSON.parse(toolCall.arguments === "" ? "{}" : toolCall.arguments);
    } catch {
      ctl.toolCallGenerationFailed(new Error(`Malformed tool arguments: ${toolCall.arguments}`));
      continue;
    }
    if (toolCall.arguments !== "") {
      ctl.toolCallGenerationArgumentFragmentGenerated(toolCall.arguments);
    }
    ctl.toolCallGenerationEnded({
      type: "function",
      name: toolCall.name,
      arguments: args,
      id: toolCall.id ?? "",
    });
  }
  state.toolCalls.clear();
  state.toolCallOrder = [];
}

async function consumeStream(ctl, response, signal) {
  const state = { inReasoning: false, toolCalls: new Map(), toolCallOrder: [] };
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let completed = false;

  try {
    for (;;) {
      let read;
      try {
        read = await reader.read();
      } catch (error) {
        if (signal.aborted) {
          // Expected: cancelling mid-read rejects the pending read() per the
          // fetch spec. Not a real failure, so don't let it surface as one.
          break;
        }
        throw error;
      }
      const { done, value } = read;
      if (done) {
        completed = true;
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      let newline;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line.startsWith("data:")) {
          continue;
        }
        const payload = line.slice(5).trim();
        if (payload === "[DONE]") {
          buffer = "";
          completed = true;
          break;
        }
        let chunk;
        try {
          chunk = JSON.parse(payload);
        } catch {
          continue;
        }
        handleDelta(ctl, state, chunk);
      }
      if (completed) {
        break;
      }
    }
  } finally {
    if (signal.aborted) {
      // The user cancelled generation: discard whatever tool call(s) were
      // still buffered instead of finalizing them, so nothing partially
      // captured can be reported as a completed call.
      await reader.cancel().catch(() => {});
    } else if (completed) {
      closeReasoning(ctl, state);
      flushToolCalls(ctl, state);
    }
  }
}

/* -------------------------------------------------------------------------- */
/*                                  Generator                                 */
/* -------------------------------------------------------------------------- */

export async function generate(ctl, history) {
  const messages = await toOpenAIMessages(history, ctl);
  const toolDefinitions = ctl.getToolDefinitions().map(tool => ({
    type: "function",
    function: {
      name: tool.function.name,
      description: tool.function.description,
      parameters: tool.function.parameters ?? {},
    },
  }));
  const tools = toolDefinitions.length > 0 ? toolDefinitions : undefined;
  const controller = new AbortController();
  ctl.onAborted(() => controller.abort());

  let response;
  try {
    response = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODEL_ID,
        messages,
        stream: true,
        ...(tools === undefined ? {} : { tools }),
      }),
      signal: controller.signal,
    });
  } catch (error) {
    if (controller.signal.aborted) {
      // The user cancelled generation before the server sent a response;
      // this is not a connectivity problem, so don't report it as one.
      return;
    }
    throw new Error(
      `Cannot reach the Bonsai llama-server at ${BASE_URL} (${error?.message ?? error}). ` +
        `Start it with scripts/start_llama_server.sh (Windows: scripts\\start_llama_server.ps1).`,
    );
  }

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`llama-server returned HTTP ${response.status}: ${body.slice(0, 500)}`);
  }

  await consumeStream(ctl, response, controller.signal);
}
