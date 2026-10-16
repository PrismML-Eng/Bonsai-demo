# Intel Arc B580 (12 GB) — llama.cpp Vulkan on Windows (Bonsai 2 27B)

Submitted 2026-10-16. Model paths in the commands are anonymized; exact
filenames and hashes are listed in the Configuration section.

## Summary

Bonsai 2 27B on Intel Arc B580 12 GB (Battlemage Xe2), Windows 11 (build 26200),
using the PrismML fork release `prism-b10777-e3de715` (prebuilt
`llama-prism-b10777-e3de715-bin-win-vulkan-x64.zip`).

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 559.35 ± 2.77 | 28.59 ± 0.07 |
| PTQ1_0 | 379.75 ± 3.57 | 34.84 ± 0.13 |
| Q2_0 (development) | 568.00 ± 1.50 | 31.59 ± 0.04 |

## Configuration

- Models, `prism-ml/Ternary-Bonsai-2-27B-gguf`:
  - `Ternary-Bonsai-2-27B-PQ2_0.gguf` — 7,206,168,928 bytes,
    sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`
  - `Ternary-Bonsai-2-27B-PTQ1_0.gguf` — 5,946,648,928 bytes,
    sha256 `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`
  - development Q2_0: `Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf` from
    `prism-ml/Ternary-Bonsai-2-27B-gguf-dev` — 7,626,008,928 bytes
- llama.cpp: PrismML fork release `prism-b10777-e3de715`, prebuilt
  `llama-prism-b10777-e3de715-bin-win-vulkan-x64.zip`
  (asset sha256 `6bf30d60dd35ae1129ae221593d79bed053c775c6ce8554f75cfe171f3028f10`);
  no source build, no code changes
- OS: Windows 11 (build 26200)
- GPU driver: Intel 32.0.101.9033; Level Zero / OpenCL from the same driver
- Hardware: Intel Arc B580 12 GB (ReBAR on), Intel Core i5-12600KF, 64 GB DDR4,
  stock power and clocks
- Flags: `-ngl 99 -fa 1`, default KV cache (f16), default context, default
  threads/batch, 5 repetitions (default). No mmproj involved (llama-bench).

## llama-bench results

### PQ2_0

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | 1 | pp512 | 559.35 ± 2.77 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | 1 | tg128 | 28.59 ± 0.07 |

build: e3de71522 (10777)

### PTQ1_0

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-PTQ1_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | Vulkan | 99 | 1 | pp512 | 379.75 ± 3.57 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | Vulkan | 99 | 1 | tg128 | 34.84 ± 0.13 |

build: e3de71522 (10777)

### Q2_0 (development)

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|-------|-----:|-------:|---------|----:|--:|-----:|----:|
| qwen35 27B Q2_0 | 7.09 GiB | 26.90 B | Vulkan | 99 | 1 | pp512 | 568.00 ± 1.50 |
| qwen35 27B Q2_0 | 7.09 GiB | 26.90 B | Vulkan | 99 | 1 | tg128 | 31.59 ± 0.04 |

build: e3de71522 (10777)

## Additional observations

- All three packings load and generate correctly on Intel Windows Vulkan with
  this build; outputs were coherent (greedy text spot-checks only, no KLD run).
- Upstream `ggml-org/llama.cpp` v0.7.0 (b11669) refuses `PQ2_0` (type 142) and
  `PTQ1_0` (type 143) as unknown types (verified on this machine). The
  development `Q2_0` runs on upstream b11669 Vulkan (pp 602.12 / tg 29.09,
  measured with a non-default q4_0 KV — cross-check only, listed here for
  completeness).
- Short-length PTQ1_0 decode (34.84) is consistent with the docs' note that
  Intel Vulkan PTQ1_0 is slow on this stack; the same card reaches ~45.9 tg128
  on SYCL with a community Intel-focused fork (sibling report
  `sycl-arc-b580-12gb-windows.md`).
- One llama-bench process at a time; no other GPU load during measurement.
