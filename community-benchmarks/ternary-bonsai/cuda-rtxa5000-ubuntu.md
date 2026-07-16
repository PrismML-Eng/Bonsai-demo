# NVIDIA RTX A5000 — CUDA

## Summary

RTX A5000 24 GB (GA102, Ampere sm_86) + prebuilt CUDA binaries (release `prism-b9591-62061f9`) on Ubuntu 22.04, driver 580.159.03. Ternary-Bonsai-27B Q2_0: **~1036 t/s pp512, ~48 t/s tg128** at depth 0, holding 41 t/s tg at 32K depth. For reference, a Q4_K_M quant of the same 27B base model on the same GPU does ~33 t/s tg128 — the ternary weights are ~1.5× faster at decode from memory bandwidth alone.

## llama-bench Results

### Ternary-Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1035.52 ± 12.21 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         48.20 ± 0.51 |

build: 62061f910 (9591)

Context-depth extension (same flags plus `-d 16384,32768`):

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  pp512 @ d16384 |       866.73 ± 27.42 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  tg128 @ d16384 |         45.20 ± 0.23 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  pp512 @ d32768 |       734.97 ± 18.28 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  tg128 @ d32768 |         41.25 ± 0.25 |

build: 62061f910 (9591)

## Configuration

- Prebuilt release binaries from `./scripts/download_binaries.sh` (`prism-b9591-62061f9`, CUDA 12.4 asset), default llama-bench settings otherwise (f16 KV).
- Reference point, same GPU/day, mainline-derived llama.cpp (build 9767): the same 27B base model at Q4_K_M (15.40 GiB) does pp512 989.94 ± 9.25 / tg128 32.59 ± 0.12, dropping to 28.99 ± 0.03 tg at d32768. Ternary tg advantage ≈ 1.48× at depth 0 and 1.42× at 32K, with ~2.3× smaller weights.
- Served end-to-end (llama-server, q4_0 KV + mean-center bias, 131072 ctx) the same model measured 909 t/s prefill / 46.8 t/s decode at depth 0 through HTTP — consistent with these kernel-level numbers.

## Notes

- Driver 580.159.03, stock clocks/power, small always-on embedding server (~1 GB VRAM) co-resident during runs.
- Vision projector and dspark drafter not loaded for these runs (llama-bench measures the bare autoregressive model).

## Hardware

NVIDIA RTX A5000 24 GB (GA102, compute 8.6), AMD Ryzen 9 7945HX, 38 GiB DDR5, Ubuntu 22.04 (kernel 6.8).
