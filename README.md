# Bonsai Demo

Backend and model format compatibility: [BACKEND-SUPPORT.md](BACKEND-SUPPORT.md).

<p align="center">
  <img src="./assets/bonsai-logo.svg" width="280" alt="Bonsai">
</p>

<p align="center">
  <a href="https://prismml.com"><b>Website</b></a> &nbsp;|&nbsp;
  <a href="https://github.com/PrismML-Eng/Bonsai-demo"><b>GitHub</b></a> &nbsp;|&nbsp;
  <a href="https://discord.gg/prismml"><b>Discord</b></a>
</p>

<p align="center">
  <b>Models:</b>
  <a href="https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf">Bonsai 2 27B GGUF</a> ·
  <a href="https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-mlx-2bit">Bonsai 2 27B MLX</a>
</p>

---

Run **Bonsai 2 27B** locally on Mac (Metal), Linux/Windows (CUDA, Vulkan, ROCm), or CPU.

For the earlier **Bonsai 1-bit and Ternary-Bonsai** models (27B, 8B, 4B, 1.7B), see
[Bonsai1_README.md](Bonsai1_README.md). For troubleshooting, see [FAQ.md](FAQ.md).

## 🌱 New: Bonsai 2 27B

**Bonsai 2 27B is this demo's default.** Full 27B-class reasoning in ternary weights, at 5.9 GB,
running on a laptop or a single GPU.

- **98.2% of FP16 intelligence retained** at roughly a ninth of the size, with the reasoning core
  intact: math within half a point of full precision, coding level with the baseline.
- **Vision:** send photos, screenshots and PDFs and ask about them, on both llama.cpp and MLX
  (see [VISION.md](VISION.md)).
- **Agentic tool calling:** native OpenAI-style `tool_calls` with full round-trips, plus MCP servers
  in both demo UIs (see [TOOLS.md](TOOLS.md)).
- **Thinking:** a reasoning model; pick the reasoning effort per chat in the UI or budget it per request.
- **262K-token context**, kept practical on-device by the hybrid-attention backbone.
- **1.75 bits per weight** in the `PTQ1_0` packing. A second packing, `PQ2_0`, trades 1.3 GB for
  faster prompt processing and is what this demo downloads by default.
  See [MODEL-FORMATS.md](MODEL-FORMATS.md).

Bonsai 2 needs this demo's llama.cpp binaries, from the [PrismML fork](https://github.com/PrismML-Eng/llama.cpp);
stock llama.cpp cannot run these files. `./setup.sh` fetches the right ones for your machine.

Quick Start below gets you there in two commands: `./setup.sh` downloads Bonsai 2 27B, then
`./scripts/start_llama_server.sh` gives you chat, vision and tools at http://localhost:8080.

## Best Practices (Bonsai 2 27B)

