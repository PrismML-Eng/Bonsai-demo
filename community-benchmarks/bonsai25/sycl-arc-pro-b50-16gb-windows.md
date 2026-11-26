# Intel Arc Pro B50 (16 GB) — llama.cpp SYCL on Windows (Bonsai 2.5 27B)

Submitted 2026-11-26. All measurements on this machine on this date; commands and
environment as listed. Sibling Bonsai 2 report on the same hardware:
`SYCL-B50-NOTES.md` in the demo repo root (untracked working notes).

## Summary

Bonsai 2.5 27B on Intel Arc Pro B50 16 GB (Arc Pro series, Xe2), Windows 11 Pro for
Workstations (build 26300), PrismML fork SYCL release packages.

### llama-bench (plain decode, no speculation)

| Model | Runtime | PP512 (t/s) | TG128 (t/s) |
|-------|---------|------------:|------------:|
| Bonsai 2 PQ2_0 | prism-b10787 | 737.06 ± 43.09 / 719.87 ± 53.17 | 25.17 ± 0.08 / 25.03 ± 0.05 |
| Bonsai 2.5 PQ2_0-mtp | prism-b10787 | 727.29 ± 33.20 | 24.22 ± 0.04 |
| Bonsai 2 PQ2_0 | prism-b12178 | 556.97 ± 19.64 / 565.43 ± 13.99 (GRAPH=1) | 22.26 ± 0.12 / 22.45 ± 0.19 (GRAPH=1) |
| Bonsai 2.5 PQ2_0-mtp | prism-b12178 | 573.30 ± 3.87 / 547.67 ± 14.71 (GRAPH=1) | 21.26 ± 0.48 / 21.35 ± 0.32 (GRAPH=1) |

Key findings:

- **b12178 is a decode regression on this card**: −11% tg128 and −23% pp512 vs
  b10787 on the identical Bonsai 2 file. `GGML_SYCL_ENABLE_GRAPH=1` recovers ~1 t/s
  only. Stay on b10787 until the SYCL path is fixed.
- **Bonsai 2.5 decodes ~4% slower than Bonsai 2 on the same runtime** (the built-in
  MTP head adds tensors that stay resident; llama-bench does not use them).
- **b10787 loads the 2.5 `-mtp` file fine** — the #372 Hadamard-list fix is not
  needed for this file on this build.

### Server with built-in MTP head (see Additional observations — not llama-bench)

| Config (Bonsai 2.5 PQ2_0-mtp) | decode (t/s) |
|---|---|
| plain, b10787 | 24.21 / 24.45 |
| `draft-mtp` 3, 0.1, b10787 | **30.46 / 31.87** |
| `draft-mtp` 3, 0.1 + `LLAMA_MTP_CHAIN=1`, b10787 | 32.08 / 28.65 |
| `draft-mtp` 5, 0.1 + chain, b10787 | DEVICE_LOST crash at 262K context |
| `draft-mtp` 3, 0.1, b12178 | server loads, requests fail |
| `draft-mtp` 8, 0.6 + `GGML_SYCL_T2_VGEMM_MIN=8`, b12178 | server fails to start |

**Recommended B50 config: b10787 + `--spec-type draft-mtp --spec-draft-n-max 3
--spec-draft-p-min 0.1` → ~30-32 t/s, +26-31% over plain 2.5 and +20-27% over
Bonsai 2 plain.** Chain drafts add nothing measurable; n-max 5 with chain exhausts
the 16 GB pool at 262K context.

## Configuration

