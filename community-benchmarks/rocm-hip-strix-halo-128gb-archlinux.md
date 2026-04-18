# AMD Strix Halo 128 GB — ROCm HIP (PrismML prism branch + TheRock)

## Summary

AMD Ryzen AI Max+ 395 (Strix Halo), Radeon 8060S (gfx1151, RDNA 3.5, 20 WGPs / 40 CUs, Wave32), 128 GB unified LPDDR5X memory, running CachyOS (Arch Linux) kernel 7.0. Backend: ROCm HIP using PrismML prism branch with Q1_0 DP4A kernel, compiled with TheRock LLVM (ROCm 7.13 from source) for native gfx1151 + Tensile GEMM. All layers offloaded to GPU (`-ngl 99`).

| Model | Quant | Size | pp512 (t/s) | tg128 (t/s) |
|-------|-------|------|-------------|-------------|
| Bonsai-1.7B | Q1_0 | 231 MB | **5,001** | 231 |
| Bonsai-4B | Q1_0 | 540 MB | 2,125 | 126 |
| Bonsai-8B | Q1_0 | 1.07 GB | 1,325 | 96 |
| BitNet-2B-4T | Q1_0 | 538 MB | 3,652 | 120 |
| BitNet-2B-4T | TQ1_0 | 1.02 GB | 282 | 50 |
| Qwen3-Coder-Next 80B-A3B | IQ1_S | 17.6 GB | 662 | 51 |
| Llama-4-Scout 17Bx16E | IQ1_S | 27.2 GB | 326 | 21 |

Bonsai-1.7B at Q1_0 breaks 5,000 tok/s prompt on a consumer APU. 80B MoE sustains 51 tok/s generation and 108B sustains 21 tok/s — both in 128 GB unified memory with no swap.

## TheRock 7.13 Uplift

Second run against TheRock ROCm 7.13 built fresh with the unified `dist/rocm` layout and `ROCBLAS_USE_HIPBLASLT=1` — every Bonsai/BitNet shape got faster:

| Model | pp512 prior | pp512 new | Δpp | tg128 prior | tg128 new | Δtg |
|---|---:|---:|---:|---:|---:|---:|
| Bonsai-1.7B | 4,127 | **5,001** | **+21%** | 230 | 231 | ~same |
| Bonsai-4B | 2,009 | 2,125 | +6% | 125 | 126 | ~same |
| Bonsai-8B | 1,269 | 1,325 | +4% | 94 | 96 | +2% |
| BitNet-2B-4T Q1_0 | 3,030 | 3,652 | **+21%** | 110 | 120 | +9% |

## llama-bench Results

### Bonsai-1.7B (Q1_0)

```bash
./build-rocm/bin/llama-bench -m ~/models/bonsai/Bonsai-1.7B.gguf -ngl 99 -p 512 -n 128 -r 3
```

| model | size | params | backend | ngl | test | t/s |
|---|---:|---:|---|---:|---:|---:|
| qwen3 1.7B Q1_0 | 231.13 MiB | 1.72 B | ROCm | 99 | pp512 | 5001.15 ± 38.23 |
| qwen3 1.7B Q1_0 | 231.13 MiB | 1.72 B | ROCm | 99 | tg128 |  230.90 ± 0.82 |

build: e2d6742

### Bonsai-4B (Q1_0)

| model | size | params | backend | ngl | test | t/s |
|---|---:|---:|---|---:|---:|---:|
| qwen3 4B Q1_0 | 540.09 MiB | 4.02 B | ROCm | 99 | pp512 | 2124.87 ± 1.78 |
| qwen3 4B Q1_0 | 540.09 MiB | 4.02 B | ROCm | 99 | tg128 |  125.64 ± 0.31 |

### Bonsai-8B (Q1_0)

| model | size | params | backend | ngl | test | t/s |
|---|---:|---:|---|---:|---:|---:|
| qwen3 8B Q1_0 | 1.07 GiB | 8.19 B | ROCm | 99 | pp512 | 1324.54 ± 4.49 |
| qwen3 8B Q1_0 | 1.07 GiB | 8.19 B | ROCm | 99 | tg128 |   96.08 ± 0.13 |

### BitNet-2B-4T (Q1_0)

| model | size | params | backend | ngl | test | t/s |
|---|---:|---:|---|---:|---:|---:|
| bitnet 2B Q1_0 | 538.03 MiB | 2.41 B | ROCm | 99 | pp512 | 3651.88 ± 14.76 |
| bitnet 2B Q1_0 | 538.03 MiB | 2.41 B | ROCm | 99 | tg128 |  120.22 ± 3.33 |

### BitNet-2B-4T (TQ1_0, 1.69 bpw ternary)

| model | size | params | backend | ngl | test | t/s |
|---|---:|---:|---|---:|---:|---:|
| bitnet 2B TQ1_0 | 1.02 GiB | 2.41 B | ROCm | 99 | pp512 |  281.59 ± 0.97 |
| bitnet 2B TQ1_0 | 1.02 GiB | 2.41 B | ROCm | 99 | tg128 |   49.69 ± 0.04 |

### Qwen3-Coder-Next 80B-A3B (IQ1_S, 1.5625 bpw)

| model | size | params | backend | ngl | test | t/s |
|---|---:|---:|---|---:|---:|---:|
| qwen3next 80B.A3B IQ1_S | 17.64 GiB | 79.67 B | ROCm | 99 | pp512 | 661.56 ± 5.06 |
| qwen3next 80B.A3B IQ1_S | 17.64 GiB | 79.67 B | ROCm | 99 | tg128 |  50.81 ± 0.04 |

