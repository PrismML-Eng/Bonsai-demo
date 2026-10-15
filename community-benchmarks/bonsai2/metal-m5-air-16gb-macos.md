# Apple M5 (MacBook Air, 16 GB) — Metal — Bonsai 2 27B

## Summary

Base-model M5 Air, 16 GB unified memory. PrismML fork `prism-b10777-e3de715` (macos-arm64),
`llama-bench -ngl 99 -fa 1 -p 512 -n 128 -r 3`:

| Band | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `PTQ1_0` (5.53 GiB) | 79.71 ± 0.12 | 7.03 ± 0.05 |
| `PQ2_0` (6.70 GiB) | 88.75 ± 0.51 | 7.82 ± 0.06 |

On this silicon `PQ2_0` takes both columns, mirroring the M4 Pro entries. Cross-generation context on
the same laptop: gen-1 upstream `Q2_g64` = 80.2/6.7 and 1-bit `Q1_0` = 84.2/11.5, so gen-2 decode lands
between the gen-1 paths while keeping the smallest 27B ternary footprint at 5.53 GiB.

## Configuration

- `prism-ml/Ternary-Bonsai-2-27B-gguf`; sha256 `53107f53…` (PTQ1_0), `3907dc16…` (PQ2_0) — same digests as the CUDA machines.
- Upstream b11630 refuses both files (`llama_model_load: error loading model`) — fork-only bands, clean refusal.
- Passively cooled Air; reported as llama-bench 3-rep mean ± std. dev., not sustained thermals.

## Hardware

```
Apple M5 (base), 16 GB unified, Metal4/tensor-API, recommendedMaxWorkingSetSize ~12.7 GB
```
