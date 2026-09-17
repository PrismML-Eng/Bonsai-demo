# NVIDIA DGX Spark (GB10) — CUDA — Ternary-Bonsai-2-27B

## Summary

NVIDIA DGX Spark with GB10 GPU (128 GB unified LPDDR5X memory), CUDA 13.0 on DGX OS (Ubuntu 24.04, aarch64). Benchmarking both released quants of the newly released Ternary-Bonsai-2-27B:

- **PQ2_0 (default, group 128, 6.70 GiB)**: **27.79 t/s tg128** generation, **919.05 t/s pp512** prompt processing.
- **PTQ1_0 (high density, 1.75 bpw, 5.53 GiB)**: **32.83 t/s tg128** generation (**+18.1% generation speedup** over PQ2_0), but prompt processing regresses to **432.59 t/s pp512** (-53% slower prompt evaluation due to dequantization overhead).

## llama-bench Results

### PQ2_0 (Default, Group 128)

```bash
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa on -r 3
```

| model | size | params | backend | ngl | fa | test | t/s |
| --- | ---: | ---: | --- | --: | --: | ---: | ---: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 919.05 ± 57.64 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 27.79 ± 0.71 |

build: 5d80cff0b (10687)

### PTQ1_0 (High Density, 1.75 bpw)

```bash
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa on -r 3
```

| model | size | params | backend | ngl | fa | test | t/s |
| --- | ---: | ---: | --- | --: | --: | ---: | ---: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 432.59 ± 6.92 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 32.83 ± 1.10 |

build: 5d80cff0b (10687)

## Observations & Trade-offs

- **Generation vs Prompt Evaluation**: On memory-bandwidth-bound unified memory (273 GB/s peak on Grace Blackwell GB10), reducing the model size from 6.70 GiB (`PQ2_0`) to 5.53 GiB (`PTQ1_0`) yields a linear throughput gain from **27.79 t/s to 32.83 t/s (+18.1%)**. However, `PTQ1_0` prompt evaluation drops from **919.05 t/s down to 432.59 t/s (-53%)**, making `PQ2_0` preferable for prompt-heavy, RAG, or long-context prefill workloads, while `PTQ1_0` is optimal for long token generation.
- **Memory Footprint**: Both quants fit comfortably in the 128 GB unified memory envelope, leaving >115 GiB free for the full 262k context window.
- **Flash Attention**: Flash Attention (`-fa on`) functions cleanly on the GB10 Blackwell SM120/SM121 architecture.

## Configuration

- All layers offloaded (`-ngl 99`); flash attention enabled (`-fa on`)
- PrismML-Eng/llama.cpp `prism` commit `5d80cff0b` (build 10687), built for CUDA architecture `121a`
- NVIDIA driver 580.178.04; CUDA toolkit 13.0.88

## Hardware

```text
Architecture: aarch64
CPU(s): 20 (10 Cortex-X925 / 10 Cortex-A725)
Mem: 121 GiB unified LPDDR5X (273 GB/s bandwidth)
OS: Ubuntu 24.04.4 LTS (DGX OS, kernel 7.0.0-1019-nvidia)
GPU: NVIDIA GB10 (compute capability 12.1)
```