These match the [model card](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf#best-practices). The start scripts already apply the thinking-mode sampling, so you only need these when calling the model from your own client.

### Generation Parameters

| | Thinking mode (default) | Instruct / non-thinking |
|---|---|---|
| `temperature` | 1.0 | 0.7 |
| `top_p` | 0.95 | 0.80 |
| `top_k` | 20 | 20 |
| `min_p` | 0.05 | 0.0 |
| `presence_penalty` | 0.0 | 1.5 |
| `repetition_penalty` | 1.0 | 1.0 |

`min_p=0.05` drops tokens far less likely than the top choice; in our tests it scored at least as well as `min_p=0.0` and followed instructions more reliably. It is also llama.cpp's default. Give the model a generous output limit (`-n 16384` or more, `max_tokens` for the API): it reasons before it answers, and a small cap ends generation mid-thought.

**The model uses `xhigh` reasoning effort by default; use `medium` for shorter responses and a balance of speed and accuracy. `low` reasoning effort is not supported and when selected the model will behave close to `xhigh`.**

### System Prompt

A simple system prompt works well:

```
You are a helpful assistant
```

## Quick Start

For repeated conversations and prompt-cache troubleshooting, see
[Prompt reuse and context checkpoints](PROMPT-CACHE.md).

Setting things up with an AI coding agent? Point it at [AGENTS.md](AGENTS.md), a guide written for agents (hardware-specific knobs, defaults, and what to ask the user).

### macOS / Linux

```bash
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo
./setup.sh
```

That installs and downloads only. To chat, start the server yourself, then open
http://localhost:8080:

```bash
./scripts/start_llama_server.sh
```

Or ask one question from the terminal without a server:

```bash
./scripts/run_llama.sh -p "What is the capital of France?"
```

`setup.sh` fetches the llama.cpp binaries for your machine and the Bonsai 2 27B
weights, 7.8 GB in the `PQ2_0` packing this demo defaults to plus its vision
projector. It also sets up Open WebUI and the code interpreter, which add a few GB
more and most of the wait. Skip those with `BONSAI_OPENWEBUI=0` and
`BONSAI_CODE_INTERPRETER=0`.

### Windows (PowerShell)

```powershell
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

Then start the server and open http://localhost:8080:

```powershell
.\scripts\start_llama_server.ps1
```

---

## Speed Benchmarks

See [community-benchmarks/](community-benchmarks/) for results on different hardware and templates to submit your own.

## Models

**Bonsai 2 27B is the default**: plain `./setup.sh` downloads it. It supports images as well as text.

### Bonsai 2 (ternary, default)

Available in GGUF (llama.cpp) and MLX 2-bit formats. Both bands need our
[llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) for now, which `./setup.sh` installs.

| Model                  | Format        | HuggingFace Repo                                                                                        |
|------------------------|---------------|---------------------------------------------------------------------------------------------------------|
| Bonsai-2-27B           | GGUF          | [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf)         |
| Bonsai-2-27B           | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-2-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-mlx-2bit) |

On Apple Silicon, Bonsai 2 text, images, and tool calls are supported by native
`mlx-vlm==0.7.2` in `.venv-vlm`. Re-run `./setup.sh` to upgrade an older environment,
then use `./scripts/start_mlx_server.sh` or
`BONSAI_BACKEND=mlx ./scripts/start_openwebui.sh`. The server keeps thinking enabled;
use `./scripts/start_mlx_server.sh --thinking-budget 8192 --max-tokens 32768`
for an example bounded server run (these are server flags, not `run_mlx.sh` flags). API clients use `thinking_budget` (MLX), not llama-server's
`thinking_budget_tokens`. Use the model-card sampling settings in API requests:
`temperature: 1.0`, `top_p: 0.95`, `top_k: 20`, `min_p: 0.05`.
Open WebUI refuses to reuse an existing server on its MLX port for Bonsai 2 because
its loader cannot be verified; stop it first so the launcher can start the tested runtime.
This does not update LM Studio's separately bundled MLX runtime.

### Environment variables

**No model-selection variables are needed for Bonsai 2 27B:** that's what plain `./setup.sh` downloads and runs.

Every launcher is configured through environment variables. The most common ones:

| Variable | Default | Values | Purpose |
|----------|---------|--------|---------|
| `BONSAI_MODEL` | `27B` | `27B` for Bonsai 2 | See the [Bonsai 1 guide](Bonsai1_README.md) for smaller models. |
| `BONSAI_FAMILY` | `bonsai2` | `bonsai2` | Earlier families: [Bonsai 1 guide](Bonsai1_README.md#setup-and-running). |
| `BONSAI_NGL` | auto-detect | int; `0` = CPU-only | GPU layer offload. |
| `BONSAI_CTX` | auto (RAM-tiered) | `0`, or ≤ `262144` | Context length (`0`/unset = automatic safe size). |
| `BONSAI_HOST` | `127.0.0.1` | any bind address | Server bind address. A non-loopback value exposes the server — see the security note in the full reference. |
| `BONSAI_KV4` | `0` | `1` | 4-bit KV cache for long contexts ([KV-CACHE.md](KV-CACHE.md)). |

**Full reference** — all 24 variables (model/setup, server, MLX, Open WebUI, tools, and platform coverage): **[environment_variables.md](environment_variables.md)**.

## Upstream Status for Bonsai 2

Bonsai 2 needs the Hadamard activation transform, which is not upstream yet, so every band currently
requires this demo's binaries from the [PrismML fork](https://github.com/PrismML-Eng/llama.cpp).

| Change | Status | Where |
|--------|--------|-------|
| FWHT with F16 input (CPU) | ⏳ Open | [ggml-org/llama.cpp#27779](https://github.com/ggml-org/llama.cpp/pull/27779) |

More will be added here as they go up. Until this work lands, do not run Bonsai 2 on stock
llama.cpp: `PQ2_0` and `PTQ1_0` are refused outright, but `Q2_0` loads without a warning and outputs
gibberish, which is why that band is kept in a
[separate repo](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf-dev).

<a id="bonsai-1-bit"></a>
<a id="ternary-bonsai"></a>
<a id="upstream-status-for-binary"></a>
<a id="upstream-status-for-ternary"></a>
<a id="upstream-status-for-ternary-bonsai-1"></a>

Earlier model formats and upstream status have moved to the [Bonsai 1 guide](Bonsai1_README.md).

## What `setup.sh` Does

The setup script handles everything for you, even on a fresh machine:

1. **Checks/installs system deps:** Xcode CLT on macOS, build-essential on Linux
2. **Installs [uv](https://docs.astral.sh/uv/):** fast Python package manager (user-local, not global)
3. **Creates a Python venv** and runs `uv sync` — installs cmake, ninja, huggingface-cli from `pyproject.toml`
4. **Downloads models** from HuggingFace (all model repos are public; no token needed)
5. **Downloads pre-built binaries** from the pinned [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10743-adfffbe) (or builds from source if you prefer)
6. **Sets up MLX** (Apple Silicon): installs the native mlx-vlm environment for Bonsai 2; earlier-family runtime details are in the [Bonsai 1 guide](Bonsai1_README.md#mlx-runtime)
7. **Installs Open WebUI** into the venv for the agentic demo (skip with `BONSAI_OPENWEBUI=0`)
8. **Builds the code-interpreter venv** (`.venv-jupyter`): Jupyter + matplotlib / pandas / numpy / scipy / sympy / yfinance for the Open WebUI code interpreter (skip with `BONSAI_CODE_INTERPRETER=0`)

Re-running `setup.sh` is safe — it skips already-completed steps.

---

## Running the Model

Every script runs Bonsai 2 27B unless you set `BONSAI_FAMILY` and `BONSAI_MODEL`
to pick another one ([Environment variables](#environment-variables)).

### llama.cpp (Mac / Linux — auto-detects platform)

```bash
./scripts/run_llama.sh -p "What is the capital of France?"
```

These scripts run the llama.cpp backend and need GGUF weights. On an MLX-only setup
(e.g. you used `BONSAI_SKIP_GGUF=1`), they stop with an error that points at both
options — running the MLX script directly (`run_mlx.sh` / `start_mlx_server.sh`), or
downloading the GGUF weights.

### llama.cpp (Windows PowerShell)

```powershell
.\scripts\run_llama.ps1 -p "What is the capital of France?"
```

### MLX — Mac (Apple Silicon)

```bash
./scripts/run_mlx.sh -p "What is the capital of France?"
```

Bonsai 2 uses the native mlx-vlm environment in `.venv-vlm`; the launcher selects it automatically. See [MLX support and settings](#bonsai-2-ternary-default) above.

### Chat Server

Start llama-server with its built-in chat UI:

```bash
./scripts/start_llama_server.sh    # http://localhost:8080
```

For Windows PowerShell:

```powershell
.\scripts\start_llama_server.ps1
```

The scripts auto-detect your GPU (Metal, CUDA, ROCm, Vulkan) and offload all layers. If the detection picks a GPU you do not want, for example Vulkan on a machine whose only GPU is a weak integrated one, set `BONSAI_NGL=0` for CPU-only inference, or any layer count for partial offload (PowerShell: `$env:BONSAI_NGL = "0"`).

#### Thinking

The 27B is a thinking model and serves with thinking **enabled**. To adjust it per conversation in the chat UI (no restart): click the lightbulb in the message box and pick a **Reasoning effort**: Off, Low (512 tokens), Medium (2,048), High (8,192), or Max (unlimited). The pick persists per browser and is sent with every request.

On slower hardware, thinking is usually the bulk of the wait; pick a lower effort in the UI. For API clients that don't specify a reasoning effort, you can cap the server-wide default by passing llama-server flags straight through the start script:

```bash
./scripts/start_llama_server.sh --reasoning-budget 2048
```

For API clients, the model's own `reasoning_effort: "medium"` is usually the better way to shorten thinking. At moderate output limits it thinks noticeably less than the default `xhigh` and is about as accurate, and it rarely runs out of budget mid-reasoning. Send it per request, or make it the server-wide default (a request can still ask for `xhigh`):

```bash
./scripts/start_llama_server.sh --chat-template-kwargs '{"reasoning_effort":"medium"}'
```

The chat UI's Reasoning effort levels are different: they are fixed thinking budgets (Medium is 2,048 tokens), which cut thinking off at that length rather than asking the model to think less.

#### Tool calling & MCP

The 27B does native OpenAI-style tool calling over the API, and the chat UI has an MCP client with Hugging Face + DeepWiki preconfigured (per-chat opt-in from the MCP selector in the message box, no prompt cost until you turn one on). Details, costs, and how to add your own servers: [TOOLS.md](TOOLS.md).

#### Agentic demo

Bonsai 2 driving the Hermes agent end to end: from a two-line brief to a playable 3D skateboard game it
verified in its own browser, then a round of plain-English feedback, all run with a fixed seed.
Clip, pages, prompts, settings and the two scripts that run it: [AGENT-DEMO.md](AGENT-DEMO.md).

#### Vision

Upload images in the chat UI (`+` in the message box) or send `image_url` parts over the API; the scripts load the vision projector automatically and downscale very large images on slower backends. Costs, the image-token cap, and OCR tips: [VISION.md](VISION.md).

#### Optional extras

Optional features for the llama.cpp chat server:

- **4-bit KV cache**: `BONSAI_KV4=1` cuts KV-cache memory roughly 3.5x for very long contexts, with an optional calibration bias for better quality (`./scripts/make_kv_bias.sh`). Details: [KV-CACHE.md](KV-CACHE.md).
- **Vision projector in RAM**: `BONSAI_MMPROJ_CPU=1` keeps the 27B's vision projector in system RAM instead of VRAM (`--no-mmproj-offload`), freeing VRAM for KV/context on tight cards. The cost is a slower image prompt (the projector runs on CPU); text-only chat is unaffected.

### Context Size

Bonsai 2 27B supports up to **262,144 tokens** of context. The FP16 KV cache costs 64 KiB per token (~6.3 GiB at 100K), so **100K context fits on many consumer devices even without KV-cache quantization**. The model's hybrid attention keeps the cache small for its size.

The launch scripts pick a **default context sized to your machine's RAM**, from 8K on small machines up to 131K for the 27B on machines with more than 71 GB (roughly 0.5 to 8 GiB of KV cache), so memory use stays predictable. Override with the `BONSAI_CTX` environment variable: pass any number up to 262144, or `0` (the same as leaving it unset) for the automatic RAM-tiered size. To force the model's full training context, pass the explicit number (e.g. `BONSAI_CTX=262144`) — only recommended on machines with plenty of headroom, since the scripts will not silently do this for you.

With the optional [4-bit KV cache](KV-CACHE.md) (`BONSAI_KV4=1`) the cache drops to roughly 18 KiB per token, about **1.8 GiB at 100K**, saving roughly 4.5 GiB of KV memory. Total memory also depends on the model packing, runtime buffers, and vision projector.

Extra arguments pass straight through to llama.cpp, so `./scripts/run_llama.sh -c 8192 -p "Your prompt"` also works for a one-off context override.

For earlier-model memory tables, see [Bonsai 1 context and memory](Bonsai1_README.md#context-and-memory).

---

## Open WebUI (Optional): the full agentic demo

[Open WebUI](https://github.com/open-webui/open-webui) gives you a ChatGPT-like interface on top of the local 27B: chat with images, tool calling against live tools, a server-side code interpreter (plots + market data), and a hidden-story sales database to investigate. Everything is configured automatically, no clicking through settings:

```bash
./scripts/start_openwebui.sh
```

`setup.sh` installs it for you; the script starts the backend, seeds the demo (tools, model settings, demo database), and opens **http://localhost:9090**. Backends, what to try, and customizing: [OPENWEBUI.md](OPENWEBUI.md).

---

## Building from Source

If you prefer to build llama.cpp from source instead of using pre-built binaries:

### Mac (Apple Silicon — Metal)

```bash
./scripts/build_mac.sh
```

Clones [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp), builds with Metal, outputs to `bin/mac/`.

### Mac (Intel — CPU only)

```bash
./scripts/build_mac.sh
```

The script auto-detects Intel vs Apple Silicon. On Intel Macs, it builds with `-DGGML_METAL=OFF` (CPU only). MLX is also skipped automatically since it requires Apple Silicon.

### Linux (CPU only)

```bash
./scripts/build_cpu_linux.sh
```

Builds a CPU-only binary with no GPU dependencies. Works on both x64 and arm64. Outputs to `bin/cpu/`.

### Linux (CUDA)

```bash
./scripts/build_cuda_linux.sh
```

Auto-detects CUDA version. Pass `--cuda-path /usr/local/cuda-12.8` to use a specific toolkit.

### Linux (Vulkan)

```bash
# Install Vulkan SDK first (e.g. sudo apt install libvulkan-dev glslc)
git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git
cd llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON
cmake --build build -j$(nproc)
# Binaries in build/bin/
```

### Linux (ROCm / AMD GPU)

```bash
# Requires ROCm toolkit (hipcc)
git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git
cd llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_HIP=ON
cmake --build build -j$(nproc)
# Binaries in build/bin/
```

### Windows (CUDA)

```powershell
.\scripts\build_cuda_windows.ps1
```

Auto-detects CUDA toolkit. Pass `-CudaPath "C:\path\to\cuda"` to use a specific version.
Requires Visual Studio Build Tools (or full Visual Studio) and CUDA toolkit.

### Windows (CPU only)

```powershell
git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git
cd llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
# Binaries in build\bin\Release\
```

Requires Visual Studio Build Tools or full Visual Studio with C++ workload.

---

## llama.cpp Pre-built Binary Downloads

All binaries are available from the pinned [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10743-adfffbe), also used by both setup scripts. The latest release may still be missing platform binaries while builds finish.

| Platform                          |
|-----------------------------------|
| macOS Apple Silicon (arm64)       |
| macOS Apple Silicon (KleidiAI)    |
| macOS Intel (x64)                 |
| Linux x64 (CPU)                   |
| Linux arm64 (CPU)                 |
| Linux x64 (CUDA 12.4)            |
| Linux x64 (CUDA 12.8)            |
| Linux x64 (Vulkan)               |
| Linux arm64 (Vulkan)             |
| Linux x64 (ROCm 7.2)             |
| Windows x64 (CPU)                |
| Windows arm64 (CPU)              |
| Windows x64 (CUDA 12.4)          |
| Windows x64 (Vulkan)             |
| Windows x64 (HIP/ROCm)           |
| iOS (XCFramework)                 |

---

## Folder Structure

After setup, the directory looks like this:

```
Bonsai-demo/
├── README.md                      # Bonsai 2 setup and usage
├── Bonsai1_README.md               # Earlier binary and ternary models
├── FAQ.md                          # Troubleshooting
├── TOOLS.md                        # Tool calling & MCP guide
├── OPENWEBUI.md                    # Open WebUI agentic demo guide
├── VISION.md                       # Image input: costs, caps, OCR tips
├── SPECULATIVE.md                  # Speculative decoding (experimental)
├── KV-CACHE.md                     # 4-bit KV cache (experimental)
├── AGENTS.md                       # Agent guide (hardware tuning knobs)
├── setup.sh                        # macOS/Linux setup
├── setup.ps1                       # Windows setup
├── pyproject.toml                  # Python dependencies
├── scripts/
│   ├── common.sh                   # Shared helpers + BONSAI_MODEL
│   ├── download_models.sh          # HuggingFace download
│   ├── download_binaries.sh        # GitHub release download
│   ├── run_llama.sh                # llama.cpp (auto-detects Mac/Linux)
│   ├── run_llama.ps1               # llama.cpp (Windows PowerShell)
│   ├── run_mlx.sh                  # MLX inference
│   ├── mlx_generate.py             # MLX Python script
│   ├── start_llama_server.sh       # llama.cpp server (port 8080)
│   ├── start_llama_server.ps1      # llama.cpp server (Windows PowerShell)
│   ├── start_mlx_server.sh         # MLX server (port 8081)
│   ├── start_openwebui.sh          # Open WebUI + auto-starts backends
│   ├── openwebui/                  # Open WebUI demo tools + seeding
│   ├── build_mac.sh                # Build llama.cpp for Mac
│   ├── build_cpu_linux.sh          # Build llama.cpp for Linux (CPU only)
│   ├── build_cuda_linux.sh         # Build llama.cpp for Linux CUDA
│   └── build_cuda_windows.ps1      # Build llama.cpp for Windows CUDA
├── models/                         # ← downloaded by setup
│   ├── bonsai2-gguf/
│   │   └── 27B/                    # Bonsai 2 GGUF + vision projector
│   └── Ternary-Bonsai-2-27B-mlx-2bit/ # Bonsai 2 MLX (Apple Silicon)
├── bin/                            # ← downloaded or built by setup
│   ├── mac/                        # macOS binaries (Metal or CPU)
│   ├── cuda/                       # CUDA binaries (Linux/Windows)
│   ├── cpu/                        # CPU-only binaries (Linux/Windows)
│   ├── vulkan/                     # Vulkan binaries
│   ├── rocm/                       # ROCm binaries (AMD Linux)
│   └── hip/                        # HIP binaries (AMD Windows)
├── mlx/                            # ← cloned by setup (macOS)
├── .venv/                          # ← created by setup
└── .venv-vlm/                      # ← native Bonsai 2 MLX environment
```

Items marked with ← are created at setup time and excluded from git.

---

## FAQ and troubleshooting

<a id="appendix--faq"></a>
<a id="the-model-allocates-huge-memory-or-the-machine-freezes-at-startup"></a>
<a id="m5-mac-on-macos-262263-metal-compile-errors-then-out-of-memory"></a>
<a id="windows-setup-selects-vulkan-or-cpu-instead-of-cuda"></a>
<a id="cuda-source-build-runs-out-of-memory-or-freezes"></a>
<a id="metal-fails-to-initialize-on-apple-m5-macos-262264"></a>

For memory issues, GPU detection, Metal errors, and CUDA build troubleshooting, see
[FAQ.md](FAQ.md).
