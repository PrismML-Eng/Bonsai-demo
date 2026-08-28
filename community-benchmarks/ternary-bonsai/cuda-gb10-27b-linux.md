# NVIDIA DGX Spark (GB10) — CUDA — Ternary-Bonsai-27B

## Summary

NVIDIA DGX Spark with GB10 GPU (128 GB unified LPDDR5X memory), CUDA 13.0 on DGX OS (Ubuntu 24.04, aarch64). Ternary-Bonsai-27B reaches **29.16 t/s tg128** and **1,005.19 t/s pp512**. Its v7 DFlash-format DSpark drafter raises matched 512-token code generation from **~28.6 t/s to ~70.0 t/s (2.45x)**.

## llama-bench Results

```bash
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-bench -m models/ternary-gguf/27B/Ternary-Bonsai-27B-PQ2_0.gguf -ngl 99 -fa on -r 5
```

| model | size | params | backend | ngl | fa | test | t/s |
| --- | ---: | ---: | --- | --: | --: | ---: | ---: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.66 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 1005.19 ± 9.76 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.66 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 29.16 ± 0.04 |

build: e311ed38f (10660)

The tg128 test was run separately with `-p 0 -n 128 -r 5` because the combined invocation emitted only pp512 for this model.

## Group-64 Q2_0

Not measured in this submission. The file first grabbed for this test, `Ternary-Bonsai-27B-Q2_0.gguf`, is the legacy pre-migration pack, and build 10660 refused it as designed. The actual group-64 file does exist in the repository as `Ternary-Bonsai-27B-Q2_g64.gguf` (7.06 GiB; note the 27B naming differs from the smaller sizes' `*-Q2_0_g64.gguf`) - a follow-up run on this hardware is welcome:

```bash
hf download prism-ml/Ternary-Bonsai-27B-GGUF --include "*Q2_g64*" --local-dir models/ternary-gguf/27B
```

## DSpark Results

The BF16 sidecar from `setup.sh` was converted for the v7 runtime and quantized to Q4_0 as documented in `SPECULATIVE.md`. Both servers used `-ngl 999 -fa on -c 16384 -np 1`; DSpark additionally used:

```bash
-md models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-dflash-Q4_0.gguf --spec-type draft-dspark --spec-draft-n-max 4 -ngld 999
```

Three passes used the same OpenAI chat request at temperature 0 and seed 42: "Implement quicksort in Python with type hints, tests, and a concise complexity explanation", with `max_tokens: 512`.

| Mode | Pass 1 | Pass 2 | Pass 3 | Mean | Speedup | Draft acceptance |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline | 28.61 | 28.60 | 28.59 | 28.60 t/s | 1.00x | — |
| DSpark Q4_0 | 69.45 | 70.41 | 70.17 | 70.01 t/s | 2.45x | 371/560 (66.3%) |

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
