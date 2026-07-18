# NVIDIA L40S — CUDA — Bonsai-27B (1-bit)

## Summary

NVIDIA L40S (48 GB), AMD EPYC 9354, CUDA 12.8 on Linux. Bonsai-27B (1-bit, `Q1_0`), all layers on GPU (`-ngl 99 -fa 1`): **~100 t/s tg128, ~2,945 t/s pp512**. With the paired DSpark drafter, end-to-end decode rises to **~99 t/s (1.38x)** on a mixed workload and **~107 t/s (1.42x)** on coding tasks — a smaller multiplier than ternary because the 1-bit target is already fast, so there is less latency to recover.

## llama-bench Results

### Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=bin/cuda $BENCH -m models/gguf/27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |     2945.02 ± 130.75 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |        100.12 ± 1.61 |

build: 62061f910 (9591) (branch `prism`)

## Speculative decoding (DSpark)

Enable with `BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh` (adds the paired `Bonsai-27B-dspark-Q4_1.gguf`, `--spec-type draft-dspark --spec-draft-n-max 4`).

Measured end-to-end over a 12-prompt code/math/reasoning/chat mix (greedy, `k=4`), target alone vs target + drafter:

| workload | no drafter | + DSpark | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| 12-prompt mix (code/math/reasoning/chat) | 72.2 | 99.3 | 0.73 | **1.38x** |
| code-only (8 prompts) | 75.4 | 106.9 | 0.72 | **1.42x** |

Output is identical to non-speculative at temperature 0. End-to-end (prompt processing included), so below the pure-decode `tg128` above. The fast 1-bit target leaves less absolute latency to recover than the ternary model, so the multiplier is lower.

## Configuration

All layers offloaded, flash attention on, single sequence. Pre-built `bin/cuda/` binaries from `setup.sh` for llama-bench; DSpark measured with the fork's speculative path.

## Notes

- NVIDIA driver 580.126.09, CUDA 12.8, L40S compute capability 8.9 (Ada)
- The 27B is a hybrid (attention + Gated-DeltaNet); the DeltaNet layers run in F16, which bounds pp512.

## Hardware

```
CPU: AMD EPYC 9354 (12 vCPU exposed), 70 GiB RAM
GPU: NVIDIA L40S, 48 GB, driver 580.126.09, CUDA 12.8
```
