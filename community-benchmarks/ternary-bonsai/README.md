# Ternary-Bonsai Community Benchmarks

Benchmark results submitted by the community running [Ternary-Bonsai](https://huggingface.co/collections/prism-ml/ternary-bonsai) models on their own hardware.

## Results

### Ternary-Bonsai-27B

| Hardware | Backend | PP512 (t/s) | TG128 (t/s) | DSpark TG (t/s) | Details |
|----------|---------|------------:|------------:|----------------:|---------|
| NVIDIA RTX A5000 24 GB | llama.cpp CUDA | 1,036 | 48.2 | | [link](cuda-rtxa5000-ubuntu.md) |
| NVIDIA L40S 48 GB | llama.cpp CUDA | 2,881 | 70.1 | ~103 (1.76x, code) | [link](cuda-l40s-linux.md) |
| NVIDIA RTX 5060 Ti 16 GB | llama.cpp CUDA | 1,029 | 44.4 | ~79 (1.78x) | [link](cuda-rtx5060ti-linux.md) |
| Apple M5 Pro 64 GB | MLX 2-bit | 466 | 29.5 | 34-49 (community dspark-mlx) | [link](mlx-m5-pro-macos.md) |
| Apple M5 Pro 64 GB | llama.cpp Metal | 130 | 26.5 | | [link](mlx-m5-pro-macos.md) |

### 8B and smaller

No submissions yet; be the first!

| Hardware | Backend | 8B PP512 (t/s) | 8B TG128 (t/s) | Details |
|----------|---------|---------------:|---------------:|---------|
| | | | | |

## Available Formats

- **GGUF** (`Q2_0`):
  - [prism-ml/Ternary-Bonsai-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf)
  - [prism-ml/Ternary-Bonsai-8B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-gguf)
  - [prism-ml/Ternary-Bonsai-4B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf)
  - [prism-ml/Ternary-Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf)
- **MLX (2-bit)**:
  - [prism-ml/Ternary-Bonsai-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-mlx-2bit)
  - [prism-ml/Ternary-Bonsai-8B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit)
  - [prism-ml/Ternary-Bonsai-4B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-mlx-2bit)
  - [prism-ml/Ternary-Bonsai-1.7B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-mlx-2bit)

## How to Submit

1. Run `BONSAI_FAMILY=ternary ./setup.sh` to download models and binaries
2. Pick a template and copy it to a new file:
   - **llama.cpp** (CPU, Metal, CUDA, Vulkan, ROCm): [TERNARY-TEMPLATE-llama-cpp.md](TERNARY-TEMPLATE-llama-cpp.md)
   - **MLX (2-bit)** (Apple Silicon only): [TERNARY-TEMPLATE-mlx.md](TERNARY-TEMPLATE-mlx.md)

   Use this naming convention:

   **`<backend>-<hardware>-<os>.md`** (lowercase, dashes for spaces)

   | Backend | Example filename |
   |---------|-----------------|
   | MLX | `mlx-m4-pro-macos.md` |
   | CUDA | `cuda-rtx4090-linux.md` |
   | Metal | `metal-m2-ultra-macos.md` |
   | Vulkan | `vulkan-rx7900xtx-linux.md` |
   | ROCm/HIP | `rocm-mi300x-linux.md` |
   | CPU (x86) | `cpu-i9-14900k-linux.md` |
   | CPU (ARM) | `cpu-m4-pro-macos.md` |

3. Follow the instructions in the template to run benchmarks and fill in results
4. Open a PR to this repo

All three model sizes (8B, 4B, 1.7B) are preferred. Skip any that don't fit in memory or are too slow.
