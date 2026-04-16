# AMD Strix Halo — Vulkan (Radeon 8060S)

## Summary

AMD Ryzen AI MAX+ 395 (24-core Zen 5, 20 WGP / 40 CU RDNA 3.5 GPU) with 128 GB unified LPDDR5X memory, running Arch Linux (kernel 7.0.0-1-mainline). Backend: Vulkan (gfx1151). All layers offloaded to GPU (`-ngl 99`).

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|-------------|-------------|
| Bonsai-8B | 831 | 64 |
| Bonsai-4B | 1,401 | 85 |
| Bonsai-1.7B | 3,121 | 137 |

## llama-bench Results

### Bonsai-8B

```bash
LD_LIBRARY_PATH=~/prism-llamacpp/llama-prism-b8796-e2d6742 \
  ~/prism-llamacpp/llama-prism-b8796-e2d6742/llama-bench \
  -m ~/models/bonsai/Bonsai-8B.gguf -ngl 99 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | Vulkan     |  99 |           pp512 |        831.39 ± 2.19 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | Vulkan     |  99 |           tg128 |         63.77 ± 0.08 |

build: e2d67422c (8796)

### Bonsai-4B

```bash
LD_LIBRARY_PATH=~/prism-llamacpp/llama-prism-b8796-e2d6742 \
  ~/prism-llamacpp/llama-prism-b8796-e2d6742/llama-bench \
  -m ~/models/bonsai/Bonsai-4B.gguf -ngl 99 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | Vulkan     |  99 |           pp512 |       1401.27 ± 7.09 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | Vulkan     |  99 |           tg128 |         84.99 ± 0.33 |

build: e2d67422c (8796)

### Bonsai-1.7B

```bash
LD_LIBRARY_PATH=~/prism-llamacpp/llama-prism-b8796-e2d6742 \
  ~/prism-llamacpp/llama-prism-b8796-e2d6742/llama-bench \
  -m ~/models/bonsai/Bonsai-1.7B.gguf -ngl 99 -r 3
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | Vulkan     |  99 |           pp512 |      3120.79 ± 33.23 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | Vulkan     |  99 |           tg128 |        136.84 ± 0.23 |

build: e2d67422c (8796)

## Configuration

Vulkan backend with all layers offloaded to GPU. Pre-built binary from PrismML GitHub Releases.

## Notes

- llama.cpp build: `e2d67422c (8796)` (PrismML fork, release `prism-b8796-e2d6742`)
- All models fit in 128 GB unified memory (LPDDR5X)
- Vulkan backend auto-detects Radeon 8060S (RDNA 3.5, gfx1151) with cooperative matrix support
- CPU backend: zen4 (AVX-512 + VNNI)
- Flash attention not available on Vulkan (Metal-only in this build)
- Prompt processing (pp512) significantly faster than M4 Pro Metal — Strix Halo has higher raw compute throughput
- Text generation (tg128) slower than Metal — Metal Q1_0 kernels are more optimized for autoregressive decode

## Also benchmarked on this hardware

| Model | Quant | Size | Backend | tg128 t/s |
|-------|-------|------|---------|----------:|
| Qwen3-Coder-Next 80B.A3B | IQ1_S (1.56 bpw) | 17.6 GB | Vulkan | 64.9 |
| MS BitNet 2B-4T | i2_s | 1.71 GB | CPU (ik_llama.cpp) | 58.8 |

Full multi-backend results: https://github.com/stampby/bleeding-edge

## Hardware

```
CPU:     AMD Ryzen AI MAX+ 395 (24C/48T Zen 5, 5.1 GHz boost)
GPU:     Radeon 8060S (40 CU RDNA 3.5, gfx1151, 2.9 GHz)
NPU:     XDNA2 (50 TOPS)
RAM:     128 GB LPDDR5X unified memory
OS:      Arch Linux (CachyOS kernel 7.0.0-1-mainline)
ROCm:    7.12.0 (TheROCk)
Vulkan:  1.3 (RADV STRIX_HALO)
```
