# NVIDIA RTX A4000 16 GB — CUDA — Bonsai 2 27B (Ternary-Bonsai-2)

## Summary

RTX A4000 16 GB (GA104, Ampere pro), driver 580.173.02, ~$0.116/hr on vast.ai. llama.cpp **PrismML fork `prism-b10777-e3de715`** (linux-cuda-12.4) on vast.ai,
`llama-bench -ngl 99 -fa 1 -p 512 -n 128 -r 3`. Both current bands measured on the same machine:

| Band | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `PTQ1_0` (5.53 GiB) | 769.94 ± 22.99 | 49.49 ± 0.11 |
| `PQ2_0` (6.70 GiB) | 758.24 ± 19.84 | 42.42 ± 0.10 |

On this RTX A4000, `PTQ1_0` has higher measured means for both tests. This matches the TITAN V report, but contrasts with the existing RTX 3090 Ti report, where `PQ2_0` leads both columns. Hardware, binary builds, and runtime settings differ between submissions, so these comparisons do not isolate an architecture-level cause; select the band from measurements on the intended setup.

## Configuration

- Files: `prism-ml/Ternary-Bonsai-2-27B-gguf` — `PTQ1_0` sha256 `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`; `PQ2_0` sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1` (identical digests across all machines in this sweep).
- Upstream b11630 cannot load either band (fork-only) and its ubuntu-cuda build additionally cannot start in the `vastai/pytorch` container (`GLIBC_2.38 not found`).
- Rented cloud pod, destroyed after capture. ± = llama-bench dispersion over 3 reps.

## Hardware

```
NVIDIA RTX A4000, 16376 MiB; driver 580.173.02; container vastai/pytorch:latest
```
