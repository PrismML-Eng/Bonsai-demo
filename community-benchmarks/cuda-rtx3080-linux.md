# NVIDIA GeForce RTX 3080 — CUDA

## Summary

NVIDIA GeForce RTX 3080 (10 GB VRAM) with AMD Ryzen 7 5800X (8-core, 32 GB DDR4), CUDA 13.0 on Linux. All layers offloaded to GPU (`-ngl 99`), flash attention enabled (`-fa 1`).

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|-------------|-------------|
| Bonsai-8B | 4,770 | 197 |
| Bonsai-4B | 7,379 | 256 |
| Bonsai-1.7B | 15,004 | 423 |

## llama-bench Results

### Bonsai-8B

```bash
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=bin/cuda $BENCH -m models/gguf/8B/*.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0_g128             |   1.07 GiB |     8.19 B | CUDA       |  99 |  1 |           pp512 |     4770.01 ± 211.32 |
| qwen3 8B Q1_0_g128             |   1.07 GiB |     8.19 B | CUDA       |  99 |  1 |           tg128 |        197.38 ± 0.25 |

build: ba7e817ee (8201)

### Bonsai-4B

```bash
LD_LIBRARY_PATH=bin/cuda $BENCH -m models/gguf/4B/*.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 4B Q1_0_g128             | 540.09 MiB |     4.02 B | CUDA       |  99 |  1 |           pp512 |     7378.98 ± 419.70 |
| qwen3 4B Q1_0_g128             | 540.09 MiB |     4.02 B | CUDA       |  99 |  1 |           tg128 |        255.61 ± 0.57 |

build: ba7e817ee (8201)

### Bonsai-1.7B

```bash
LD_LIBRARY_PATH=bin/cuda $BENCH -m models/gguf/1.7B/*.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 1.7B Q1_0_g128           | 231.13 MiB |     1.72 B | CUDA       |  99 |  1 |           pp512 |   15004.06 ± 1029.73 |
| qwen3 1.7B Q1_0_g128           | 231.13 MiB |     1.72 B | CUDA       |  99 |  1 |           tg128 |        422.86 ± 1.50 |

build: ba7e817ee (8201)

## Configuration

CUDA backend with all layers offloaded to GPU. Used pre-built binaries from `bin/cuda/` (included via `setup.sh`).

## Notes

- llama.cpp build: `ba7e817ee (8201)`
- NVIDIA driver 580.126.09, CUDA 13.0
- GPU compute capability 8.6 (Ampere)
- GPU was at 39C idle before benchmark, fan at 0% (semi-passive cooling)
- All three model sizes tested (8B, 4B, 1.7B)

## Hardware

```bash
lscpu | head -20 && free -h && nvidia-smi
```

```
Architecture:                            x86_64
CPU op-mode(s):                          32-bit, 64-bit
Byte Order:                              Little Endian
CPU(s):                                  16
Vendor ID:                               AuthenticAMD
Model name:                              AMD Ryzen 7 5800X 8-Core Processor
Thread(s) per core:                      2
Core(s) per socket:                      8
Socket(s):                               1
CPU max MHz:                             4853.5850

               total        used        free
Mem:            31Gi       4.9Gi        12Gi
Swap:           14Gi          0B        14Gi

NVIDIA-SMI 580.126.09    Driver Version: 580.126.09    CUDA Version: 13.0
GPU: NVIDIA GeForce RTX 3080    10240 MiB    Temp: 39C
```
