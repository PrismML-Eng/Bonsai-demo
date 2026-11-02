# NVIDIA TITAN V 12 GB — CUDA — Ternary-Bonsai-27B

## Summary

TITAN V 12 GB (GV100, Volta sm_70, HBM2; driver 580.173.02; ~$0.114/hr) measured with the PrismML llama.cpp fork `prism-b10777-e3de715`
(linux-cuda-12.4 assets) on a vast.ai pod, `llama-bench -ngl 99 -fa 1 -p 512 -n 128 -r 3`.

| file | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `Q2_g64` (7.05 GiB) | 576.58 ± 11.77 | 49.20 ± 0.09 |

## Configuration

- fork `prism-b10777-e3de715` CUDA-12.4 prebuilt
- Model: `prism-ml/Ternary-Bonsai-27B-gguf` — `Ternary-Bonsai-27B-Q2_g64.gguf` sha256 `59a45d1ecef702b14531b06d22949f33b25c1897da31a8c0b298e01e4d9138eb` (digest identical across the whole fleet).
- Per the formats guide, current builds expect `PQ2_0` (group-128) **and** `Q2_0` group-64; this entry measures the group-64 file on a current fork build. `PQ2_0` (this gen) not yet run — follow-up planned.
- Rented pod destroyed after capture; ± = llama-bench dispersion over 3 reps.

## Notes

A 2017 Volta flagship on a $0.11/hr pod decodes a 27B ternary model at ~49 t/s — the density story lives on legacy silicon, not only on Blackwell.

## Hardware

```
NVIDIA TITAN V, 12288 MiB; driver 580.173.02
```
