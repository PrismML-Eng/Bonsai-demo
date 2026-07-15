# Bonsai Demo

<p align="center">
  <img src="./assets/bonsai-logo.svg" width="280" alt="Bonsai">
</p>

<p align="center">
  <a href="https://prismml.com"><b>Website</b></a> &nbsp;|&nbsp;
  <a href="https://github.com/PrismML-Eng/Bonsai-demo"><b>GitHub</b></a> &nbsp;|&nbsp;
  <a href="https://discord.gg/prismml"><b>Discord</b></a>
</p>

<p align="center">
  <b>HF Collections:</b>
  <a href="https://huggingface.co/collections/prism-ml/bonsai-27b">Bonsai 27B</a> ·
  <a href="https://huggingface.co/collections/prism-ml/bonsai">Bonsai (1-bit)</a> ·
  <a href="https://huggingface.co/collections/prism-ml/ternary-bonsai">Ternary-Bonsai</a>
</p>

<p align="center">
  <b>Whitepapers:</b>
  <a href="bonsai-27b-whitepaper.pdf">Bonsai 27B</a> ·
  <a href="1-bit-bonsai-8b-whitepaper.pdf">1-bit Bonsai 8B</a> ·
  <a href="ternary-bonsai-8b-whitepaper.pdf">Ternary-Bonsai 8B</a>
</p>

---


Using this demo repository you can run **Bonsai** (1-bit) and **Ternary-Bonsai** language models locally on Mac (Metal), Linux/Windows (CUDA, Vulkan, ROCm), or CPU.

## 🌱 New: Bonsai 27B

The family's newest and largest generation, and its first **vision-language** models ([Bonsai 27B collection](https://huggingface.co/collections/prism-ml/bonsai-27b)):

- **Vision:** send photos, screenshots, and PDFs; ask about them (see [VISION.md](VISION.md)).
- **Agentic tool calling:** native OpenAI-style `tool_calls` with full round-trips, plus MCP servers in both demo UIs (see [TOOLS.md](TOOLS.md)).
- **Thinking:** a reasoning model; pick the reasoning effort per chat in the UI or budget it per request.
- **Long context:** 256k+ token conversations.
- **Tiny footprint:** the 1-bit Bonsai-27B packs to ~1.125 bits per weight: it fits on a modern iPhone without memory offloading. Ternary-Bonsai-27B (~1.7 bits per weight, packed into 2-bit for fast accelerated kernels) is the higher-quality option and this demo's default.

Quick Start below gets you there in two commands: `./setup.sh` downloads Ternary-Bonsai-27B by default, then `./scripts/start_llama_server.sh` gives you chat, vision, and tools at http://localhost:8080.

## Quick Start

Setting things up with an AI coding agent? Point it at [AGENTS.md](AGENTS.md), a guide written for agents (hardware-specific knobs, defaults, and what to ask the user).

### macOS / Linux

