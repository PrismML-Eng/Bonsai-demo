# AMD Strix Halo 128 GB — ROCm HIP (PrismML prism branch + TheRock)

## Summary

AMD Ryzen AI Max+ 395 (Strix Halo), Radeon 8060S (gfx1151, RDNA 3.5, 20 WGPs / 40 CUs, Wave32), 128 GB unified LPDDR5X memory, running CachyOS (Arch Linux) kernel 7.0. Backend: ROCm HIP using PrismML prism branch with Q1_0 DP4A kernel, compiled with TheRock LLVM (ROCm 7.13 from source) for native gfx1151 + Tensile GEMM. All layers offloaded to GPU (`-ngl 99`).

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|-------------|-------------|
| Bonsai-8B | 1,269 | 94 |
| Bonsai-4B | 2,009 | 125 |
| Bonsai-1.7B | 4,127 | 230 |

## llama-bench Results

### Bonsai-1.7B

```bash
./build-rocm/bin/llama-bench -m ~/models/bonsai/Bonsai-1.7B.gguf -ngl 99 -p 512 -n 128 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | ROCm       |  99 |           pp512 |      4126.63 ± 30.55 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | ROCm       |  99 |           tg128 |        230.33 ± 0.52 |

build: e2d67422c (8796)

### Bonsai-4B

```bash
./build-rocm/bin/llama-bench -m ~/models/bonsai/Bonsai-4B.gguf -ngl 99 -p 512 -n 128 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | ROCm       |  99 |           pp512 |      2009.43 ± 44.68 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | ROCm       |  99 |           tg128 |        125.04 ± 1.37 |

build: e2d67422c (8796)

### Bonsai-8B

```bash
./build-rocm/bin/llama-bench -m ~/models/bonsai/Bonsai-8B.gguf -ngl 99 -p 512 -n 128 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | ROCm       |  99 |           pp512 |       1269.30 ± 3.31 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | ROCm       |  99 |           tg128 |         93.97 ± 0.10 |

build: e2d67422c (8796)

## vs Vulkan (Same Hardware, PrismML Vulkan fork)

| Model | ROCm pp512 | Vulkan pp512 | Delta | ROCm tg128 | Vulkan tg128 | Delta |
|-------|------------|--------------|-------|------------|--------------|-------|
| Bonsai-1.7B | 4,127 | 3,121 | +32% | 230 | 137 | +68% |
| Bonsai-4B | 2,009 | 1,401 | +43% | 125 | 85 | +47% |
| Bonsai-8B | 1,269 | 831 | +53% | 94 | 64 | +47% |

ROCm beats Vulkan on both prompt AND generation across all models.

## vs Metal M4 Pro (Apple Silicon)

| Model | ROCm gfx1151 pp512 | Metal M4 Pro pp512 | ROCm tg128 | Metal tg128 |
|-------|--------------------|--------------------|------------|-------------|
| Bonsai-1.7B | 4,127 | 2,236 | 230 | 308 |
| Bonsai-4B | 2,009 | 888 | 125 | 178 |
| Bonsai-8B | 1,269 | 487 | 94 | 117 |

ROCm prompt processing is 1.8-2.6x faster than M4 Pro. M4 Pro generation still faster (higher memory bandwidth per CU).

## Configuration

PrismML prism branch of llama.cpp (`e2d67422c`, build 8796) with Q1_0 DP4A kernel. Compiled with TheRock LLVM for native gfx1151. TheRock ROCm 7.13 built from source with 55 native Tensile GEMM kernels.

```bash
# Compiler
CMAKE_HIP_COMPILER=$HOME/therock/build/compiler/amd-llvm/dist/lib/llvm/bin/clang++

# Environment
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export HSA_ENABLE_SDMA=0
export ROCBLAS_USE_HIPBLASLT=1
export HIP_VISIBLE_DEVICES=0
export LD_LIBRARY_PATH=$HOME/therock/build/math-libs/BLAS/rocBLAS/dist/lib:$LD_LIBRARY_PATH
export ROCBLAS_TENSILE_LIBPATH=$HOME/therock/build/math-libs/BLAS/rocBLAS/dist/lib/rocblas/library
```

## How to Replicate

```bash
# 1. Build TheRock from source for your GPU target
git clone https://github.com/ROCm/TheRock.git && cd TheRock
git submodule update --init --recursive
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DTHEROCK_AMDGPU_TARGETS=gfx1151 \
    -DTHEROCK_ENABLE_BLAS=ON
cmake --build build --parallel $(nproc)

# 2. Build PrismML llama.cpp with ROCm
git clone https://github.com/PrismML-Eng/llama.cpp.git && cd llama.cpp
git checkout prism
cmake -B build-rocm -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151 \
    -DCMAKE_HIP_COMPILER=$HOME/therock/build/compiler/amd-llvm/dist/lib/llvm/bin/clang++ \
    -DCMAKE_C_COMPILER=$HOME/therock/build/compiler/amd-llvm/dist/lib/llvm/bin/clang \
    -DCMAKE_CXX_COMPILER=$HOME/therock/build/compiler/amd-llvm/dist/lib/llvm/bin/clang++
cmake --build build-rocm --parallel $(nproc) --target llama-bench

# 3. Run
export HSA_OVERRIDE_GFX_VERSION=11.5.1 HSA_ENABLE_SDMA=0 HIP_VISIBLE_DEVICES=0
export LD_LIBRARY_PATH=$HOME/therock/build/math-libs/BLAS/rocBLAS/dist/lib:/opt/rocm/lib
export ROCBLAS_TENSILE_LIBPATH=$HOME/therock/build/math-libs/BLAS/rocBLAS/dist/lib/rocblas/library
./build-rocm/bin/llama-bench -m Bonsai-1.7B.gguf -ngl 99 -p 512 -n 128 -r 3
```

Full build guide including GCC 15 patches: https://github.com/stampby/rocm-cpp

## Hardware

```
GPU: Radeon 8060S Graphics (gfx1151)
CUs: 40 (20 WGPs — HIP reports multiProcessorCount as WGP count on RDNA)
Wave Size: 32
VRAM: 63967 MiB (unified with CPU)
CPU: AMD Ryzen AI Max+ 395
Memory: 128 GB LPDDR5X unified
OS: CachyOS (Arch Linux)
Kernel: 7.0.0-1-cachyos
```
