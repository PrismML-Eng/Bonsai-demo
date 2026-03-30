# Bonsai Demo

> Check out [prismml.com](https://prismml.com/) for more info, benchmarks, and other demos.
> Browse all models on the [Bonsai HuggingFace collection](https://huggingface.co/collections/prism-ml/bonsai).
> Read the [1-bit Bonsai whitepaper](1-bit-bonsai-8b-whitepaper.pdf) for technical details.

Using this demo you can run Bonsai language models locally on Mac (Metal), Linux/Windows (CUDA).

Three model sizes are available: **8B**, **4B**, and **1.7B**, each in two formats:

- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** (GGUF) — C/C++, runs on Mac (Metal), Linux/Windows (CUDA), and CPU.
- **[MLX](https://github.com/ml-explore/mlx)** (MLX format) — Python, optimized for Apple Silicon.

The required inference kernels are not yet available in upstream llama.cpp or MLX. Pre-built binaries and source code come from our forks:
- **llama.cpp:** [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) — [pre-built binaries](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8194-1179bfc)
- **MLX:** [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) (branch `prism`)

## Models

| Model               | Format | HuggingFace Repo                                                                          |
|---------------------|--------|-------------------------------------------------------------------------------------------|
| Bonsai-8B           | GGUF   | [prism-ml/Bonsai-8B-gguf](https://huggingface.co/prism-ml/Bonsai-8B-gguf)               |
| Bonsai-8B           | MLX    | [prism-ml/Bonsai-8B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-8B-mlx-1bit)       |
| Bonsai-4B           | GGUF   | [prism-ml/Bonsai-4B-gguf](https://huggingface.co/prism-ml/Bonsai-4B-gguf)               |
| Bonsai-4B           | MLX    | [prism-ml/Bonsai-4B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-4B-mlx-1bit)       |
| Bonsai-1.7B         | GGUF   | [prism-ml/Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Bonsai-1.7B-gguf)           |
| Bonsai-1.7B         | MLX    | [prism-ml/Bonsai-1.7B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-1.7B-mlx-1bit)   |

Set `BONSAI_MODEL` to choose which size to download and run (default: `8B`).

---

## Quick Start

### macOS / Linux

```bash
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# (Optional) Choose a model size: 8B (default), 4B, 1.7B, or "all"
export BONSAI_MODEL=8B

# Set your HuggingFace token (required while repos are private)
export PRISM_HF_TOKEN="hf_your_token_here"

# One command does everything: installs deps, downloads models + binaries
./setup.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# (Optional) Choose a model size: 8B (default), 4B, 1.7B, or "all"
$env:BONSAI_MODEL = "8B"

# Set your HuggingFace token (required while repos are private)
$env:PRISM_HF_TOKEN = "hf_your_token_here"

# Run setup
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

### Switching models

You can download multiple sizes and switch between them instantly:

```bash
# download the 4B model
BONSAI_MODEL=4B ./setup.sh          
BONSAI_MODEL=4B ./scripts/run_llama.sh -p "Who are you? Introduce yourself in haiku"

# download all three sizes
BONSAI_MODEL=all ./setup.sh         
```
---

## What `setup.sh` Does

The setup script handles everything for you, even on a fresh machine:

1. **Checks/installs system deps** — Xcode CLT on macOS, build-essential on Linux
2. **Installs [uv](https://docs.astral.sh/uv/)** — fast Python package manager (user-local, not global)
3. **Creates a Python venv** and runs `uv sync` — installs cmake, ninja, huggingface-cli from `pyproject.toml`
4. **Downloads models** from HuggingFace (needs `PRISM_HF_TOKEN` while repos are private)
5. **Downloads pre-built binaries** from [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8194-1179bfc) (or builds from source if you prefer)
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

### Context Size

The 8B model supports up to 65,536 tokens.

By default the scripts pass `-c 0`, which lets llama.cpp's `--fit` automatically size the KV cache to your available memory (no pre-allocation waste). If your build doesn't support `-c 0`, the scripts fall back to a safe value based on system RAM:

*Estimates for Bonsai-8B (weights + KV cache + activations):*

| Fallback Context    | Est. Memory Usage |
|---------------------|-------------------|
| 8,192 tokens        | ~2.5 GB           |
| 32,768 tokens       | ~5.9 GB           |
| 65,536 tokens (max) | ~10.5 GB          |

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

### Mac

```bash
./scripts/build_mac.sh
```

Clones [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp), builds with Metal, outputs to `bin/mac/`.

### Linux (CUDA)

```bash
./scripts/build_cuda_linux.sh
```

Auto-detects CUDA version. Pass `--cuda-path /usr/local/cuda-12.8` to use a specific toolkit.

### Windows (CUDA)

```powershell
.\scripts\build_cuda_windows.ps1
```

Auto-detects CUDA toolkit. Pass `-CudaPath "C:\path\to\cuda"` to use a specific version.
Requires Visual Studio Build Tools (or full Visual Studio) and CUDA toolkit.

---

## llama.cpp Pre-built Binary Downloads

All binaries are available from the [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8194-1179bfc):

| Platform                |
|-------------------------|
| macOS Apple Silicon     |
| Linux x64 (CUDA 12.4)  |
| Linux x64 (CUDA 12.8)  |
| Linux x64 (CUDA 13.1)  |
| Windows x64 (CUDA 12.4) |
| Windows x64 (CUDA 13.1) |

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
│   ├── run_mlx.sh                  # MLX inference
│   ├── mlx_generate.py             # MLX Python script
│   ├── start_llama_server.sh       # llama.cpp server (port 8080)
│   ├── start_mlx_server.sh         # MLX server (port 8081)
│   ├── start_openwebui.sh          # Open WebUI + auto-starts backends
│   ├── build_mac.sh                # Build llama.cpp for Mac
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
│   ├── mac/                        # macOS binaries
│   └── cuda/                       # CUDA binaries
├── mlx/                            # ← cloned by setup (macOS)
└── .venv/                          # ← created by setup
```

Items marked with ← are created at setup time and excluded from git.
