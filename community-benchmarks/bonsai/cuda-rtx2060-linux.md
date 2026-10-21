# RTX 2060 SUPER 8 GB — CUDA (Ubuntu / WSL)

## Summary

RTX 2060 SUPER 8 GB + CUDA 13.3 on Ubuntu 22.04 under WSL

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|-------------|-------------|
| Bonsai-27B | 494 | 32.7 |
| Bonsai-8B | 1,862 | 105.9 |
| Bonsai-4B | 3,081 | 176.0 |
| Bonsai-1.7B | 6,356 | 308.8 |

### Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
$BENCH -m models/gguf/27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |       493.96 ± 11.51 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         32.73 ± 0.14 |

build: 9a9394a89 (10709)

### Bonsai-8B

```bash
$BENCH -m models/gguf/8B/*.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           pp512 |      1862.25 ± 75.06 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           tg128 |        105.89 ± 0.28 |

build: 9a9394a89 (10709)

### Bonsai-4B

```bash
$BENCH -m models/gguf/4B/*.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           pp512 |     3081.03 ± 212.69 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           tg128 |        175.96 ± 0.69 |

build: 9a9394a89 (10709)

### Bonsai-1.7B

```bash
$BENCH -m models/gguf/1.7B/*.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           pp512 |     6355.98 ± 952.69 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           tg128 |        308.82 ± 3.37 |

build: 9a9394a89 (10709)

## Hardware

```
Architecture:                       x86_64
CPU op-mode(s):                     32-bit, 64-bit
Address sizes:                      40 bits physical, 48 bits virtual
Byte Order:                         Little Endian
CPU(s):                             24
On-line CPU(s) list:                0-23
Vendor ID:                          GenuineIntel
Model name:                         Intel(R) Xeon(R) CPU           X5650  @ 2.67GHz
CPU family:                         6
Model:                              44
Thread(s) per core:                 2
Core(s) per socket:                 12
Socket(s):                          1
Stepping:                           2
BogoMIPS:                           5319.99
Flags:                              fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon rep_good nopl xtopology cpuid pni pclmulqdq ssse3 cx16 pdcm pcid sse4_1 sse4_2 popcnt aes hypervisor lahf_lm pti ssbd ibrs ibpb stibp flush_l1d arch_capabilities
Hypervisor vendor:                  Microsoft
Virtualization type:                full
L1d cache:                          384 KiB (12 instances)
L1i cache:                          384 KiB (12 instances)
               total        used        free      shared  buff/cache   available
Mem:            15Gi       666Mi       1.2Gi       2.0Mi        13Gi        14Gi
Swap:          4.0Gi       4.0Mi       4.0Gi
Mon Sep 21 11:15:30 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 610.43.02              KMD Version: 610.47        CUDA UMD Version: 13.3     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 2060 ...    On  |   00000000:0F:00.0  On |                  N/A |
| 43%   41C    P8             13W /  184W |     383MiB /   8192MiB |      1%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A              33      G   /Xwayland                             N/A      |
+-----------------------------------------------------------------------------------------+
```
