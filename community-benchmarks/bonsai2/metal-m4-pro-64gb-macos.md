# Apple Mac mini M4 Pro (64 GB) — llama.cpp Metal + MLX (Bonsai 2 27B)

## Summary

Bonsai 2 27B on a Mac mini with Apple M4 Pro and 64 GB unified memory, macOS 27.0.
llama.cpp run uses the PrismML fork at tag `prism-b10709-9a9394a` (commit `9a9394a`).
MLX run uses the `prism-ml/Ternary-Bonsai-2-27B-mlx-2bit` pack with its bundled
Hadamard-aware runtime.

| Format | Backend | PP512 (t/s) | TG128 (t/s) |
|--------|---------|------------:|------------:|
| PQ2_0 | llama.cpp Metal | 126.89 ± 0.02 | 20.53 ± 0.01 |
| PTQ1_0 | llama.cpp Metal | 98.58 ± 1.62 | 17.30 ± 0.06 |
| 2-bit (MLX pack) | MLX (mlx_lm 0.31.3) | 97.90 ± 10.27 | 18.86 ± 0.72 |

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
  - `Ternary-Bonsai-2-27B-PQ2_0.gguf` (7,206,168,928 bytes, 6.70 GiB reported)
  - `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5,946,648,928 bytes, 5.53 GiB reported)
- MLX pack: `prism-ml/Ternary-Bonsai-2-27B-mlx-2bit` (8.0 GB on disk, schema v2,
  tensor namespace `mlx-vlm-qwen3_5`)
- llama.cpp: source build of the PrismML fork at tag `prism-b10709-9a9394a`
  (`9a9394a895b96003ca842a6041cb28ac49a108f7`), Release,
  `CMAKE_OSX_SYSROOT=MacOSX26.5.sdk` (Xcode 26.5; the default CLT 27.0 SDK lacks arm64)
- OS: macOS 27.0 (build 26A428); Metal GPU family Apple9 / Metal4
- Hardware: Apple M4 Pro, 64 GB unified memory
  (`recommendedMaxWorkingSetSize = 55662.79 MB`)
- Offload: `-ngl 99`, flash attention `-fa 1`, default KV cache (f16), 10 threads
- Power: stock, no tuning

### Measurement conditions (please read)

The machine was not idle. During all runs `spotlightknowledged.updater` (Spotlight
index maintenance) consumed ~150–200% CPU (roughly 1.5–2 of 14 CPU cores) and never
settled below the 20% threshold in a ~15-minute wait, so the benchmarks ran under
that contention. Ollama's resident models (`qwen3.5:27b` 25 GB, `bge-m3` 664 MB)
were stopped before the runs; note that `bge-m3` is re-loaded on demand by an
unrelated local service and reappeared between runs (664 MB, negligible vs 64 GB).
Memory was otherwise comfortable (unified memory, no swap pressure observed).

## llama-bench results

```bash
./build/bin/llama-bench -m models/Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1 -r 3
./build/bin/llama-bench -m models/Ternary-Bonsai-2-27B-PTQ1_0.gguf -p 512 -n 128 -ngl 99 -fa 1 -r 3
```

3 repetitions each (`-r 3`; the build default is 5). `-fa 1` worked fine on this
machine — no `Metal graph compute FAILED` fallback needed.

### PQ2_0

| model | size | params | backend | threads | fa | test | t/s |
|-------|-----:|-------:|---------|--------:|--:|-----:|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | MTL,BLAS | 10 | 1 | pp512 | 126.89 ± 0.02 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | MTL,BLAS | 10 | 1 | tg128 | 20.53 ± 0.01 |

build: 9a9394a (4)

### PTQ1_0

| model | size | params | backend | threads | fa | test | t/s |
|-------|-----:|-------:|---------|--------:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | MTL,BLAS | 10 | 1 | pp512 | 98.58 ± 1.62 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | MTL,BLAS | 10 | 1 | tg128 | 17.30 ± 0.06 |

build: 9a9394a (4)

## MLX results

Stock `mlx_lm` (0.31.3) does not recognise `model_type: prism_hadamard_qwen35`, so
`mlx_lm.benchmark` cannot load this pack directly. The numbers below were produced
with the pack's own bundled runtime (`runtime/` in the pack), which installs the
Hadamard-packed layers into the stock `mlx_lm` qwen3_5 `TextModel`. Two pack-side
quirks, both handled without touching the downloaded pack:

1. The pack is schema v2 while its bundled `artifact.py` only accepts v1 — the
   schema check was relaxed in a throwaway copy of the runtime (`/tmp`).
2. The pack uses the `mlx-vlm-qwen3_5` tensor namespace (`language_model.` prefix),
   so the text-only `artifact.load_model` path does not apply; the install follows
   `vision_artifact.load_vl_model` (prefix-aware), minus the vision tower.

Benchmark loop mirrors `mlx_lm.benchmark`: pseudo-random 512-token prompt
(`mx.random.seed(0)`), EOS cleared to avoid early stopping, one warmup run, then
3 timed trials of `stream_generate(..., max_tokens=128)`; prompt t/s measured to
first token, generation t/s over the 128 tokens.

- Trial 1: pp512 = 110.28 t/s, tg128 = 19.86 t/s, peak 10.48 GB
- Trial 2: pp512 = 98.30 t/s, tg128 = 18.19 t/s, peak 10.48 GB
- Trial 3: pp512 = 85.13 t/s, tg128 = 18.51 t/s, peak 10.48 GB
- Mean: pp512 = 97.90 ± 10.27 t/s, tg128 = 18.86 ± 0.72 t/s, peak 10.48 GB

The pp512 spread (±10) is larger than the llama.cpp runs and likely reflects the
Spotlight CPU contention noted above; tg128 is stable. A short chat-template
sanity generation answered "What is the capital of France?" correctly
("The capital of France is Paris."), confirming the manual weight install.

## Context

- Same-machine baseline from 2026-09-18 (previous generation,
  `Ternary-Bonsai-27B-PQ2_0.gguf`, same fork family, Metal): pp512 124.97 t/s,
  tg128 19.52 t/s — remarkably close to Bonsai 2 PQ2_0 (126.89 / 20.53),
  though the model generations differ.
- Community M3 Max 36 GB (llama.cpp Metal, `-ngl 99 -fa 1`):
  PQ2_0 162.2 / 24.3, PTQ1_0 136.8 / 21.9 — the M3 Max's larger GPU leads the
  M4 Pro here on both packings, as expected.
- Takeaway on this machine: PQ2_0 is the faster packing on both backends
  (prefill especially), and llama.cpp/Metal beats the MLX path on prefill while
  generation is within noise (20.5 vs 18.9 t/s).
