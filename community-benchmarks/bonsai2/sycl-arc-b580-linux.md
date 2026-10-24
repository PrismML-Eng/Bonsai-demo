# Intel Arc B580 12 GB — SYCL on Linux

## Summary

Intel Arc B580 12 GB (Battlemage, BMG-G21, 20 Xe cores) on Linux, with Intel oneAPI 2026.1 / Level Zero (legacy adapter). Bonsai 2 27B `PTQ1_0` fully GPU-offloaded, flash attention on, q4_0 KV cache. Built from the Torchit1 SYCL development branch of llama.cpp (derived from PrismML llama.cpp; not yet public).

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|------------:|------------:|
| Bonsai 2 27B `PTQ1_0` | 1,593.11 ± 3.89 | 47.94 ± 0.02 |

## llama-bench Results

```bash
llama-bench -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 \
  -ub 512 -b 2048 -p 512 -n 128 -r 5
```

Runtime settings: the development branch's recommended Arc B580 configuration.

| model | size | params | backend | ngl | type_k | type_v | fa | test | t/s |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.85 GiB | 27.32 B | SYCL | 99 | q4_0 | q4_0 | 1 | pp512 | 1593.11 ± 3.89 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.85 GiB | 27.32 B | SYCL | 99 | q4_0 | q4_0 | 1 | tg128 | 47.94 ± 0.02 |

build: Torchit1 SYCL development branch (b6ecc0b2d)

## Serving with MTP speculative decoding (not comparable to llama-bench)

`llama-server` with the MTP head (`--spec-type draft-mtp,ngram-mod --spec-draft-n-max 4`), one user, 160K context, measured with BetterBench 0.6.1 (corpus v1.0, temperature 0.7, two runs):

- Combined decode: 98.3 / 100.8 t/s
- TTFT p50: 78 ms
- Prefill at 2K / 8K / 16K / 32K / 64K: about 1,490 / 1,580 / 1,545 / 1,420 / 1,230 t/s

## System

- GPU: Intel Arc B580 12 GB, PCIe, Linux host (Unraid), container with oneAPI 2026.1
- Model file: `Ternary-Bonsai-2-27B-PTQ1_0` (MTP bundle, plain inference for llama-bench)
