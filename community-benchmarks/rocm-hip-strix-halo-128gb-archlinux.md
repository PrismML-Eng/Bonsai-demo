# AMD Strix Halo 128 GB — ROCm HIP (Q1_0 Kernel)

## Summary

AMD Ryzen AI Max+ 395 (Strix Halo), Radeon 8060S (gfx1151, RDNA 3.5, 20 CUs, Wave32), 128 GB unified LPDDR5X memory, running CachyOS (Arch Linux) kernel 7.0. Backend: ROCm HIP with custom Q1_0 vec_dot kernel, TheRock ROCm 7.13 from source with native Tensile GEMM kernels for gfx1151. All layers offloaded to GPU (`-ngl 99`).

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|-------------|-------------|
| Bonsai-8B | 1,058 | 22 |
| Bonsai-4B | 1,934 | 29 |
| Bonsai-1.7B | 3,638 | 60 |

## llama-bench Results

### Bonsai-1.7B

```bash
./build-rocm/bin/llama-bench -m ~/models/bonsai/Bonsai-1.7B.gguf -ngl 99 -p 512 -n 128 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | ROCm       |  99 |           pp512 |      3638.24 ± 11.51 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | ROCm       |  99 |           tg128 |         59.85 ± 0.32 |

build: 1e9d771e2 (8768)

### Bonsai-4B

```bash
./build-rocm/bin/llama-bench -m ~/models/bonsai/Bonsai-4B.gguf -ngl 99 -p 512 -n 128 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | ROCm       |  99 |           pp512 |      1934.32 ± 10.26 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | ROCm       |  99 |           tg128 |         28.58 ± 0.00 |

build: 1e9d771e2 (8768)

### Bonsai-8B

```bash
./build-rocm/bin/llama-bench -m ~/models/bonsai/Bonsai-8B.gguf -ngl 99 -p 512 -n 128 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | ROCm       |  99 |           pp512 |       1058.17 ± 2.28 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | ROCm       |  99 |           tg128 |         21.80 ± 0.00 |

build: 1e9d771e2 (8768)

## vs Vulkan (Same Hardware)

| Model | ROCm pp512 | Vulkan pp512 | ROCm tg128 | Vulkan tg128 |
|-------|------------|--------------|------------|--------------|
| Bonsai-1.7B | 3,638 | 3,121 | 60 | 137 |
| Bonsai-4B | 1,934 | 1,401 | 29 | 85 |
| Bonsai-8B | 1,058 | 831 | 22 | 64 |

ROCm prompt processing beats Vulkan (+17-38%). Vulkan decode still faster (optimized compute shaders for generation path).

## Configuration

ROCm HIP backend with custom Q1_0 vec_dot + dequantize kernels added to llama.cpp. TheRock ROCm 7.13 built from source with 55 native Tensile GEMM kernels for gfx1151. All layers offloaded to GPU.

Required environment:
```bash
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export HSA_ENABLE_SDMA=0
export ROCBLAS_USE_HIPBLASLT=1
export HIP_VISIBLE_DEVICES=0
export ROCBLAS_TENSILE_LIBPATH=$HOME/therock/build/math-libs/BLAS/rocBLAS/dist/lib/rocblas/library
```

## Notes

- llama.cpp build: `1e9d771e2 (8768)` with custom Q1_0 HIP kernel patches
- Q1_0 GPU support did not exist in llama.cpp HIP backend before this — added vec_dot, dequantize, type traits, and dispatch
- TheRock (ROCm from source) required for native Tensile GEMM on gfx1151
- Source: https://github.com/stampby/rocm-cpp

## Hardware

```
GPU: Radeon 8060S Graphics (gfx1151)
CUs: 20
Wave Size: 32
VRAM: 63967 MiB (unified with CPU)
CPU: AMD Ryzen AI Max+ 395
Memory: 128 GB LPDDR5X unified
OS: CachyOS (Arch Linux)
Kernel: 7.0.0-1-cachyos
```
