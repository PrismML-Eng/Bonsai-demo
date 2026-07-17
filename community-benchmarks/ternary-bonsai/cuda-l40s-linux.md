# NVIDIA L40S — CUDA — Ternary-Bonsai-27B

## Summary

NVIDIA L40S (46 GB), AMD EPYC 9354, CUDA 12.8 on Linux. Ternary-Bonsai-27B (`Q2_0`), all layers on GPU (`-ngl 99 -fa 1`): **~70 t/s tg128, ~2,881 t/s pp512**. With the paired DSpark drafter, end-to-end decode rises to **~87 t/s (1.63x)** on a code/reasoning/chat mix.

## llama-bench Results

### Ternary-Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=bin/cuda $BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |     2880.76 ± 128.56 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         70.11 ± 1.41 |

build: 62061f910 (9591) (branch `prism`)

## Speculative decoding (DSpark)

Enable with `BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh` (adds the paired `Ternary-Bonsai-27B-dspark-Q4_1.gguf`, `--spec-type draft-dspark --spec-draft-n-max 4`).

Measured end-to-end over a 12-prompt code/math/reasoning/chat mix (greedy, `k=4`), target alone vs target + drafter:

| | decode t/s | accept | speedup |
| --- | ---: | ---: | ---: |
| no drafter | 53.3 | — | 1.00x |
| + DSpark | 86.9 | 0.70 | **1.63x** |

Output is identical to non-speculative at temperature 0. This is end-to-end generation (prompt processing included), so it runs below the pure-decode `tg128` above; the speedup is workload-dependent (code/reasoning gain most, casual chat least).

## Configuration

All layers offloaded, flash attention on, single sequence. Pre-built `bin/cuda/` binaries from `setup.sh` for llama-bench; DSpark measured with the fork's speculative path.

## Notes

- NVIDIA driver 580.126.09, CUDA 12.8, L40S compute capability 8.9 (Ada)
- The 27B is a hybrid (attention + Gated-DeltaNet); the DeltaNet layers run in F16, which bounds pp512.

## Hardware

```
CPU: AMD EPYC 9354 (12 vCPU exposed), 70 GiB RAM
GPU: NVIDIA L40S, 46 GB, driver 580.126.09, CUDA 12.8
```
