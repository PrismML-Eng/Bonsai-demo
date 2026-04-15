# Community Benchmarks

Benchmark results submitted by the community running Bonsai models on their own hardware.

## How to Submit

1. Run `./setup.sh` to download models and binaries
2. Pick a template and copy it to a new file:
   - **llama.cpp** (CPU, Metal, CUDA, Vulkan, ROCm): [TEMPLATE-llama-cpp.md](TEMPLATE-llama-cpp.md)
   - **MLX** (Apple Silicon only): [TEMPLATE-mlx.md](TEMPLATE-mlx.md)

   Use this naming convention:

   **`<backend>-<hardware>-<os>.md`** (lowercase, dashes for spaces)

   | Backend | Example filename |
   |---------|-----------------|
   | CPU (x86) | `cpu-i9-14900k-linux.md` |
   | CPU (ARM) | `cpu-m4-pro-macos.md` |
   | CUDA | `cuda-rtx4090-linux.md` |
   | Metal | `metal-m2-ultra-macos.md` |
   | Vulkan | `vulkan-rx7900xtx-linux.md` |
   | ROCm/HIP | `rocm-mi300x-linux.md` |
   | MLX | `mlx-m4-pro-macos.md` |

3. Follow the instructions in the template to run benchmarks and fill in results
4. Open a PR to this repo

All three model sizes (8B, 4B, 1.7B) are preferred. Skip any that don't fit in memory or are too slow.

## Results

<!-- Add links to submitted benchmarks below, grouped by backend -->

*No submissions yet. Be the first!*
