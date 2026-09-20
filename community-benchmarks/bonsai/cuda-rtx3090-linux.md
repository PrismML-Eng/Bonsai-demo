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
| 27B   | 1479.97 tok/s  |
| 8B    | 5593.02 tok/s |
| 4B    | 8358.98 tok/s |
| 1.7B  | 15407.02 tok/s |


`llama-bench` tg128:

| Model | tokens/second   |
| ----- | ------------ |
| 27B   | 89.23 tok/s  |
| 8B    | 263.32 tok/s |
| 4B    | 358.08 tok/s |
| 1.7B  | 598.58 tok/s |

## llama-bench Results

Run `./setup.sh` first, then find your `llama-bench` binary:
```bash
find bin/ llama.cpp/ -name "llama-bench" -type f 2>/dev/null
```

### Bonsai-27B (the one we most want numbers for!)

```bash
BENCH=bin/cuda/llama-bench
$BENCH -m models/gguf/27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

Device 0: NVIDIA GeForce RTX 3090, compute capability 8.6, VMM: yes, VRAM: 24121 MiB
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1479.97 ± 39.96 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         89.23 ± 0.54 |

build: 9a9394a89 (10709)

### Bonsai-8B

```bash
# GPU (Metal / CUDA / Vulkan / ROCm) — adjust BENCH path:
$BENCH -m models/gguf/8B/*.gguf -ngl 99 -fa 1
```

Device 0: NVIDIA GeForce RTX 3090, compute capability 8.6, VMM: yes, VRAM: 24121 MiB
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           pp512 |     5593.02 ± 302.87 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           tg128 |        263.32 ± 7.70 |

build: 9a9394a89 (10709)

### Bonsai-4B

```bash
$BENCH -m models/gguf/4B/*.gguf -ngl 99 -fa 1
```

Device 0: NVIDIA GeForce RTX 3090, compute capability 8.6, VMM: yes, VRAM: 24121 MiB
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           pp512 |     8358.98 ± 730.62 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           tg128 |        358.08 ± 9.90 |

build: 9a9394a89 (10709)

### Bonsai-1.7B

```bash
$BENCH -m models/gguf/1.7B/*.gguf -ngl 99 -fa 1
```

Device 0: NVIDIA GeForce RTX 3090, compute capability 8.6, VMM: yes, VRAM: 24121 MiB
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           pp512 |   15407.02 ± 2040.87 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           tg128 |       598.58 ± 14.51 |

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
