# Apple M5 Max — Metal — Ternary-Bonsai-27B

## Summary

Apple M5 Max (40-core GPU, 48 GB unified memory), macOS 26.5.2, llama.cpp Metal. Measured after the fork's rebase onto current mainline llama.cpp (build `e311ed38f`, release line `prism-b10658+`), on both post-migration ternary formats: **`PQ2_0`: ~45.8 t/s tg128, ~816 t/s pp512** and **`Q2_0` group 64: ~43.7 t/s tg128, ~705 t/s pp512**. PQ2_0 is the smaller and faster file on Metal (+5% decode, +16% prefill).

DSpark speculative decoding on Metal is workload-dependent: about **1.2x on code/math**, but a slowdown on chat/reasoning, netting out flat (1.03x) on a mixed workload — measure your own workload before enabling it.

## llama-bench Results

### Ternary-Bonsai-27B (PQ2_0, group 128)

```bash
BENCH=build/bin/llama-bench
$BENCH -m models/Ternary-27B/Ternary-Bonsai-27B-PQ2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.66 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           pp512 |        815.72 ± 1.02 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.66 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           tg128 |         45.83 ± 0.58 |

build: e311ed38f (10660)

### Ternary-Bonsai-27B (Q2_0 group 64, official upstream format)

```bash
$BENCH -m models/Ternary-27B/Ternary-Bonsai-27B-Q2_g64.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   7.05 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           pp512 |       705.26 ± 30.54 |
| qwen35 27B Q2_0                |   7.05 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           tg128 |         43.69 ± 0.96 |

build: e311ed38f (10660)

## Speculative decoding (DSpark)

Post-migration drafter: the published `Ternary-Bonsai-27B-dspark-bf16.gguf` sidecar converted with `gguf_dspark_to_dflash.py --drop-shared-tensors` and quantized to Q4_0 (~0.6 GiB; embedding and lm_head are shared with the target at load). Target `PQ2_0`, `llama-server`, greedy, `--spec-draft-n-max 4`, 16 chat-templated prompts (4 per category, 256 tokens each), end-to-end decode t/s:

| workload | no drafter | + DSpark | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| code | 45.5 | 54.2 | 0.73 | **1.19x** |
| math | 43.7 | 51.2 | 0.74 | **1.17x** |
| reasoning | 43.3 | 39.3 | 0.50 | 0.91x |
| chat | 42.7 | 35.5 | 0.48 | 0.83x |
| blended (16 prompts) | 43.8 | 45.0 | 0.60 | 1.03x |

On Metal the drafter only pays for itself when acceptance is high (code/math); on low-acceptance workloads the draft overhead wins out. Output is identical to non-speculative at temperature 0.

**Methodology caveats:** these are `llama-server` numbers with the chat template applied, so they reflect what `start_llama_server.sh` users actually get, and they run below bare-loop tools on the same hardware for two reasons: (1) the chat template engages the model's thinking phase, whose token distribution drafts differently than a raw completion (acceptance here vs the mid-70s% a single raw code prompt reaches), and (2) the server adds per-token work (sampler chain, incremental detokenization, streaming/slot bookkeeping, and the speculative path's extra KV-cache management) that a tight loop like `llama-speculative-simple` skips. A single raw code prompt through `llama-speculative-simple` therefore reads higher on the same machine; the tables above are the deployed-reality numbers.

## Configuration

All layers offloaded, flash attention on, single sequence. Both formats benchmarked per the post-migration guidance (the legacy `Ternary-Bonsai-27B-Q2_0.gguf` without `g64` is refused by these builds).

## Notes

- This is an update after the fork's mainline rebase; numbers are from the maintainers' own M5 Max.
- The DSpark-table rates are the server's decode-only `timings` (prompt processing excluded); they sit slightly below llama-bench tg128 due to server overhead and growing context.

## Hardware

```
Apple M5 Max, 18-core CPU, 40-core GPU, 48 GB unified memory
macOS 26.5.2, Metal 4
```
