# NVIDIA RTX 2060 SUPER 8 GB — CUDA

## Summary

NVIDIA GeForce RTX 2060 SUPER 8 GB (Turing, compute capability 7.5) as a
headless eGPU on Windows 11 Pro, running the Bonsai 27B (1-bit, Q1_0) family
with llama.cpp CUDA from this demo's fork (build `d7b289683`, release
`prism-b12128-d7b2896`), flash attention enabled, `-ngl 99`.

| Model | PP512 (t/s) | TG128 (t/s) |
|-------|------------:|------------:|
| Bonsai-27B (Q1_0) | 496.92 ± 3.33 | 40.85 ± 0.26 |

Bonsai-27B plus the 8B/4B/1.7B size models were llama-benched (raw results
below). The existing entry `cuda-rtx2060-linux.md` (same GPU, build 10709,
WSL) reports 494 / 32.7 for the 27B — the newer fork build improves 27B
TG128 by ~25 % on this Turing card while PP512 stays on par.

## Configuration

- Model repository: `lmstudio-community/Bonsai-27B-GGUF`
  (same weights as `prism-ml/Bonsai-27B-gguf`)
- Model: `Bonsai-27B-Q1_0.gguf` (reported by `llama-bench` as 3.53 GiB,
  26.90 B params, Q1_0)
- llama.cpp fork build: `d7b289683 (12128)`, release `prism-b12128-d7b2896`,
  asset `llama-prism-b12128-d7b2896-bin-win-cuda-12.4-x64.zip` +
  `cudart-llama-bin-win-cuda-12.4-x64.zip`
- Backend: CUDA; NVIDIA driver 621.01
- GPU: NVIDIA GeForce RTX 2060 SUPER, 8191 MiB VRAM, headless (drives no
  display); eGPU via M.2-to-Thunderbolt/USB4 dock (TH3P4G3-class), desktop
  on the laptop's integrated Intel Arc iGPU
- CPU: Intel Core Ultra 7 (mobile, Arrow Lake-H class); system RAM: withheld
- OS: Microsoft Windows 11 Pro
- Compute capability: 7.5
- Flash attention enabled (`-fa 1`), GPU layers `-ngl 99`, default ubatch 512
- KV cache: default f16 (no `-ctk/-ctv` overrides for this run)
- Benchmark repetitions: 5 (`-r 5`)
- No power limit or tuning changes.
- Bonsai-8B / 4B / 1.7B were llama-benched locally as well (raw results
  below); the smaller-size rows currently in the tables for this GPU come
  from `cuda-rtx2060-linux.md` (build 10709, WSL).

## llama-bench results

Binaries from the pinned GitHub release; vendor DLLs from
`cudart-llama-bin-win-cuda-12.4-x64.zip` placed next to the executables.

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
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 8191 MiB):
  Device 0: NVIDIA GeForce RTX 2060 SUPER, compute capability 7.5, VMM: yes, VRAM: 8191 MiB

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |        496.92 ± 3.33 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         40.85 ± 0.26 |

build: d7b289683 (12128)
```

### Bonsai-8B / 4B / 1.7B

Exact commands: same as above with `-m` pointing to each size file.

Raw results:

```text
=== Bonsai-8B Q1_0 ===
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           pp512 |      1766.65 ± 68.62 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CUDA       |  99 |   1 |           tg128 |        112.09 ± 0.36 |

build: d7b289683 (12128)

=== Bonsai-4B Q1_0 ===
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  |  540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           pp512 |      3020.30 ± 61.83 |
| qwen3 4B Q1_0                  |  540.09 MiB |     4.02 B | CUDA       |  99 |   1 |           tg128 |        171.04 ± 0.43 |

build: d7b289683 (12128)

=== Bonsai-1.7B Q1_0 ===
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                |  231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           pp512 |     5753.94 ± 796.72 |
| qwen3 1.7B Q1_0                |  231.13 MiB |     1.72 B | CUDA       |  99 |   1 |           tg128 |        262.90 ± 8.06 |

build: d7b289683 (12128)
```

## Additional observations

Separate from llama-bench (server workload, `llama-server` OpenAI API,
65,536-token context, KV cache q4_0, `-ub 256`, same build):

- End-to-end chat generation at 65k context: **36.9 tok/s** — above the
  32.7 tok/s (plain TG128, smaller 128-token context!) this same GPU
  produced with build 10709 under WSL. The b12128 kernel work is a
  substantial Turing upgrade.
- Prompt processing through the server at 131k context: ~420-480 tok/s
  (`-ub 256`), degrading with VRAM pressure: at 262,144 tokens (the model's
  native maximum, which still boots in 7,940 MiB with `-ub 128` + q4_0 KV)
  prefill collapses to ~12 tok/s and generation to ~2.7 tok/s from WDDM
  spilling — booting is possible, sustained operation is not.
- Speculative decoding on Turing: DFlash2 (`draft-dflash`) drops generation
  to 0.8-1.2 tok/s regardless of drafter placement (kernels appear to need
  newer GPU generations; the working report is Metal/M3). Classic drafting
  with Bonsai-1.7B-Q1_0 against Bonsai-27B-Q1_0 gives no speedup (+1 %) —
  different base-model generations (qwen3 vs qwen35) prevent useful draft
  acceptance. MTP drafting asserts on the missing `h_nextn` tensors of the
  27B target.
