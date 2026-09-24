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
  <b>Models:</b>
  <a href="https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf">Bonsai 2 27B GGUF</a> ·
  <a href="https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-mlx-2bit">Bonsai 2 27B MLX</a> ·
  <a href="https://huggingface.co/collections/prism-ml/bonsai-27b">Bonsai 27B</a> ·
  <a href="https://huggingface.co/collections/prism-ml/ternary-bonsai">Ternary-Bonsai</a> ·
  <a href="https://huggingface.co/collections/prism-ml/bonsai">Bonsai (1-bit)</a>
</p>

<p align="center">
  <b>Whitepapers:</b>
  <a href="bonsai-27b-whitepaper.pdf">Bonsai 27B</a> ·
  <a href="1-bit-bonsai-8b-whitepaper.pdf">1-bit Bonsai 8B</a> ·
  <a href="ternary-bonsai-8b-whitepaper.pdf">Ternary-Bonsai 8B</a>
</p>

---


Using this demo repository you can run **Bonsai 2**, **Bonsai** (1-bit) and **Ternary-Bonsai** language models locally on Mac (Metal), Linux/Windows (CUDA, Vulkan, ROCm), or CPU.

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

The earlier Bonsai families are still here, in smaller sizes too. See [Models](#models).

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

**Bonsai 2 27B is the default**: plain `./setup.sh` downloads and runs it. Two earlier families remain available in sizes **27B**, **8B**, **4B**, and **1.7B**. Every 27B model is a vision-language model: it accepts images as well as text.

Both earlier formats are landing in mainline llama.cpp: **Q1_0 (1-bit) is fully merged upstream**, and **Q2_0 (ternary) now runs on mainline CPU, Metal, Vulkan, and CUDA**. Details and mainline-compatible files: [binary status](#upstream-status-for-binary) and [ternary status](#upstream-status-for-ternary) below.

### Bonsai 2 (ternary, default)

Available in GGUF (llama.cpp) and MLX 2-bit formats. Both bands need our
[llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) for now, which `./setup.sh` installs.

| Model                  | Format        | HuggingFace Repo                                                                                        |
|------------------------|---------------|---------------------------------------------------------------------------------------------------------|
| Bonsai-2-27B           | GGUF          | [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf)         |
| Bonsai-2-27B           | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-2-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-mlx-2bit) |

Set `BONSAI_FAMILY=ternary` or `BONSAI_FAMILY=bonsai` for the earlier families
and their smaller sizes.

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

Set `BONSAI_FAMILY=ternary` to use this family.

### Environment variables

Both variables are optional. **If you set neither, the default is `Bonsai-2-27B`:** that's what plain `./setup.sh` downloads and runs.

Every launcher is configured through environment variables. The most common ones:

| Variable | Default | Values | Purpose |
|----------|---------|--------|---------|
| `BONSAI_MODEL` | `27B` | `27B`, `8B`, `4B`, `1.7B` | Model size. Bonsai 2 is `27B`. |
| `BONSAI_FAMILY` | `bonsai2` | `bonsai2`, `ternary`, `bonsai` | Model family (`bonsai2` = Bonsai 2, `ternary` = Ternary-Bonsai, `bonsai` = 1-bit Bonsai). |
| `BONSAI_NGL` | auto-detect | int; `0` = CPU-only | GPU layer offload. |
| `BONSAI_CTX` | auto (RAM-tiered) | `0`, or ≤ `262144` | Context length (`0`/unset = automatic safe size). |
| `BONSAI_HOST` | `127.0.0.1` | any bind address | Server bind address. A non-loopback value exposes the server — see the security note in the full reference. |
| `BONSAI_SPECULATIVE` | `0` | `1` | Speculative decoding with the dspark drafter ([SPECULATIVE.md](SPECULATIVE.md)). |
| `BONSAI_KV4` | `0` | `1` | 4-bit KV cache for long contexts ([KV-CACHE.md](KV-CACHE.md)). |

**Full reference** — all 24 variables (model/setup, server, MLX, Open WebUI, tools, and platform coverage): **[environment_variables.md](environment_variables.md)**.

Combine them freely:

```bash
./setup.sh                                                  # Bonsai-2-27B (default)
BONSAI_FAMILY=ternary ./setup.sh                            # Ternary-Bonsai-27B
BONSAI_FAMILY=ternary BONSAI_MODEL=1.7B ./setup.sh          # Ternary-Bonsai-1.7B
BONSAI_FAMILY=bonsai ./setup.sh                             # Bonsai-27B (1-bit)
BONSAI_FAMILY=bonsai BONSAI_MODEL=4B ./setup.sh             # Bonsai-4B
BONSAI_FAMILY=ternary BONSAI_MODEL=all ./setup.sh           # All 4 Ternary-Bonsai sizes
BONSAI_FAMILY=all BONSAI_MODEL=all ./setup.sh               # Full matrix
BONSAI_FAMILY=bonsai BONSAI_SKIP_GGUF=1 ./setup.sh          # Bonsai-27B, MLX only (macOS, saves disk space)
```

## Upstream Status for Binary

Q1_0 is supported out of the box in upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) across many backends: CPU (generic, NEON, and optimized x86), Metal, CUDA, and Vulkan.

