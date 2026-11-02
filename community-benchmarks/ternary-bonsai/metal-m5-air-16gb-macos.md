# Apple M5 (MacBook Air, 16 GB) — Metal — Ternary-Bonsai-27B

## Summary

Base-model M5 Air (16 GB unified, recommendedMaxWorkingSetSize ~12.7 GB). Three runtimes on the same laptop:

| file | build | pp512 (t/s) | tg128 (t/s) |
|------|-------|------------:|------------:|
| `Q2_g64` (7.05 GiB) | upstream llama.cpp **b11630** | 80.22 ± 0.38 | 6.68 ± 0.18 |
| legacy `Q2_0` group-128 (6.66 GiB) | fork **prism-b9596** | 34.05 ± 1.70 | 6.06 ± 0.52 |
| 1-bit `Q1_0` (3.53 GiB) | upstream b11630 → see [../bonsai/metal-m5-air-16gb-macos.md](../bonsai/metal-m5-air-16gb-macos.md) | 84.18 ± 0.36 | 11.54 ± 0.08 |

## Configuration

- Upstream command: `LD_LIBRARY_PATH=./bin/b11630 ./bin/b11630/llama-bench -m Ternary-Bonsai-27B-Q2_g64.gguf -ngl 99 -fa 1 -p 512 -n 128 -r 3` (build 6868a52cb).
- Fork command: `DYLD_LIBRARY_PATH=~/Bonsai-demo/bin/mac ~/Bonsai-demo/bin/mac/llama-bench -m Ternary-Bonsai-27B-Q2_0.gguf …` (release `prism-b9596`, build 9fcaed763).
- **Legacy-format evidence (matches the formats guide):** llama-bench prints the same type string `Q2_0` for the 7.05 GiB group-64 file and the 6.66 GiB group-128 file — same type id, different block size. Upstream ggml **0.15.3 refuses both** (`llama_bench: error: failed to load model`); upstream **b11630 loads the group-64 file and refuses the legacy group-128** file; the old fork b9596 loads the legacy file fine.
- Files sha256: `Q2_g64 59a45d1e…9138eb`; legacy `Q2_0 868c11714cf8fe47f5ec9eeb2be0ab1a337112886f92ee0ede6b855c4fa31757`.

## Notes

- Passively cooled Air; reported as llama-bench 3-rep mean ± std. dev. The cross-build pp512 gap (34.05 b9596 vs 80.22 b11630) is NOT a controlled format comparison — build and file differ together; treat as two independent rows.
- 27B ternary is usable-but-warm on a $999 laptop; the same box's Bonsai-2 and 1-bit entries show better decode.

## Hardware

```
Apple M5 (base), 16 GB unified, Metal4 (MTLGPUFamilyApple10), bfloat + tensor API
```