```bash
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# (Optional) Choose a model size: 27B (default), 8B, 4B, or 1.7B
export BONSAI_MODEL=27B

# Set your HuggingFace token (only required for 27B while its repos are private)
export BONSAI_TOKEN="hf_your_token_here"

# One command does everything: installs deps, downloads models + binaries
./setup.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# (Optional) Choose a model size: 27B (default), 8B, 4B, or 1.7B
$env:BONSAI_MODEL = "27B"

# Set your HuggingFace token (only required for 27B while its repos are private)
$env:BONSAI_TOKEN = "hf_your_token_here"

# Run setup
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

### Switching families and sizes

You can switch between the Ternary (default) and 1-bit families, and different model sizes instantly:

```bash
# run Ternary-Bonsai 4B
BONSAI_FAMILY=ternary BONSAI_MODEL=4B ./scripts/download_models.sh
BONSAI_FAMILY=ternary BONSAI_MODEL=4B ./scripts/run_llama.sh -p "Hello!"
```

for Windows:
```powershell
$env:BONSAI_FAMILY="ternary"; $env:BONSAI_MODEL="4B"
.\setup.ps1
.\scripts\run_llama.ps1 -p "Hello!"
```

---

## Speed Benchmarks

See [community-benchmarks/](community-benchmarks/) for results on different hardware and templates to submit your own.

## Models

Two model families are available, each in sizes **27B**, **8B**, **4B**, and **1.7B**. The 27B models are vision-language models: they accept images as well as text; all 27B repos are gathered in the [Bonsai 27B HF collection](https://huggingface.co/collections/prism-ml/bonsai-27b).

Both formats are landing in mainline llama.cpp: **Q1_0 (1-bit) is fully merged upstream**, and **Q2_0 (ternary) now runs on mainline CPU and Metal**, with Vulkan in review. Details and mainline-compatible files: [binary status](#upstream-status-for-binary) and [ternary status](#upstream-status-for-ternary) below.

### Bonsai (1-bit)

Available in GGUF (llama.cpp) and MLX 1-bit formats.

| Model               | Format   | HuggingFace Repo                                                                          |
|---------------------|----------|-------------------------------------------------------------------------------------------|
| Bonsai-27B          | GGUF     | [prism-ml/Bonsai-27B-gguf](https://huggingface.co/prism-ml/Bonsai-27B-gguf)             |
| Bonsai-27B          | MLX      | [prism-ml/Bonsai-27B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit)     |
| Bonsai-8B           | GGUF     | [prism-ml/Bonsai-8B-gguf](https://huggingface.co/prism-ml/Bonsai-8B-gguf)               |
| Bonsai-8B           | MLX      | [prism-ml/Bonsai-8B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-8B-mlx-1bit)       |
| Bonsai-4B           | GGUF     | [prism-ml/Bonsai-4B-gguf](https://huggingface.co/prism-ml/Bonsai-4B-gguf)               |
| Bonsai-4B           | MLX      | [prism-ml/Bonsai-4B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-4B-mlx-1bit)       |
| Bonsai-1.7B         | GGUF     | [prism-ml/Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Bonsai-1.7B-gguf)           |
| Bonsai-1.7B         | MLX      | [prism-ml/Bonsai-1.7B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-1.7B-mlx-1bit)   |

Set `BONSAI_MODEL` to choose which size to download and run (default: `27B`).

### Ternary-Bonsai

Available in GGUF (llama.cpp) and MLX 2-bit formats.


| Model                  | Format        | HuggingFace Repo                                                                                        |
|------------------------|---------------|---------------------------------------------------------------------------------------------------------|
| Ternary-Bonsai-27B     | GGUF          | [prism-ml/Ternary-Bonsai-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf)             |
| Ternary-Bonsai-27B     | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-mlx-2bit)     |
| Ternary-Bonsai-8B      | GGUF          | [prism-ml/Ternary-Bonsai-8B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-gguf)               |
| Ternary-Bonsai-8B      | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-8B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit)       |
| Ternary-Bonsai-4B      | GGUF          | [prism-ml/Ternary-Bonsai-4B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf)               |
| Ternary-Bonsai-4B      | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-4B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-mlx-2bit)       |
| Ternary-Bonsai-1.7B    | GGUF          | [prism-ml/Ternary-Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf)           |
| Ternary-Bonsai-1.7B    | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-1.7B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-mlx-2bit)   |

This is the default family. Set `BONSAI_FAMILY=bonsai` to use the 1-bit Bonsai family instead.

### Environment variables

Both variables are optional. **If you set neither, the default is `Ternary-Bonsai-27B`:** that's what plain `./setup.sh` downloads and runs. They're read by `setup.sh`, `setup.ps1`, `download_models.sh`, and every `run_*` / `start_*` script (Linux, macOS, and Windows).

| Variable        | Default   | Valid values                       | Purpose |
|-----------------|-----------|------------------------------------|---------|
| `BONSAI_FAMILY` | `ternary` | `ternary`, `bonsai`, `all`         | Model family. `ternary` = Ternary-Bonsai; `bonsai` = 1-bit Bonsai. `all` expands to both families (setup/download only). |
| `BONSAI_MODEL`  | `27B`    | `27B`, `8B`, `4B`, `1.7B`, `all`   | Model size. `all` expands to all four sizes (setup/download only). |
| `BONSAI_TOKEN`  | —        | HF read-only token                 | Only needed for the 27B models while their repos are private (removed at launch). |

`all` is only valid for `setup.sh` / `setup.ps1` / `download_models.sh` — the run/server scripts need a concrete family/size.

Combine them freely:

```bash
./setup.sh                                                  # Ternary-Bonsai-27B (default)
BONSAI_MODEL=1.7B ./setup.sh                                # Ternary-Bonsai-1.7B
BONSAI_FAMILY=bonsai ./setup.sh                             # Bonsai-27B (1-bit)
BONSAI_FAMILY=bonsai BONSAI_MODEL=4B ./setup.sh             # Bonsai-4B
BONSAI_MODEL=all ./setup.sh                                 # All 4 Ternary-Bonsai sizes
BONSAI_FAMILY=all BONSAI_MODEL=all ./setup.sh               # Full matrix (8 downloads)
```

## Upstream Status for Binary

Q1_0 is supported out of the box in upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) across many backends: CPU (generic, NEON, and optimized x86), Metal, CUDA, and Vulkan.

| Runtime | Status |
|---------|--------|
| llama.cpp (CPU, Metal, CUDA, Vulkan) | ✅ Merged upstream, works out of the box |
| MLX (1-bit) | ⏳ Pending upstream: [mlx#3161](https://github.com/ml-explore/mlx/pull/3161); until it merges, use [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) (branch `prism`, built automatically by `setup.sh`) |

## Upstream Status for Ternary

Ternary support is in the middle of migrating into mainline [llama.cpp](https://github.com/ggml-org/llama.cpp): backends are landing one by one, so today it is a mix of mainline and our fork. The practical consequence first: **we currently ship three ternary GGUF variants, and each one needs to run in the right place.**

| File | Format | Runs on |
|------|--------|---------|
| `*-Q2_0.gguf` | Group size 128. **The format this demo uses**, compatible with our fork. Once the llama.cpp migration completes, these files will be deprecated and replaced by the `PQ2_0` ggufs | This demo / the fork binaries. Will not load on mainline (same type id, different block size) |
| `*-Q2_0_g64.gguf` | Group size 64 (2.25 bpw). The official llama.cpp format; these will be renamed to plain `Q2_0`, replacing the current ones | Mainline llama.cpp (CPU and Metal so far) |
| `*-PQ2_0.gguf` | Not supported yet. Planned as the fork format going forward: the same format as the current group-128 `Q2_0`, just under its own ggml type id so it can coexist with the upstream `Q2_0` | Nothing yet (fork support planned) |

Backend-by-backend migration status:

| Backend | Status | Where |
|---------|--------|-------|
| CPU (ARM NEON + generic scalar) | ✅ Merged in mainline llama.cpp | [ggml-org/llama.cpp#24448](https://github.com/ggml-org/llama.cpp/pull/24448) |
| Metal | ✅ Merged in mainline llama.cpp | [ggml-org/llama.cpp#25419](https://github.com/ggml-org/llama.cpp/pull/25419) |
| Vulkan | 🔄 In progress upstream (separate PR, not ours) | [ggml-org/llama.cpp#25430](https://github.com/ggml-org/llama.cpp/pull/25430) |
| CUDA | 🔄 In review upstream | [ggml-org/llama.cpp#25707](https://github.com/ggml-org/llama.cpp/pull/25707) |
| x86 (AVX-512-VNNI) | ⏳ Pending | TBD |

**CPU and Metal now run `Q2_0` on mainline llama.cpp, no fork needed** (use a recent `ggml-org/llama.cpp` build with the `*-Q2_0_g64.gguf` files). For CUDA and the other backends, use this demo: it ships the fork [pre-built binaries](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b9591-62061f9), so everything works out of the box with the group-128 `*-Q2_0.gguf` files it downloads. MLX 2-bit is supported in stock [MLX](https://github.com/ml-explore/mlx), no fork needed.

To run the smaller ternary models directly on stock `ggml-org/llama.cpp` (CPU or Metal), use the group-64 files:

| Model | Repo | File (mainline-compatible) |
|-------|------|----------------------------|
| 1.7B | [prism-ml/Ternary-Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf) | `Ternary-Bonsai-1.7B-Q2_0_g64.gguf` |
| 4B | [prism-ml/Ternary-Bonsai-4B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf) | `Ternary-Bonsai-4B-Q2_0_g64.gguf` |
| 8B | [prism-ml/Ternary-Bonsai-8B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-gguf) | `Ternary-Bonsai-8B-Q2_0_g64.gguf` |

```bash
hf download prism-ml/Ternary-Bonsai-1.7B-gguf Ternary-Bonsai-1.7B-Q2_0_g64.gguf --local-dir models
hf download prism-ml/Ternary-Bonsai-4B-gguf  Ternary-Bonsai-4B-Q2_0_g64.gguf  --local-dir models
hf download prism-ml/Ternary-Bonsai-8B-gguf  Ternary-Bonsai-8B-Q2_0_g64.gguf  --local-dir models
```

## What `setup.sh` Does

The setup script handles everything for you, even on a fresh machine:

1. **Checks/installs system deps:** Xcode CLT on macOS, build-essential on Linux
2. **Installs [uv](https://docs.astral.sh/uv/):** fast Python package manager (user-local, not global)
3. **Creates a Python venv** and runs `uv sync` — installs cmake, ninja, huggingface-cli from `pyproject.toml`
4. **Downloads models** from HuggingFace (needs `BONSAI_TOKEN` for 27B while its repos are private)
5. **Downloads pre-built binaries** from [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b9591-62061f9) (or builds from source if you prefer)
6. **Builds MLX from source** (macOS only): clones our fork, builds it into the venv, installs the ML stack (mlx-lm, torch, transformers)
7. **Installs Open WebUI** into the venv for the agentic demo (skip with `BONSAI_OPENWEBUI=0`)
8. **Builds the code-interpreter venv** (`.venv-jupyter`): Jupyter + matplotlib / pandas / numpy / scipy / sympy / yfinance for the Open WebUI code interpreter (skip with `BONSAI_CODE_INTERPRETER=0`)

Re-running `setup.sh` is safe — it skips already-completed steps.

---

## Running the Model

All run scripts respect `BONSAI_MODEL` (default `27B`). Set it to run a different size:

### llama.cpp (Mac / Linux — auto-detects platform)

```bash
./scripts/run_llama.sh -p "What is the capital of France?"

