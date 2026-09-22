# NVIDIA GeForce RTX 5080 (16 GB) — llama.cpp CUDA on Windows (Bonsai 2 27B)

## Summary

Bonsai 2 27B on a Windows 11 desktop with NVIDIA GeForce RTX 5080 (16 GB VRAM),
using the PrismML llama.cpp fork release `prism-b10709-9a9394a` (commit `9a9394a89`).

| Format | Backend | PP512 (t/s) | TG128 (t/s) |
|--------|---------|------------:|------------:|
| PQ2_0 | llama.cpp CUDA | 1687.64 ± 272.06 | 86.25 ± 3.62 |
| PTQ1_0 | llama.cpp CUDA | 895.81 ± 7.84 | 84.64 ± 0.09 |

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
  - `Ternary-Bonsai-2-27B-PQ2_0.gguf` (7,206,168,928 bytes, 6.70 GiB reported)
  - `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5,946,648,928 bytes, 5.53 GiB reported)
- llama.cpp: PrismML fork release `prism-b10709-9a9394a`
  (prebuilt binaries `llama-prism-b10709-9a9394a-bin-win-cuda-12.4-x64.zip`
  + CUDA runtime `cudart-llama-bin-win-cuda-12.4-x64.zip`)
- OS: Windows 11 Pro (build 26200)
- GPU: NVIDIA GeForce RTX 5080, 16 GB (16,275 MiB visible to the CUDA backend),
  driver 616.92, compute capability 12.0
- CPU: AMD Ryzen 7 9800X3D (8 cores); 62 GB system RAM
- Offload: `-ngl 99`, flash attention `-fa 1`, default KV cache (f16),
  default threads and batch sizes
- Power: stock, no tuning

### Methodology and comparison scope

No source build and no code changes: the PrismML prebuilt CUDA binaries were
used as downloaded (`llama-bench.exe` + CUDA runtime, CUDA 12.4). The only
pre-run step was stopping the resident `BonsaiLLM` inference service to free
the GPU; its configuration was not changed and it was restarted afterwards.

PQ2_0 and PTQ1_0 are both GGUF files from `prism-ml/Ternary-Bonsai-2-27B-gguf`,
run through the same binary with identical flags (`-p 512 -n 128 -ngl 99 -fa 1`,
3 repetitions each), so this is a clean packing-to-packing comparison on the
same backend. The development `Q2_0` format was not tested.

### Measurement conditions

The machine was otherwise idle.

## llama-bench results

```powershell
.\llama-bench.exe -m C:\bench-bonsai2\Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1 -r 3
.\llama-bench.exe -m C:\bench-bonsai2\Ternary-Bonsai-2-27B-PTQ1_0.gguf -p 512 -n 128 -ngl 99 -fa 1 -r 3
```

3 repetitions each (`-r 3`; the build default is 5). Same settings for both
packings, no overrides.

### PQ2_0

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 1687.64 ± 272.06 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 86.25 ± 3.62 |

build: 9a9394a89 (10709)

### PTQ1_0

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 895.81 ± 7.84 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 84.64 ± 0.09 |

build: 9a9394a89 (10709)

## Additional observations

In these runs, decode throughput (tg128) is similar for both packings
(~85–86 t/s), while average prompt processing is ~1.9x faster on PQ2_0 than on PTQ1_0.
PQ2_0 prefill has substantial run-to-run variation (±272.06 t/s, about 16% of
its mean across three repetitions), so the prefill ratio is an observed average,
not a precise speedup. The measurements above are reported unchanged.
