# NVIDIA GeForce RTX 5080 (16 GB) — llama.cpp CUDA on Windows (Bonsai 2 27B)

## Summary

Bonsai 2 27B on a Windows 11 desktop with NVIDIA GeForce RTX 5080 (16 GB VRAM),
using the PrismML llama.cpp fork release `prism-b10709-9a9394a` (commit `9a9394a89`).
Two runs of this release are recorded and labeled separately (different prebuilt
asset, GPU driver, and repetition count): run 1 with the CUDA 12.4 prebuilt
binaries on driver 616.92, and run 2 (definitive, `-r 5`, JSON retained, GPU
telemetry captured through the whole run) with the CUDA 13.3 prebuilt binaries
on driver 616.64. Run 2 covers both packings (`PQ2_0` and `PTQ1_0`).

| Format | Backend | Run | PP512 (t/s) | PP2048 (t/s) | TG128 (t/s) |
|--------|---------|-----|------------:|-------------:|------------:|
| PQ2_0 | llama.cpp CUDA | 1 — CUDA 12.4 binaries, driver 616.92, `-r 3` | 1687.64 ± 272.06 | — | 86.25 ± 3.62 |
| PQ2_0 | llama.cpp CUDA | 2 — CUDA 13.3 binaries, driver 616.64, `-r 5` | **2345.32 ± 52.34** | **2320.92 ± 0.71** | **92.53 ± 0.16** |
| PTQ1_0 | llama.cpp CUDA | 1 — CUDA 12.4 binaries, driver 616.92, `-r 3` | 895.81 ± 7.84 | — | 84.64 ± 0.09 |
| PTQ1_0 | llama.cpp CUDA | 2 — CUDA 13.3 binaries, driver 616.64, `-r 5` | **1016.55 ± 9.90** | **1008.83 ± 0.11** | **89.32 ± 0.11** |

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
  - `Ternary-Bonsai-2-27B-PQ2_0.gguf` (7,206,168,928 bytes, 6.70 GiB reported)
  - `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5,946,648,928 bytes, 5.53 GiB reported)
- llama.cpp: PrismML fork release `prism-b10709-9a9394a` — no source build and no
  code changes in either run; prebuilt binaries used as downloaded:
  - run 1: `llama-prism-b10709-9a9394a-bin-win-cuda-12.4-x64.zip`
    + CUDA runtime `cudart-llama-bin-win-cuda-12.4-x64.zip`
  - run 2 (definitive): the CUDA 13.3 prebuilt binaries installed by the demo's
    `setup.ps1` (`bin\cuda\llama-bench.exe`)
- OS: Windows 11 Pro (build 26200)
- GPU: NVIDIA GeForce RTX 5080, 16 GB (16,275 MiB visible to the CUDA backend),
  driver 616.92 (run 1) / 616.64 (run 2), compute capability 12.0
- CPU: AMD Ryzen 7 9800X3D (8 cores)
- Offload: `-ngl 99`, flash attention `-fa 1`, default KV cache (f16),
  default threads and batch sizes, stock power and clocks

### Methodology

Run 2 (definitive) ran `llama-bench -p 512,2048 -n 128 -r 5 -o json` for both
packings with the raw JSON retained (per-test `avg_ts`, `stddev_ts`, and the
five individual `samples_ts`). GPU telemetry (`nvidia-smi --query-gpu`,
5 s cadence: temperature, power draw, SM clock, memory used) was captured
through the whole run — 10 samples, 7 of them under load (model resident,
~8–9.5 GB used): power 217–319 W (mean ~258 W), temperature 60–63 °C,
SM clock 2767–2857 MHz. No throttling behavior observed. Run 2 was measured
with a mostly-idle Windows desktop; run 1 was measured on an otherwise-idle
machine with the resident `BonsaiLLM` service stopped beforehand (and
restarted after). The two runs differ in prebuilt asset, driver, repetition
count, and background load — observed averages across builds, not a
controlled A/B.

## llama-bench results

Run 1 (CUDA 12.4 binaries, driver 616.92, `-r 3`):

```powershell
.\llama-bench.exe -m C:\bench-bonsai2\Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1 -r 3
.\llama-bench.exe -m C:\bench-bonsai2\Ternary-Bonsai-2-27B-PTQ1_0.gguf -p 512 -n 128 -ngl 99 -fa 1 -r 3
```

### PQ2_0 — run 1

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 1687.64 ± 272.06 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 86.25 ± 3.62 |

build: 9a9394a89 (10709)

### PTQ1_0 — run 1

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 895.81 ± 7.84 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 84.64 ± 0.09 |

build: 9a9394a89 (10709)

### Run 2 — definitive re-run (CUDA 13.3 binaries, driver 616.64, `-r 5`, JSON + full telemetry)

```powershell
D:\Bonsai-demo\bin\cuda\llama-bench.exe -m D:\Bonsai-demo\models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1 -p 512,2048 -n 128 -r 5 -o json
D:\Bonsai-demo\bin\cuda\llama-bench.exe -m D:\Bonsai-demo\models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1 -p 512,2048 -n 128 -r 5 -o json
```

PQ2_0 (5 samples per test; build 9a9394a89 / 10709):

| test | t/s (avg ± sd) | samples |
|------|---------------:|---------|
| pp512 | 2345.32 ± 52.34 | 2244.99 · 2331.31 · 2390.62 · 2382.56 · 2377.10 |
| pp2048 | 2320.92 ± 0.71 | 2319.94 · 2321.53 · 2320.42 · 2322.02 · 2320.67 |
| tg128 | 92.53 ± 0.16 | 92.43 · 92.34 · 92.75 · 92.57 · 92.56 |

PTQ1_0 (5 samples per test; same build):

| test | t/s (avg ± sd) | samples |
|------|---------------:|---------|
| pp512 | 1016.55 ± 9.90 | 1003.21 · 1016.53 · 1019.03 · 1030.29 · 1013.68 |
| pp2048 | 1008.83 ± 0.11 | 1008.72 · 1008.87 · 1008.91 · 1008.94 · 1008.72 |
| tg128 | 89.32 ± 0.11 | 89.44 · 89.22 · 89.29 · 89.35 · 89.32 |

(`pp2048` is kept in this report for completeness — the summary tables in this
repo track pp512/tg128 only.)

## Additional observations

- **PQ2_0 vs PTQ1_0 (run 2, same binary, same flags):** prefill is ~2.3× faster
  on PQ2_0 (2345.32 vs 1016.55 t/s); decode is ~4% faster (92.53 vs 89.32).
- **Build-to-build (observed, not controlled):** both packings measured faster
  on the CUDA 13.3 asset — PQ2_0 pp512 +39% (1687.64 → 2345.32) with variance
  dropping from ~16% of the mean to ~2% (n=5), tg128 +7% (86.25 → 92.53);
  PTQ1_0 pp512 +13% (895.81 → 1016.55), tg128 +5.5% (84.64 → 89.32).
- **pp2048 is flat vs pp512** in run 2 (PQ2_0: 2320.92 vs 2345.32; PTQ1_0:
  1008.83 vs 1016.55) — prefill throughput does not degrade with longer
  prompts at these lengths.
- The development `Q2_0` format was not tested.

## Hardware

Collected 2026-09-27 with PowerShell, after both runs:

```powershell
PS> Get-CimInstance Win32_Processor | Format-List Name,NumberOfCores,NumberOfLogicalProcessors

Name                      : AMD Ryzen 7 9800X3D 8-Core Processor
NumberOfCores             : 8
NumberOfLogicalProcessors : 8

PS> Get-CimInstance Win32_VideoController | Format-List Name,DriverVersion

Name          : AMD Radeon(TM) Graphics
DriverVersion : 32.0.13036.4

Name          : NVIDIA GeForce RTX 5080
DriverVersion : 32.0.16.1714

PS> [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
94
```

Notes: `Win32_VideoController` reports the driver installed at collection time —
`32.0.16.1714` (NVIDIA 617.14 per `nvidia-smi`, CUDA 13.4); both benchmark runs
predate this query (run 1: driver 616.92; run 2: driver 616.64). The run-1
configuration recorded 62 GB system RAM as reported at that time; the query
above, run on 2026-09-27, returns 94 GB.
