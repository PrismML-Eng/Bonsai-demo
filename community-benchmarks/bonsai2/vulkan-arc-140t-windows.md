# Intel Arc 140T iGPU — Vulkan

## Summary

Intel Arc 140T iGPU (Xe1, unified memory) running Bonsai 2 27B with
llama.cpp Vulkan from this demo's fork (build `d7b289683 (12128)`, the same
commit as release `prism-b12128-d7b2896`), flash attention enabled,
`-ngl 99`. The discrete eGPU normally present in this laptop (RTX 2060
SUPER, see `cuda-rtx2060super-8gb-windows.md`) was undocked; the Arc was
the only Vulkan device.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 118.86 | 5.11 |
| PTQ1_0 | 58.70 | 6.53 |
| Q2_0 | 121.94 | 4.29 |

All three packings tested with identical settings. Notable for Intel Arc
(Xe1, KHR_coopmat): the PTQ1_0 prompt-processing collapse (58.70 vs
~119–122 for PQ2_0/Q2_0) is packing-specific and does not occur on Turing
CUDA, where PP512 is packing-independent. The TG128 ranking also flips
compared to Turing: Q1_0 > PTQ1_0 > PQ2_0 > Q2_0 here, while on Turing
PTQ1_0 clearly wins TG128.

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
- Models: `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5.53 GiB reported),
  `Ternary-Bonsai-2-27B-PQ2_0.gguf` (6.70 GiB),
  `Ternary-Bonsai-2-27B-Q2_0.gguf` (7.09 GiB); 26.90 B params each;
  official llama.cpp `Q2_0` format for Q2_0
- llama.cpp fork build: `d7b289683 (12128)` (same commit as release
  `prism-b12128-d7b2896`), Vulkan backend build
- Backend: Vulkan; device `Intel(R) Arc(TM) 140T GPU (31GB)`, uma: 1,
  fp16: 1, int dot: 1, matrix cores: KHR_coopmat (left enabled — see
  additional observations)
- GPU driver: Intel 32.0.101.8991
- CPU: Intel Core Ultra 7 255H (Arrow Lake-H); system RAM: 62.9 GB
  (shared memory / UMA)
- OS: Microsoft Windows 11 Pro
- Flash attention enabled (`-fa 1`), GPU layers `-ngl 99`
- KV cache: default f16 (no `-ctk/-ctv` overrides)
- Benchmark repetitions: 5 (`-r 5`)
- Prompt processing test: PP512; token generation test: TG128
- No power limit or tuning changes.
- All three packings tested: identical settings for each, one
  `llama-bench` invocation per packing.

## llama-bench results

### PTQ1_0

Exact command:

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
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Arc(TM) 140T GPU (31GB) (Intel Corporation) | uma: 1 | fp16: 1 | bf16: 0 | fp4: 0 | warp size: 32 | shared memory: 49152 | int dot: 1 | matrix cores: KHR_coopmat

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | Vulkan     |  99 |   1 |           pp512 |         58.70 ± 0.99 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | Vulkan     |  99 |   1 |           tg128 |          6.53 ± 0.38 |

build: d7b289683 (12128)
```

### PQ2_0

Exact command: same as above with `-m "Ternary-Bonsai-2-27B-PQ2_0.gguf"`.

Raw result:

```text
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | Vulkan     |  99 |   1 |           pp512 |        118.86 ± 2.95 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | Vulkan     |  99 |   1 |           tg128 |          5.11 ± 0.08 |

build: d7b289683 (12128)
```

### Q2_0

Exact command: same as above with `-m "Ternary-Bonsai-2-27B-Q2_0.gguf"`.

Raw result:

```text
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   7.09 GiB |    26.90 B | Vulkan     |  99 |   1 |           pp512 |        121.94 ± 2.05 |
| qwen35 27B Q2_0                |   7.09 GiB |    26.90 B | Vulkan     |  99 |   1 |           tg128 |          4.29 ± 0.06 |

build: d7b289683 (12128)
```

### Standalone size models (llama-bench, same GPU, same build)

| file | pp512 | tg128 |
|---|---:|---:|
| Ternary-Bonsai-2-9B-PTQ1_0.gguf (1.85 GiB) | 179.10 | 13.35 |
| Ternary-Bonsai-2-4B-PTQ1_0.gguf (895.04 MiB) | 301.65 | 20.15 |
| Ternary-Bonsai-2-2B-PTQ1_0.gguf (398.81 MiB) | 735.67 | 37.19 |

Exact command: same as above with `-m` pointing to each size file.

## Additional observations

- The PTQ1_0 prefill collapse on Vulkan (58.70 vs 118.86/121.94 for
  PQ2_0/Q2_0 — the other packings process prompts ~2× faster) looks like a
  packing-specific kernel gap on Intel Arc: on Turing CUDA the same build
  shows packing-independent PP512 (~466–477). Possibly relevant for the
  Vulkan kernel backlog.
- TG128 ranking on Arc flips vs. Turing: Q1_0 (7.45) > PTQ1_0 (6.53) >
  PQ2_0 (5.11) > Q2_0 (4.29); on Turing PTQ1_0 wins TG128 by a wide
  margin (48.1 vs ~28.5).
- Build choice matters on Vulkan: in a follow-up run (same GPU, driver and
  command, 2026-11-19), upstream llama.cpp b11429 measured the
  upstream-loadable Bonsai-1 27B Q1_0 at 122.6 ± 1.1 / 10.6 ± 0.7 and
  v1.0.0 (b12359) at 129.5 ± 0.8 / 10.0 ± 0.7 — i.e. ~40 % higher TG128
  than the fork build used here (7.45 in this run). The fork build is
  required for PTQ1_0/PQ2_0, so the 27B ternary rows above cannot be
  reproduced on upstream builds.
- KHR_coopmat was left enabled (default). Disabling it
  (`GGML_VK_DISABLE_COOPMAT`) collapses PP512 by ~6× on this driver
  (Bonsai-1 27B: 19.6 vs ~120).
