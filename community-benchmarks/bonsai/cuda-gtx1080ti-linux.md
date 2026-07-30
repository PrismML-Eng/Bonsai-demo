# NVIDIA GeForce GTX 1080 Ti — CUDA

## Summary

GTX 1080 Ti 11 GB (GP102, Pascal sm_61, compute 6.1) + prebuilt CUDA binaries (release `prism-9596`, build `9fcaed763`) on Linux, driver 580.173.02 (CUDA 13.0). All four model sizes fit and were fully GPU-offloaded.

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|------------:|------------:|
| Bonsai-27B | 285 | 28.3 |
| Bonsai-8B | 1,008 | 101.2 |
| Bonsai-4B | 1,721 | 145.8 |
| Bonsai-1.7B | 4,047 | 243.9 |

The 1-bit 27B packs to just 3.53 GiB (~1.125 bpw), leaving ~7.3 GiB of the 11 GB frame buffer free for KV/context — a modern iPhone-class footprint running on a legacy Pascal GPU. For comparison, the ternary (Q2_0) family on the same hardware is in [../ternary-bonsai/cuda-gtx1080ti-linux.md](../ternary-bonsai/cuda-gtx1080ti-linux.md): the 1-bit 27B decodes ~38% faster than ternary (28.3 vs 20.5 t/s) at ~half the weight size, while prefill is ~tied (285 vs 278 t/s) — the expected quality/size/speed trade between the two families. Pascal (sm_61) is a legacy compute capability, so these numbers reflect the prebuilt binaries running on an older-architecture GPU.

## llama-bench Results

### Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/gguf/27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |        284.73 ± 0.56 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         28.26 ± 0.09 |

build: 9fcaed763 (9596)

### Bonsai-8B

```bash
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/gguf/8B/Bonsai-8B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           pp512 |       1007.80 ± 1.95 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           tg128 |        101.15 ± 0.13 |

build: 9fcaed763 (9596)

### Bonsai-4B

```bash
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/gguf/4B/Bonsai-4B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  |  540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           pp512 |       1720.52 ± 6.71 |
| qwen3 4B Q1_0                  |  540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           tg128 |        145.78 ± 0.38 |

build: 9fcaed763 (9596)

### Bonsai-1.7B

```bash
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/gguf/1.7B/Bonsai-1.7B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                |  231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           pp512 |      4047.44 ± 109.27 |
| qwen3 1.7B Q1_0                |  231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           tg128 |        243.88 ± 0.86 |

build: 9fcaed763 (9596)

## Configuration

- Prebuilt CUDA binaries from the Bonsai demo (`bin/cuda/llama-bench`, release `prism-9596`, build `9fcaed763`), default llama-bench settings (f16 KV).
- Stock clocks/power, all 99 layers offloaded to GPU (`-ngl 99`), flash attention on (`-fa 1`).

## Notes

- Driver 580.173.02, CUDA 13.0. Pascal is compute capability 6.1 (sm_61) — the oldest currently-supported CUDA target in these builds; useful as a legacy-architecture data point.
- The 3.53 GiB Q1_0 weights leave ~7.3 GiB of the 11 GiB frame buffer free for KV cache. At FP16 KV (~64 KiB/token) that is room for well over 100K tokens of context on the GPU.
- Vision projector and dspark drafter not loaded (llama-bench measures the bare autoregressive model).

## Hardware

NVIDIA GeForce GTX 1080 Ti 11 GB (GP102, compute capability 6.1), dual-socket Intel Xeon (2 × 10 cores / 40 threads), 125 GiB RAM, Linux.

```text
Architecture:                            x86_64
CPU(s):                                  40
Model name:                              Genuine Intel(R) CPU 0000 @ 2.20GHz
Thread(s) per core:                      2
Core(s) per socket:                      10
Socket(s):                               2

Mem:           125Gi       5.1Gi        68Gi        26Mi        53Gi       120Gi

+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.173.02             Driver Version: 580.173.02     CUDA Version: 13.0     |
|=========================================+========================+======================|
|   0  NVIDIA GeForce GTX 1080 Ti     Off |   00000000:02:00.0 Off |                  N/A |
|  0%   39C    P8             12W /  250W |       3MiB /  11264MiB |      0%      Default |
+-----------------------------------------------------------------------------------------+
```
