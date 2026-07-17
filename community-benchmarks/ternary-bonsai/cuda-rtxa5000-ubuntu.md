# NVIDIA RTX A5000 — CUDA

## Summary

RTX A5000 24 GB (GA102, Ampere sm_86) + prebuilt CUDA binaries (release `prism-b9591-62061f9`) on Ubuntu 22.04, driver 580.159.03. Ternary-Bonsai-27B Q2_0: **~1036 t/s pp512, ~48 t/s tg128** at depth 0, holding 41 t/s tg at 32K depth. For reference, a Q4_K_M quant of the same 27B base model on the same GPU decodes at ~33 t/s tg128 — an observed **~1.45× ternary decode advantage** at ~2.3× smaller weights. The two runs use different quant kernels and builds, so this is an end-to-end observed difference rather than an isolated memory-bandwidth measurement.

## llama-bench Results

### Ternary-Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
LD_LIBRARY_PATH=$PWD/bin/cuda $BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1035.52 ± 12.21 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         48.20 ± 0.51 |

build: 62061f910 (9591)

Context-depth extension (same flags plus `-d 16384,32768`):

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  pp512 @ d16384 |       866.73 ± 27.42 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  tg128 @ d16384 |         45.20 ± 0.23 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  pp512 @ d32768 |       734.97 ± 18.28 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | CUDA       |  99 |   1 |  tg128 @ d32768 |         41.25 ± 0.25 |

build: 62061f910 (9591)

### Qwen3.6-27B Q4_K_M (reference)

Same 27B base model quantized to Q4_K_M (15.40 GiB), same `-ngl 99 -fa 1` flags, on a mainline-derived llama.cpp fork (build 9767). This is the comparison point for the decode numbers above:

```bash
BENCH=llama-bench   # mainline-derived fork, build 9767 (15d22acc8)
$BENCH -m Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -d 0,32768
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1016.66 ± 10.74 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         33.31 ± 0.13 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | CUDA       |  99 |   1 |  pp512 @ d32768 |        735.68 ± 8.22 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | CUDA       |  99 |   1 |  tg128 @ d32768 |         29.26 ± 0.17 |

build: 15d22acc8 (9767)

Observed decode delta (ternary vs Q4_K_M, same GPU): **48.20 / 33.31 ≈ 1.45×** at depth 0 and **41.25 / 29.26 ≈ 1.41×** at 32K, at ~2.3× smaller weights. Because the two paths use different quant kernels and different builds (9591 vs 9767), treat this as an observed end-to-end decode difference, not an isolated memory-bandwidth measurement.

## Served (llama-server) measurement

The kernel-level ternary numbers hold up served end-to-end. Ternary-Bonsai-27B run through `llama-server` (q4_0 KV + mean-center bias, 131072 ctx) on the PrismML patched fork, build 9592 (52dac8d02):

```bash
# server (patched fork, build 9592)
bin/cuda-patched/llama-server \
  -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf \
  --mmproj models/ternary-gguf/27B/Ternary-Bonsai-27B-mmproj-BF16.gguf \
  -ngl 99 -fa on -c 131072 \
  --cache-type-k q4_0 --cache-type-v q4_0 \
  --kv-mean-center models/ternary-gguf/27B/Ternary-Bonsai-27B-kv-bias.gguf \
  --host 127.0.0.1 --port 8080 --alias ternary-bonsai-27b-kv4
```

```bash
# client: llama-benchy 0.3.5, OpenAI-compatible endpoint
llama-benchy \
  --base-url http://localhost:8080/v1 \
  --model ternary-bonsai-27b-kv4-sweep \
  --served-model-name ternary-bonsai-27b-kv4 \
  --tokenizer Qwen/Qwen3.6-27B \
  --pp 2048 --tg 128 \
  --depth 0 4096 8192 16384 32768 65536 98304 122880 \
  --runs 2 --no-cache --latency-mode generation
```

| model                        |             test |            t/s |          ttfr (ms) |
|:-----------------------------|-----------------:|---------------:|-------------------:|
| ternary-bonsai-27b-kv4-sweep |           pp2048 | 909.16 ± 23.03 |    2440.18 ± 57.12 |
| ternary-bonsai-27b-kv4-sweep |            tg128 |   46.77 ± 0.01 |                    |
| ternary-bonsai-27b-kv4-sweep |  pp2048 @ d16384 |  863.58 ± 6.90 |  21531.21 ± 170.46 |
| ternary-bonsai-27b-kv4-sweep |   tg128 @ d16384 |   37.29 ± 0.01 |                    |
| ternary-bonsai-27b-kv4-sweep |  pp2048 @ d32768 |  818.03 ± 0.37 |   42746.61 ± 18.48 |
| ternary-bonsai-27b-kv4-sweep |   tg128 @ d32768 |   32.21 ± 0.04 |                    |

The full 0→122880 sweep continues to 583.83 ± 0.22 pp2048 / 18.45 ± 0.01 tg128 at d122880. The served depth-0 prefill/decode (909 / 46.8) is consistent with the bare-AR llama-bench numbers above.

## Configuration

- Prebuilt release binaries from `./scripts/download_binaries.sh` (`prism-b9591-62061f9`, CUDA 12.4 asset), default llama-bench settings otherwise (f16 KV).
- The three paths use different builds — ternary llama-bench 9591 (`62061f910`), Q4_K_M reference 9767 (`15d22acc8`), served patched fork 9592 (`52dac8d02`) — so cross-quant deltas are observed end-to-end differences, not isolated kernel measurements.

## Notes

- Driver 580.159.03, stock clocks/power, small always-on embedding server (~1 GB VRAM) co-resident during runs.
- Vision projector and dspark drafter not loaded for these runs (llama-bench measures the bare autoregressive model).

## Hardware

NVIDIA RTX A5000 24 GB (GA102, compute 8.6), AMD Ryzen 9 7945HX, 38 GiB DDR5, Ubuntu 22.04 (kernel 6.8).