- Models:
  - `Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf` from `prism-ml/Ternary-Bonsai-2.5-27B-GGUF`
    (7,492,338,944 bytes, sha256 `ededc9fc0a8a6a8dd30914d107b2d2ce7674d789f1d05a1a481f240609aa6c23`
    — matches the HF `X-Linked-ETag`)
  - `Ternary-Bonsai-2-27B-PQ2_0.gguf` from `prism-ml/Ternary-Bonsai-2-27B-gguf`
    (7,206,168,928 bytes, sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`)
- llama.cpp: PrismML fork release packages, Windows x64 SYCL (overlaid on the CPU
  package from the same release):
  - `prism-b10787-73bfe6c` (build 10787, commit `73bfe6cc4`)
  - `prism-b12178-03ec600` (build 12178, commit `03ec60072`)
- OS: Windows 11 Pro for Workstations 10.0.26300; GPU driver 32.0.101.8976
- GPU: Intel Arc Pro B50 16 GB (Level Zero device 0, driver 1.15.39183+4; the iGPU
  Iris Xe is device 1 and unused). CPU: 13th Gen Intel Core i9-13900H, 64 GB RAM.
- llama-bench flags: `-ngl 99 -fa 1`, default KV (f16), default context, 5
  repetitions. No mmproj involved.
- Fork environment switches (identical for every run):
  `GGML_SYCL_PTQ1_T2=all`, `GGML_SYCL_FA_DEC_DPAS=1`,
  `GGML_SYCL_FA_ONEDNN_MAX_KV=98304`, `GGML_SYCL_T2_W8A8_MIN=1024`,
  `LLAMA_ARG_SPEC_DRAFT_UBATCH=512`.
- Provenance: every pp/tg value below was measured on this machine on 2026-11-26
  with the exact commands shown; `±` figures are llama-bench's native mean ± stddev
  over 5 repetitions.

## llama-bench results

### b10787, Bonsai 2 PQ2_0 (baseline)

```powershell
bin\sycl\llama-bench.exe -m models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|------|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | SYCL | 99 | 1 | pp512 | 737.06 ± 43.09 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | SYCL | 99 | 1 | tg128 | 25.17 ± 0.08 |

build: 73bfe6cc4 (10787)

### b10787, Bonsai 2.5 PQ2_0-mtp

```powershell
bin\sycl\llama-bench.exe -m models\bonsai25-gguf\27B\Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|------|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.97 GiB | 27.32 B | SYCL | 99 | 1 | pp512 | 727.29 ± 33.20 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.97 GiB | 27.32 B | SYCL | 99 | 1 | tg128 | 24.22 ± 0.04 |

build: 73bfe6cc4 (10787)

### b12178, Bonsai 2 PQ2_0

```powershell
bin\sycl-b12178\llama-bench.exe -m models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|------|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | SYCL | 99 | 1 | pp512 | 556.97 ± 19.64 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | SYCL | 99 | 1 | tg128 | 22.26 ± 0.12 |

build: 03ec60072 (12178). With `GGML_SYCL_ENABLE_GRAPH=1`: pp512 565.43 ± 13.99,
tg128 22.45 ± 0.19.

### b12178, Bonsai 2.5 PQ2_0-mtp

```powershell
bin\sycl-b12178\llama-bench.exe -m models\bonsai25-gguf\27B\Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|------|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.97 GiB | 27.32 B | SYCL | 99 | 1 | pp512 | 573.30 ± 3.87 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.97 GiB | 27.32 B | SYCL | 99 | 1 | tg128 | 21.26 ± 0.48 |

build: 03ec60072 (12178). First run of this pair read pp512 387.96 ± 110.33 /
tg128 20.77 ± 0.60 — a cold-start artifact, the rerun above is the steady value.
With `GGML_SYCL_ENABLE_GRAPH=1`: pp512 547.67 ± 14.71, tg128 21.35 ± 0.32.

## Additional observations

Server runs (kept separate from llama-bench timings per the template). Server flags:
`-c 262144 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 --temp 1.0 --top-p 0.95 --top-k 20
--min-p 0 --jinja`, same env as above. Probe: one short chat request
(~50-token prompt, `max_tokens 192`, temperature 0.3), two probes per server
(cold/warm); decode rate is the server's `timings.predicted_per_second`, draft
engagement via `timings.draft_n`. These are short-prompt rates, not filled-context
measurements.

| Config | probe1 | probe2 | draft_n |
|---|---:|---:|---:|
| plain @ b10787 | 24.21 | 24.45 | — |
| draft-mtp 3, 0.1 @ b10787 | 30.46 | 31.87 | 258 / 267 |
| draft-mtp 3, 0.1 + `LLAMA_MTP_CHAIN=1` @ b10787 | 32.08 | 28.65 | 252 / 267 |
| draft-mtp 5, 0.1 + chain @ b10787 | crash | — | — |
| plain @ b12178 | 20.24 | 22.08 | — |
| draft-mtp 3, 0.1 @ b12178 | request failed | — | — |
| draft-mtp 8, 0.6 + `GGML_SYCL_T2_VGEMM_MIN=8` @ b12178 | server did not start | — | — |

- The built-in MTP head works on **b10787** with no sidecar and no conversion:
  `--spec-type draft-mtp` alone, `creating MTP draft context against the target
  model` in the log, `draft_n` > 0 in every response. Gain ~+26-31% decode on this
  workload.
- MTP prefill cost visible on the cold probe: prompt_ms 413 (plain) → 1429 (MTP);
  warm prompt stays ~100 ms. Consistent with the whitepaper's 2-8% prefill penalty
  being much larger on a short prompt.
- `draft-mtp` 5, 0.1 with chain crashed with `UR_RESULT_ERROR_DEVICE_LOST` at
  262K context on 16 GB — the drafted-token KV/scratch pressure at n-max 5 does not
  fit. 3, 0.1 is the working ceiling here.
- b12178 regressions on this card: plain decode −11%, and the MTP path is broken
  (requests fail / server fails to start) despite `speculative decoding enabled:
  draft-mtp` in the load log. Do not use b12178 on Arc Pro B50.
- Correctness: outputs coherent on all MTP runs (qualitative); no KLD run.
- PTQ1_0 band not tested (XMX expands it to the same layout on SYCL, see
  SYCL-B50-NOTES.md); Q2_0 not tested; vision/mmproj not exercised in this report.
