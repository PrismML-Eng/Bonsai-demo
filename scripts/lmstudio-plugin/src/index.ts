/**
 * LM Studio generator plugin for Bonsai 2 27B (prism-ml/Ternary-Bonsai-2-27B-gguf).
 *
 * LM Studio's bundled llama.cpp is mainline and cannot load any Bonsai 2 band:
 * PQ2_0 / PTQ1_0 are fork-only tensor types and the weights need the fork's
 * Hadamard activation transform. So the model runs on this demo's llama-server
 * (scripts/start_llama_server.sh - see LMSTUDIO.md) and this generator makes that
 * server look like a model to LM Studio. Text, thinking and tool calls stream
 * straight through.
 *
 * It registers as "prism-ml/bonsai-2-27b" (owner and name come from manifest.json)
 * and shows up in LM Studio's chat model picker. It is chat-only: LM Studio does
 * not serve generator models from its Server tab or its REST API.
 *
 * Env overrides:
 *   BONSAI_BASE_URL  default http://127.0.0.1:8080/v1
 *   BONSAI_MODEL_ID  model name sent to llama-server (it routes by server, not by
 *                    name, so any value works; the alias set by the launcher is
 *                    bonsai-2-27b)
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
    return null;
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
    if (state.inReasoning) {
      ctl.fragmentGenerated("", { reasoningType: "reasoningEndTag" });
      state.inReasoning = false;
    }
    ctl.fragmentGenerated(delta.content);
  }

  for (const toolCall of delta.tool_calls ?? []) {
    if (toolCall.id !== undefined && toolCall.id !== null) {
      flushToolCall(ctl, state);
      state.toolCall = { id: toolCall.id, name: null, arguments: "" };
      ctl.toolCallGenerationStarted();
    }
    if (state.toolCall === null) {
      continue;
    }
    if (typeof toolCall.function?.name === "string" && toolCall.function.name !== "") {
      state.toolCall.name = toolCall.function.name;
      ctl.toolCallGenerationNameReceived(toolCall.function.name);
    }
    if (typeof toolCall.function?.arguments === "string" && toolCall.function.arguments !== "") {
      state.toolCall.arguments += toolCall.function.arguments;
      ctl.toolCallGenerationArgumentFragmentGenerated(toolCall.function.arguments);
    }
  }

  if (choice.finish_reason === "tool_calls") {
    flushToolCall(ctl, state);
  }
}

function flushToolCall(ctl, state) {
  const toolCall = state.toolCall;
  if (toolCall === null) {
    return;
  }
  state.toolCall = null;
  if (toolCall.name === null) {
    ctl.toolCallGenerationFailed(new Error("llama-server streamed a tool call without a name."));
    return;
  }
  let args;
  try {
    args = JSON.parse(toolCall.arguments === "" ? "{}" : toolCall.arguments);
  } catch {
    ctl.toolCallGenerationFailed(new Error(`Malformed tool arguments: ${toolCall.arguments}`));
    return;
  }
  ctl.toolCallGenerationEnded({
    type: "function",
    name: toolCall.name,
    arguments: args,
    id: toolCall.id,
  });
}

async function consumeStream(ctl, response, signal) {
  const state = { inReasoning: false, toolCall: null };
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) {
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
    }
  } finally {
    if (state.inReasoning) {
      ctl.fragmentGenerated("", { reasoningType: "reasoningEndTag" });
    }
    flushToolCall(ctl, state);
    if (signal.aborted) {
      await reader.cancel().catch(() => {});
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
    throw new Error(
      `Cannot reach the Bonsai llama-server at ${BASE_URL} (${error?.message ?? error}). ` +
        `Start it with serve-bonsai.ps1.`,
    );
  }

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`llama-server returned HTTP ${response.status}: ${body.slice(0, 500)}`);
  }

  await consumeStream(ctl, response, controller.signal);
}
