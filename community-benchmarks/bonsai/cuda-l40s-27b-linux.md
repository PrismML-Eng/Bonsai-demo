# NVIDIA L40S — CUDA — Bonsai-27B (1-bit)

## Summary

NVIDIA L40S (46 GB), Intel Xeon Platinum 8462Y+, CUDA 12.8 on Linux. **Updated after the fork's rebase onto current mainline llama.cpp** (build `e311ed38f`, release line `prism-b10658+`). Bonsai-27B (1-bit, `Q1_0`), all layers on GPU (`-ngl 99 -fa 1`): **~107.5 t/s tg128, ~2,937 t/s pp512** — decode up ~7% from the pre-migration 100.1 t/s on the same GPU.

With the post-migration DSpark drafter (~0.6 GiB, shared tensors stripped), end-to-end decode reaches **~169 t/s blended (1.60x)** and **~184 t/s on code/math (1.75x)** — up from 1.4x with the old 1.95 GiB drafter.

## llama-bench Results

### Bonsai-27B

```bash
BENCH=build/bin/llama-bench
$BENCH -m models/Binary-27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |     2936.73 ± 184.57 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |        107.47 ± 1.41 |

build: e311ed38f (10660)

## Speculative decoding (DSpark)

Post-migration drafter: the published `Bonsai-27B-dspark-bf16.gguf` sidecar converted with `gguf_dspark_to_dflash.py --drop-shared-tensors` and quantized to Q4_0 (~0.6 GiB; embedding and lm_head are shared with the target at load — see SPECULATIVE.md). Target `Q1_0`, `llama-server`, greedy, `--spec-draft-n-max 4`, 16 chat-templated prompts (4 per category, 256 tokens each), decode rate from the server's `timings`:

| workload | no drafter | + DSpark | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| code | 105.5 | 184.1 | 0.71 | **1.75x** |
| math | 105.7 | 183.8 | 0.68 | **1.74x** |
| reasoning | 105.7 | 160.6 | 0.50 | **1.52x** |
| chat | 105.8 | 148.1 | 0.47 | **1.40x** |
| blended (16 prompts) | 105.7 | 169.1 | 0.58 | **1.60x** |

Output is identical to non-speculative at temperature 0. The multiplier stays below ternary's (2.06x blended) because the 1-bit target is already fast, so each accepted draft token saves less absolute time.

## Configuration

All layers offloaded, flash attention on, single sequence.

## Notes

- NVIDIA driver 580.126.09, CUDA 12.8, L40S compute capability 8.9 (Ada)
- The 27B is a hybrid (attention + Gated-DeltaNet); the DeltaNet layers run in F16, which bounds pp512.

## Hardware

```
CPU: Intel Xeon Platinum 8462Y+ (12 vCPU exposed), 70 GiB RAM
GPU: NVIDIA L40S, 46 GB, driver 580.126.09, CUDA 12.8
```
