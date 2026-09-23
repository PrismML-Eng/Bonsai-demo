# NVIDIA RTX 3070 8 GB — CUDA

## Summary

NVIDIA GeForce RTX 3070 8 GB (Ampere, compute capability 8.6) on Windows 11 Pro,
running Bonsai 2 27B with llama.cpp CUDA from this demo's fork
(build `9a9394a89`), flash attention enabled, and `-ngl 999`.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 838.92 ± 21.34 | 43.70 ± 1.83 |

Only PQ2_0 was tested.

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
- Model: `Ternary-Bonsai-2-27B-PQ2_0.gguf`
- Model size reported by `llama-bench`: 6.70 GiB
- Parameters: 26.90B
- Packing: PQ2_0, 2.13 bpw, group 128
- llama.cpp fork build: `9a9394a89 (10709)`
- Backend: CUDA
- CUDA runtime installed by `setup.ps1`: CUDA 12.4
- GPU: NVIDIA GeForce RTX 3070
- VRAM reported by llama.cpp: 8191 MiB
- Compute capability: 8.6
- Flash attention enabled (`-fa 1`)
- GPU layer setting: `-ngl 999`
- Benchmark repetitions: 5 (`-r 5`)
- Prompt processing test: PP512
- Token generation test: TG128
- PTQ1_0 was not tested.
- Q2_0 development format was not tested.

## llama-bench results

Setup was performed using `.\setup.ps1` from the repository root. The setup
detected the NVIDIA GPU and CUDA 12.4, downloaded Bonsai 2 27B PQ2_0, and
installed the CUDA llama.cpp binaries supplied by this demo.

### PQ2_0

Exact command:

```powershell
.\bin\cuda\llama-bench.exe `
  -m ".\models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PQ2_0.gguf" `
  -p 512 `
  -n 128 `
  -ngl 999 `
  -fa 1 `
  -r 5
```

Raw result:

```text
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 8191 MiB):
  Device 0: NVIDIA GeForce RTX 3070, compute capability 8.6, VMM: yes, VRAM: 8191 MiB

| model                                   |       size |     params | backend | ngl | fa |  test |              t/s |
| --------------------------------------- | ---------: | ---------: | ------- | --: | -: | ----: | ---------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA    | 999 |  1 | pp512 | 838.92 ± 21.34 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA    | 999 |  1 | tg128 |  43.70 ± 1.83 |

build: 9a9394a89 (10709)
```

### PTQ1_0

Not tested.

### Q2_0 (development)

Not tested.

## Additional observations

A separate interactive text-generation check was performed with `llama-cli`
using the same PQ2_0 model, CUDA backend, flash attention, `-ngl 999`, and a
2048-token context.

The interactive run reported:

```text
Prompt: 254.3 t/s
Generation: 37.0 t/s
```

This result is included only as an additional observation. It was not produced
by the `llama-bench` PP512/TG128 workload and should not be directly compared
with the benchmark measurements above.

The model successfully generated text during this interactive test.

## Hardware

```text
CPU: 12th Gen Intel(R) Core(TM) i7-12700KF
CPU cores: 12
CPU logical processors: 20

GPU: NVIDIA GeForce RTX 3070
GPU VRAM: 8191 MiB
GPU compute capability: 8.6
NVIDIA driver version: 32.0.15.7688

System RAM: 64 GB

OS: Microsoft Windows 11 Pro
Version: 10.0.26200
Build: 26200
```

The system also has Parsec Virtual Display Adapter and Microsoft Remote Display
Adapter devices installed. These were not used as compute backends for the
benchmark.