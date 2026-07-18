# Community Benchmarks

Benchmark results submitted by the community, organized by model. **We are especially looking for Bonsai-27B numbers right now**: any hardware, any backend, five minutes with `llama-bench`. See [How to Submit](#how-to-submit).

## Bonsai-27B

The 27B models come in two families: Bonsai (1-bit, `Q1_0`) and Ternary-Bonsai (`Q2_0`). Optional column: decode speed with the paired DSpark drafter, where the submitter measured it (llama-server via `BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh`; on MLX via community harnesses such as dspark-mlx). Plain `llama-bench` does not exercise the drafter.

| Family | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | DSpark TG (t/s) | Details |
|--------|----------|---------|------------:|------------:|----------------:|---------|
| Ternary | NVIDIA RTX A5000 24 GB | llama.cpp CUDA | 1,036 | 48.2 | | [link](ternary-bonsai/cuda-rtxa5000-ubuntu.md) |
| Ternary | NVIDIA RTX 5060 Ti 16 GB | llama.cpp CUDA | 1,029 | 44.4 | ~79 (1.78x) | [link](ternary-bonsai/cuda-rtx5060ti-linux.md) |
| Bonsai (1-bit) | NVIDIA DGX Spark (GB10) | llama.cpp CUDA | 1,003 | 44.1 | no gain on this HW | [link](bonsai/cuda-gb10-27b-linux.md) |
| Ternary | Apple M5 Pro 64 GB | MLX 2-bit | 466 | 29.5 | 34-49 (community dspark-mlx) | [link](ternary-bonsai/mlx-m5-pro-macos.md) |
| Ternary | Apple M5 Pro 64 GB | llama.cpp Metal | 130 | 26.5 | | [link](ternary-bonsai/mlx-m5-pro-macos.md) |
| Ternary | Apple M3 Pro 18 GB | llama.cpp Metal | 78.6 | 12.6 | | [link](ternary-bonsai/metal-m3-pro-macos.md) |

## 8B and smaller

| Family | Hardware | Backend | 8B PP512 (t/s) | 8B TG128 (t/s) | Details |
|--------|----------|---------|---------------:|---------------:|---------|
| Bonsai (1-bit) | Apple M4 Pro 48 GB | llama.cpp Metal | 487 | 117 | [link](bonsai/metal-m4-pro-48gb-macos.md) |
| Bonsai (1-bit) | NVIDIA DGX Spark (GB10) | llama.cpp CUDA | 3,978 | 159 | [link](bonsai/cuda-gb10-linux.md) |
| Bonsai (1-bit) | AMD Strix Halo 128 GB | llama.cpp Vulkan | 831 | 64 | [link](bonsai/vulkan-strix-halo-128gb-archlinux.md) |
| Bonsai (1-bit) | AMD Strix Halo 128 GB | llama.cpp ROCm HIP | 1,325 | 96 | [link](bonsai/rocm-hip-strix-halo-128gb-archlinux.md) |
| Bonsai (1-bit) | NVIDIA GeForce RTX 3080 10 GB | llama.cpp CUDA | 4,770 | 197 | [link](bonsai/cuda-rtx3080-linux.md) |
| Bonsai (1-bit) | NVIDIA RTX A2000 Laptop (4 GB) | llama.cpp CUDA | 1,387 | 63 | [link](bonsai/cuda-rtxa2000-debian.md) |
| Ternary | Apple M3 Pro 18 GB | llama.cpp Metal | 288 | 51.3 | [link](ternary-bonsai/metal-m3-pro-macos.md) |

## Model Families

- **[Bonsai (1-bit)](bonsai/)**: the 1-bit Bonsai family (27B, 8B, 4B, 1.7B) in GGUF and MLX 1-bit formats.
- **[Ternary-Bonsai](ternary-bonsai/)**: the ternary Bonsai family (27B, 8B, 4B, 1.7B) in GGUF (`Q2_0`) and MLX (2-bit) formats.

Each subfolder has its own README with results, submission templates, and filename conventions.

## How to Submit

1. Run `./setup.sh` to download models and binaries (`BONSAI_FAMILY=bonsai` for the 1-bit family; the default is ternary)
2. Go into the subfolder for your model family and follow its `README.md`:
   - [bonsai/README.md](bonsai/README.md)
   - [ternary-bonsai/README.md](ternary-bonsai/README.md)
3. Open a PR to this repo with your filled-in file placed inside the appropriate subfolder.
