# Agent guide — tuning the Bonsai demo

For AI agents (and humans) helping someone set up this demo. Goal: pick the right
flags for the user's hardware and use case. The behavior notes below come from real
testing; measure on the user's own hardware before promising performance (the
`timings` object in every API response has the numbers).

## Why the 27B models (what to show off)

The 27B generation is a step change over the earlier 8B/4B/1.7B demos:

- **Vision** — image input end to end (photos, screenshots) via the mmproj on llama-server.
- **Agentic / tool calling** — much stronger at tool use; both llama-server (`--jinja`)
  and `mlx_lm.server` emit native OpenAI `tool_calls`, verified with full tool round-trips.
- **Thinking** — a reasoning model; thought is streamed separately (`reasoning_content`)
  and can be budgeted (`--reasoning-budget N`) or picked per chat in the web UI.
- **Long context** — 256k+ tokens per conversation on a 48 GB Mac (hybrid GDN keeps KV cheap).
- **Tiny footprint** — the binary 27B packs to ~1.125 bits per weight: it fits
  on a modern iPhone without memory offloading. The ternary build (~1.7 bpw, packed into
  2-bit for faster acceleration) is the higher-quality option and the default.

## The models

| `BONSAI_FAMILY` / `BONSAI_MODEL` | Weights | Notes |
|---|---|---|
| `ternary` / `27B` (default) | GGUF Q2_0 ~6.7 GB + mmproj 0.9 GB; MLX 2-bit ~7.9 GB | Higher quality |
| `bonsai` / `27B` | GGUF Q1_0 ~3.5 GB + mmproj 0.9 GB; MLX 1-bit ~4.8 GB | Smallest and fastest; fits on a modern iPhone without offloading |
| `8B` / `4B` / `1.7B` (both families) | smaller | Text-only, no tools wiring, legacy tested flag set |

Both 27B families have identical capabilities (vision, tools, thinking, long context) —
they differ in size and speed. Context: 262,144 tokens max; FP16 KV cache is
64 KiB/token (~6.3 GiB at 100K), so 100K context fits on many consumer devices —
full peak-memory table in the README's Context Size section. All 27B repos:
https://huggingface.co/collections/prism-ml/bonsai-27b. While the 27B repos are
private, downloads need `BONSAI_TOKEN` (read-only HF token).

## Knobs that matter (27B)

All extra args pass straight through the start scripts, e.g.
`./scripts/start_llama_server.sh --image-max-tokens 1024 -ub 1024`.

