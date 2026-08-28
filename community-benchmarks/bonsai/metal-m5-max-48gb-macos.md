# Apple M5 Max — Metal — Bonsai-27B (1-bit)

## Summary

Apple M5 Max (40-core GPU, 48 GB unified memory), macOS 26.5.2, llama.cpp Metal. Measured after the fork's rebase onto current mainline llama.cpp (build `e311ed38f`, release line `prism-b10658+`). Bonsai-27B (1-bit, `Q1_0`): **~63.9 t/s tg128, ~796 t/s pp512**.

DSpark speculative decoding is **not worth it for the 1-bit family on Metal**: the target is fast enough that the draft overhead loses on every workload category we measured (0.67-0.87x).

## llama-bench Results

### Bonsai-27B

```bash
BENCH=build/bin/llama-bench
$BENCH -m models/Binary-27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           pp512 |       796.04 ± 12.40 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           tg128 |         63.93 ± 0.24 |

build: e311ed38f (10660)

## Speculative decoding (DSpark)

Post-migration drafter (converted `dspark-dflash` Q4_0, ~0.6 GiB), target `Q1_0`, `llama-server`, greedy, `--spec-draft-n-max 4`, 16 chat-templated prompts (4 per category, 256 tokens each), end-to-end decode t/s:

| workload | no drafter | + DSpark | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| code | 54.8 | 47.6 | 0.72 | 0.87x |
| math | 52.2 | 45.2 | 0.68 | 0.87x |
| reasoning | 52.0 | 38.6 | 0.51 | 0.74x |
| chat | 52.2 | 34.8 | 0.47 | 0.67x |
| blended (16 prompts) | 52.8 | 41.5 | 0.58 | 0.79x |

Even at 0.72 acceptance the drafter loses on Metal here: the 1-bit target decodes so fast that the per-step draft cost exceeds the tokens it saves. Leave `BONSAI_SPECULATIVE` off for this family on Apple Silicon.

## Configuration

All layers offloaded, flash attention on, single sequence.

## Notes

- This is an update after the fork's mainline rebase; numbers are from the maintainers' own M5 Max.
- The DSpark-table rates are the server's decode-only `timings` (prompt processing excluded); they sit slightly below llama-bench tg128 due to server overhead and growing context.

## Hardware

```
Apple M5 Max, 18-core CPU, 40-core GPU, 48 GB unified memory
macOS 26.5.2, Metal 4
```
