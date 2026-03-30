# Bonsai Demo

Run the Bonsai-8B language model locally on Mac (Metal), Linux/Windows (CUDA).

The model is provided in two formats for the two popular open-source inference engines:

- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** (GGUF) — C/C++, runs on Mac (Metal), Linux/Windows (CUDA), and CPU.
- **[MLX](https://github.com/ml-explore/mlx)** (MLX format) — Python, optimized for Apple Silicon.

The required inference kernels are not yet available in upstream llama.cpp or MLX. Pre-built binaries and source code come from our forks:
- **llama.cpp:** [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) — [pre-built binaries](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8194-1179bfc)
- **MLX:** [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) (branch `prism`)

## Models

| Model | HuggingFace Repo | Size |
|-------|-----------------|------|
| Bonsai-8B (GGUF) | [prism-ml/Bonsai-8B-gguf](https://huggingface.co/prism-ml/Bonsai-8B-gguf) | ~1.1 GB |
| Bonsai-8B (MLX) | [prism-ml/Bonsai-8B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-8B-mlx-1bit) | ~1.2 GB |

---

## Quick Start

### macOS / Linux

```bash
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# Set your HuggingFace token (required for private model repos)
export PRISM_HF_TOKEN="hf_your_token_here"

# One command does everything: installs deps, downloads models + binaries
./setup.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo

# Set your HuggingFace token
$env:PRISM_HF_TOKEN = "hf_your_token_here"

# Run setup
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

---

## What `setup.sh` Does

The setup script handles everything for you, even on a fresh machine:

1. **Checks/installs system deps** — Xcode CLT on macOS, build-essential on Linux
2. **Installs [uv](https://docs.astral.sh/uv/)** — fast Python package manager (user-local, not global)
3. **Creates a Python venv** and runs `uv sync` — installs cmake, ninja, huggingface-cli from `pyproject.toml`
4. **Downloads models** from HuggingFace (needs `PRISM_HF_TOKEN`)
5. **Downloads pre-built binaries** from [GitHub Release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b8194-1179bfc) (or builds from source if you prefer)
6. **Builds MLX from source** (macOS only) — clones our fork, then `uv sync --extra mlx` for the full ML stack

Re-running `setup.sh` is safe — it skips already-completed steps.

---

## Running the Model

### llama.cpp (Mac / Linux — auto-detects platform)

```bash
./scripts/run_llama.sh -p "What is the capital of France?"
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
```

### Context Size

The model supports up to 65,536 tokens.

By default the scripts pass `-c 0`, which lets llama.cpp's `--fit` automatically size the KV cache to your available memory (no pre-allocation waste). If your build doesn't support `-c 0`, the scripts fall back to a safe value based on system RAM:

| System RAM | Fallback context | Weights + KV cache + activations |
|-----------|-----------------|----------------------------------|
| 8 GB | 8,192 tokens | ~2.5 GB |
| 16 GB | 32,768 tokens | ~5.9 GB |
| 24 GB+ | 65,536 tokens (max) | ~10.5 GB |

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

| Platform | Asset |
|----------|-------|
| macOS Apple Silicon | `llama-prism-b8194-1179bfc-bin-macos-arm64.tar.gz` |
| Linux x64 (CUDA 12.4) | `llama-prism-b8194-1179bfc-bin-linux-cuda-12.4-x64.tar.gz` |
| Linux x64 (CUDA 12.8) | `llama-prism-b8194-1179bfc-bin-linux-cuda-12.8-x64.tar.gz` |
| Linux x64 (CUDA 13.1) | `llama-prism-b8194-1179bfc-bin-linux-cuda-13.1-x64.tar.gz` |
| Windows x64 (CUDA 12.4) | `llama-prism-b8194-1179bfc-bin-win-cuda-12.4-x64.zip` |
| Windows x64 (CUDA 13.1) | `llama-prism-b8194-1179bfc-bin-win-cuda-13.1-x64.zip` |

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
│   ├── common.sh                   # Shared helpers
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
│   ├── gguf/                       # GGUF model files
│   └── Bonsai-8B-mlx/             # MLX model (macOS)
├── bin/                            # ← downloaded or built by setup
│   ├── mac/                        # macOS binaries
│   └── cuda/                       # CUDA binaries
├── mlx/                            # ← cloned by setup (macOS)
└── .venv/                          # ← created by setup
```

Items marked with ← are created at setup time and excluded from git.
