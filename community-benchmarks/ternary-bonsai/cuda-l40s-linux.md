# NVIDIA L40S — CUDA — Ternary-Bonsai-27B

## Summary

NVIDIA L40S (46 GB), Intel Xeon Platinum 8462Y+, CUDA 12.8 on Linux. **Updated after the fork's rebase onto current mainline llama.cpp** (build `e311ed38f`, release line `prism-b10658+`), covering both post-migration ternary formats. All layers on GPU (`-ngl 99 -fa 1`): **`PQ2_0` ~74.3 t/s tg128, ~3,036 t/s pp512**; **`Q2_0` group 64 ~71.3 t/s tg128, ~3,021 t/s pp512**. Both are faster than the pre-migration numbers on the same GPU (70.1 tg / 2,881 pp).

With the post-migration DSpark drafter (now ~0.6 GiB, shared tensors stripped), end-to-end decode reaches **~150 t/s blended (2.06x)** and up to **~175 t/s on math (2.39x)** — a substantially better multiplier than the old 1.95 GiB drafter (1.6-1.8x).

## llama-bench Results

### Ternary-Bonsai-27B (PQ2_0, group 128)

```bash
BENCH=build/bin/llama-bench
$BENCH -m models/Ternary-27B/Ternary-Bonsai-27B-PQ2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |     3035.90 ± 161.92 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         74.25 ± 0.66 |

build: e311ed38f (10660)

### Ternary-Bonsai-27B (Q2_0 group 64, official upstream format)

```bash
$BENCH -m models/Ternary-27B/Ternary-Bonsai-27B-Q2_g64.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   7.05 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |     3020.66 ± 166.14 |
| qwen35 27B Q2_0                |   7.05 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         71.26 ± 0.53 |

build: e311ed38f (10660)

## Speculative decoding (DSpark)

Post-migration drafter: the published `Ternary-Bonsai-27B-dspark-bf16.gguf` sidecar converted with `gguf_dspark_to_dflash.py --drop-shared-tensors` and quantized to Q4_0 (~0.6 GiB; embedding and lm_head are shared with the target at load — see SPECULATIVE.md). Target `PQ2_0`, `llama-server`, greedy, `--spec-draft-n-max 4`, 16 chat-templated prompts (4 per category, 256 tokens each), decode rate from the server's `timings`:

| workload | no drafter | + DSpark | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| code | 72.8 | 155.9 | 0.70 | **2.14x** |
| math | 72.9 | 174.6 | 0.75 | **2.39x** |
| reasoning | 72.7 | 137.6 | 0.50 | **1.89x** |
| chat | 72.5 | 132.5 | 0.48 | **1.83x** |
| blended (16 prompts) | 72.7 | 150.1 | 0.59 | **2.06x** |

Output is identical to non-speculative at temperature 0. The lighter drafter helps every category now — even low-acceptance chat is 1.8x, where the old 1.95 GiB drafter topped out at 1.76x on its best category.

**Methodology caveats:** these are `llama-server` numbers with the chat template applied, so they reflect what `start_llama_server.sh` users actually get, and they run below bare-loop tools on the same hardware for two reasons: (1) the chat template engages the model's thinking phase, whose token distribution drafts differently than a raw completion (acceptance here vs the mid-70s% a single raw code prompt reaches), and (2) the server adds per-token work (sampler chain, incremental detokenization, streaming/slot bookkeeping, and the speculative path's extra KV-cache management) that a tight loop like `llama-speculative-simple` skips. A single raw code prompt through `llama-speculative-simple` therefore reads higher on the same machine; the tables above are the deployed-reality numbers.

## Configuration

All layers offloaded, flash attention on, single sequence. The legacy `Ternary-Bonsai-27B-Q2_0.gguf` (no `g64` in the name) is refused by these builds with an error pointing at the two formats above.

## Notes

- NVIDIA driver 580.126.09, CUDA 12.8, L40S compute capability 8.9 (Ada)
- The 27B is a hybrid (attention + Gated-DeltaNet); the DeltaNet layers run in F16, which bounds pp512.

## Hardware

```
CPU: Intel Xeon Platinum 8462Y+ (12 vCPU exposed), 70 GiB RAM
GPU: NVIDIA L40S, 46 GB, driver 580.126.09, CUDA 12.8
```
