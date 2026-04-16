# NVIDIA DGX Spark (GB10) — CUDA

## Summary

NVIDIA DGX Spark with GB10 GPU (128 GB unified memory), CUDA 13.0 on Ubuntu Linux. All layers offloaded to GPU (`-ngl 99`), flash attention enabled (`-fa 1`).

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|-------------|-------------|
| Bonsai-8B | 3,978 | 159 |
| Bonsai-4B | 6,381 | 212 |
| Bonsai-1.7B | 13,950 | 372 |

## llama-bench Results

### Bonsai-8B

```bash
BENCH=llama.cpp-prismml/build/bin/llama-bench
$BENCH -m models/gguf/8B/Bonsai-8B.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |  1 |           pp512 |     3978.15 ± 103.54 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |  1 |           tg128 |        159.44 ± 1.22 |

build: e2d67422c (8796)

### Bonsai-4B

```bash
$BENCH -m models/gguf/4B/Bonsai-4B.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |  1 |           pp512 |     6381.41 ± 157.17 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |  1 |           tg128 |        212.10 ± 0.42 |

build: e2d67422c (8796)

### Bonsai-1.7B

```bash
$BENCH -m models/gguf/1.7B/Bonsai-1.7B.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |  1 |           pp512 |    13949.73 ± 541.62 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |  1 |           tg128 |        372.06 ± 1.36 |

build: e2d67422c (8796)

## Configuration

CUDA backend with all layers offloaded to GPU. Built PrismML fork from source with `cmake -B build -DGGML_CUDA=ON`.

## Notes

- llama.cpp build: `e2d67422c (8796)` (PrismML fork, built from source)
- DGX Spark uses 128 GB unified LPDDR5X memory shared between CPU and GPU
- NVIDIA driver 580.126.09, CUDA 13.0
- GPU compute capability 12.1 (Blackwell)

## Hardware

```bash
lscpu | head -20 && free -h && nvidia-smi
```

```
Architecture:                            aarch64
CPU op-mode(s):                          64-bit
CPU(s):                                  20
Vendor ID:                               ARM
Model name:                              Cortex-X925 / Cortex-A725
Thread(s) per core:                      1
Core(s) per socket:                      10
Socket(s):                               1
CPU max MHz:                             3900.0000

               total        used        free
Mem:           119Gi       4.4Gi        84Gi

NVIDIA-SMI 580.126.09    Driver Version: 580.126.09    CUDA Version: 13.0
GPU: NVIDIA GB10    Temp: 48C
```
