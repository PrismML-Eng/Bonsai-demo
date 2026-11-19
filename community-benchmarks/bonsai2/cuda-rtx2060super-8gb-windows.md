# NVIDIA RTX 2060 SUPER 8 GB — CUDA

## Summary

NVIDIA GeForce RTX 2060 SUPER 8 GB (Turing, compute capability 7.5) as a
headless eGPU on Windows 11 Pro, running Bonsai 2 27B with llama.cpp CUDA from
this demo's fork (build `d7b289683`, release `prism-b12128-d7b2896`), flash
attention enabled, `-ngl 99`.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 477.00 ± 0.93 | 28.52 ± 0.09 |
| PTQ1_0 | 466.28 ± 0.77 | 48.10 ± 0.23 |
| Q2_0 | 466.75 ± 0.94 | 28.31 ± 0.12 |

All three packings tested with identical settings. Notable for Turing
(compute capability 7.5): the PQ2_0 prompt-processing advantage reported on
newer GPUs (e.g. 4090: 3,285 vs 1,597 PP512) does **not** replicate here —
PP512 is essentially equal across packings (~466–477), while TG128 strongly
favors the dense PTQ1_0 packing (48.1 vs ~28.5), consistent with TG being
purely weight-traffic bound. On Turing, PTQ1_0 wins both columns.

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
- Model: `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5,946,648,928 bytes on disk,
  reported by `llama-bench` as 5.53 GiB)
- Parameters: 26.90B
- Packing: PTQ1_0, 1.75 bpw, group 128
- llama.cpp fork build: `d7b289683 (12128)`, release `prism-b12128-d7b2896`,
  asset `llama-prism-b12128-d7b2896-bin-win-cuda-12.4-x64.zip` +
  `cudart-llama-bin-win-cuda-12.4-x64.zip`
- Backend: CUDA
- CUDA runtime: CUDA 12.4 (cudart 12.4 zip above); NVIDIA driver 621.01
- GPU: NVIDIA GeForce RTX 2060 SUPER, 8191 MiB VRAM, headless (drives no
  display)
- eGPU setup: RTX 2060 SUPER in an M.2-to-Thunderbolt/USB4 dock
  (TH3P4G3-class); display/desktop handled by the laptop's integrated
  Intel Arc iGPU. All inference runs fully in the eGPU's own VRAM; the
  Thunderbolt link is only used at model-load time, not during generation.
- CPU: Intel Core Ultra 7 (mobile, Arrow Lake-H class); system RAM: withheld
- OS: Microsoft Windows 11 Pro
- Compute capability: 7.5
- Flash attention enabled (`-fa 1`)
- GPU layer setting: `-ngl 99` (all layers)
- KV cache: default f16 (llama-bench default; no `-ctk/-ctv` overrides for
  this run)
- Benchmark repetitions: 5 (`-r 5`)
- Prompt processing test: PP512
- Token generation test: TG128
- No power limit or tuning changes.
- All three packings tested: identical settings for each, one `llama-bench`
  invocation per packing.

## llama-bench results

Binaries taken from the pinned GitHub release (not built from source); the
Windows vendor DLLs from `cudart-llama-bin-win-cuda-12.4-x64.zip` are placed
next to the executables.

### PTQ1_0

Exact command (Git Bash / PowerShell equivalent with the release's
`llama-bench.exe`):

```bash
llama-bench.exe \
  -m "Ternary-Bonsai-2-27B-PTQ1_0.gguf" \
  -p 512 \
  -n 128 \
  -ngl 99 \
  -fa 1 \
  -r 5
```

Raw result:

```text
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 8191 MiB):
  Device 0: NVIDIA GeForce RTX 2060 SUPER, compute capability 7.5, VMM: yes, VRAM: 8191 MiB

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |        466.28 ± 0.77 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         48.10 ± 0.23 |

build: d7b289683 (12128)
```

### PQ2_0

Exact command: same as above with
`-m "Ternary-Bonsai-2-27B-PQ2_0.gguf"`.

Raw result:

```text
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |        477.00 ± 0.93 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         28.52 ± 0.09 |

build: d7b289683 (12128)
```

### Q2_0

Exact command: same as above with
`-m "Ternary-Bonsai-2-27B-Q2_0.gguf"` (official llama.cpp `Q2_0` format,
tested on the fork; upstream llama.cpp b11556+ also loads this packing).

Raw result:

```text
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   7.09 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |        466.75 ± 0.94 |
| qwen35 27B Q2_0                |   7.09 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         28.31 ± 0.12 |

build: d7b289683 (12128)
```

### Standalone size models (llama-bench, same GPU, same build)

| file | pp512 | tg128 | VRAM during gen |
|---|---:|---:|---|
| Ternary-Bonsai-2-9B-PTQ1_0.gguf (1.85 GiB) | 1454.93 ± 11.02 | 117.56 ± 1.20 | 2744 MiB @65k |
| Ternary-Bonsai-2-4B-PTQ1_0.gguf (895 MiB) | 2251.12 ± 10.51 | 165.16 ± 0.15 | 1876 MiB @65k |
| Ternary-Bonsai-2-2B-PTQ1_0.gguf (399 MiB) | 5189.70 ± 46.68 | 265.58 ± 2.37 | 880 MiB @65k |

Exact command: same as above with `-m` pointing to each size file.
The 2B model achieves the highest tokens/second of the family on this GPU.

## Additional observations

Separate from the llama-bench numbers above (server workload, 65,536-token
context, KV cache quantized to q4_0, `-ub 256`, same build):

- The same PTQ1_0 model serves chat with ~30–33 tok/s measured end-to-end
  through `llama-server`'s OpenAI API at 65k context (bigger KV footprint and
  chat-template overhead; TG128-style plain generation is not the serving
  number).
- The older Bonsai-1 27B (Q1_0, qwen35-base 3.53 GiB) measures 36.9 tok/s
  generation at 65k context on this GPU with the same fork — notably above
  the 32.7 tok/s reported for this exact GPU in
  `community-benchmarks/bonsai/cuda-rtx2060-linux.md` (build 10709, WSL).
  The b12128 kernels appear to be a meaningful upgrade on Turing.
- Speculative decoding was tested and does NOT work on this GPU: DFlash2
  (`draft-dflash`, Tier-1 drafter, 715 MB) drops generation to 0.8–1.2 tok/s
  at 8k/16k context regardless of drafter placement (suspected missing
  Turing-optimized kernels; the working report for DFlash2 is Metal/M3).
  Classic speculative decoding with the Bonsai-1.7B-Q1_0 drafter loads and
  runs but yields no speedup (+1 %) against Bonsai-27B-Q1_0 — different
  base-model generations (qwen3 vs qwen35) appear to prevent useful draft
  acceptance. MTP-style drafting is not applicable to the Bonsai-1 27B target
  (GGML assert on missing `h_nextn` tensors).