### Llama-4-Scout 17Bx16E (IQ1_S, 1.5625 bpw)

| model | size | params | backend | ngl | test | t/s |
|---|---:|---:|---|---:|---:|---:|
| llama4 17Bx16E Scout IQ1_S | 27.24 GiB | 107.77 B | ROCm | 99 | pp512 | 325.67 ± 0.69 |
| llama4 17Bx16E Scout IQ1_S | 27.24 GiB | 107.77 B | ROCm | 99 | tg128 |  21.32 ± 0.01 |

## vs Vulkan (Same Hardware, Same Binary)

Fresh head-to-head against the same commit (PrismML-Eng prism branch, `e2d6742`) built twice — once with `GGML_HIP=ON`, once with `GGML_VULKAN=ON`. No cross-version comparisons.

| Model | ROCm pp512 | Vulkan pp512 | Δ pp | ROCm tg128 | Vulkan tg128 | Δ tg |
|-------|-----------:|-------------:|-----:|-----------:|-------------:|-----:|
| Bonsai-1.7B | 5,001 | 4,667 | **ROCm +7%** | 231 | 349 | **Vulkan +51%** |
| Bonsai-4B | 2,125 | 1,698 | **ROCm +25%** | 126 | 187 | **Vulkan +48%** |
| Bonsai-8B | 1,325 | 1,020 | **ROCm +30%** | 96 | 120 | **Vulkan +26%** |
| BitNet-2B-4T Q1_0 | 3,652 | 3,221 | **ROCm +13%** | 120 | 146 | **Vulkan +22%** |
| Qwen3-Coder-Next 80B-A3B IQ1_S | 662 | 731 | Vulkan +10% | 51 | 67 | Vulkan +31% |
| Llama-4-Scout 17Bx16E IQ1_S | 326 | 312 | ROCm +5% | 21 | 24 | Vulkan +15% |

**Honest read, not marketing:** ROCm wins prompt processing on every Bonsai / BitNet shape thanks to the Q1_0 DP4A kernel in the prism branch. Vulkan wins token generation across the board — its scalar GEMV path stays leaner than ROCm's for decode. On the 80B MoE, Vulkan leads both axes.

Practical guidance: pick ROCm when prompt dominates (agentic workflows, long-context prefill, RAG); pick Vulkan for pure chat/streaming where tg throughput is the user-visible latency.

## vs Metal M4 Pro (Apple Silicon)

| Model | ROCm gfx1151 pp512 | Metal M4 Pro pp512 | ROCm tg128 | Metal tg128 |
|-------|-------------------:|-------------------:|-----------:|------------:|
| Bonsai-1.7B | 5,001 | 2,236 | 231 | 308 |
| Bonsai-4B | 2,125 | 888 | 126 | 178 |
| Bonsai-8B | 1,325 | 487 | 96 | 117 |

ROCm prompt processing is now 2.2–2.7× faster than M4 Pro on Bonsai. M4 Pro generation still leads on Bonsai-1.7B and Bonsai-8B (higher memory bandwidth per CU).

## Configuration

PrismML prism branch of llama.cpp (`e2d6742`) with the Q1_0 DP4A kernel. Compiled with TheRock LLVM for native gfx1151. TheRock ROCm 7.13 built from source targets `gfx1151` only (~3h 50m total on a 32-core build). The unified distribution staged under `dist/rocm/` is the single runtime prefix used at load time.

```bash
# Paths (TheRock unified dist layout)
THEROCK=$HOME/therock/build/dist/rocm

# Compiler
CMAKE_HIP_COMPILER=$THEROCK/lib/llvm/bin/clang++

# Environment
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export HSA_ENABLE_SDMA=0
export ROCBLAS_USE_HIPBLASLT=1
export HIP_VISIBLE_DEVICES=0
export LD_LIBRARY_PATH=$THEROCK/lib:/opt/rocm/lib
export ROCBLAS_TENSILE_LIBPATH=$THEROCK/lib/rocblas/library
```

## How to Replicate

```bash
# 1. Build TheRock from source for your GPU target
git clone https://github.com/ROCm/TheRock.git therock && cd therock
git submodule update --init --recursive
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DTHEROCK_AMDGPU_TARGETS=gfx1151 \
    -DTHEROCK_DIST_AMDGPU_FAMILIES=gfx115X-all \
    -DTHEROCK_ENABLE_BLAS=ON
cmake --build build --parallel $(nproc)

# 2. Build PrismML llama.cpp with ROCm, pointing at TheRock's unified dist
export THEROCK=$HOME/therock/build/dist/rocm
git clone https://github.com/PrismML-Eng/llama.cpp.git && cd llama.cpp
git checkout prism
cmake -B build-rocm -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151 \
    -DCMAKE_HIP_COMPILER=$THEROCK/lib/llvm/bin/clang++ \
    -DCMAKE_C_COMPILER=$THEROCK/lib/llvm/bin/clang \
    -DCMAKE_CXX_COMPILER=$THEROCK/lib/llvm/bin/clang++ \
    -DCMAKE_PREFIX_PATH=$THEROCK -DROCM_PATH=$THEROCK
cmake --build build-rocm --parallel $(nproc) --target llama-bench

# 3. Run
export HSA_OVERRIDE_GFX_VERSION=11.5.1 HSA_ENABLE_SDMA=0 HIP_VISIBLE_DEVICES=0
export ROCBLAS_USE_HIPBLASLT=1
export LD_LIBRARY_PATH=$THEROCK/lib:/opt/rocm/lib
export ROCBLAS_TENSILE_LIBPATH=$THEROCK/lib/rocblas/library
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
