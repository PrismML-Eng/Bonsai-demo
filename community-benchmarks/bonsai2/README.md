# Bonsai 2 Community Benchmarks

Benchmark results submitted by the community running
[Bonsai 2 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) on their own hardware.

## Results

### Bonsai-2-27B

| Band | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | Details |
|------|----------|---------|------------:|------------:|---------|
| `PQ2_0` | NVIDIA RTX 5080 16 GB | llama.cpp CUDA (Windows) | 1,688 | 86.3 | [link](cuda-rtx5080-16gb-windows.md) |
| `PTQ1_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 1,597 | 86.0 | [link](cuda-rtx4090-windows.md) |
| `PQ2_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 3,285 | 84.9 | [link](cuda-rtx4090-windows.md) |
| `PTQ1_0` | NVIDIA RTX 5080 16 GB | llama.cpp CUDA (Windows) | 896 | 84.6 | [link](cuda-rtx5080-16gb-windows.md) |
| `PQ2_0` | NVIDIA RTX 3090 Ti 24 GB | llama.cpp CUDA (Linux) | 1,552 | 81.6 | [link](cuda-rtx3090ti-linux.md) |
| `PTQ1_0` | NVIDIA RTX 3090 Ti 24 GB | llama.cpp CUDA (Linux) | 805 | 67.7 | [link](cuda-rtx3090ti-linux.md) |
| `PQ2_0` (community MTP file, plain inference) | NVIDIA RTX 5070 Ti Laptop 12 GB | llama.cpp CUDA (Windows) | 1,135 | 49.0 | [link](cuda-rtx5070ti-laptop-windows.md) |
| `PQ2_0` (MTP bundle, plain inference) | AMD Radeon RX 9070 XT 16 GB | llama.cpp ROCm/HIP (Proxmox) | 1,258 | 48.64 | [link](rocm-hip-rx9070xt-proxmox.md) |
| `PQ2_0` | AMD Radeon RX 9070 XT 16 GB | llama.cpp ROCm/HIP (Proxmox) | 1,259 | 48.53 | [link](rocm-hip-rx9070xt-proxmox.md) |
| `PTQ1_0` | NVIDIA RTX 5070 Ti Laptop 12 GB | llama.cpp CUDA (Windows) | 527 | 49.0 | [link](cuda-rtx5070ti-laptop-windows.md) |
| `PQ2_0` | AMD Radeon RX 7800 XT 16 GB | llama.cpp ROCm/HIP | 316.3 | 46.8 | [link](rocm-hip-rx7800xt-fedora44.md) |
| `PQ2_0` | NVIDIA Tesla V100-SXM2 16 GB | llama.cpp CUDA (Windows) | 798 | 46.0 | [link](cuda-tesla-v100-windows.md) |
| `PQ2_0` | AMD Radeon RX 6800 XT 16 GB | llama.cpp ROCm/HIP (Windows) | 266.4 | 44.9 | [link](rocm-hip-rx6800xt-windows.md) |
| `PQ2_0` | NVIDIA RTX 3070 8 GB | llama.cpp CUDA (Windows) | 838.9 | 43.7 | [link](cuda-rtx3070-8gb-windows.md) |
| `PTQ1_0` | NVIDIA Tesla V100-SXM2 16 GB | llama.cpp CUDA (Windows) | 852 | 34.3 | [link](cuda-tesla-v100-windows.md) |
| `PQ2_0` | Apple M3 Max 36 GB | llama.cpp Metal | 162.2 | 24.3 | [link](metal-m3-max-36gb-macos.md) |
| `PQ2_0` | AMD BC-250 16 GB UMA | llama.cpp Vulkan (Linux, local patches) | 142.58 | 24.11 | [link](vulkan-bc250-linux.md) |
| `PTQ1_0` | Apple M3 Max 36 GB | llama.cpp Metal | 136.8 | 21.9 | [link](metal-m3-max-36gb-macos.md) |
| `PQ2_0` | Apple M4 Pro 64 GB | llama.cpp Metal | 126.9 | 20.5 | [link](metal-m4-pro-64gb-macos.md) |
| `PTQ1_0` | Apple M4 Pro 64 GB | llama.cpp Metal | 98.6 | 17.3 | [link](metal-m4-pro-64gb-macos.md) |
| `2-bit` | Apple M4 Pro 64 GB | MLX (mlx_lm 0.31.3) | 97.9 | 18.9 | [link](metal-m4-pro-64gb-macos.md) |

## How to Submit

1. Run `./setup.sh` on macOS/Linux or `.\setup.ps1` in Windows PowerShell.
   The default family is Bonsai 2; setup downloads `PQ2_0` and the required fork binaries.
   For `PTQ1_0`, download it from the model repository above and pass its path to
   `llama-bench -m` (`BONSAI_MODEL` selects a size, not a file path).
   The development [Q2_0 file](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf-dev/blob/main/Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf) is also welcome for benchmarking via `-m`.
   It uses the official llama.cpp `Q2_0` format but **currently requires our fork**
   for Bonsai 2's Hadamard transform support. Upstream support is pending our PRs.
2. Copy [TEMPLATE-llama-cpp.md](TEMPLATE-llama-cpp.md) to
   `<backend>-<hardware>-<os>.md` here (lowercase, dashes). Keep tested formats in
   the same machine report, with separate commands and raw results for each.
3. Include the exact model filename, binary release or commit, hardware, OS,
   driver/backend version, and benchmark command. `PQ2_0`, `PTQ1_0`, and development `Q2_0` results are welcome;
   one is enough if that is what you tested. Note any skipped or unsupported runs.
4. Add a row per tested packing to the table above and the
   [Bonsai 2 table in the main index](../README.md#bonsai-2-27b), then open a PR.

Use pp512/tg128 for the summary tables. Preserve raw output (including variation)
in the report. Keep different builds or settings labeled separately.

MLX submissions are also welcome in this folder. Identify the model, runtime versions,
harness, and prompt/generation lengths. Only put matching pp512/tg128 measurements
in those columns. Keep server, long-context, speculative decoding, and vision or
quality checks in separate labeled sections, with their commands and workloads.
