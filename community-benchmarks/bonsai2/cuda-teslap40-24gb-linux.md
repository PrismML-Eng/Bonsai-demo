# Tesla P40 24 GB — CUDA — Bonsai 2 27B (Ternary-Bonsai-2)

## Summary

Tesla P40 24 GB (GP102, Pascal sm_61), driver 580.126.09, ~$0.107/hr on vast.ai. llama.cpp **PrismML fork `prism-b10777-e3de715`** (linux-cuda-12.4) on vast.ai,
`llama-bench -ngl 99 -fa 1 -p 512 -n 128 -r 3`. Both current bands measured on the same machine:

| Band | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `PTQ1_0` (5.53 GiB) | 139.85 ± 0.08 | 19.86 ± 0.09 |
| `PQ2_0` (6.70 GiB) | 254.38 ± 0.62 | 23.16 ± 0.00 |

**Pascal strongly prefers `PQ2_0`** — 1.8x the prefill of `PTQ1_0` on this card, matching the `PQ2_0` prefill dominance on the newer Blackwell/Ada entries already in this table.

## Configuration

- Files: `prism-ml/Ternary-Bonsai-2-27B-gguf` — `PTQ1_0` sha256 `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`; `PQ2_0` sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1` (identical digests across all machines in this sweep).
- Upstream b11630 cannot load either band (fork-only) and its ubuntu-cuda build additionally cannot start in the `vastai/pytorch` container (`GLIBC_2.38 not found`).
- Rented cloud pod, destroyed after capture. ± = llama-bench dispersion over 3 reps.

## Hardware

```
Tesla P40, 24576 MiB; driver 580.126.09; container vastai/pytorch:latest
```
