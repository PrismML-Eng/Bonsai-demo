# Laptop RTX A2000 — CUDA / CPU

## Summary

Laptop Thinkpad P15 Gen2
NVIDIA RTX A2000 Laptop GPU (4 GB VRAM) with Intel Core i7-11800H (8-core, 16 threads, 32 GB DDR4 3200 MHz),
CUDA 13.2 on Debian 13. GPU: all layers offloaded (`-ngl 99`), flash attention enabled (`-fa 1`). 

CPU comparison included for reference.
There is no significant performance difference on the CPU beyond 7 threads, with no noticeable benefit from hyperthreading.
The threads column is not displayed when using -t 8 (number of CPU cores).

| Model        | pp512 GPU (t/s) | tg128 GPU (t/s) | pp512 CPU (t/s) | tg128 CPU (t/s) |
|-------------|----------------:|----------------:|----------------:|----------------:|
| Bonsai-8B   | 1,387           | 63              | 1,063           | 21              |
| Bonsai-4B   | 2,375           | 70              | 1,620           | 37              |
| Bonsai-1.7B | 5,064           | 129             | 3,183           | 85              |

## llama-bench Results

Run `./setup.sh` first, then find your `llama-bench` binary:
```bash
find bin/ llama.cpp/ -name "llama-bench" -type f 2>/dev/null
```

### Bonsai-8B

```bash
# GPU (Debian + CUDA prebuilt binary):
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=bin/cuda $BENCH -m models/gguf/8B/*.gguf -ngl 99 -fa 1
```

```bash
$BENCH -m models/gguf/8B/*.gguf -ngl 99 -fa 1  
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |  1 |           pp512 |      1387.23 ± 61.40 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |  1 |           tg128 |         63.22 ± 1.23 |

build: e2d67422c (8796)

CPU only 11th Gen Intel(R) Core(TM) i7-11800H @ 2.30GHz
```bash
$BENCH -m models/gguf/8B/*.gguf -ngl 0 -fa 1 -t $(nproc)  
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ------: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |      16 |  1 |           pp512 |      1063.34 ± 12.41 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |      16 |  1 |           tg128 |         21.05 ± 0.34 |

build: e2d67422c (8796)

```bash
$BENCH -m models/gguf/8B/*.gguf -ngl 0 -fa 1 -t 8 
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |  1 |           pp512 |       1060.83 ± 8.77 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |  1 |           tg128 |         21.96 ± 0.23 |

build: e2d67422c (8796)

```bash
$BENCH -m models/gguf/8B/*.gguf -ngl 0 -fa 1 -t 7
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ------: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |       7 |  1 |           pp512 |       1055.88 ± 9.40 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |       7 |  1 |           tg128 |         19.20 ± 0.11 |

build: e2d67422c (8796)

```bash
$BENCH -m models/gguf/8B/*.gguf -ngl 0 -fa 1 -t 6
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ------: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |       6 |  1 |           pp512 |      1057.68 ± 16.02 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |   0 |       6 |  1 |           tg128 |         17.71 ± 0.32 |

build: e2d67422c (8796)


### Bonsai-4B

```bash
$BENCH -m models/gguf/4B/*.gguf -ngl 99 -fa 1 
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |  1 |           pp512 |      2374.75 ± 84.02 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |  99 |  1 |           tg128 |         69.84 ± 1.46 |

build: e2d67422c (8796)

CPU run with CUDA build (`-ngl 0`) on 11th Gen Intel(R) Core(TM) i7-11800H @ 2.30GHz
```bash
$BENCH -m models/gguf/4B/*.gguf -ngl 0 -fa 1
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |   0 |  1 |           pp512 |      1619.73 ± 62.18 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CUDA       |   0 |  1 |           tg128 |         36.57 ± 0.62 |


build: e2d67422c (8796)


### Bonsai-1.7B

```bash
$BENCH -m models/gguf/1.7B/*.gguf -ngl 99 -fa 1
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |  1 |           pp512 |     5063.94 ± 155.91 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |  99 |  1 |           tg128 |        129.11 ± 6.49 |

build: e2d67422c (8796)

CPU run with CUDA build (`-ngl 0`): 11th Gen Intel(R) Core(TM) i7-11800H @ 2.30GHz
```bash
$BENCH -m models/gguf/1.7B/*.gguf -ngl 0 -fa 1
```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 3770 MiB):
  Device 0: NVIDIA RTX A2000 Laptop GPU, compute capability 8.6, VMM: yes, VRAM: 3770 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |   0 |  1 |           pp512 |     3182.52 ± 106.89 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CUDA       |   0 |  1 |           tg128 |         84.97 ± 1.22 |

build: e2d67422c (8796)


## Configuration

## Notes


## Hardware

```bash
lscpu | head -20 && free -h && (nvidia-smi 2>/dev/null || rocminfo 2>/dev/null || vulkaninfo --summary 2>/dev/null || true)
Architecture :                            x86_64
Mode(s) opératoire(s) des processeurs :   32-bit, 64-bit
Tailles des adresses:                     39 bits physical, 48 bits virtual
Boutisme :                                Little Endian
Processeur(s) :                           16
Liste de processeur(s) en ligne :         0-15
Identifiant constructeur :                GenuineIntel
Nom de modèle :                           11th Gen Intel(R) Core(TM) i7-11800H @ 2.30GHz
Famille de processeur :                   6
Modèle :                                  141
Thread(s) par cœur :                      2
Cœur(s) par socket :                      8
Socket(s) :                               1
Révision :                                1
multiplication des MHz du/des CPU(s) :    24%
Vitesse maximale du processeur en MHz :   4600,0000
Vitesse minimale du processeur en MHz :   800,0000
BogoMIPS :                                4608,00
Drapeaux :                                fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl vmx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb cat_l2 cdp_l2 ssbd ibrs ibpb stibp ibrs_enhanced tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid rdt_a avx512f avx512dq rdseed adx smap avx512ifma clflushopt clwb intel_pt avx512cd sha_ni avx512bw avx512vl xsaveopt xsavec xgetbv1 xsaves split_lock_detect user_shstk dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req vnmi avx512vbmi umip pku ospke avx512_vbmi2 gfni vaes vpclmulqdq avx512_vnni avx512_bitalg avx512_vpopcntdq rdpid movdiri movdir64b fsrm avx512_vp2intersect md_clear ibt flush_l1d arch_capabilities
Virtualisation :                          VT-x
               total       utilisé      libre     partagé tamp/cache   disponible
Mem:            31Gi        24Gi       1,9Gi       3,9Gi       8,6Gi       6,1Gi
Échange:       976Mi       976Mi       124Ki
Fri Apr 17 16:48:56 2026       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 550.163.01             Driver Version: 595.58.03      CUDA Version: 13.2     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA RTX A2000 Laptop GPU    On  |   00000000:01:00.0  On |                  N/A |
| N/A   49C    P8             11W /   60W |     136MiB /   4096MiB |     19%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
                                                                                         
+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A     10426      G   /usr/bin/gnome-shell                          105MiB |
+-----------------------------------------------------------------------------------------+
