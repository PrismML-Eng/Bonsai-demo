# NVIDIA RTX 3090 Ti — CUDA (Linux)

## Summary

Bonsai 2 27B on an NVIDIA GeForce RTX 3090 Ti 24 GB (Ampere, compute 8.6) under CachyOS (Arch Linux,
kernel 7.2.7), driver 615.71.09, using the demo's pinned fork release `prism-b10709-9a9394a`
(`linux-cuda-13.3-x64` asset, build `9a9394a89 (10709)`), flash-attn on, `-ngl 99`:

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 1,551.7 | 81.6 |
| PTQ1_0 | 804.9 | 67.7 |
| Q2_0 (development) | not tested | not tested |

`PQ2_0` token generation on this setup is within ~4 % of the RTX 4090 report, while
prompt processing is about half of that report's `PQ2_0` figure. Unlike the 4090 report,
`PTQ1_0` is ~17 % slower than `PQ2_0` in tg128 and ~48 % slower in pp512 here.
These measurements do not isolate the cause of the difference; hardware, builds, and
runtime settings differ between submissions.

## Configuration

- Model repository, exact filename(s): [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf),
  `Ternary-Bonsai-2-27B-PQ2_0.gguf` (6.70 GiB) downloaded by `./setup.sh`; `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5.53 GiB)
  downloaded from the same repository (`main`, 2026-09-24).
- llama.cpp release and downloaded asset: PrismML fork release `prism-b10709-9a9394a`,
  `llama-prism-b10709-9a9394a-bin-linux-cuda-13.3-x64.tar.gz`, build `9a9394a89 (10709)`.
- OS, GPU driver, backend: CachyOS (Arch Linux), kernel `7.2.7-1-cachyos`, NVIDIA driver 615.71.09 (open kernel module),
  CUDA runtime 13.x driver support; CUDA 13.3 binary asset.
- GPU/CPU, VRAM, system RAM: RTX 3090 Ti 24 GB (24,564 MiB), AMD Ryzen 9 7900X (12C/24T), 64 GB DDR5.
- Offload, flash attention, KV cache, threads, batch: `-ngl 99 -fa 1`, `llama-bench` defaults otherwise (pp512/tg128,
  5 repetitions, f16 KV cache, default threads/batch).
- Power limit or tuning: stock 450 W power limit, no overclock or memory tuning. Desktop session (Wayland, mango +
  DankMaterialShell) was running on the same GPU during the runs (~1.9 GiB of VRAM in use before loading the model).

## llama-bench results

Run from the repository root after `BONSAI_OPENWEBUI=0 BONSAI_CODE_INTERPRETER=0 ./setup.sh`.

### PQ2_0

```bash
BENCH=bin/cuda/llama-bench
"$BENCH" -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1
```

```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 24142 MiB):
  Device 0: NVIDIA GeForce RTX 3090 Ti, compute capability 8.6, VMM: yes, VRAM: 24142 MiB
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1551.72 ± 33.41 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         81.60 ± 0.27 |

build: 9a9394a89 (10709)

Peak GPU memory during the run (`nvidia-smi`, whole GPU including the desktop): 9,378 MiB.

An earlier run of the same command on the same build gave `pp512 1561.34 ± 28.62`, `tg128 81.67 ± 0.56`; a run
without flash attention (`-fa 0`, 2 repetitions) gave `pp512 1563.05 ± 33.49`, `tg128 82.18 ± 0.69`, so `-fa`
showed no measurable benefit in these short pp512/tg128 runs.

### PTQ1_0

```bash
BENCH=bin/cuda/llama-bench
"$BENCH" -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1
```

```
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 24142 MiB):
  Device 0: NVIDIA GeForce RTX 3090 Ti, compute capability 8.6, VMM: yes, VRAM: 24142 MiB
```

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |        804.89 ± 7.40 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         67.71 ± 0.54 |

build: 9a9394a89 (10709)

Peak GPU memory during the run (`nvidia-smi`, whole GPU including the desktop): 8,234 MiB.

### Q2_0 (development)

Not tested.

## Additional observations

- CPU-only (`-ngl 0`, 12 threads, same PQ2_0 file, 2 repetitions): `pp512 585.70 ± 40.72` (prompt still routed
  through CUDA by the CUDA build), `tg128 1.06 ± 0.00`. Token generation on the x86 CPU path is not usable with this
  build. A separate CPU build was not tested; the release includes the Linux CPU asset
  `llama-prism-b10709-9a9394a-bin-ubuntu-x64.tar.gz`.
- Server workload (`llama-server` from the same asset, `-c 65536 -np 2 --reasoning-budget 4096 --jinja -fa on`,
  PQ2_0, vision projector loaded): a 58,587-token prompt (own documentation) was processed at ~1,180 t/s with
  generation at ~60 t/s at that context; short prompts generate at 78–82 t/s. Steady-state VRAM with that
  configuration: ~12 GiB.
