# AMD Strix Halo 128 GB - ROCm HIP

## Summary

AMD Ryzen AI Max+ 395 (Strix Halo), Radeon 8060S (`gfx1151`), 128 GB unified memory. Backend: ROCm HIP using the PrismML `prism` branch of llama.cpp at `d104cf1b6` (`prism-b8846-d104cf1`), built with `GGML_HIP=ON` and `AMDGPU_TARGETS=gfx1151`. All layers were offloaded to GPU (`-ngl 99`) with flash attention enabled (`-fa 1`).

| Model | Quant | Size | pp512 (t/s) | pp2048 (t/s) | tg128 (t/s) | tg512 (t/s) |
|-------|-------|------|-------------|--------------|-------------|-------------|
| Ternary-Bonsai-1.7B | Q2_0 | 436.2 MiB | 5,324 | 4,896 | 227 | 219 |
| Ternary-Bonsai-4B | Q2_0 | 1019.5 MiB | 2,205 | 1,988 | 115 | 114 |
| Ternary-Bonsai-8B | Q2_0 | 2.03 GiB | 1,243 | 1,181 | 78 | 78 |

## llama-bench Results

### Isolated prompt/decode

```bash
PATH=/opt/rocm/bin:$PATH \
LD_LIBRARY_PATH=bin/rocm:/opt/rocm/lib \
./bin/rocm/llama-bench \
  -m models/ternary-gguf/<size>/Ternary-Bonsai-<size>-Q2_0.gguf \
  -ngl 99 -fa 1 -p 128,512,2048 -n 0,128,512 -r 5 -o jsonl
```

| model | size | params | backend | ngl | fa | test | t/s |
|---|---:|---:|---|---:|---:|---:|---:|
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | ROCm | 99 | 1 | pp128 | 4484.49 +/- 27.21 |
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | ROCm | 99 | 1 | pp512 | 5323.98 +/- 21.80 |
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | ROCm | 99 | 1 | pp2048 | 4895.75 +/- 69.05 |
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | ROCm | 99 | 1 | tg128 | 226.83 +/- 0.51 |
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | ROCm | 99 | 1 | tg512 | 218.93 +/- 0.31 |
| qwen3 4B Q2_0 | 1019.5 MiB | 4.02 B | ROCm | 99 | 1 | pp128 | 2214.76 +/- 43.92 |
| qwen3 4B Q2_0 | 1019.5 MiB | 4.02 B | ROCm | 99 | 1 | pp512 | 2204.51 +/- 12.58 |
| qwen3 4B Q2_0 | 1019.5 MiB | 4.02 B | ROCm | 99 | 1 | pp2048 | 1987.75 +/- 2.60 |
| qwen3 4B Q2_0 | 1019.5 MiB | 4.02 B | ROCm | 99 | 1 | tg128 | 115.15 +/- 0.61 |
| qwen3 4B Q2_0 | 1019.5 MiB | 4.02 B | ROCm | 99 | 1 | tg512 | 113.88 +/- 0.09 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | ROCm | 99 | 1 | pp128 | 1227.80 +/- 41.03 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | ROCm | 99 | 1 | pp512 | 1243.48 +/- 3.41 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | ROCm | 99 | 1 | pp2048 | 1181.10 +/- 3.51 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | ROCm | 99 | 1 | tg128 | 78.28 +/- 0.15 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | ROCm | 99 | 1 | tg512 | 77.52 +/- 0.25 |

### Combined prompt + generation

```bash
PATH=/opt/rocm/bin:$PATH \
LD_LIBRARY_PATH=bin/rocm:/opt/rocm/lib \
./bin/rocm/llama-bench \
  -m models/ternary-gguf/<size>/Ternary-Bonsai-<size>-Q2_0.gguf \
  -ngl 99 -fa 1 \
  -pg 128,128 -pg 512,128 -pg 2048,128 -pg 512,512 \
  -r 3 -o jsonl
```

| model | pp+tg | t/s |
|---|---:|---:|
| qwen3 1.7B Q2_0 | 128+128 | 430.56 +/- 0.36 |
| qwen3 1.7B Q2_0 | 512+128 | 909.98 +/- 9.84 |
| qwen3 1.7B Q2_0 | 2048+128 | 1865.64 +/- 24.75 |
| qwen3 1.7B Q2_0 | 512+512 | 389.49 +/- 1.40 |
| qwen3 4B Q2_0 | 128+128 | 215.43 +/- 2.09 |
| qwen3 4B Q2_0 | 512+128 | 456.50 +/- 2.64 |
| qwen3 4B Q2_0 | 2048+128 | 909.66 +/- 4.47 |
| qwen3 4B Q2_0 | 512+512 | 203.67 +/- 0.43 |
| qwen3 8B Q2_0 | 128+128 | 145.29 +/- 0.89 |
| qwen3 8B Q2_0 | 512+128 | 304.61 +/- 0.91 |
| qwen3 8B Q2_0 | 2048+128 | 609.48 +/- 0.40 |
| qwen3 8B Q2_0 | 512+512 | 141.32 +/- 0.11 |

build: `d104cf1b6` (`8846`)

Raw JSONL from the run is stored under `benchmarks/data/`.

## Flash Attention Comparison

Follow-up comparison at `pp512/tg128` with flash attention disabled and enabled:

| Model | FA | pp512 (t/s) | tg128 (t/s) |
|---|---:|---:|---:|
| Ternary-Bonsai-1.7B Q2_0 | 0 | 4843.50 +/- 36.70 | 199.52 +/- 0.55 |
| Ternary-Bonsai-1.7B Q2_0 | 1 | 4926.64 +/- 71.57 | 212.57 +/- 19.67 |
| Ternary-Bonsai-4B Q2_0 | 0 | 1911.58 +/- 192.90 | 100.55 +/- 0.86 |
| Ternary-Bonsai-4B Q2_0 | 1 | 2290.08 +/- 74.69 | 112.62 +/- 4.04 |
| Ternary-Bonsai-8B Q2_0 | 0 | 1142.11 +/- 15.63 | 70.39 +/- 0.33 |
| Ternary-Bonsai-8B Q2_0 | 1 | 1303.33 +/- 53.55 | 78.25 +/- 0.25 |

## Smoke Test

The repo launcher also ran the same model through `scripts/run_llama.sh` after building ROCm binaries into `bin/rocm`:

```bash
BONSAI_FAMILY=ternary BONSAI_MODEL=8B ./scripts/run_llama.sh \
  -c 4096 -n 32 \
  -p "Explain ternary Bonsai inference on Strix Halo in one sentence."
```

Observed timings from the launcher smoke run:

| Prompt (t/s) | Generation (t/s) |
|-------------:|-----------------:|
| 411.0 | 80.0 |

## Hardware

```text
GPU: AMD Radeon Graphics, gfx1151
Reported VRAM: 63945 MiB
CPU: AMD Ryzen AI Max+ 395
Memory: 128 GB unified
ROCm: /opt/rocm
```
