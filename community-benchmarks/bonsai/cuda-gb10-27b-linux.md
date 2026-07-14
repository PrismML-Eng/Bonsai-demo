# NVIDIA DGX Spark (GB10) — CUDA — Bonsai-27B

## Summary

NVIDIA DGX Spark with GB10 GPU (128 GB unified LPDDR5X memory), CUDA 13.0 on DGX OS (Ubuntu 24.04 base, aarch64). Extends the existing [GB10 results](cuda-gb10-linux.md) (8B/4B/1.7B) with the **27B model**: **~44 t/s tg128, ~1,003 t/s pp512** — full 27B-class reasoning at reading speed on a compact unified-memory box.

Also tested speculative decoding against the 27B Q1_0 target on this hardware: it does not help (details in Configuration).

## llama-bench Results

### Bonsai-27B

```bash
BENCH=llama.cpp-prism/build/bin/llama-bench
$BENCH -m models/gguf/27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |       1003.34 ± 7.71 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         44.14 ± 0.06 |

build: 62061f9 (branch `prism`, built from source)

## Configuration

- Server-mode sustained generation (320-token responses via `/v1/chat/completions`, temp 0, 3 passes) matches llama-bench closely: 43.7 t/s.
- Speculative decoding on the 27B Q1_0 target was consistently neutral-to-negative on this hardware — the Q1_0 forward pass is cheap enough that drafting overhead cancels verification-batching gains:
  - `draft-dspark` with the official 27B DSpark drafter (Q4_1, `--spec-draft-n-max 4`): 21.6 t/s at 78% acceptance (vs 43.7 base)
  - Same drafter requantized to Q2_K: 21.2 t/s (still ~2x slower than base)
  - Bonsai-8B-Q1_0 as a `draft-simple` drafter: 43.9 t/s — exact wash with base
  - `ngram-simple`: ~6% acceptance on reasoning-heavy output, no gain
  - KV-cache quantization (q8_0/q4_0) and batch tuning (`-b 4096 -ub 1024`): no measurable change
- The experimental `megakernel/rmsnorm-qmv-fuse` branch (5d906dc) measured 42.82 ± 0.08 tg128 — parity with `prism` on this GPU.

## Notes

- NVIDIA driver 580.126.09, CUDA 13.0, GPU compute capability 12.1
- Numbers are stable across runs (± 0.1 t/s server-mode)
- For contrast, standard PTQ imatrix quants of the same model (Q4_K_M, 16.6 GB) decode at ~12 t/s on this hardware (bandwidth-bound), where the DSpark drafter *does* help: 15.7 t/s (+31%) at 79% acceptance

## Hardware

```
Architecture:                            aarch64
CPU(s):                                  20 (Cortex-X925 / Cortex-A725)
Mem:                                     119Gi unified LPDDR5X
NVIDIA-SMI 580.126.09    Driver Version: 580.126.09    CUDA Version: 13.0
GPU: NVIDIA GB10 (compute capability 12.1)
```
