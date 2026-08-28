# Community Benchmarks

Benchmark results submitted by the community, organized by model. **We are especially looking for Bonsai-27B numbers right now**: any hardware, any backend, five minutes with `llama-bench`. See [How to Submit](#how-to-submit).

## Bonsai-27B

Sorted by decode speed (TG128). The 27B models come in two families: Bonsai (1-bit, `Q1_0`) and Ternary-Bonsai (2-bit). Since the fork's rebase onto current mainline llama.cpp (releases `prism-b10658` and newer), the ternary GGUFs come in **two formats**: `PQ2_0` (our group-128 packing, smallest and usually fastest where supported) and `Q2_0` (the official upstream group-64 format, widest backend coverage). Ternary submissions on new builds should include **both** where possible; the table's ternary numbers use `PQ2_0` unless noted. Optional column: decode speed with the paired DSpark drafter, where the submitter measured it (llama-server via `BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh`; on MLX via community harnesses such as dspark-mlx). Plain `llama-bench` does not exercise the drafter. DSpark numbers measured via `llama-server` with the chat template read lower than single-prompt bare-loop tools (`llama-speculative-simple`) on the same hardware — server per-token overhead plus a harder-to-draft token distribution — so compare like with like; the entry files state which harness was used.

| Family | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | DSpark TG (t/s) | Details |
|--------|----------|---------|------------:|------------:|----------------:|---------|
| Ternary | NVIDIA RTX PRO 6000 Blackwell 96 GB | llama.cpp CUDA | 4,552 | 129.9 | | [link](ternary-bonsai/cuda-rtx-pro-6000-blackwell-linux.md) |
| Bonsai (1-bit) | NVIDIA L40S 48 GB | llama.cpp CUDA | 2,937 | 107.5 | ~169 (1.60x) | [link](bonsai/cuda-l40s-27b-linux.md) |
| Ternary | NVIDIA L40S 48 GB | llama.cpp CUDA | 3,036 | 74.3 | ~150 (2.06x, 2.4x math) | [link](ternary-bonsai/cuda-l40s-linux.md) |
| Ternary | NVIDIA RTX 4070 Ti SUPER 16 GB | llama.cpp CUDA (Windows) | 1,717 | 69.6 | | [link](ternary-bonsai/cuda-rtx4070tisuper-windows.md) |
| Bonsai (1-bit) | Apple M5 Max 48 GB | llama.cpp Metal | 796 | 63.9 | slower on this HW | [link](bonsai/metal-m5-max-48gb-macos.md) |
| Ternary | NVIDIA RTX A5000 24 GB | llama.cpp CUDA | 1,036 | 48.2 | | [link](ternary-bonsai/cuda-rtxa5000-ubuntu.md) |
| Ternary | Apple M5 Max 48 GB | llama.cpp Metal | 816 | 45.8 | ~1.2x code/math only | [link](ternary-bonsai/metal-m5-max-48gb-macos.md) |
| Ternary | NVIDIA RTX 5060 Ti 16 GB | llama.cpp CUDA | 1,029 | 44.4 | ~79 (1.78x) | [link](ternary-bonsai/cuda-rtx5060ti-linux.md) |
| Bonsai (1-bit) | NVIDIA DGX Spark (GB10) | llama.cpp CUDA | 1,003 | 44.1 | no gain on this HW | [link](bonsai/cuda-gb10-27b-linux.md) |
| Ternary | Apple M5 Pro 64 GB | MLX 2-bit | 466 | 29.5 | 34-49 (community dspark-mlx) | [link](ternary-bonsai/mlx-m5-pro-macos.md) |
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

- **[Bonsai (1-bit)](bonsai/)**: the 1-bit Bonsai family (27B, 8B, 4B, 1.7B) in GGUF and MLX 1-bit formats.
- **[Ternary-Bonsai](ternary-bonsai/)**: the ternary Bonsai family (27B, 8B, 4B, 1.7B) in GGUF (`PQ2_0` and `Q2_0` group-64) and MLX (2-bit) formats.

Each subfolder has its own README with results, submission templates, and filename conventions.

## How to Submit

1. Run `./setup.sh` to download models and binaries (`BONSAI_FAMILY=bonsai` for the 1-bit family; the default is ternary)
2. Go into the subfolder for your model family and follow its `README.md`:
   - [bonsai/README.md](bonsai/README.md)
   - [ternary-bonsai/README.md](ternary-bonsai/README.md)
3. Open a PR to this repo with your filled-in file placed inside the appropriate subfolder.
