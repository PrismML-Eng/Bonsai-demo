# Intel Arc B580 (12 GB) — llama.cpp SYCL on Windows (Bonsai 2 27B)

Submitted 2026-10-16. Model paths in the commands are anonymized; exact
filenames and hashes are listed in the Configuration section.
Sibling report with the PrismML fork on Vulkan: `vulkan-arc-b580-12gb-windows.md`.

## Summary

Bonsai 2 27B on Intel Arc B580 12 GB (Battlemage Xe2), Windows 11 (build 26200),
using the community fork `Torchit1/llama.cpp` branch `arc-b580`, release
`arc-b580-v0.10.1` (commit `7adb2dd`), prebuilt
`llama-arc-b580-win-sycl-x64.zip`. This fork adds TernSYCL XMX kernels for the
PrismML ternary packings (PTQ1_0 and PQ2_0) on Xe2.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PTQ1_0 (official file) | 1559.69 ± 2.84 | 45.89 ± 0.08 |
| PTQ1_0 (community mtp-lean graft, plain inference) | 1561.62 ± 2.09 | 45.45 ± 0.71 |
| PQ2_0 | 1533.14 ± 34.41 | 45.87 ± 0.12 |
| Q2_0 (development) | 770.03 ± 0.66 | 10.26 ± 0.00 |

> llama-bench measures plain decode — the MTP head in the mtp-lean file is not
> used for speculation in these numbers (speculative serving speeds are in
> Additional observations).

## Configuration

- Models:
  - `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from `prism-ml/Ternary-Bonsai-2-27B-gguf`
    (5,946,648,928 bytes, sha256 `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`)
  - `Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf` from
    `sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF` (community graft of the same
    PTQ1_0 weights with the model's MTP head, deduplicated embeddings;
    6,297,658,848 bytes, sha256 `1e33c571a5ce7a9a3e42474d66192923d5a6d77da7fb3a22986dc809522b5685`)
  - `Ternary-Bonsai-2-27B-PQ2_0.gguf` (7,206,168,928 bytes, sha256
    `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`)
  - development Q2_0: `Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf` from
    `prism-ml/Ternary-Bonsai-2-27B-gguf-dev` (7,626,008,928 bytes; dev-format file,
    no upstream-published reference hash)
- llama.cpp: `Torchit1/llama.cpp` release `arc-b580-v0.10.1` (commit `7adb2dd`),
  prebuilt `llama-arc-b580-win-sycl-x64.zip`
  (asset sha256 `27ebc7204fe9700024ce6fc0b69aff68298769aed15003542bab46ec19d29bf4`);
  no source build, no code changes. The author marks the Windows build
  EXPERIMENTAL (CI-built); these runs used the stock prebuilt zip.
- OS: Windows 11 (build 26200)
- GPU driver: Intel 32.0.101.9033; Level Zero / OpenCL from the same driver
- Hardware: Intel Arc B580 12 GB (ReBAR on), Intel Core i5-12600KF, 64 GB DDR4,
  stock power and clocks
- Flags: `-ngl 99 -fa 1`, default KV cache (f16), default context, default
  threads/batch, 5 repetitions (default). No mmproj involved (llama-bench).
- Fork environment switches (as documented in the fork's
  `docs/bonsai-arc-b580.md`; identical for every run):
  `GGML_SYCL_PTQ1_T2=all`, `LLAMA_ARG_SPEC_DRAFT_UBATCH=512`,
  `GGML_SYCL_FA_ONEDNN_MAX_KV=98304`, `GGML_SYCL_FA_DEC_DPAS=1`,
  `GGML_SYCL_T2_W8A8_MIN=1024`
- Provenance and statistics: all pp/tg values in this report were measured on
  this machine on 2026-10-16 with the exact commands shown; no numbers are
  borrowed from other reports, other cards, or release notes. The `±` figures
  are llama-bench's native mean ± sample stddev over the 5 repetitions
  (default), not medians — same convention as the existing reports in this
  folder (cf. the RTX 5080 methodology note).

## llama-bench results

### PTQ1_0 (official file)

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-PTQ1_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | SYCL | 99 | 1 | pp512 | 1559.69 ± 2.84 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | SYCL | 99 | 1 | tg128 | 45.89 ± 0.08 |

build: 7adb2dd (1)

### PTQ1_0 (community mtp-lean graft)

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.85 GiB | 27.32 B | SYCL | 99 | 1 | pp512 | 1561.62 ± 2.09 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.85 GiB | 27.32 B | SYCL | 99 | 1 | tg128 | 45.45 ± 0.71 |

build: 7adb2dd (1)

### PQ2_0

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | SYCL | 99 | 1 | pp512 | 1533.14 ± 34.41 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | SYCL | 99 | 1 | tg128 | 45.87 ± 0.12 |

build: 7adb2dd (1)

### Q2_0 (development)

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B Q2_0 | 7.09 GiB | 26.90 B | SYCL | 99 | 1 | pp512 | 770.03 ± 0.66 |
| qwen35 27B Q2_0 | 7.09 GiB | 26.90 B | SYCL | 99 | 1 | tg128 | 10.26 ± 0.00 |

build: 7adb2dd (1)

## Additional observations

- The TernSYCL XMX fast path covers **both** PTQ1_0 and PQ2_0 at equal speed
  (45.45–45.89 tg128, pp ~1533–1562). The upstream-format `Q2_0` (type 42,
  group 64) has no ternary kernel in this fork and decodes at ~10.3 t/s.
- Per the fork's docs, PTQ1_0 expands to a 2-bit layout at load on the XMX path
  (~+31% weight memory), so its smaller file does not translate into smaller
  VRAM at runtime.
- Serving notes (kept separate from llama-bench timings, per the template):
  - These serving runs used plain `q4_0` KV without a mean-centering bias,
    unlike the FP16 KV used for the llama-bench results above. Mean-centered
    Q4 KV support in this community SYCL runtime has not yet been verified.
  - With the mtp-lean file and `--spec-type draft-mtp,ngram-mod`, effective
    generation on short prompts runs ~63 t/s with the context capacity configured
    to 65536, and ~62.8 t/s with the capacity configured to 131072 (the fork's
    delta-net replay keeps it within 12 GB). Probe prompts in both cases were
    short (~50-100 tokens); these are not filled-context measurements. Correctness checked by exact-match greedy spot tests; no KLD run.
  - PQ2_0 carries no MTP head; with n-gram-only speculation it used 9,340 MiB
    dedicated VRAM with the context capacity configured to 65536 and 10,620 MiB
    at 131072 (Get-Counter, dedicated-usage samples) while decoding
    ~46.5–47.4 t/s on short prompts. No OOM at either setting; VRAM headroom at
    the 131072 configuration was ~1.7 GB.
  - A 32K trimmed draft head (`add_draft_head.py`, English-corpus token
    frequencies) works with the one-graph draft chain, but draft acceptance on
    Chinese text collapses (3.9%); it behaves as intended for English/code.
- One llama-bench process at a time; no other GPU load during measurement.
