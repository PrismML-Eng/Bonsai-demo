# LM Studio

LM Studio can run Bonsai 2 27B's `PQ2_0` and `PTQ1_0` bands through a small generator plugin that
fronts this demo's `llama-server`. The mainline `Q2_0` band no longer needs this: the Hadamard
changes it depends on have merged into upstream llama.cpp and mlx-vlm, so once LM Studio ships a
runtime/model-loader built against that upstream code, `Q2_0` loads directly - check LM Studio's
release notes before reaching for the plugin. This doc, and the plugin, exist for `PQ2_0` and
`PTQ1_0`, which stay fork-only: no upstream project has the Hadamard activation transform they need,
so they always need this demo's binaries (`AGENTS.md`, "Do not run Bonsai 2 on stock llama.cpp").

Pointing LM Studio straight at a `PQ2_0`/`PTQ1_0` GGUF fails at load, the safe failure mode:

```
E gguf_init_from_reader: failed to read tensor info
E llama_model_load: error loading model: llama_model_loader: failed to load model from ...Ternary-Bonsai-2-27B-PQ2_0.gguf
```

**The dev-only `Q2_0` band is different and more dangerous.** It is not in the model repo (it lives
at
[Ternary-Bonsai-2-27B-gguf-dev](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf-dev),
published for testing), because mainline llama.cpp - and LM Studio's engine, before it picks up the
upstream Hadamard changes - **loads that file without a warning and produces gibberish**: `Q2_0` is
a tensor type upstream already knows and `qwen35` is a supported architecture, so nothing in the
file makes an older engine refuse it. If a load silently succeeds instead of failing like the error
above, check which band and which engine version produced it before trusting the output.

Swapping the libraries inside LM Studio's engine folder does not rescue `PQ2_0`/`PTQ1_0` either, and
is worth ruling out before anyone spends an evening on it: their engine modules and this demo's
binaries export different symbol sets (`llama_model_dflash_selector_top_k`, `mtmd_get_memory_usage`,
`mtmd_helper_init_opt_default`, `ggml_prec_set_acc` on one side, `ggml_dsv4_hc_pre_gated`,
`llama_adapter_lora_init_from_file_ptr` on the other), so the engine refuses the replacement.

The route that works for `PQ2_0`/`PTQ1_0` is the one this demo is already built for: `llama-server`
speaks the OpenAI-compatible API, and LM Studio's **generator plugins** can front any such endpoint.
A small generator plugin ships in `scripts/lmstudio-plugin/`: it forwards the conversation to the
server the start scripts already run, and streams the answer back, thinking included.

```
LM Studio chat -> generator plugin -> llama-server (this demo, :8080) -> Bonsai 2 27B (PQ2_0/PTQ1_0)
```

## Setup

1. Start the demo server. It does the inference; LM Studio is only the front end.

   ```bash
   ./scripts/start_llama_server.sh          # Windows: .\scripts\start_llama_server.ps1
   ```

   Leave it running. The plugin talks to `http://127.0.0.1:8080`, which is the port those scripts use.

2. Install the plugin once:

   ```bash
   cd scripts/lmstudio-plugin
   npm install
   lms dev -i -y
   ```

   `lms` ships with LM Studio. `npm install` is the only Node step. In LM Studio, developer plugins
   have to be allowed: **Settings -> Developer -> Allow development plugins**.

3. In LM Studio, pick `prism-ml/bonsai-2-27b` in the chat's model selector, under **Your
   Generators**. Nothing needs to be loaded from the Server tab - see the next section for why.

## What works

| | |
|---|---|
| Text, streaming | Yes. |
| Thinking | Yes. The plugin maps the server's `reasoning_content` into LM Studio's collapsible reasoning block, so you get "Thought for N s" and the answer underneath. |
| Tool calling | Yes, native `tool_calls` round-trips, same as the API. |
| Vision | Images attached from disk, forwarded as `image_url` data URIs. Images *pasted* into the chat are stored by LM Studio in its own base64 store, which plugins cannot read (`FileHandle.getFilePath()` throws for them), so the plugin tells the model an image was omitted instead. The server's default image-token cap still applies on Metal/Vulkan/CPU: large images are downscaled to ~1024 vision tokens (fast, but loses fine detail/small text); start the server with `BONSAI_IMAGE_MAX_TOKENS=0` for full detail at the cost of slower per-image prefill. CUDA/ROCm are uncapped by default. |
| Sampling and context | Whatever the server was started with. The plugin deliberately sends no sampling or budget overrides, so the demo's tested flags stay in charge. |

Thinking is the one knob worth reaching for: LM Studio's own reasoning controls do not apply to a
generator, so cap it on the server instead, where the flag is already supported:

```bash
./scripts/start_llama_server.sh --reasoning-budget 2048
```

The built-in web UI's reasoning-effort picker is unaffected and still works alongside LM Studio.

## What does not work: the Server tab and the REST API

The model shows up in the chat picker but not in LM Studio's **Server tab**, `GET /v1/models`, or
`/v1/chat/completions`. LM Studio only serves models that exist as files on disk; a generator plugin
is not one of those, and there is no way to force-load it:

```bash
curl -s http://127.0.0.1:11434/api/v1/models/load -H "Content-Type: application/json" \
  -d '{"model":"prism-ml/bonsai-2-27b"}'
# {"error":{"type":"model_not_found","message":"Model prism-ml/bonsai-2-27b not found in downloaded models"}}
```

That is upstream behaviour in LM Studio, tracked at
[lmstudio-bug-tracker#2009](https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/2009). Nothing
is misconfigured here, and nothing to work around on this side: if you need HTTP, ask the demo's own
server, which is already an OpenAI-compatible endpoint on :8080.

```bash
curl http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"bonsai-2-27b","messages":[{"role":"user","content":"Hello"}]}'
```

## Tested

- LM Studio 0.4.24+1 with its CUDA 12 llama.cpp runtime pack (v2.41.0), Windows 11, RTX 4090 24 GB,
  `BONSAI_FAMILY=bonsai2`, `BONSAI_MODEL=27B`, `PQ2_0` weights.
- 79.5 tok/s decode at ~14 GB VRAM on a text turn (the whitepaper reports 81.2 tok/s for this
  packing on a 4090), thinking block rendered, and a test image read correctly through the plugin.
- The chat UI path was verified end to end. The shell commands above are the ones run locally; the
  model name the plugin registers is `owner/name` from its `manifest.json`, so rename it there if
  you want a different namespace.

Both sides are young APIs: LM Studio marks generators `@experimental`, so a future LM Studio release
may need a change here. The plugin itself is ~200 lines with a single dependency (`@lmstudio/sdk`)
and talks to `BONSAI_BASE_URL`, loopback (`127.0.0.1`) by default - set that env var only if you
need to point it at a server on another host - so it is quick to audit and to fix.
