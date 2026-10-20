# NVIDIA GeForce RTX 2060 12 GB — CUDA — Bonsai-27B (1-bit)

## Summary

RTX 2060 12 GB (TU106, Turing sm_75; driver 580.178.04; ~$0.100/hr) measured with the PrismML llama.cpp fork `prism-b10777-e3de715`
(linux-cuda-12.4 assets) on a vast.ai pod, `llama-bench -ngl 99 -fa 1 -p 512 -n 128 -r 3`.

| file | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `Q1_0` (3.53 GiB) | 431.23 ± 4.28 | 29.96 ± 0.05 |

## Configuration

- fork `prism-b10777-e3de715` CUDA-12.4
- Model: `prism-ml/Bonsai-27B-gguf` — `Bonsai-27B-Q1_0.gguf` sha256 `17ef842e47450caeb8eaa3ebfbbab5d2f2278b62b79be107985fb69a2f819aa0` (digest identical across the whole fleet).
- Rented pod destroyed after capture; ± = llama-bench dispersion over 3 reps.

## Notes

Same card as the ternary entry: 1-bit gives +3.7% prefill, +17% decode, half the bytes.

## Hardware

```
NVIDIA GeForce RTX 2060, 12288 MiB; driver 580.178.04
```
