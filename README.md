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
  <a href="https://huggingface.co/collections/prism-ml/bonsai">Bonsai (1-bit)</a> ·
  <a href="https://huggingface.co/collections/prism-ml/ternary-bonsai">Ternary-Bonsai (1.58-bit)</a>
  &nbsp;|&nbsp;
  <b>Whitepapers:</b>
  <a href="1-bit-bonsai-8b-whitepaper.pdf">1-bit Bonsai 8B</a> ·
  <a href="ternary-bonsai-8b-whitepaper.pdf">Ternary-Bonsai 8B</a>
</p>

<p align="center">
  <b>Other Demos:</b>
  <a href="https://huggingface.co/spaces/prism-ml/Bonsai-demo">Bonsai {1, 1.58}-bit GPU Demo</a> ·
  <a href="https://huggingface.co/spaces/webml-community/bonsai-webgpu">Bonsai WebGPU</a> ·
  <a href="https://huggingface.co/spaces/webml-community/bonsai-ternary-webgpu">Ternary-Bonsai WebGPU</a> ·
  <a href="https://colab.research.google.com/drive/1EzyAaQ2nwDv_1X0jaC5XiVC3ZREg9bdG?usp=sharing">Google Colab Notebook</a>
</p>

---


Using this demo repository you can run **Bonsai** (1-bit) and **Ternary-Bonsai** language models locally on Mac (Metal), Linux/Windows (CUDA, Vulkan, ROCm), or CPU.

## Upstream Status for 1-bit (Q1_0)

