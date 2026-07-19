# NVIDIA RTX 4070 Ti SUPER — CUDA

## Summary

NVIDIA RTX 4070 Ti SUPER 16 GB (Ada, compute 8.9) on Windows 11, driver
32.0.16.1074 (more HW specs below). Ternary-Bonsai (llama.cpp CUDA, build
`62061f9`, flash-attn on, `-ngl 99`). No thermal throttling:

- **27B Q2_0: ~1,717 t/s pp512, ~69.6 t/s tg128** — 6.66 GiB weights, fits comfortably in 16 GB.
- 8B: ~6,675 t/s pp512, ~216 t/s tg128.
- 4B: ~10,894 t/s pp512, ~312 t/s tg128.
- 1.7B: ~25,484 t/s pp512, ~533 t/s tg128.

## llama-bench Results

### Ternary-Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
$BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 16375 MiB):

  Device 0: NVIDIA GeForce RTX 4070 Ti SUPER, compute capability 8.9, VMM: yes, VRAM: 16375 MiB

| model           |     size |  params | backend | ngl | fa |  test |             t/s |
|-----------------|---------:|--------:|---------|----:|---:|------:|----------------:|
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA    |  99 |  1 | pp512 | 1716.93 ± 22.06 |
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA    |  99 |  1 | tg128 |    69.59 ± 0.07 |

build: 62061f9 (1)

### Ternary-Bonsai-8B

```bash
$BENCH -m models/ternary-gguf/8B/*.gguf -ngl 99 -fa 1
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 16375 MiB):

  Device 0: NVIDIA GeForce RTX 4070 Ti SUPER, compute capability 8.9, VMM: yes, VRAM: 16375 MiB

| model         |     size | params | backend | ngl | fa |  test |              t/s |
|---------------|---------:|-------:|---------|----:|---:|------:|-----------------:|
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | CUDA    |  99 |  1 | pp512 | 6674.61 ± 352.95 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | CUDA    |  99 |  1 | tg128 |    215.73 ± 0.48 |

build: 62061f9 (1)

### Ternary-Bonsai-4B

```bash
$BENCH -m models/ternary-gguf/4B/*.gguf -ngl 99 -fa 1
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 16375 MiB):

  Device 0: NVIDIA GeForce RTX 4070 Ti SUPER, compute capability 8.9, VMM: yes, VRAM: 16375 MiB

| model         |        size | params | backend | ngl | fa |  test |               t/s |
|---------------|------------:|-------:|---------|----:|---:|------:|------------------:|
| qwen3 4B Q2_0 | 1019.50 MiB | 4.02 B | CUDA    |  99 |  1 | pp512 | 10893.64 ± 471.60 |
| qwen3 4B Q2_0 | 1019.50 MiB | 4.02 B | CUDA    |  99 |  1 | tg128 |     311.68 ± 1.61 |

build: 62061f9 (1)

### Ternary-Bonsai-1.7B

```bash
$BENCH -m models/ternary-gguf/1.7B/*.gguf -ngl 99 -fa 1
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 16375 MiB):

  Device 0: NVIDIA GeForce RTX 4070 Ti SUPER, compute capability 8.9, VMM: yes, VRAM: 16375 MiB

| model           |       size | params | backend | ngl | fa |  test |                t/s |
|-----------------|-----------:|-------:|---------|----:|---:|------:|-------------------:|
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | CUDA    |  99 |  1 | pp512 | 25483.89 ± 1656.59 |
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | CUDA    |  99 |  1 | tg128 |      532.73 ± 2.45 |

build: 62061f9 (1)

## Configuration

This is a hand-built tower, hand-optimized (i.e.: very mild undervolts, no OC, UEFI tweaks,
ThrottleStop, MSI Afterburner), primarily for gaming, which I also use for model research and
real-time audio (separate performance profiles for each). Configs/power profiles available on
request.

- Intel Core i7-14700KF 3.4 GHz (20 cores / 28 threads)
- MSI PRO Z790-VC WIFI, 32 GB DDR5-6400 CL32
- NVIDIA RTX 4070 Ti SUPER 16 GB (MSI VENTUS 2X OC) 285W
- All four sizes run fully on-GPU (`-ngl 99`) with flash-attn (`-fa 1`).

## Notes

None.

## Hardware

```powershell
PS> Get-CimInstance Win32_Processor | Format-List Name,NumberOfCores,NumberOfLogicalProcessors

Name                      : Intel(R) Core(TM) i7-14700KF
NumberOfCores             : 20
NumberOfLogicalProcessors : 28

PS> Get-CimInstance Win32_VideoController | Format-List Name,DriverVersion

Name          : NVIDIA GeForce RTX 4070 Ti SUPER
DriverVersion : 32.0.16.1074

PS> [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
32
```
