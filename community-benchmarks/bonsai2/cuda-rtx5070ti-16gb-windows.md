# NVIDIA GeForce RTX 5070 Ti (16 GB) - llama.cpp CUDA on Windows (Bonsai 2 27B)

## Summary

Bonsai 2 27B on a Windows 11 desktop with an NVIDIA GeForce RTX 5070 Ti (16 GB VRAM),
using the PrismML llama.cpp fork release `prism-b10787-73bfe6c` (build `73bfe6cc4`),
the CUDA 13.3 prebuilt binaries that `setup.ps1` selects for this driver. Both packings
were run twice, alternated (PTQ1_0, PQ2_0, PTQ1_0, PQ2_0); the table shows the first
round, the second is in the raw output below.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 2044.67 ± 40.37 | 86.91 ± 0.07 |
| PTQ1_0 | 1958.61 ± 34.14 | 99.25 ± 0.10 |
| Q2_0 (development) | not tested | not tested |

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
  - `Ternary-Bonsai-2-27B-PQ2_0.gguf` (7,206,168,928 bytes, sha256
    `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`)
  - `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5,946,648,928 bytes, sha256
    `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`)
  - Both hashes match the repository's LFS hashes.
- llama.cpp: PrismML fork release `prism-b10787-73bfe6c`, prebuilt and unmodified:
  `llama-prism-b10787-73bfe6c-bin-win-cuda-13.3-x64.zip` plus
  `cudart-llama-bin-win-cuda-13.3-x64.zip`, unpacked to `bin\cuda` as `setup.ps1` does
- OS: Windows 11 Pro (build 26200)
- GPU: NVIDIA GeForce RTX 5070 Ti, 16 GB (16,275 MiB visible to the CUDA backend),
  compute capability 12.0, driver 617.42 (CUDA UMD 13.4), stock 300 W power limit
- CPU: Intel Core Ultra 7 270K Plus
- System RAM: 32 GB
- Offload: `-ngl 99`, flash attention `-fa 1`, default KV cache (f16), default threads,
  batch sizes and repetitions (`-r 5`), stock clocks, no `GGML_*` or `LLAMA_*` environment
  overrides, idle desktop with no other llama.cpp process running

## llama-bench results

Run from the repository root, alternated, two rounds:

```powershell
.\bin\cuda\llama-bench.exe -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -p 512 -n 128 -ngl 99 -fa 1
.\bin\cuda\llama-bench.exe -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

### PQ2_0

Round 1 (GPU 51 °C at start):

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 2044.67 ± 40.37 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 86.91 ± 0.07 |

Round 2 (GPU 55 °C at start):

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 2048.15 ± 47.23 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 86.83 ± 0.12 |

build: 73bfe6cc4 (10787)

### PTQ1_0

Round 1 (GPU 45 °C at start):

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 1958.61 ± 34.14 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 99.25 ± 0.10 |

Round 2 (GPU 52 °C at start):

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 1959.10 ± 40.01 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 99.16 ± 0.26 |

build: 73bfe6cc4 (10787)

### Q2_0 (development)

Not tested.

## Additional observations

Not measured here: server, speculative decoding, long-context, vision and quality.