| Knob | What it does | Trade-off |
|---|---|---|
| `BONSAI_SPECULATIVE=1` (env, `start_llama_server.sh` only) | **Experimental.** Loads the paired `dspark` drafter for speculative decoding (`--spec-type draft-dspark`), ~1.8-2x decode on code/reasoning. Off by default. | The drafter path is stable and fast on CUDA; Apple Silicon (Metal) support will be improved in a later release, so do not recommend it on Macs yet. Disables cross-request prompt-cache reuse (every turn re-prefills) and forces single-slot (`-np 1`); worse for multi-turn and the agentic Open WebUI path, which is why it is server-only and opt-in. The prebuilt binaries include both the dspark-capable `llama-server` and the CLI one-shot `llama-speculative-simple`. Details: SPECULATIVE.md. |
| `BONSAI_KV4=1` (env, `start_llama_server.sh` only) | **Experimental.** Q4_0 (4-bit) KV cache, ~3.5x smaller KV memory. Optional quality booster: `./scripts/make_kv_bias.sh` builds a model-specific mean-centering bias (tiny calibration corpus is enough; users can pass their own text) that the server picks up automatically. | Memory tool, not a speed tool: decode is slightly slower than F16 KV. The 27B's hybrid attention already keeps KV small, so only reach for this at very long contexts on tight machines. The bias is calibrated with K-rotation off and the script/server handle the matching flags automatically; llama.cpp backend only. Details: KV-CACHE.md. |
| `--reasoning-budget N` | Caps thinking at N tokens (default -1 = unlimited) | Middle ground; pair with `--reasoning-budget-message` |
| `--image-max-tokens N` | Downscales images to ~N vision tokens (1 token ~ 32x32 px). Model allows ~4096 (=4.2 MP) | The scripts default this to **1024 on Metal / Vulkan / CPU** and leave CUDA/ROCm uncapped; override with `BONSAI_IMAGE_MAX_TOKENS` (0 = uncapped). Loses fine detail (small text / OCR) on large images; images under the cap are unaffected |
| `BONSAI_NGL=N` (env) | Overrides GPU layer offload (auto-detect defaults to all layers when CUDA/ROCm/Vulkan/Metal tooling is present; 0 = CPU-only) | The auto-detect keys on installed tooling, not GPU capability: a CPU box with only an integrated GPU and Vulkan drivers will offload to that iGPU. Capable iGPUs (e.g. Strix Halo) genuinely benefit, weak ones are better on CPU; recommend `BONSAI_NGL=0` when decode is slower than expected on iGPU-only machines |
| `-ub N` | Prefill microbatch (default 512) | Sometimes faster prefill on Metal at 1024; measure |
| `BONSAI_CTX=N` (env) | Overrides the default context. The scripts default to a RAM-tiered size (8192 up to 131072 by machine memory) for predictable memory use; `0` (or unset) resolves to that same tiered size — it is *not* passed to llama.cpp as `-c 0` (which would use the model's full 262k training context and OOM constrained machines). Pass an explicit number to force full context | Bigger context = more KV memory at 64 KiB/token FP16; pair huge contexts with `BONSAI_KV4=1` |
| `--parallel N` | Server slots (default 4) | More slots = more concurrent users, same total context pool |
| `BRAVE_API_KEY` (env, Open WebUI) | Makes a Brave Search MCP server available next to the preconfigured Hugging Face + DeepWiki ones | Needs `npm i -g @brave/brave-search-mcp-server`; skipped otherwise. Limited to web/news/summarizer (~2.9k tokens); its full tool set is ~29k (brave_place_search alone ~20k). Override with BONSAI_BRAVE_TOOLS. |
| `BONSAI_CODE_INTERPRETER=0` (env, Open WebUI) | Disables the server-side Jupyter code interpreter (plots via matplotlib, data via pandas/numpy, market data via yfinance). On by default. | Off falls back to browser Pyodide: plots still work, but no yfinance/network. The Jupyter stack (`.venv-jupyter`) is built by setup.sh. |

Thinking is extracted into `reasoning_content` by default (collapsible in UIs).

## Built-in web UI (llama-server) — what it can do without any setup

Everything below is per-conversation, in Settings, no server restart:

- **Thinking on demand**: the message box has a **Reasoning effort** picker
  (lightbulb icon) - Off / Low (512) / Medium (2048) / High (8192) / Max (unlimited),
  per-conversation, overrides the server default. Under the hood these are reasoning
  budgets; the API also accepts `thinking_budget_tokens` per request
  (`0` = off, `N` = cap, `-1` = unlimited).
- **MCP tools with an agentic loop**: pre-configured for the 27B — the start scripts
  pass `--webui-config-file scripts/webui-config.json`, which seeds Hugging Face Hub
  and DeepWiki as admin defaults (verified served via `/props.webui_settings`).
  Config `enabled:true` only makes them **available in the message-box MCP selector**;
  tool schemas are sent only for chats that turn a server on. The new-chat screen's
  toggle becomes the user's default for future chats (stored in the browser) — that
  is the knob that trades the prompt tokens below for always-on tools. On a fast GPU
  always-on is cheap (one-time cost per server run). Add more servers in
  Settings -> MCP Client or in the JSON (add `"useProxy": true` if one rejects
  browser CORS — llama-server ships a `/cors-proxy`). `agenticMaxTurns` (default 10)
  bounds the tool loop.

  **MCP prompt cost** — every enabled server's tool schemas are rendered into the
  system prompt of each chat, so they add prefill before the first token. Measured
  from the live servers (2026-07; will drift as they update their tools):

  | MCP server | Tools | Approx. prompt tokens |
  |---|---|---|
  | Hugging Face | 8 | ~2,600 (biggest: `hf_fs` ~670, `hub_repo_details` ~490, `hub_repo_search` ~440) |
  | DeepWiki | 3 | ~400 |
  | Brave Search | 3 (web/news/summarizer) | ~2,900 (full 8-tool set is ~29k; `brave_place_search` alone ~20k - demo limits it via `--enabled-tools`) |

  The cost is paid once per server run, not per chat: the schemas are a stable prompt
  prefix and llama-server reuses the cached prefix across new chats as long as the
  enabled set (and order) does not change. On slow hardware prefer a small fixed
  subset over toggling servers between chats. Same logic in the Open WebUI demo:
  the servers are connected but not attached to the model - pick them per chat from
  the tool menu, or add `server:mcp:<id>` to the model's toolIds to make one permanent.
- **System message**: settable in Settings (useful to give the model a Bonsai identity).
  Can also be shipped as an admin default via `scripts/webui-config.json` (`systemMessage`).
- (A Pyodide Python interpreter setting exists but is NOT implemented in the current
  webui build — the Experimental settings section is a post-release TODO upstream.
  For code execution, use the Open WebUI demo's code interpreter instead.)
- **All sampling params** per conversation; empty fields fall back to the server
  flags (shown as placeholders read from `/props`).
- PDF attachments (optionally as images) and image upload for vision.

Note: UI settings live in the browser (localStorage), so they are per-user/per-machine —
server-side pre-seeding of tools is only available in the Open WebUI demo. This also
means browser state outlives config changes: if every NEW chat prefills thousands of
tokens, the user toggled an MCP server on from the new-chat screen (that saves it as
their default for future chats) - toggle it off there, or clear site data for
localhost:8080; an incognito window shows what a fresh browser would get.

**Agent: tell the user about the image-token cap.** If they are on Metal / Vulkan / CPU,
say that large images are downscaled to ~1024 vision tokens by default (fast, but fine
detail in big images is lost) and ask which they prefer:
- keep the cap — much snappier image answers;
- `BONSAI_IMAGE_MAX_TOKENS=0` — full image detail (best for OCR / screenshots / small
  text), noticeably slower per large image on consumer hardware.
On CUDA/ROCm there is nothing to decide — images run uncapped by default.

## Adding MCP servers

Full guide with entry examples: **TOOLS.md** (repo root). The essentials:

- Only streamable-HTTP servers work directly; stdio-only servers need a local HTTP
  bridge first (the Brave block in `start_openwebui.sh` is the pattern).
- llama-server webui: per-browser in Settings -> MCP Client (localStorage, wins over
  defaults), or shipped for everyone via the `mcpServers` JSON-string in
  `scripts/webui-config.json` (`"enabled":true` = listed in the per-chat selector,
  chats still opt in individually; `"useProxy":true` for CORS-rejecting servers).
- Open WebUI: edit `TOOL_SERVER_CONNECTIONS` in `scripts/start_openwebui.sh` and
  restart. Do NOT use the admin panel - `ENABLE_PERSISTENT_CONFIG=false` means panel
  edits are lost on restart; the script is the source of truth. For bearer tokens set
  `"auth_type":"bearer"` and inject the secret at runtime from an environment
  variable or a gitignored file (mirror the `.brave_key` handling below); never
  write a literal token into the tracked script. To attach a server to every chat,
  add `server:mcp:<id>` to the model `toolIds` in `scripts/openwebui/seed_openwebui.py`
  (mind the prompt-token table above).

**Optional web search (Brave)** - needs a Brave Search API key; the key stays local
(never committed). Install the bridge once: `npm i -g @brave/brave-search-mcp-server`.
- Open WebUI: put the key in a gitignored `.brave_key` file (or `BRAVE_API_KEY` env)
  and run `start_openwebui.sh` - it auto-starts the bridge on 127.0.0.1:8001 and adds
  the `brave` MCP (per-chat opt-in). Tell the user this is how they get web search.
- llama-server webui: no auto-bridge (out-of-box only). Run the bridge yourself
  (`BRAVE_API_KEY=... brave-search-mcp-server --transport http --host 127.0.0.1 --port 8001`)
  and add `http://127.0.0.1:8001/mcp` in Settings -> MCP Client. See TOOLS.md.
- Cost: ~2.9k prompt tokens (limited to web/news/summarizer; the full Brave set is ~29k, so start_openwebui.sh passes --enabled-tools).

## Behavior notes (from testing on Apple Silicon)

- Binary is the snappier demo; ternary trades speed for quality-per-bit. Both were
  tested working end to end (text, native tool_calls with round-trips, vision).
- With thinking on, most of a "slow answer" is reasoning tokens, not vision or prefill —
  before blaming the hardware, reach for a thinking budget. On slow machines prefer
  **capping** over disabling: `./scripts/start_llama_server.sh --reasoning-budget 2048`
  keeps most of the quality while bounding latency; the web UI's Reasoning-effort
  picker (Off ... Max) does the same per chat. (Default stays uncapped; these are
  user choices, not shipped defaults.)
- Image cost scales with resolution and is mostly a first-turn cost: the prompt cache
  makes follow-up questions about the same image near-instant.
- **Check macOS Low Power Mode** when speeds look far off — it throttles inference hard
  (System Settings -> Battery).
- Vision encode runs on GPU by default (`--mmproj-offload`).
- MLX: the **ternary 27B gets full vision + native tool calls** via mlx-vlm
  (`start_mlx_server.sh` uses the stock-mlx `.venv-vlm` that setup.sh creates;
  `BONSAI_MLX_VLM=0` opts out). The binary 27B MLX should support vision the same
  way (the vision tower is full precision in both packs) — it just hasn't been
  wired through / verified in these scripts yet.
- MLX has **no cross-request prompt cache** (mlx-vlm re-prefills the full
  conversation, image tokens included, on every turn), so follow-ups are much
  slower than llama.cpp (which caches the KV prefix). Steer multi-turn users to
  the llama.cpp backend; the image encoder itself is cached, it's the LM prefill.
- **M5 Macs on macOS 26.2–26.4:** if Metal init fails with `error compiling source` /
  command-buffer status 5, set `GGML_METAL_TENSOR_DISABLE=1` (README Appendix — FAQ has
  details). Keep `-ngl` on GPU; don't reach for `BONSAI_NGL=0`.
- Linux CUDA / Windows / CPU-only: not tested yet — extend these notes after testing.

## Quick verification commands

```bash
# server capabilities and effective context/slots
curl -s http://localhost:8080/props | python3 -m json.tool | head -30

# timing any request: read the "timings" object in the response
# (prompt_ms = encode+prefill, predicted_per_second = generation speed)
```

Tool calling: send an OpenAI `tools` array; expect `finish_reason: "tool_calls"`.
Vision: send an `image_url` content part (data URI works). Both verified on both
27B families.
