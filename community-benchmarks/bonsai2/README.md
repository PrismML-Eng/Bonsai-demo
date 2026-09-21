# Bonsai-2 Community Benchmarks

Benchmark results submitted by the community running Bonsai-2 models on their own
hardware.

## Results

### Bonsai-2-27B

| Hardware | Backend | PP512 (t/s) | TG128 (t/s) | Details |
|----------|---------|------------:|------------:|---------|
| AMD Radeon RX 7800 XT 16 GB (gfx1101) | llama.cpp ROCm/HIP (fork binary prism-b10709-9a9394a) | 316.3 | 46.8 | [link](rocm-hip-rx7800xt-fedora44.md) |

¹ Cold-prompt prefill at 11.2K tokens: 295.9 t/s (≈ 37.9 s). The linked report also
includes pp64/tg4, a long-context q4_0-KV ("no bias") depth ladder, and a working
262,144-token context recipe on 16 GB.

## Available Formats

- **GGUF** (`PQ2_0`):
  - [prism-ml/Ternary-Bonsai-2-27B-gguf-dev](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf-dev)
    — current testing format, requires the PrismML fork (not loadable by stock
    llama.cpp); public 27B GGUF repos also exist.

## How to Submit

1. Run `BONSAI_FAMILY=bonsai2 ./setup.sh` (adjust if the family env differs)
2. Follow the llama.cpp template from the
   [ternary-bonsai family](../ternary-bonsai/TERNARY-TEMPLATE-llama-cpp.md) until a
   Bonsai-2-specific template lands. Naming: `<backend>-<hardware>-<os>.md`
3. Open a PR to this repo with your file placed in this subfolder
