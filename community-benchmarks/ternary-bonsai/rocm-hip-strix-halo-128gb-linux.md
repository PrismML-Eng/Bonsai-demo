# AMD Strix Halo 128 GB - ROCm HIP

## Summary

AMD Ryzen AI Max+ 395 (Strix Halo), Radeon 8060S (`gfx1151`), 128 GB unified memory. Backend: ROCm HIP using the PrismML `prism` branch of llama.cpp at `d104cf1b6` (`prism-b8846-d104cf1`), built with `GGML_HIP=ON` and `AMDGPU_TARGETS=gfx1151`. All layers were offloaded to GPU (`-ngl 99`) with flash attention enabled (`-fa 1`).

| Model | Quant | Size | pp512 (t/s) | tg128 (t/s) |
|-------|-------|------|-------------|-------------|
| Ternary-Bonsai-8B | Q2_0 | 2.03 GiB | 1,323 | 79 |

## llama-bench Results

```bash
PATH=/opt/rocm/bin:$PATH \
LD_LIBRARY_PATH=bin/rocm:/opt/rocm/lib \
./bin/rocm/llama-bench \
  -m models/ternary-gguf/8B/Ternary-Bonsai-8B-Q2_0.gguf \
  -ngl 99 -fa 1 -p 512 -n 128 -r 3
```

| model | size | params | backend | ngl | fa | test | t/s |
|---|---:|---:|---|---:|---:|---:|---:|
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | ROCm | 99 | 1 | pp512 | 1323.29 +/- 10.55 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | ROCm | 99 | 1 | tg128 | 79.04 +/- 0.57 |

build: `d104cf1b6` (`8846`)

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
