# RTX PRO 6000 Blackwell — CUDA

## Summary

RTX PRO 6000 Blackwell Workstation Edition (96GB VRAM) + CUDA 13.2 on Ubuntu 24.04. Ternary-Bonsai-27B Q2_0 (6.66 GiB): ~4552 t/s pp512, ~130 t/s tg128. Fastest submitted result for the 27B model, nearly 2× the L40S numbers.

## llama-bench Results

### Ternary-Bonsai-27B

```
./llama-bench -m /models/bonsai/Ternary-Bonsai-27B-Q2_0.gguf -ngl 9999
```

| model | size | params | backend | ngl | test | t/s |
|-------|-----:|-------:|---------|----:|-----:|----:|
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA | 9999 | pp512 | 4552.38 ± 163.78 |
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA | 9999 | tg128 | 129.92 ± 1.95 |

build: 9fcaed763 (9596)

## Configuration

- llama.cpp PrismML fork build 9fcaed7 (prism-b9596)
- CUDA 13.2, driver 595.71.05
- Single GPU (host GPU 1), all layers on GPU (-ngl 9999)
- No speculative decoding for plain llama-bench

## Notes

- Host GPU 0 is occupied by a vLLM service; benchmark ran on host GPU 1 only
- Model served via docker compose (nvidia/cuda:12.8.1-devel-ubuntu24.04 base)

## Hardware

**CPU:** Intel Core Ultra 9 285K (24 cores, no HT)
**RAM:** 62 GiB
**GPU:** NVIDIA RTX PRO 6000 Blackwell Workstation Edition, 96 GB VRAM, SM 12.0
**Driver:** 595.71.05, CUDA 13.2
**OS:** Ubuntu 24.04