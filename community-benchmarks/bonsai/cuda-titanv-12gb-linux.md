# NVIDIA TITAN V 12 GB — CUDA — Bonsai-27B (1-bit)

## Summary

TITAN V 12 GB (GV100, Volta sm_70, HBM2; driver 580.173.02; ~$0.114/hr) measured with the PrismML llama.cpp fork `prism-b10777-e3de715`
(linux-cuda-12.4 assets) on a vast.ai pod, `llama-bench -ngl 99 -fa 1 -p 512 -n 128 -r 3`.

| file | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `Q1_0` (3.53 GiB) | 552.38 ± 0.51 | 56.47 ± 0.10 |

## Configuration

- fork `prism-b10777-e3de715` CUDA-12.4; upstream b11630 runs `Q1_0` too (fully merged)
- Model: `prism-ml/Bonsai-27B-gguf` — `Bonsai-27B-Q1_0.gguf` sha256 `17ef842e47450caeb8eaa3ebfbbab5d2f2278b62b79be107985fb69a2f819aa0` (digest identical across the whole fleet).
- Rented pod destroyed after capture; ± = llama-bench dispersion over 3 reps.

## Notes

3.53 GiB leaves ~8 GB for context on a 12 GB card; decode beats the same machine's ternary row (49.20 t/s, [../ternary-bonsai/cuda-titanv-12gb-linux.md]).

## Hardware

```
NVIDIA TITAN V, 12288 MiB; driver 580.173.02
```
