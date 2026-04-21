# Community Benchmarks

Benchmark results submitted by the community, organized by model family.

## All Results

Combined view across both model families. See the per-family subfolders below for details, submission templates, and filename conventions.

| Family | Hardware | Backend | 8B PP512 (t/s) | 8B TG128 (t/s) | Details |
|--------|----------|---------|---------------:|---------------:|---------|
| Bonsai (1-bit) | Apple M4 Pro 48 GB | llama.cpp Metal | 487 | 117 | [link](bonsai/metal-m4-pro-48gb-macos.md) |
| Bonsai (1-bit) | NVIDIA DGX Spark (GB10) | llama.cpp CUDA | 3,978 | 159 | [link](bonsai/cuda-gb10-linux.md) |
| Bonsai (1-bit) | AMD Strix Halo 128 GB | llama.cpp Vulkan | 831 | 64 | [link](bonsai/vulkan-strix-halo-128gb-archlinux.md) |
| Bonsai (1-bit) | AMD Strix Halo 128 GB | llama.cpp ROCm HIP | 1,325 | 96 | [link](bonsai/rocm-hip-strix-halo-128gb-archlinux.md) |
| Bonsai (1-bit) | NVIDIA GeForce RTX 3080 10 GB | llama.cpp CUDA | 4,770 | 197 | [link](bonsai/cuda-rtx3080-linux.md) |
| Bonsai (1-bit) | NVIDIA RTX A2000 Laptop (4 GB) | llama.cpp CUDA | 1,387 | 63 | [link](bonsai/cuda-rtxa2000-debian.md) |
| Ternary-Bonsai (1.58-bit) | *coming soon* | | | | |

## Model Families

- **[Bonsai (1-bit)](bonsai/)** — the original 1-bit Bonsai family (8B, 4B, 1.7B) in GGUF and MLX 1-bit formats.
- **[Ternary-Bonsai (1.58-bit)](ternary-bonsai/)** — the ternary Bonsai family (8B, 4B, 1.7B) in GGUF (`Q2_0`) and MLX (2-bit) formats.

Each subfolder has its own README with results, submission templates, and filename conventions.

## How to Submit

1. Run `./setup.sh` to download models and binaries
2. Go into the subfolder for your model family and follow its `README.md`:
   - [bonsai/README.md](bonsai/README.md)
   - [ternary-bonsai/README.md](ternary-bonsai/README.md)
3. Open a PR to this repo with your filled-in file placed inside the appropriate subfolder.