# Run a different model size
BONSAI_MODEL=4B ./scripts/run_llama.sh -p "Write a haiku about bonsai trees"
```

### llama.cpp (Windows PowerShell)

```powershell
.\scripts\run_llama.ps1 -p "What is the capital of France?"

# Run a different model size
$env:BONSAI_MODEL = "4B"
.\scripts\run_llama.ps1 -p "Write a haiku about bonsai trees"
```

### MLX — Mac (Apple Silicon)

```bash
source .venv/bin/activate
./scripts/run_mlx.sh -p "What is the capital of France?"
```

### Chat Server

Start llama-server with its built-in chat UI:

```bash
./scripts/start_llama_server.sh    # http://localhost:8080

# Serve a different model size
BONSAI_MODEL=4B ./scripts/start_llama_server.sh
```

For Windows PowerShell:

```powershell
.\scripts\start_llama_server.ps1
```

#### Thinking

The 27B is a thinking model and serves with thinking **enabled**. To adjust it per conversation in the chat UI (no restart): click the lightbulb in the message box and pick a **Reasoning effort**: Off, Low (512 tokens), Medium (2,048), High (8,192), or Max (unlimited). The pick persists per browser and is sent with every request.

On slower hardware, thinking is usually the bulk of the wait; pick a lower effort in the UI. For API clients that don't specify a reasoning effort, you can cap the server-wide default by passing llama-server flags straight through the start script:

```bash
./scripts/start_llama_server.sh --reasoning-budget 2048
```

#### Tool calling & MCP

The 27B does native OpenAI-style tool calling over the API, and the chat UI has an MCP client with Hugging Face + DeepWiki preconfigured (per-chat opt-in from the MCP selector in the message box, no prompt cost until you turn one on). Details, costs, and how to add your own servers: [TOOLS.md](TOOLS.md).

#### Vision

Upload images in the chat UI (`+` in the message box) or send `image_url` parts over the API; the scripts load the vision projector automatically and downscale very large images on slower backends. Costs, the image-token cap, and OCR tips: [VISION.md](VISION.md).

#### Optional extras

Two experimental, off-by-default features for the llama.cpp chat server:

- **Speculative decoding**: `BONSAI_SPECULATIVE=1` pairs the 27B with its dspark drafter for roughly 1.8-2x faster decode on code and reasoning (CUDA; Apple Silicon support will be improved later). Trade-offs and verification: [SPECULATIVE.md](SPECULATIVE.md).
- **4-bit KV cache**: `BONSAI_KV4=1` cuts KV-cache memory roughly 3.5x for very long contexts, with an optional calibration bias for better quality (`./scripts/make_kv_bias.sh`). Details: [KV-CACHE.md](KV-CACHE.md).

### Context Size

The 27B models support up to **262,144 tokens** of context. The FP16 KV cache costs 64 KiB per token (~6.3 GiB at 100K), so **100K context fits on many consumer devices even without KV-cache quantization**. The model's hybrid attention keeps the cache small for its size.

With the optional [4-bit KV cache](KV-CACHE.md) (`BONSAI_KV4=1`) the cache drops to roughly 18 KiB per token, about **1.8 GiB at 100K**, shaving ~4.5 GiB off the 100K figures below (for example, Ternary-Bonsai-27B on llama.cpp goes from ~13.7 to ~9.2 GiB).

*Peak memory for the 27B (weights + activations + FP16 KV cache + ~1.2 GiB overhead; text-only, add ~0.9 GiB for the vision projector):*

| Model | Format | Weights | 4K context | 10K context | 100K context |
|---|---|---|---|---|---|
| Bonsai-27B (1-bit) | llama.cpp `Q1_0` | 3.53 GiB | 4.8 GiB | 5.2 GiB | 10.8 GiB |
| Bonsai-27B (1-bit) | MLX 1-bit | 3.92 GiB | 5.5 GiB | 5.9 GiB | 11.4 GiB |
| Ternary-Bonsai-27B | llama.cpp `Q2_0` | 6.66 GiB | 7.8 GiB | 8.1 GiB | 13.7 GiB |
| Ternary-Bonsai-27B | MLX 2-bit | 7.05 GiB | 8.6 GiB | 8.9 GiB | 14.4 GiB |
| *reference: 27B 16-bit* | GGUF BF16 | 47.73 GiB | 49 GiB | 49.6 GiB | 55.2 GiB |
| *reference: 27B "4-bit"* | llama.cpp `UD Q4_K_M` | 15.73 GiB | 17.2 GiB | 17.6 GiB | 23.2 GiB |
| *reference: 27B "4-bit"* | MLX 4-bit | 13.3 GiB | 17.0 GiB | 17.3 GiB | 22 GiB |

(The MLX packs are ~400 MiB larger than GGUF because MLX stores both scales and biases, GGUF only scales.)

By default the scripts pass `-c 0`, which lets llama.cpp's `--fit` automatically size the KV cache to your available memory (no pre-allocation waste). If your build doesn't support `-c 0`, the scripts fall back to a safe value based on system RAM. Override with: `./scripts/run_llama.sh -c 8192 -p "Your prompt"`

The older text-only sizes are smaller across the board; the 8B supports up to 65,536 tokens of context:

*Estimates for Bonsai-8B (weights + KV cache + activations):*

| Context Size        | Est. Memory Usage |
|---------------------|-------------------|
| 8,192 tokens        | ~2.5 GB           |
| 32,768 tokens       | ~5.9 GB           |
| 65,536 tokens       | ~10.5 GB          |

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

All binaries are available from the [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b9591-62061f9):

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
├── README.md
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
│   ├── gguf/
│   │   ├── 27B/                    # GGUF 27B model (+ mmproj for vision)
│   │   ├── 8B/                     # GGUF 8B model
│   │   ├── 4B/                     # GGUF 4B model
│   │   └── 1.7B/                   # GGUF 1.7B model
│   ├── Bonsai-27B-mlx/            # MLX 27B model (macOS)
│   ├── Bonsai-8B-mlx/             # MLX 8B model (macOS)
│   ├── Bonsai-4B-mlx/             # MLX 4B model (macOS)
│   └── Bonsai-1.7B-mlx/           # MLX 1.7B model (macOS)
├── bin/                            # ← downloaded or built by setup
│   ├── mac/                        # macOS binaries (Metal or CPU)
│   ├── cuda/                       # CUDA binaries (Linux/Windows)
│   ├── cpu/                        # CPU-only binaries (Linux/Windows)
│   ├── vulkan/                     # Vulkan binaries
│   ├── rocm/                       # ROCm binaries (AMD Linux)
│   └── hip/                        # HIP binaries (AMD Windows)
├── mlx/                            # ← cloned by setup (macOS)
└── .venv/                          # ← created by setup
```

Items marked with ← are created at setup time and excluded from git.

---

## Appendix — FAQ

### CUDA source build runs out of memory or freezes

**Symptom:** `cmake --build` hangs, the system becomes unresponsive, or the build process is killed with an OOM error when building llama.cpp from source with CUDA enabled.

**Cause:** Compiling CUDA kernels is memory-intensive — each parallel compile job can consume several GB of GPU VRAM and/or system RAM. Running `make -j$(nproc)` on a machine with a low-VRAM GPU (< 16 GB) or limited system RAM can exhaust available memory.

**How the build scripts handle this:** `build_cuda_linux.sh` and `build_cuda_windows.ps1` automatically detect the GPU's VRAM before building. If the maximum detected VRAM is less than 16 GB, the scripts cap parallelism at `-j 2` instead of using all logical CPU cores. You will see a message like:

```
Detected GPU VRAM: 8.0 GB (< 16 GB) -- limiting CUDA build to -j 2
```

**Manual override:** If you still encounter OOM errors, reduce parallelism further by editing the build invocation in the relevant script, or close other GPU-heavy applications before building.
