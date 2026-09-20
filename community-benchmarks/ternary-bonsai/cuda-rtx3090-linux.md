# RTX 3090 — CUDA

## Summary

Benchmarked Ternary-Bonsai model family on CachyOS with: 
- AMD Ryzen 7 3800X
- RTX 3090 (24 GB)
- 32 GB RAM
- Kernel: Linux 7.2.2-1-cachyos

Benchmarked all model sizes, here's the brief results

`llama-bench` pp512:

| Model | tokens/second   |
| ----- | ------------ |
| 27B   | 1477.96 tok/s  |
| 8B    | 1505.82 tok/s |
| 4B    | 5380.10 tok/s |
| 1.7B  | 9283.78 tok/s |


`llama-bench` tg128:

| Model | tokens/second   |
| ----- | ------------ |
| 27B   | 62.98 tok/s  |
| 8B    | 77.75 tok/s |
| 4B    | 230.27 tok/s |
| 1.7B  | 349.25 tok/s |


## llama-bench Results

### Ternary-Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
$BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-PQ2_0.gguf -ngl 99 -fa 1
```
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1477.96 ± 67.38 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         80.49 ± 1.09 |

build: 9a9394a89 (10709)

```bash
# and the official group-64 format (download if setup.sh didn't):
hf download prism-ml/Ternary-Bonsai-27B-GGUF --include "*Q2_g64*" --local-dir models/ternary-gguf/27B
$BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_g64.gguf -ngl 99 -fa 1
```


| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   7.05 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1505.82 ± 45.33 |
| qwen35 27B Q2_0                |   7.05 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         77.75 ± 0.95 |

build: 9a9394a89 (10709)

### Ternary-Bonsai-8B

```bash
# GPU (Metal / CUDA / Vulkan / ROCm) — adjust BENCH path:
BENCH=bin/cuda/llama-bench
$BENCH -m models/ternary-gguf/8B/Ternary-Bonsai-8B-PQ2_0.gguf -ngl 99 -fa 1
hf download prism-ml/Ternary-Bonsai-8B-GGUF --include "*Q2*" --local-dir models/ternary-gguf/8B
$BENCH -m models/ternary-gguf/8B/Ternary-Bonsai-8B-Q2_0_g64.gguf -ngl 99 -fa 1

```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B PQ2_0 - 2.13 bpw (group 128) |   2.03 GiB |     8.19 B | CUDA       |  99 |   1 |           pp512 |     5380.10 ± 283.40 |
| qwen3 8B PQ2_0 - 2.13 bpw (group 128) |   2.03 GiB |     8.19 B | CUDA       |  99 |   1 |           tg128 |        230.27 ± 2.41 |

build: 9a9394a89 (10709)


| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B Q2_0                  |   2.15 GiB |     8.19 B | CUDA       |  99 |   1 |           pp512 |     5888.74 ± 355.12 |
| qwen3 8B Q2_0                  |   2.15 GiB |     8.19 B | CUDA       |  99 |   1 |           tg128 |        242.47 ± 4.34 |

build: 9a9394a89 (10709)

### Ternary-Bonsai-4B

```bash
hf download prism-ml/Ternary-Bonsai-4B-GGUF --include "*Q2*" --local-dir models/ternary-gguf/4B
$BENCH -m models/ternary-gguf/4B/Ternary-Bonsai-4B-PQ2_0.gguf -ngl 99 -fa 1
$BENCH -m models/ternary-gguf/4B/Ternary-Bonsai-4B-Q2_0_g64.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B PQ2_0 - 2.13 bpw (group 128) | 1019.50 MiB |     4.02 B | CUDA       |  99 |   1 |           pp512 |     9283.78 ± 716.87 |
| qwen3 4B PQ2_0 - 2.13 bpw (group 128) | 1019.50 MiB |     4.02 B | CUDA       |  99 |   1 |           tg128 |        349.25 ± 3.27 |

build: 9a9394a89 (10709)


| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B Q2_0                  |   1.05 GiB |     4.02 B | CUDA       |  99 |   1 |           pp512 |    8813.77 ± 2476.47 |
| qwen3 4B Q2_0                  |   1.05 GiB |     4.02 B | CUDA       |  99 |   1 |           tg128 |        345.48 ± 0.71 |

build: 9a9394a89 (10709)

### Ternary-Bonsai-1.7B

```bash
hf download prism-ml/Ternary-Bonsai-1.7B-GGUF --include "*Q2*" --local-dir models/ternary-gguf/1.7B
$BENCH -m models/ternary-gguf/1.7B/Ternary-Bonsai-1.7B-PQ2_0.gguf -ngl 99 -fa 1
$BENCH -m models/ternary-gguf/1.7B/Ternary-Bonsai-1.7B-Q2_0_g64.gguf -ngl 99 -fa 1
```


| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B PQ2_0 - 2.13 bpw (group 128) | 436.16 MiB |     1.72 B | CUDA       |  99 |   1 |           pp512 |   18599.66 ± 2455.78 |
| qwen3 1.7B PQ2_0 - 2.13 bpw (group 128) | 436.16 MiB |     1.72 B | CUDA       |  99 |   1 |           tg128 |        574.72 ± 3.08 |

build: 9a9394a89 (10709)


| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B Q2_0                | 461.79 MiB |     1.72 B | CUDA       |  99 |   1 |           pp512 |   19091.64 ± 2614.61 |
| qwen3 1.7B Q2_0                | 461.79 MiB |     1.72 B | CUDA       |  99 |   1 |           tg128 |        566.00 ± 1.64 |

build: 9a9394a89 (10709)

## Configuration

My CachyOS gaming and home desktop. Nothing tweaked with thermals or power draw.
- Single GPU
- Air cooled CPU
- CUDA 13.3 (no special binaries or downloads needed to run any models in report)

## Notes

Nothing of note

## Hardware

**Linux:**
```bash
lscpu | head -20 && free -h && (nvidia-smi 2>/dev/null || rocminfo 2>/dev/null || vulkaninfo --summary 2>/dev/null || true)
#fish: lscpu | head -20; and free -h; and begin nvidia-smi 2>/dev/null; or rocminfo 2>/dev/null; or vulkaninfo --summary 2>/dev/null; or true; end
```

```
Architecture:                            x86_64
CPU op-mode(s):                          32-bit, 64-bit
Address sizes:                           43 bits physical, 48 bits virtual
Byte Order:                              Little Endian
CPU(s):                                  16
On-line CPU(s) list:                     0-15
Vendor ID:                               AuthenticAMD
Model name:                              AMD Ryzen 7 3800X 8-Core Processor
CPU family:                              23
Model:                                   113
Thread(s) per core:                      2
Core(s) per socket:                      8
Socket(s):                               1
Stepping:                                0
Microcode version:                       0x8701034
Frequency boost:                         enabled
CPU(s) scaling MHz:                      94%
CPU max MHz:                             4560.3242
CPU min MHz:                             576.9090
BogoMIPS:                                7785.54
               total        used        free      shared  buff/cache   available
Mem:            31Gi        12Gi       6.6Gi        47Mi        12Gi        18Gi
Swap:           31Gi        15Gi        15Gi
Sat Sep 19 22:48:02 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 610.57.04              KMD Version: 610.57.04     CUDA UMD Version: 13.3     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 3090        Off |   00000000:0E:00.0  On |                  N/A |
| 53%   44C    P8             51W /  390W |    3447MiB /  24576MiB |     16%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
```
