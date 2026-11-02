# NVIDIA TITAN V 12 GB — CUDA — Bonsai 2 27B (Ternary-Bonsai-2)

## Summary

TITAN V 12 GB (GV100, Volta sm_70, HBM2), driver 580.173.02, ~$0.114/hr on vast.ai. llama.cpp **PrismML fork `prism-b10777-e3de715`** (linux-cuda-12.4) on vast.ai,
`llama-bench -ngl 99 -fa 1 -p 512 -n 128 -r 3`. Both current bands measured on the same machine:

| Band | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `PTQ1_0` (5.53 GiB) | 562.22 ± 7.73 | 51.25 ± 0.03 |
| `PQ2_0` (6.70 GiB) | 528.20 ± 0.72 | 46.66 ± 0.05 |

On this desktop-Volta board `PTQ1_0` takes both columns. The table's V100-SXM2 rows disagree on decode (`PQ2_0` 46.0 > `PTQ1_0` 34.3) — Volta is not internally consistent across product tiers, so selection should be per measured card.

## Configuration

- Files: `prism-ml/Ternary-Bonsai-2-27B-gguf` — `PTQ1_0` sha256 `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`; `PQ2_0` sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1` (identical digests across all machines in this sweep).
- Upstream b11630 cannot load either band (fork-only) and its ubuntu-cuda build additionally cannot start in the `vastai/pytorch` container (`GLIBC_2.38 not found`).
- Rented cloud pod, destroyed after capture. ± = llama-bench dispersion over 3 reps.

## Hardware

```
NVIDIA TITAN V, 12288 MiB; driver 580.173.02; container vastai/pytorch:latest
```
