# NVIDIA GeForce GTX 1080 Ti — CUDA

## Summary

GTX 1080 Ti 11 GB (GP102, Pascal sm_61, compute 6.1) + prebuilt CUDA binaries (release `prism-9596`, build `9fcaed763`) on Linux, driver 580.173.02 (CUDA 13.0). All four model sizes fit and were fully GPU-offloaded.

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|------------:|------------:|
| Ternary-Bonsai-27B | 278 | 20.5 |
| Ternary-Bonsai-8B | 985 | 68.8 |
| Ternary-Bonsai-4B | 1,679 | 97.4 |
| Ternary-Bonsai-1.7B | 4,025 | 169.9 |

The 6.66 GiB ternary 27B weights fit comfortably in the 11 GB frame buffer with ~4.4 GiB to spare for KV/context — notable because a conventional Q4_K_M of the same 27B base (15.4 GiB) would not fit this card at all. Pascal (sm_61) is a legacy compute capability, so these numbers reflect the prebuilt binaries running on an older-architecture GPU. The 1-bit Bonsai family on the same hardware is in [../bonsai/cuda-gtx1080ti-linux.md](../bonsai/cuda-gtx1080ti-linux.md).

## llama-bench Results

### Ternary-Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |        278.47 ± 0.69 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         20.54 ± 0.09 |

build: 9fcaed763 (9596)

### Ternary-Bonsai-8B

```bash
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/ternary-gguf/8B/Ternary-Bonsai-8B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B Q2_0                  |   2.03 GiB |     8.19 B | CUDA       |  99 |   1 |           pp512 |        985.44 ± 4.82 |
| qwen3 8B Q2_0                  |   2.03 GiB |     8.19 B | CUDA       |  99 |   1 |           tg128 |         68.84 ± 0.06 |

build: 9fcaed763 (9596)

### Ternary-Bonsai-4B

```bash
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/ternary-gguf/4B/Ternary-Bonsai-4B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B Q2_0                  | 1019.50 MiB |     4.02 B | CUDA       |  99 |   1 |           pp512 |       1679.21 ± 4.05 |
| qwen3 4B Q2_0                  | 1019.50 MiB |     4.02 B | CUDA       |  99 |   1 |           tg128 |         97.39 ± 0.34 |

build: 9fcaed763 (9596)

### Ternary-Bonsai-1.7B

```bash
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/ternary-gguf/1.7B/Ternary-Bonsai-1.7B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B Q2_0                |  436.16 MiB |     1.72 B | CUDA       |  99 |   1 |           pp512 |      4025.07 ± 27.06 |
| qwen3 1.7B Q2_0                |  436.16 MiB |     1.72 B | CUDA       |  99 |   1 |           tg128 |        169.92 ± 0.14 |

build: 9fcaed763 (9596)

## Configuration

- Prebuilt CUDA binaries from the Bonsai demo (`bin/cuda/llama-bench`, release `prism-9596`, build `9fcaed763`), default llama-bench settings (f16 KV).
- Stock clocks/power, all 99 layers offloaded to GPU (`-ngl 99`), flash attention on (`-fa 1`).

## Notes

- Driver 580.173.02, CUDA 13.0. Pascal is compute capability 6.1 (sm_61) — the oldest currently-supported CUDA target in these builds; useful as a legacy-architecture data point.
- The 6.66 GiB Q2_0 weights leave ~4.4 GiB of the 11 GiB frame buffer free for KV cache. At FP16 KV (~64 KiB/token) that is room for roughly ~70K tokens of context on the GPU before spilling to system RAM; `BONSAI_KV4=1` (q4 KV) would roughly triple that headroom.
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
