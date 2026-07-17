# Apple M5 Pro — MLX (2-bit)

## Summary

MacBook Pro, Apple M5 Pro, 64 GB unified memory, macOS 26.5.1.
Ternary-Bonsai-27B, MLX 2-bit pack, on stock mlx 0.32.0 + mlx-lm 0.31.3.

Headline numbers: pp512 466 t/s, tg128 29.5 t/s on plain mlx-lm. With the
DSpark drafter running under MLX via [dspark-mlx](https://github.com/iggerask/dspark-mlx)
(speculative decoding, greedy, output identical to plain decoding): 42 t/s
on a chat prompt, 33.6-48.7 t/s across workloads. For reference, the
prebuilt llama.cpp binaries measure tg128 26.5 / pp512 130.5 on the same
machine.

## llama.cpp reference (prebuilt binaries, same machine)

Command: `bin/mac/llama-bench -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -fa 1 -r 5`

| model                          |       size |     params | backend    | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | -: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           pp512 |        130.47 ± 1.32 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | MTL,BLAS   |       6 |   1 |           tg128 |         26.53 ± 0.06 |

build: 62061f910 (9591)

Note: the Metal init logs `has tensor = false` on this machine, so this
build does not use the M5 tensor cores; that likely explains the pp512 gap
vs the published table.

## MLX Results (2-bit)

Setup — the MLX speculative harnesses live in the linked repo:

```bash
git clone https://github.com/iggerask/dspark-mlx && cd dspark-mlx
pip install -e .   # pulls mlx 0.32.0, mlx-lm 0.31.3

# One-time: convert prism-ml's BF16 drafter GGUF -> MLX safetensors.
# The drafter is quantized to 4-bit at load (quantize_drafter=True, the
# default in every harness below); there is no separate quantize step.
hf download prism-ml/Ternary-Bonsai-27B-gguf Ternary-Bonsai-27B-dspark-bf16.gguf --local-dir /tmp/dspark
dspark-convert --gguf /tmp/dspark/Ternary-Bonsai-27B-dspark-bf16.gguf \
    --output weights/dspark_Ternary-Bonsai-27B.safetensors
```

### Ternary-Bonsai-27B, plain mlx-lm

llama-bench-style protocol (fresh cache per rep, r=5, no chat template;
harness: benchmarks/benchmark_release_protocol.py in the dspark-mlx repo).
tg128 (raw) decodes predetermined tokens like llama-bench's tg test;
tg128 (greedy) is argmax-chained generation.

```bash
python benchmarks/benchmark_release_protocol.py \
    --model prism-ml/Ternary-Bonsai-27B-mlx-2bit \
    --weights weights/dspark_Ternary-Bonsai-27B.safetensors --reps 5
```

pp512        :   465.97 ± 10.21 t/s
tg128 (raw)  :    29.53 ± 0.41 t/s
tg128 (greedy):   29.78 ± 0.29 t/s

### Ternary-Bonsai-27B + DSpark drafter (speculative, MLX)

The 27B ships with a paired DSpark drafter. The llama.cpp speculative path
is documented as CUDA-only for now; [dspark-mlx](https://github.com/iggerask/dspark-mlx)
runs the same drafter weights under MLX (drafter Q4, greedy verification,
output token-identical to plain greedy decoding — verified per run).

128-token generation, chat-templated prompt ("Write a short story about a
lighthouse keeper who discovers something unusual in the fog."), 3 reps,
EOS honored (chat template applied by default), format accept/t-s:

```bash
for i in 1 2 3; do
  dspark-generate -n 128 \
    -p "Write a short story about a lighthouse keeper who discovers something unusual in the fog."
done
```

eos-honored: reps = ['63%/41.9t/s', '63%/42.1t/s', '63%/42.1t/s']

Four-workload suite, 250-token generations, best of 2:

```bash
python benchmarks/benchmark_dspark.py \
    --model prism-ml/Ternary-Bonsai-27B-mlx-2bit \
    --weights weights/dspark_Ternary-Bonsai-27B.safetensors \
    --max-tokens 250 --runs 2
```

code         base  30.0 t/s | dspark  44.2 t/s (1.48x) | accept 67% | tok/step 3.69 | identical=True
qa           base  30.1 t/s | dspark  33.6 t/s (1.12x) | accept 46% | tok/step 2.85 | identical=True
math         base  30.1 t/s | dspark  48.7 t/s (1.62x) | accept 77% | tok/step 4.07 | identical=True
prose        base  29.8 t/s | dspark  36.5 t/s (1.23x) | accept 52% | tok/step 3.10 | identical=True

## Configuration

- mlx 0.32.0, mlx-lm 0.31.3 (pip, no forks or patches to either).
  mlx >= 0.32 is needed for its improved 2-bit multi-token kernels; the
  speculative verify batch is much slower on 0.31.x.
- Drafter converted locally from prism-ml's BF16 GGUF
  (Ternary-Bonsai-27B-dspark-bf16.gguf) with dspark-convert, then
  quantized to 4-bit at load. 4-bit is the acceptance floor: a 3-bit
  drafter measured 60% accept / 40.3 t/s and 2-bit 46% / 33.9 t/s on the
  code workload, both slower end to end than 4-bit.
- Acceptance is workload- and context-dependent (19-77% observed).
  Contextless prompts (llama-bench-style) are the worst case for the
  drafter; the margin_tau=1.5 option truncates low-confidence draft tails
  and holds the worst case at baseline speed.

## Notes

- Speculative decoding here is greedy-only and batch 1.
- No other applications running; power connected; several minutes of
  sustained load per suite, no visible thermal drop across reps.

## Hardware

- MacBook Pro, Apple M5 Pro, 64 GB unified memory
- macOS 26.5.1
