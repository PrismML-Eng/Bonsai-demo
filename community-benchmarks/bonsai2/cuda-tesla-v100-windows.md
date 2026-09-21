# Tesla V100-SXM2 16 GB — CUDA

## Summary

Tesla V100-SXM2-16GB (Volta, compute capability 7.0, 300 W SXM2 board) on Windows 11 Pro for
Workstations (10.0.26200, build 26200), NVIDIA driver 581.15, ECC on, WDDM. This submission is for
the **Ternary Bonsai 2 27B** release (`prism-ml/Ternary-Bonsai-2-27B-gguf`, the PQ2_0 / PTQ1_0
bands), not the previous Ternary-Bonsai family. PrismML fork commit `9a9394a89` (prism-b10709).

- **PQ2_0: 797.7 t/s pp512, 46.0 t/s tg128** — 6.70 GiB of weights, fits in 16 GB with room to spare
  (a 128K-context q4_0 KV cache brings the card to ~12 of 16 GB).
- **PTQ1_0: 851.7 t/s pp512, 34.3 t/s tg128** — prompt processing ~7% faster, decode ~25% slower on Volta.
- The **official prebuilt** Windows CUDA archive (sm_86/sm_89 SASS + sm_70 PTX) and a **locally built
  sm_70 SASS** binary measure the same: 793.8 / 49.0 vs 797.7 / 46.0. Volta has no baked SASS in the
  release, but the bundled PTX JIT-compiles for sm_70 and runs correctly.
- Long-context sanity checks with the q4_0 KV cache (outside the headline numbers): a 120,081-token
  prompt prefilled at 402.7 t/s and decoded at 19.5 t/s; a 250,067-token prompt (the model's full
  262,144-token context) prefilled at 252.6 t/s and decoded at 11.2 t/s, at 14.8 / 16 GB VRAM.

## llama-bench Results

### Ternary Bonsai 2 27B — PQ2_0 (locally built sm_70 SASS)

```bash
# locally built sm_70 SASS binary
BENCH=bin/cuda/llama-bench
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1 -p 512 -n 128 -r 3
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 16383 MiB):

  Device 0: Tesla V100-SXM2-16GB, compute capability 7.0, VMM: yes, VRAM: 16383 MiB

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |       797.67 ± 26.43 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         45.95 ± 2.30 |

build: unknown (0)

### Ternary Bonsai 2 27B — PQ2_0 (official prebuilt release)

```bash
BENCH=bin/cuda-prebuilt/llama-bench
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1 -p 512 -n 128 -r 3
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 16383 MiB):

  Device 0: Tesla V100-SXM2-16GB, compute capability 7.0, VMM: yes, VRAM: 16383 MiB

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |       793.75 ± 27.30 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         48.99 ± 0.28 |

build: 9a9394a89 (10709)

### Ternary Bonsai 2 27B — PTQ1_0 (locally built sm_70 SASS)

```bash
# back to the locally built sm_70 SASS binary (do not reuse the prebuilt $BENCH from the previous section)
BENCH=bin/cuda/llama-bench
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1 -p 512 -n 128 -r 3
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 16383 MiB):

  Device 0: Tesla V100-SXM2-16GB, compute capability 7.0, VMM: yes, VRAM: 16383 MiB

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |       851.73 ± 25.74 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         34.31 ± 0.10 |

build: unknown (0)

## Configuration

- All runs fully on-GPU (`-ngl 99`), flash-attn on (`-fa 1`), default f16 KV cache, `-p 512 -n 128 -r 3`.
- Local build: PrismML fork commit `9a9394a89`, CUDA 12.9 toolchain, MSVC 19.44,
  `-DCMAKE_CUDA_ARCHITECTURES=70` (native sm_70 SASS).
- The service was stopped for the whole run; about 1.8 GB of the 16 GB was held by desktop
  applications (browser, remote-display software) — that is this machine's normal state. A second
  window with only ~1.1 GB held gave 791.3 t/s pp512 / 46.2 t/s tg128 for PQ2_0 with a **q4_0** KV cache,
  i.e. quantizing the KV cache costs nothing in speed here, matching the KV-CACHE.md note that it is a
  memory tool rather than a speed tool.
- PTQ1_0 keeps its 1.2 GB size advantage and is the better band for prompt-processing-heavy work
  (long prompts / RAG); PQ2_0 wins on decode.

## Notes

- No thermal throttling: ~49–52 °C idle, ~68–70 °C under sustained load, drawing 150–220 W of the
  300 W limit with the SM clock at 1530 MHz.
- Volta (sm_70) is not in the prebuilt SASS list, but the PTX in the official archive JIT-compiles and
  performs identically to a natively compiled sm_70 binary; only the first load pays a JIT cost.
- Long-context behaviour (same model, q4_0 KV, flash-attn on, `-c 131072` / `-c 262144`):
  prefill throughput falls from ~563 t/s at the start of a 250K-token prompt to ~256 t/s near the end
  (402.7 t/s average for 120K tokens; 252.6 t/s average for 250K tokens).

## Hardware

```powershell
PS> Get-CimInstance Win32_Processor | Format-List Name,NumberOfCores,NumberOfLogicalProcessors

Name                      : Intel(R) Xeon(R) CPU E5-2682 v4 @ 2.50GHz
NumberOfCores             : 16
NumberOfLogicalProcessors : 32

PS> Get-CimInstance Win32_VideoController | Format-List Name,DriverVersion

Name          : NVIDIA Tesla V100-SXM2-16GB
DriverVersion : 32.0.15.8115

PS> [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
64
```

- Tesla V100-SXM2-16GB, 16384 MiB, VBIOS 88.00.13.00.02, 300 W power limit, 1530 MHz max SM clock,
  ECC enabled, P0.
- Windows 11 Pro for Workstations, 10.0.26200 (build 26200). NVIDIA driver 581.15.
