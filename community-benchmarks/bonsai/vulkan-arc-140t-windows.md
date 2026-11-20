# Intel Arc 140T iGPU — Vulkan

## Summary

Intel Arc 140T iGPU (Xe1, unified memory) running the Bonsai (1-bit, Q1_0)
family with llama.cpp Vulkan from this demo's fork (build
`d7b289683 (12128)`, the same commit as release
`prism-b12128-d7b2896`), flash attention enabled, `-ngl 99`. The discrete
eGPU normally present in this laptop (RTX 2060 SUPER, see
`cuda-rtx2060super-8gb-windows.md`) was undocked; the Arc was the only
Vulkan device.

| Model | PP512 (t/s) | TG128 (t/s) |
|-------|------------:|------------:|
| Bonsai-27B (Q1_0) | 119.26 | 7.45 |

The Q1_0 format loads on upstream llama.cpp as well; on this iGPU, upstream
builds generate noticeably faster than the fork build (see additional
observations), so these numbers should be read as the fork-consistent
comparison to the CUDA report for the same machine.

## Configuration

- Model repository: `lmstudio-community/Bonsai-27B-GGUF`
  (same weights as `prism-ml/Bonsai-27B-gguf`)
- Model: `Bonsai-27B-Q1_0.gguf` (3.53 GiB, 26.90 B params, Q1_0)
- llama.cpp fork build: `d7b289683 (12128)` (same commit as release
  `prism-b12128-d7b2896`), Vulkan backend build
- Backend: Vulkan; device `Intel(R) Arc(TM) 140T GPU (31GB)`, uma: 1,
  fp16: 1, int dot: 1, matrix cores: KHR_coopmat (left enabled)
- GPU driver: Intel 32.0.101.8991
- CPU: Intel Core Ultra 7 255H (Arrow Lake-H); system RAM: 62.9 GB
  (shared memory / UMA)
- OS: Microsoft Windows 11 Pro
- Flash attention enabled (`-fa 1`), GPU layers `-ngl 99`
- KV cache: default f16 (no `-ctk/-ctv` overrides)
- Benchmark repetitions: 5 (`-r 5`)
- No power limit or tuning changes.
- Bonsai-8B / 4B / 1.7B benched with the same command (raw results below).

## llama-bench results

### Bonsai-27B (Q1_0)

Exact command:

```bash
llama-bench.exe \
  -m "Bonsai-27B-Q1_0.gguf" \
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
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | Vulkan     |  99 |   1 |           pp512 |        119.26 ± 1.95 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | Vulkan     |  99 |   1 |           tg128 |          7.45 ± 0.40 |

build: d7b289683 (12128)
```

### Bonsai-8B / 4B / 1.7B

Exact commands: same as above with `-m` pointing to each size file.

Raw results:

```text
=== Bonsai-8B Q1_0 ===
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | Vulkan     |  99 |   1 |           pp512 |        378.36 ± 8.91 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | Vulkan     |  99 |   1 |           tg128 |         24.52 ± 1.43 |

build: d7b289683 (12128)

=== Bonsai-4B Q1_0 ===
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | Vulkan     |  99 |   1 |           pp512 |        555.86 ± 9.40 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | Vulkan     |  99 |   1 |           tg128 |         34.60 ± 2.49 |

build: d7b289683 (12128)

=== Bonsai-1.7B Q1_0 ===
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | Vulkan     |  99 |   1 |           pp512 |       1207.63 ± 67.80 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | Vulkan     |  99 |   1 |           tg128 |         65.57 ± 12.65 |

build: d7b289683 (12128)
```

## Additional observations

- Build choice matters on Vulkan: in a follow-up run (same GPU, driver and
  command, 2026-11-19), upstream llama.cpp b11429 measured Bonsai-27B Q1_0
  at 122.6 ± 1.1 / 10.6 ± 0.7 and v1.0.0 (b12359) at 129.5 ± 0.8 /
  10.0 ± 0.7 — i.e. ~40 % higher TG128 than the fork build used here
  (7.45 in this run). PP512 stays on par across builds.
- KHR_coopmat was left enabled (default). Disabling it
  (`GGML_VK_DISABLE_COOPMAT`) collapses PP512 by ~6× on this driver
  (Bonsai-27B: 19.6 vs ~120).
- Reference points from the same machine with the discrete eGPU are in the
  companion report `cuda-rtx2060super-8gb-windows.md` (same fork commit,
  CUDA vs. Vulkan): the eGPU is ~4–5.5× faster on this family.
