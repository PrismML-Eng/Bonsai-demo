/**
 * Regression tests for the stream adapter in ../src/index.ts, covering the
 * correctness issues raised in PR #172's review:
 *   - multiple concurrent streamed tool calls must not have their
 *     name/arguments fragments mixed together
 *   - a reasoning block must close before a tool call starts
 *   - cancelling generation must not finalize a buffered tool call
 *   - a response that ends abruptly (dropped connection, no [DONE] and no
 *     cancellation) must not finalize a buffered tool call either
 *
 * Run with: npm test (node --experimental-strip-types --test test/)
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import { generate } from "../src/index.ts";

function mockCtl(log) {
  return {
    client: {},
    onAborted(fn) {
      this._abort = fn;
    },
    fragmentGenerated: (...a) => log.push(["fragmentGenerated", ...a]),
    toolCallGenerationStarted: () => log.push(["started"]),
    toolCallGenerationNameReceived: (n) => log.push(["name", n]),
    toolCallGenerationArgumentFragmentGenerated: (f) => log.push(["argFrag", f]),
    toolCallGenerationEnded: (c) => log.push(["ended", c]),
    toolCallGenerationFailed: (e) => log.push(["failed", e.message]),
    getToolDefinitions: () => [],
  };
}

function sseResponse(events) {
  const body = events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join("") + "data: [DONE]\n\n";
  return {
    ok: true,
    status: 200,
    body: new Response(body).body,
    text: async () => "",
  };
}

test("multiple concurrent streamed tool calls do not get their arguments mixed", async () => {
  globalThis.fetch = async () =>
    sseResponse([
      { choices: [{ delta: { tool_calls: [{ index: 0, id: "call_a", function: { name: "foo", arguments: "" } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 1, id: "call_b", function: { name: "bar", arguments: "" } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: '{"x":' } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 1, function: { arguments: '{"y":2}' } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: "1}" } }] } }] },
      { choices: [{ delta: {}, finish_reason: "tool_calls" }] },
    ]);

  const log = [];
  await generate(mockCtl(log), []);

  const ended = log.filter((e) => e[0] === "ended").map((e) => e[1]);
  assert.equal(ended.length, 2);
  assert.equal(ended[0].name, "foo");
  assert.deepEqual(ended[0].arguments, { x: 1 });
  assert.equal(ended[1].name, "bar");
  assert.deepEqual(ended[1].arguments, { y: 2 });
});

test("reasoning closes before a tool call starts when there is no content in between", async () => {
  globalThis.fetch = async () =>
    sseResponse([
      { choices: [{ delta: { reasoning_content: "thinking..." } }] },
      { choices: [{ delta: { tool_calls: [{ index: 0, id: "call_c", function: { name: "baz", arguments: "{}" } }] } }] },
      { choices: [{ delta: {}, finish_reason: "tool_calls" }] },
    ]);

  const log = [];
  await generate(mockCtl(log), []);

  const reasoningEndIdx = log.findIndex(
    (e) => e[0] === "fragmentGenerated" && e[2]?.reasoningType === "reasoningEndTag",
  );
  const startedIdx = log.findIndex((e) => e[0] === "started");
  assert.notEqual(reasoningEndIdx, -1);
  assert.notEqual(startedIdx, -1);
  assert.ok(reasoningEndIdx < startedIdx, "reasoning must close before the tool call starts");
});

test("cancelling generation mid tool-call does not finalize it", async () => {
  const firstChunkRead = Promise.withResolvers();
  let pendingRead = null;

  globalThis.fetch = async (url, opts) => {
    let aborted = false;
    let delivered = false;
    opts.signal.addEventListener("abort", () => {
      aborted = true;
      if (pendingRead !== null) {
        pendingRead.reject(new DOMException("aborted", "AbortError"));
        pendingRead = null;
      }
    });
    const reader = {
      read: async () => {
        if (aborted) {
          throw new DOMException("aborted", "AbortError");
        }
        if (!delivered) {
          delivered = true;
          const chunk = {
            done: false,
            value: new TextEncoder().encode(
              `data: ${JSON.stringify({
                choices: [
                  { delta: { tool_calls: [{ index: 0, id: "call_d", function: { name: "danger", arguments: '{"exec":true}' } }] } },
                ],
              })}\n\n`,
            ),
          };
          firstChunkRead.resolve();
          return chunk;
        }
        // The connection stays open ("thinking") until cancelled; resolved
        // only by the abort listener above, never by a wall-clock timer.
        const resolver = Promise.withResolvers();
        pendingRead = resolver;
        return await resolver.promise;
      },
      cancel: async () => {},
    };
    return { ok: true, status: 200, body: { getReader: () => reader }, text: async () => "" };
  };

  const log = [];
  const ctl = mockCtl(log);
  const genPromise = generate(ctl, []);
  await firstChunkRead.promise;
  ctl._abort();
  await genPromise;

  assert.ok(!log.some((e) => e[0] === "ended"), "a cancelled tool call must not be finalized");
});

test("a response that ends abruptly (no [DONE], no cancellation) does not finalize a buffered tool call", async () => {
  globalThis.fetch = async () => {
    let delivered = false;
    const reader = {
      read: async () => {
        if (!delivered) {
          delivered = true;
          return {
            done: false,
            value: new TextEncoder().encode(
              `data: ${JSON.stringify({
                choices: [
                  { delta: { tool_calls: [{ index: 0, id: "call_e", function: { name: "danger", arguments: '{"exec":true}' } }] } },
                ],
              })}\n\n`,
            ),
          };
        }
        // Connection drops: the reader rejects with a plain network error,
        // not an AbortError, and generation was never cancelled.
        throw new Error("socket hang up");
      },
      cancel: async () => {},
    };
    return { ok: true, status: 200, body: { getReader: () => reader }, text: async () => "" };
  };

  const log = [];
  await assert.rejects(() => generate(mockCtl(log), []), /socket hang up/);
  assert.ok(!log.some((e) => e[0] === "ended"), "an interrupted response must not finalize a buffered tool call");
});
