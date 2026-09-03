# Apple M1 Pro (16-core GPU, 32 GB) — MLX (2-bit)

## Summary

Apple M1 Pro with 16-core GPU and 32 GB unified memory, macOS 26.6.2.
Ternary-Bonsai-27B (MLX 2-bit): **~15.0 t/s generation, ~65.1 t/s prompt
processing** on plain `mlx_lm.benchmark`, peak memory 9.0 GB.

With the paired DSpark drafter under MLX via
[dspark-mlx](https://github.com/iggerask/dspark-mlx) (stock mlx 0.32.2,
greedy, output identical to plain decoding): **~10.2 t/s blended across four
workloads (0.74x)** — a net slowdown on this chip; high-acceptance math held
closest to baseline (12.3 t/s, 0.90x) while code/prose/qa lost ground. For
reference, llama.cpp Metal on the same machine measured **~8.4 t/s tg128**;
its DSpark path reached **~11.1 t/s on code (1.15x)** but **~8.1 t/s on chat
(0.85x)** via `BONSAI_SPECULATIVE=1`.

## MLX Results (2-bit)

Setup for speculative runs — harness from
[dspark-mlx](https://github.com/iggerask/dspark-mlx) in a separate venv with
stock PyPI mlx 0.32.2 (the demo's source-built mlx 0.31.x is too slow on the
2-bit verify batch for speculation to pay off):

```bash
pip install git+https://github.com/iggerask/dspark-mlx
dspark-convert --gguf models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-bf16.gguf \
    --output /tmp/dspark_Ternary-Bonsai-27B.safetensors
```

### Ternary-Bonsai-27B, plain mlx-lm

```bash
.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-27B-mlx-2bit -p 512 -g 128
```

```
Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=63.335, generation_tps=14.849, peak_memory=8.976, total_time=16.906
Trial 2:  prompt_tps=65.495, generation_tps=15.054, peak_memory=8.976, total_time=16.521
Trial 3:  prompt_tps=64.699, generation_tps=14.746, peak_memory=8.977, total_time=16.804
Trial 4:  prompt_tps=66.606, generation_tps=15.035, peak_memory=8.977, total_time=16.406
Trial 5:  prompt_tps=65.429, generation_tps=15.179, peak_memory=8.978, total_time=16.453
Averages: prompt_tps=65.113, generation_tps=14.972, peak_memory=8.977
```

Model: [Ternary-Bonsai-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-mlx-2bit)

llama-bench-style protocol (dspark-mlx `benchmark_release_protocol.py`, mlx
0.32.2, r=3):

```bash
python benchmarks/benchmark_release_protocol.py \
    --model models/Ternary-Bonsai-27B-mlx-2bit \
    --weights /tmp/dspark_Ternary-Bonsai-27B.safetensors --reps 3
```

pp512        :    48.51 ± 4.83 t/s
tg128 (raw)  :     9.53 ± 1.11 t/s
tg128 (greedy):   10.63 ± 2.76 t/s
tg128 (dspark):    6.72 ± 0.12 t/s (accept 30%)

### Ternary-Bonsai-27B + DSpark drafter (speculative, MLX)

The 27B ships with a paired DSpark drafter. [dspark-mlx](https://github.com/iggerask/dspark-mlx)
runs it under MLX (drafter Q4 at load, greedy verification, output
token-identical to plain greedy decoding — verified per run).

128-token generation, chat-templated prompt ("Write a short story about a
lighthouse keeper who discovers something unusual in the fog."), 3 reps,
EOS honored:

```bash
for i in 1 2 3; do
  dspark-generate -n 128 \
    --model models/Ternary-Bonsai-27B-mlx-2bit \
    --weights /tmp/dspark_Ternary-Bonsai-27B.safetensors \
    -p "Write a short story about a lighthouse keeper who discovers something unusual in the fog."
done
```

eos-honored: reps = ['64%/3.7t/s', '64%/5.6t/s', '64%/6.0t/s']

Four-workload suite, 250-token generations, best of 2:

```bash
python benchmarks/benchmark_dspark.py \
    --model models/Ternary-Bonsai-27B-mlx-2bit \
    --weights /tmp/dspark_Ternary-Bonsai-27B.safetensors \
    --max-tokens 250 --runs 2
```

code         base  14.0 t/s | dspark  10.7 t/s (0.77x) | accept 67% | tok/step 3.69 | identical=True
qa           base  13.6 t/s | dspark   8.4 t/s (0.62x) | accept 46% | tok/step 2.85 | identical=True
math         base  13.7 t/s | dspark  12.3 t/s (0.90x) | accept 79% | tok/step 4.15 | identical=True
prose        base  13.8 t/s | dspark   9.3 t/s (0.68x) | accept 52% | tok/step 3.10 | identical=True

On M1 Pro the verify-step overhead dominates even when acceptance is high; do
not enable MLX speculation on this generation — plain MLX (~15 t/s) or
llama.cpp DSpark on code-only workloads are the better options.

## llama.cpp reference (prebuilt binaries, same machine)

```bash
bin/mac/llama-bench -m models/ternary-gguf/27B/Ternary-Bonsai-27B-PQ2_0.gguf -ngl 99 -fa 1 -r 3
```

| model | size | params | backend | threads | fa | test | t/s |
| --- | ---: | ---: | --- | ---: | ---: | --- | ---: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.66 GiB | 26.90 B | MTL,BLAS | 8 | 1 | pp512 | 67.37 ± 10.25 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.66 GiB | 26.90 B | MTL,BLAS | 8 | 1 | tg128 | 8.37 ± 2.20 |

build: e311ed38f (10660)

### DSpark drafter (llama.cpp Metal)

One-time conversion from the bf16 sidecar (`setup.sh` downloads it); see
[SPECULATIVE.md](../../SPECULATIVE.md):

```bash
python gguf_dspark_to_dflash.py --drop-shared-tensors \
  models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-bf16.gguf \
  models/ternary-gguf/27B/Ternary-Bonsai-27B-PQ2_0.gguf \
  /tmp/drafter-conv.gguf
bin/mac/llama-quantize /tmp/drafter-conv.gguf \
  models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-dflash-Q4_0.gguf Q4_0
```

Then `BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh`. Measured via
`/v1/chat/completions` decode rate, greedy, 256-token cap:

| workload | no drafter | + DSpark | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| code ("Implement quicksort in Python.") | 9.6 t/s | 11.1 t/s | 64% (183/284) | **1.15x** |
| chat ("What are three fun things to do in Paris?") | 9.6 t/s | 8.1 t/s | 40% (156/386) | 0.85x |

## Configuration

- Plain MLX benchmark: mlx 0.31.2.dev20260902+10b5fe43 (source build via
  `setup.sh`), mlx-lm 0.31.2
- DSpark MLX harness: mlx 0.32.2, mlx-lm 0.31.3 (PyPI wheels via dspark-mlx)
- llama.cpp prebuilt release `prism-b10660-e311ed3`
- Drafter converted locally from `Ternary-Bonsai-27B-dspark-bf16.gguf`
  (MLX: `dspark-convert`; llama.cpp: `gguf_dspark_to_dflash.py` + Q4_0 quant)

## Hardware

```
ProductName:            macOS
ProductVersion:         26.6.2
BuildVersion:           25G83
machdep.cpu.brand_string: Apple M1 Pro
hw.memsize: 34359738368
hw.ncpu: 10
      Chipset Model: Apple M1 Pro
      Total Number of Cores: 16
      Metal Support: Metal 4
```
