# NVIDIA DGX Spark (GB10) — CUDA — Bonsai-27B

## Summary

NVIDIA DGX Spark with GB10 GPU (128 GB unified LPDDR5X memory), CUDA 13.0 on DGX OS (Ubuntu 24.04, aarch64). Bonsai-27B reaches **45.44 t/s tg128** and **1,023.58 t/s pp512**. The current v7 DFlash-format DSpark drafter raises matched 512-token code generation from **~43.5 t/s to ~96.1 t/s (2.21x)**.

## llama-bench Results

```bash
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-bench -m models/gguf/27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa on -r 5
```

| model | size | params | backend | ngl | fa | test | t/s |
| --- | ---: | ---: | --- | --: | --: | ---: | ---: |
| qwen35 27B Q1_0 | 3.53 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 1023.58 ± 16.55 |
| qwen35 27B Q1_0 | 3.53 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 45.44 ± 0.07 |

build: e311ed38f (10660)

## DSpark Results

The BF16 sidecar from `setup.sh` was converted for the v7 runtime and quantized to Q4_0 as documented in `SPECULATIVE.md`. Both servers used `-ngl 999 -fa on -c 16384 -np 1`; DSpark additionally used:

```bash
-md models/gguf/27B/Bonsai-27B-dspark-dflash-Q4_0.gguf --spec-type draft-dspark --spec-draft-n-max 4 -ngld 999
```

Three passes used the same OpenAI chat request at temperature 0 and seed 42: "Implement quicksort in Python with type hints, tests, and a concise complexity explanation", with `max_tokens: 512`.

| Mode | Pass 1 | Pass 2 | Pass 3 | Mean | Speedup | Draft acceptance |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline | 43.49 | 43.46 | 43.55 | 43.50 t/s | 1.00x | — |
| DSpark Q4_0 | 94.10 | 96.91 | 97.18 | 96.07 t/s | 2.21x | 383/512 (74.8%) |

## Configuration

- All layers offloaded; flash attention enabled; one server slot
- PrismML-Eng/llama.cpp `prism` commit `e311ed38f` (build 10660), built for CUDA architecture `121a`
- NVIDIA driver 580.173.02; CUDA toolkit 13.0.88
- GPU idle before recorded runs; a lightweight inspection service retained ~1.5 GiB at 0% GPU utilization

## Hardware

```text
Architecture: aarch64
CPU(s): 20 (10 Cortex-X925 / 10 Cortex-A725)
Mem: 121 GiB unified LPDDR5X
OS: Ubuntu 24.04.4 LTS
GPU: NVIDIA GB10 (compute capability 12.1)
```
