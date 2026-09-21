# Community Benchmarks

Benchmark results submitted by the community, organized by model. **We are especially looking for Bonsai 2 27B numbers right now**: any hardware, any backend, five minutes with `llama-bench`. See [How to Submit](#how-to-submit).

## Bonsai 2 27B

The current generation (`bonsai2`, the setup default). Results are sorted by TG128;
keep each packing on its own row. These are community measurements on the stated
hardware and build, not controlled comparisons across machines. See the linked reports
for commands, raw output, memory use, and configuration.

| Format | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | Details |
|--------|----------|---------|------------:|------------:|---------|
| `PTQ1_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 1,597 | 86.0 | [link](bonsai2/cuda-rtx4090-windows.md) |
| `PQ2_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 3,285 | 84.9 | [link](bonsai2/cuda-rtx4090-windows.md) |

## Earlier 27B families

Bonsai (1-bit, `Q1_0`) and Ternary-Bonsai (previous generation) results are sorted by
TG128. Ternary rows use `PQ2_0` unless noted; see the
[ternary format guide](ternary-bonsai/README.md#available-formats) for `PQ2_0` and
upstream-format `Q2_0` group-64 submissions.

The optional DSpark column records speculative decoding with a paired drafter.
Plain `llama-bench` does not exercise it. Server and standalone harness results are
not directly comparable; each report should identify its harness and workload.

| Family | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | DSpark TG (t/s) | Details |
|--------|----------|---------|------------:|------------:|----------------:|---------|
| Ternary | NVIDIA RTX PRO 6000 Blackwell 96 GB | llama.cpp CUDA | 4,552 | 129.9 | | [link](ternary-bonsai/cuda-rtx-pro-6000-blackwell-linux.md) |
| Bonsai (1-bit) | NVIDIA L40S 48 GB | llama.cpp CUDA | 2,937 | 107.5 | ~169 (1.60x) | [link](bonsai/cuda-l40s-27b-linux.md) |
| Ternary | NVIDIA L40S 48 GB | llama.cpp CUDA | 3,036 | 74.3 | ~150 (2.06x, 2.4x math) | [link](ternary-bonsai/cuda-l40s-linux.md) |
| Ternary | NVIDIA RTX 4070 Ti SUPER 16 GB | llama.cpp CUDA (Windows) | 1,717 | 69.6 | | [link](ternary-bonsai/cuda-rtx4070tisuper-windows.md) |
| Bonsai (1-bit) | Apple M5 Max 48 GB | llama.cpp Metal | 796 | 63.9 | slower on this HW | [link](bonsai/metal-m5-max-48gb-macos.md) |
| Ternary | NVIDIA RTX A5000 24 GB | llama.cpp CUDA | 1,036 | 48.2 | | [link](ternary-bonsai/cuda-rtxa5000-ubuntu.md) |
| Ternary | Apple M5 Max 48 GB | llama.cpp Metal | 816 | 45.8 | ~1.2x code/math only | [link](ternary-bonsai/metal-m5-max-48gb-macos.md) |
| Bonsai (1-bit) | NVIDIA DGX Spark (GB10) | llama.cpp CUDA | 1,024 | 45.4 | ~96.1 (2.21x, code) | [link](bonsai/cuda-gb10-27b-linux.md) |
| Ternary | NVIDIA RTX 5060 Ti 16 GB | llama.cpp CUDA | 1,029 | 44.4 | ~79 (1.78x) | [link](ternary-bonsai/cuda-rtx5060ti-linux.md) |
| Ternary | Apple M5 Pro 64 GB | MLX 2-bit | 466 | 29.5 | 34-49 (community dspark-mlx) | [link](ternary-bonsai/mlx-m5-pro-macos.md) |
| Ternary | NVIDIA DGX Spark (GB10) | llama.cpp CUDA | 1,005 | 29.2 | ~70.0 (2.45x, code) | [link](ternary-bonsai/cuda-gb10-27b-linux.md) |
| Bonsai (1-bit) | NVIDIA GeForce GTX 1080 Ti 11 GB | llama.cpp CUDA | 285 | 28.3 | | [link](bonsai/cuda-gtx1080ti-linux.md) |
| Ternary | Apple M5 Pro 64 GB | llama.cpp Metal | 130 | 26.5 | | [link](ternary-bonsai/mlx-m5-pro-macos.md) |
| Ternary | Apple M4 Pro 64 GB | MLX 2-bit | 120 | 24.8 | | [link](ternary-bonsai/mlx-m4-pro-64gb-macos.md) |
| Ternary | Apple M4 Pro 64 GB | llama.cpp Metal | 116 | 19.0 | slower on this HW | [link](ternary-bonsai/metal-m4-pro-64gb-macos.md) |
| Ternary | NVIDIA GeForce GTX 1080 Ti 11 GB | llama.cpp CUDA | 278 | 20.5 | | [link](ternary-bonsai/cuda-gtx1080ti-linux.md) |
| Ternary | Apple M4 24 GB | MLX 2-bit | 65.2 | 12.7 | | [link](ternary-bonsai/mlx-m4-24gb-macos.md) |
| Ternary | Apple M3 Pro 18 GB | llama.cpp Metal | 78.6 | 12.6 | | [link](ternary-bonsai/metal-m3-pro-macos.md) |

## 8B and smaller

| Family | Hardware | Backend | 8B PP512 (t/s) | 8B TG128 (t/s) | Details |
|--------|----------|---------|---------------:|---------------:|---------|
| Ternary | NVIDIA RTX 4070 Ti SUPER 16 GB | llama.cpp CUDA (Windows) | 6,675 | 215.7 | [link](ternary-bonsai/cuda-rtx4070tisuper-windows.md) |
| Bonsai (1-bit) | NVIDIA GeForce RTX 3080 10 GB | llama.cpp CUDA | 4,770 | 197 | [link](bonsai/cuda-rtx3080-linux.md) |
| Bonsai (1-bit) | NVIDIA DGX Spark (GB10) | llama.cpp CUDA | 3,978 | 159 | [link](bonsai/cuda-gb10-linux.md) |
| Bonsai (1-bit) | Apple M4 Pro 48 GB | llama.cpp Metal | 487 | 117 | [link](bonsai/metal-m4-pro-48gb-macos.md) |
| Bonsai (1-bit) | NVIDIA GeForce GTX 1080 Ti 11 GB | llama.cpp CUDA | 1,008 | 101.2 | [link](bonsai/cuda-gtx1080ti-linux.md) |
| Bonsai (1-bit) | AMD Strix Halo 128 GB | llama.cpp ROCm HIP | 1,325 | 96 | [link](bonsai/rocm-hip-strix-halo-128gb-archlinux.md) |
| Ternary | NVIDIA GeForce GTX 1080 Ti 11 GB | llama.cpp CUDA | 985 | 68.8 | [link](ternary-bonsai/cuda-gtx1080ti-linux.md) |
| Bonsai (1-bit) | AMD Strix Halo 128 GB | llama.cpp Vulkan | 831 | 64 | [link](bonsai/vulkan-strix-halo-128gb-archlinux.md) |
| Bonsai (1-bit) | NVIDIA RTX A2000 Laptop (4 GB) | llama.cpp CUDA | 1,387 | 63 | [link](bonsai/cuda-rtxa2000-debian.md) |
| Ternary | Apple M3 Pro 18 GB | llama.cpp Metal | 288 | 51.3 | [link](ternary-bonsai/metal-m3-pro-macos.md) |

## Model Families

- **[Bonsai 2](bonsai2/)**: the current generation (27B) in GGUF (`PTQ1_0` and `PQ2_0`) and MLX 2-bit. The GGUF formats require this demo's llama.cpp fork; MLX uses the model's Hadamard-aware runtime.
- **[Bonsai (1-bit)](bonsai/)**: the 1-bit Bonsai family (27B, 8B, 4B, 1.7B) in GGUF and MLX 1-bit formats.
- **[Ternary-Bonsai](ternary-bonsai/)**: the ternary Bonsai family (27B, 8B, 4B, 1.7B) in GGUF (`PQ2_0` and `Q2_0` group-64) and MLX (2-bit) formats.

Each subfolder has its own README with results, submission templates, and filename conventions.

## How to Submit

1. Run `./setup.sh` on macOS/Linux or `.\setup.ps1` in Windows PowerShell to download models and binaries (the default family is Bonsai 2; `BONSAI_FAMILY=ternary` or `BONSAI_FAMILY=bonsai` for the older families)
2. Go into the subfolder for your model family and follow its `README.md`:
   - [bonsai2/README.md](bonsai2/README.md)
   - [bonsai/README.md](bonsai/README.md)
   - [ternary-bonsai/README.md](ternary-bonsai/README.md)
3. Open a PR to this repo with your filled-in file placed inside the appropriate subfolder.