| Runtime | Status |
|---------|--------|
| llama.cpp (CPU, Metal, CUDA, Vulkan) | ✅ Merged upstream, works out of the box |
| MLX (1-bit) | ⏳ Pending upstream: [mlx#3161](https://github.com/ml-explore/mlx/pull/3161); until it merges, use [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) (branch `prism`, built automatically by `setup.sh`) |

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

## Upstream Status for Ternary (Bonsai 1)

Ternary support has landed in mainline [llama.cpp](https://github.com/ggml-org/llama.cpp) for CPU,
Metal, Vulkan and CUDA, so the group-64 `Q2_0` files run on a stock build with no fork needed. The
x86 AVX-512-VNNI optimization is still pending, but x86 already works through the generic CPU path.
MLX 2-bit runs on stock [MLX](https://github.com/ml-explore/mlx).

Published files were deliberately not renamed, since too many things link to them. The result is
three ternary formats on the current repos, and each needs the right binaries:

| File | Format | Runs on |
|------|--------|---------|
| `*-PQ2_0.gguf` | Group size 128 (2.13 bpw), our packing under its own ggml type. **What this demo prefers**: smallest file and usually fastest where the backend is optimized (CUDA, Metal, CPU, ROCm) | This demo / fork binaries `prism-b10658+` |
| `*-Q2_0_g64.gguf` (27B file: `*-Q2_g64.gguf`) | Group size 64 (2.25 bpw). The official llama.cpp `Q2_0` format, widest backend coverage (adds Vulkan and SYCL) | Mainline llama.cpp and fork binaries `prism-b10658+` |
| `*-Q2_0.gguf` (legacy, no `g64`) | ⚠️ **Deprecated.** Pre-migration group-128 files stored under the ggml type id that now belongs to the official group-64 format | Only the old `prism-v5` releases; newer binaries refuse them with an error |

Future releases drop the transitional suffix. The demo's setup scripts download `PQ2_0` where the
backend is optimized for it and the group-64 file otherwise (details:
[community-benchmarks/ternary-bonsai/README.md](community-benchmarks/ternary-bonsai/README.md#available-formats)).

**Speculative decoding: use this demo's binaries.** Since the rebase, dspark rides on mainline llama.cpp's own DSpark implementation ([ggml-org/llama.cpp#25173](https://github.com/ggml-org/llama.cpp/pull/25173)) with fork-side patches on top, and the drafter is the converted `*dspark-dflash*` sidecar (~0.6 GB; the old `*dspark-Q4_1*.gguf` files are the pre-migration packing). Use `BONSAI_SPECULATIVE=1` with this demo's binaries — see [SPECULATIVE.md](SPECULATIVE.md).

To run the smaller ternary models directly on stock `ggml-org/llama.cpp`, use the group-64 files:

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
4. **Downloads models** from HuggingFace (all model repos are public; no token needed)
5. **Downloads pre-built binaries** from the pinned [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10709-9a9394a) (or builds from source if you prefer)
6. **Builds MLX from source** (macOS only): clones our fork, builds it into the venv, installs the ML stack (mlx-lm, torch, transformers)
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
source .venv/bin/activate
./scripts/run_mlx.sh -p "What is the capital of France?"
```

**Tested versions (reproducibility).** The released MLX weights are plain safetensors and need no runtime patches. The 1-bit packs need an MLX build with 1-bit quantization support: the [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) fork, branch `prism`, until [mlx#3161](https://github.com/ml-explore/mlx/pull/3161) merges upstream. The 2-bit ternary packs run on stock MLX. The released 27B packs were validated with:

- Python 3.11
- mlx fork branch `prism` at commit [`88c9c20`](https://github.com/PrismML-Eng/mlx/commit/88c9c205a50f)
- `mlx-lm==0.31.2` (the version `setup.sh` pins)

`setup.sh` builds the fork from the branch tip. To pin the exact validated runtime instead, clone and check out the commit before running setup; setup reuses an existing `./mlx` checkout:

```bash
git clone -b prism https://github.com/PrismML-Eng/mlx.git mlx
git -C mlx checkout 88c9c20
./setup.sh
```

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

#### Tool calling & MCP

The 27B does native OpenAI-style tool calling over the API, and the chat UI has an MCP client with Hugging Face + DeepWiki preconfigured (per-chat opt-in from the MCP selector in the message box, no prompt cost until you turn one on). Details, costs, and how to add your own servers: [TOOLS.md](TOOLS.md).

#### Vision

Upload images in the chat UI (`+` in the message box) or send `image_url` parts over the API; the scripts load the vision projector automatically and downscale very large images on slower backends. Costs, the image-token cap, and OCR tips: [VISION.md](VISION.md).

#### Optional extras

Two experimental, off-by-default features for the llama.cpp chat server:

- **Speculative decoding**: `BONSAI_SPECULATIVE=1` pairs the 27B with its dspark drafter. Measured on an L40S (CUDA): 1.8-2.4x faster decode for the ternary 27B and 1.4-1.75x for the 1-bit 27B, workload-dependent (code/math best). On Apple Silicon (Metal) it only pays off for ternary code/math (~1.2x) and is a net slowdown otherwise, so leave it off on Macs. Needs this demo's binaries. Trade-offs and verification: [SPECULATIVE.md](SPECULATIVE.md).
- **4-bit KV cache**: `BONSAI_KV4=1` cuts KV-cache memory roughly 3.5x for very long contexts, with an optional calibration bias for better quality (`./scripts/make_kv_bias.sh`). Details: [KV-CACHE.md](KV-CACHE.md).
- **Vision projector in RAM**: `BONSAI_MMPROJ_CPU=1` keeps the 27B's vision projector in system RAM instead of VRAM (`--no-mmproj-offload`), freeing ~0.9 GiB of VRAM for KV/context on tight cards. The cost is a slower image prompt (the projector runs on CPU); text-only chat is unaffected.

### Context Size

The 27B models support up to **262,144 tokens** of context. The FP16 KV cache costs 64 KiB per token (~6.3 GiB at 100K), so **100K context fits on many consumer devices even without KV-cache quantization**. The model's hybrid attention keeps the cache small for its size.

The launch scripts pick a **default context sized to your machine's RAM**, from 8K on small machines up to 131K for the 27B on machines with more than 71 GB (roughly 0.5 to 8 GiB of KV cache), so memory use stays predictable. With a bundled CUDA build, GPU offload on, and a single NVIDIA GPU, the default is also capped by the card's total VRAM (8K below 10 GB, 16K below 12 GB, 32K below 16 GB, 64K below 24 GB), since the KV cache then lives in VRAM rather than system RAM. This is a best-effort default, not a guarantee that the model will fit: total VRAM does not reflect what other applications are using, and the cap is skipped with several GPUs, on other backends, and with `BONSAI_NGL=0`. Override with the `BONSAI_CTX` environment variable: pass any number up to 262144, or `0` (the same as leaving it unset) for the automatic RAM-tiered size. To force the model's full training context, pass the explicit number (e.g. `BONSAI_CTX=262144`) — only recommended on machines with plenty of headroom, since the scripts will not silently do this for you.

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

Extra arguments pass straight through to llama.cpp, so `./scripts/run_llama.sh -c 8192 -p "Your prompt"` also works for a one-off context override.

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

All binaries are available from the pinned [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10709-9a9394a), also used by both setup scripts. The latest release may still be missing platform binaries while builds finish.

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

### The model allocates huge memory or the machine freezes at startup

Older revisions defaulted to llama.cpp's `-c 0`, which uses the model's full training context (262K on the 27B) regardless of available memory and could exhaust it on constrained machines. The scripts now always use a RAM-tiered context instead; `BONSAI_CTX=0` maps to that same safe default rather than `-c 0`. If you still hit memory pressure, pin a smaller context:

```bash
BONSAI_CTX=8192 ./scripts/start_llama_server.sh
```

### M5 Mac on macOS 26.2/26.3: Metal compile errors, then out-of-memory

On M5 devices with certain macOS 26 point releases, the Metal tensor-API probe fails to compile at runtime (`ggml_metal_library_init_from_source: error compiling source`) and can leave the GPU in a bad state. This is an ecosystem-wide issue in the OS Metal headers, hitting every ggml-based project. Workaround, keeps full Metal speed and just skips the tensor-API path:

```bash
GGML_METAL_TENSOR_DISABLE=1 ./scripts/run_llama.sh -p "Hello"
```


### Windows setup selects Vulkan or CPU instead of CUDA

**Symptom:** `setup.ps1` reports `[INFO] No GPU toolchain detected. Will use CPU build.` or selects Vulkan, even though `nvidia-smi` runs successfully and detects your NVIDIA GPU.

**Cause:** Older versions of the setup script expected the header `CUDA Version:`. Some newer NVIDIA drivers instead report `CUDA UMD Version:`. The extra `UMD` prevented CUDA detection, causing setup to select another backend.

This can leave you with binaries under `bin\vulkan` or `bin\cpu` rather than `bin\cuda`. On affected Bonsai 2 setups, users reported prompts stalling without processing any tokens instead of producing a clear error.

### CUDA source build runs out of memory or freezes

**Symptom:** `cmake --build` hangs, the system becomes unresponsive, or the build process is killed with an OOM error when building llama.cpp from source with CUDA enabled.

**Cause:** Compiling CUDA kernels is memory-intensive — each parallel compile job can consume several GB of GPU VRAM and/or system RAM. Running `make -j$(nproc)` on a machine with a low-VRAM GPU (< 16 GB) or limited system RAM can exhaust available memory.

**How the build scripts handle this:** `build_cuda_linux.sh` and `build_cuda_windows.ps1` automatically detect the GPU's VRAM before building. If the maximum detected VRAM is less than 16 GB, the scripts cap parallelism at `-j 2` instead of using all logical CPU cores. You will see a message like:

```
Detected GPU VRAM: 8.0 GB (< 16 GB) -- limiting CUDA build to -j 2
```

**Manual override:** If you still encounter OOM errors, reduce parallelism further by editing the build invocation in the relevant script, or close other GPU-heavy applications before building.

### Metal fails to initialize on Apple M5 (macOS 26.2–26.4)

**Symptom:** On M5 Macs, `run_llama.sh` / `start_llama_server.sh` fail with Metal errors and produce no output, e.g.:

```
ggml_metal_library_init_from_source: error compiling source
ggml_metal_device_init: - the tensor API is not supported in this environment - disabling
ggml_metal_synchronize: error: command buffer 0 failed with status 5
```

Pre-M5 Apple Silicon (M1–M4) is not affected — those devices load the embedded, precompiled Metal library and never compile shaders at runtime.

**Cause:** On M5 (and A19) devices, ggml compiles its Metal library from source at runtime to enable the tensor API (Neural Accelerators). Some macOS 26 point releases ship stricter MetalPerformancePrimitives headers whose `static_assert` (bfloat/half type mismatch) breaks that runtime compile. This is an ecosystem-wide issue also seen in [ollama](https://github.com/ollama/ollama/issues/15594) and [whisper.cpp](https://github.com/ggml-org/whisper.cpp/issues/3722); see [#93](https://github.com/PrismML-Eng/Bonsai-demo/issues/93).

**Workaround:** Disable the tensor API so the M5 uses the embedded library like pre-M5 devices — full Metal speed is kept, only the Neural Accelerator prefill boost is lost:

```bash
GGML_METAL_TENSOR_DISABLE=1 ./scripts/run_llama.sh -p "Hello"
GGML_METAL_TENSOR_DISABLE=1 ./scripts/start_llama_server.sh
```

This is much faster than falling back to CPU (`BONSAI_NGL=0`). If out-of-memory errors persist afterwards on lower-memory machines, additionally pin a smaller context, e.g. `-c 16384` (extra args pass through to llama.cpp and override the default).