Q1_0 support for CPU, Metal, CUDA, and Vulkan backends is already merged into upstream [llama.cpp](https://github.com/ggml-org/llama.cpp). Additional backends (optimized x86 CPU, AMD) are pending. In the meantime, our fork provides a more complete set of backends in one place:
- **llama.cpp:** [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) — [pre-built binaries](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8846-d104cf1)
- **MLX:** [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) (branch `prism`)

| Backend | Status | PR |
|---------|--------|----|
| CPU (generic) | ✅ Merged | [#21273](https://github.com/ggml-org/llama.cpp/pull/21273) |
| Metal | ✅ Merged | [#21528](https://github.com/ggml-org/llama.cpp/pull/21528) |
| CUDA | ✅ Merged | [#21629](https://github.com/ggml-org/llama.cpp/pull/21629) |
| Vulkan | ✅ Merged | [#21539](https://github.com/ggml-org/llama.cpp/pull/21539) (community contribution) |
| CPU (optimized x86) |  ✅ Merged | [#21636](https://github.com/ggml-org/llama.cpp/pull/21636) |
| MLX | ⏳ Pending | [mlx#3161](https://github.com/ml-explore/mlx/pull/3161) |

## Upstream Status for 1.58-bit

`Q2_0` is the format we currently use to pack ternary weights (~1.58 bits of information stored in 2 bits). It's a hardware-friendly choice: 2-bit alignment maps cleanly onto Metal and CUDA quantization paths and unlocks fast accelerated kernels, at the cost of being larger than a tight ternary packing.

More compact ternary formats are TBD. llama.cpp already has `TQ1_0` and `TQ2_0` formats which are conceptually close, but they use group size 256 while Bonsai uses group size 128 so the existing TQ formats don't fit Bonsai weights exactly.

`Q2_0` kernels for ternary inference are in our [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) fork (`prism` branch); upstream PRs are coming next. MLX 2-bit is already supported today via [MLX](https://github.com/ml-explore/mlx) (no fork needed).

| Backend | Status | PR |
|---------|--------|----|
| CPU (NEON / generic) | `prism` fork | [9f31ffca](https://github.com/PrismML-Eng/llama.cpp/commit/9f31ffca); PR coming soon |
| Metal | `prism` fork | [0eed5340](https://github.com/PrismML-Eng/llama.cpp/commit/0eed5340); PR coming soon |
| CUDA | `prism` fork | [e380897e](https://github.com/PrismML-Eng/llama.cpp/commit/e380897e); PR coming soon |
| CPU (optimized x86) | ⏳ TBD | — |
| Vulkan | ⏳ TBD | — |
| ROCm / HIP | ⏳ TBD | — |
| MLX (2-bit) | Already supported in stock [MLX](https://github.com/ml-explore/mlx) | - |

## Benchmarks

See [community-benchmarks/](community-benchmarks/) for results on different hardware and templates to submit your own.

## Models

Two model families are available, each in sizes **8B**, **4B**, and **1.7B**.

<p align="center">
  <img src="./assets/frontier.svg" width="700" alt="Bonsai accuracy vs model size frontier">
</p>

### Bonsai (1-bit)

Available in GGUF (llama.cpp) and MLX 1-bit formats.

| Model               | Format | HuggingFace Repo                                                                          |
|---------------------|--------|-------------------------------------------------------------------------------------------|
| Bonsai-8B           | GGUF   | [prism-ml/Bonsai-8B-gguf](https://huggingface.co/prism-ml/Bonsai-8B-gguf)               |
| Bonsai-8B           | MLX    | [prism-ml/Bonsai-8B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-8B-mlx-1bit)       |
| Bonsai-4B           | GGUF   | [prism-ml/Bonsai-4B-gguf](https://huggingface.co/prism-ml/Bonsai-4B-gguf)               |
| Bonsai-4B           | MLX    | [prism-ml/Bonsai-4B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-4B-mlx-1bit)       |
| Bonsai-1.7B         | GGUF   | [prism-ml/Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Bonsai-1.7B-gguf)           |
| Bonsai-1.7B         | MLX    | [prism-ml/Bonsai-1.7B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-1.7B-mlx-1bit)   |

Set `BONSAI_MODEL` to choose which size to download and run (default: `8B`).

### Ternary-Bonsai (1.58-bit)

Available in GGUF (`Q2_0`) and MLX (2-bit) formats. See the [Ternary-Bonsai HF collection](https://huggingface.co/collections/prism-ml/ternary-bonsai) and the [whitepaper](ternary-bonsai-8b-whitepaper.pdf).

| Model                  | Format        | HuggingFace Repo                                                                                        |
|------------------------|---------------|---------------------------------------------------------------------------------------------------------|
| Ternary-Bonsai-8B      | GGUF          | [prism-ml/Ternary-Bonsai-8B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-gguf)               |
| Ternary-Bonsai-8B      | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-8B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit)       |
| Ternary-Bonsai-4B      | GGUF          | [prism-ml/Ternary-Bonsai-4B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf)               |
| Ternary-Bonsai-4B      | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-4B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-mlx-2bit)       |
| Ternary-Bonsai-1.7B    | GGUF          | [prism-ml/Ternary-Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf)           |
| Ternary-Bonsai-1.7B    | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-1.7B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-mlx-2bit)   |

Set `BONSAI_FAMILY=ternary` to download and run this family (default family is `bonsai`).

### Environment variables

Both variables are optional. **If you set neither, the default is `Bonsai-8B` (1-bit, 8 billion parameters)** — that's what plain `./setup.sh` downloads and runs. They're read by `setup.sh`, `setup.ps1`, `download_models.sh`, and every `run_*` / `start_*` script (Linux, macOS, and Windows).

| Variable        | Default  | Valid values                   | Purpose |
|-----------------|----------|--------------------------------|---------|
| `BONSAI_FAMILY` | `bonsai` | `bonsai`, `ternary`, `all`     | Model family. `bonsai` = 1-bit Bonsai; `ternary` = 1.58-bit Ternary-Bonsai. `all` expands to both families (setup/download only). |
| `BONSAI_MODEL`  | `8B`     | `8B`, `4B`, `1.7B`, `all`      | Model size. `all` expands to all three sizes (setup/download only). |

`all` is only valid for `setup.sh` / `setup.ps1` / `download_models.sh` — the run/server scripts need a concrete family/size.

Combine them freely:

```bash
./setup.sh                                                  # Bonsai-8B (default)
BONSAI_MODEL=1.7B ./setup.sh                                # Bonsai-1.7B
BONSAI_FAMILY=ternary ./setup.sh                            # Ternary-Bonsai-8B
BONSAI_FAMILY=ternary BONSAI_MODEL=4B ./setup.sh            # Ternary-Bonsai-4B
BONSAI_MODEL=all ./setup.sh                                 # All 3 Bonsai sizes
BONSAI_FAMILY=all BONSAI_MODEL=all ./setup.sh               # Full matrix (6 downloads)
```

---

## Quick Start

### macOS / Linux

```bash
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# (Optional) Choose a model size: 8B (default), 4B, or 1.7B
export BONSAI_MODEL=8B

# One command does everything: installs deps, downloads models + binaries
./setup.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# (Optional) Choose a model size: 8B (default), 4B, or 1.7B
$env:BONSAI_MODEL = "8B"

# Run setup
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

### Switching families and sizes

You can switch between 1-bit (default) and Ternary (1.58-bit) families, and different model sizes instantly:

```bash
# run Ternary-Bonsai 4B
BONSAI_FAMILY=ternary BONSAI_MODEL=4B ./scripts/download_models.sh
BONSAI_FAMILY=ternary BONSAI_MODEL=4B ./scripts/run_llama.sh -p "Who are you?"
```

for Windows:
```powershell
$env:BONSAI_FAMILY="ternary"; $env:BONSAI_MODEL="4B"
.\setup.ps1
.\scripts\run_llama.ps1 -p "Who are you?"
```

---

## What `setup.sh` Does

The setup script handles everything for you, even on a fresh machine:

1. **Checks/installs system deps** — Xcode CLT on macOS, build-essential on Linux
2. **Installs [uv](https://docs.astral.sh/uv/)** — fast Python package manager (user-local, not global)
3. **Creates a Python venv** and runs `uv sync` — installs cmake, ninja, huggingface-cli from `pyproject.toml`
4. **Downloads models** from HuggingFace (needs `PRISM_HF_TOKEN` while repos are private)
5. **Downloads pre-built binaries** from [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8846-d104cf1) (or builds from source if you prefer)
6. **Builds MLX from source** (macOS only) — clones our fork, then `uv sync --extra mlx` for the full ML stack

Re-running `setup.sh` is safe — it skips already-completed steps.

---

## Running the Model

All run scripts respect `BONSAI_MODEL` (default `8B`). Set it to run a different size:

### llama.cpp (Mac / Linux — auto-detects platform)

```bash
./scripts/run_llama.sh -p "What is the capital of France?"

# Run a different model size
BONSAI_MODEL=4B ./scripts/run_llama.sh -p "Who are you? Introduce yourself in haiku"
```

### llama.cpp (Windows PowerShell)

```powershell
.\scripts\run_llama.ps1 -p "What is the capital of France?"

# Run a different model size
$env:BONSAI_MODEL = "4B"
.\scripts\run_llama.ps1 -p "Who are you? Introduce yourself in haiku"
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

### Context Size

The 8B model supports up to 65,536 tokens.

By default the scripts pass `-c 0`, which lets llama.cpp's `--fit` automatically size the KV cache to your available memory (no pre-allocation waste). If your build doesn't support `-c 0`, the scripts fall back to a safe value based on system RAM:

*Estimates for Bonsai-8B (weights + KV cache + activations):*

| Context Size        | Est. Memory Usage |
|---------------------|-------------------|
| 8,192 tokens        | ~2.5 GB           |
| 32,768 tokens       | ~5.9 GB           |
| 65,536 tokens       | ~10.5 GB          |

Override with: `./scripts/run_llama.sh -c 8192 -p "Your prompt"`

---

## Open WebUI (Optional)

[Open WebUI](https://github.com/open-webui/open-webui) provides a ChatGPT-like browser interface.
It auto-starts the backend servers if they're not already running. Ctrl+C stops everything.

```bash
# Install (heavy — separate from base deps)
source .venv/bin/activate
uv pip install open-webui

# One command — starts backends + opens http://localhost:9090
./scripts/start_openwebui.sh
```

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

All binaries are available from the [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8846-d104cf1):

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
│   ├── build_mac.sh                # Build llama.cpp for Mac
│   ├── build_cpu_linux.sh          # Build llama.cpp for Linux (CPU only)
│   ├── build_cuda_linux.sh         # Build llama.cpp for Linux CUDA
│   └── build_cuda_windows.ps1      # Build llama.cpp for Windows CUDA
├── models/                         # ← downloaded by setup
│   ├── gguf/
│   │   ├── 8B/                     # GGUF 8B model
│   │   ├── 4B/                     # GGUF 4B model
│   │   └── 1.7B/                   # GGUF 1.7B model
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
