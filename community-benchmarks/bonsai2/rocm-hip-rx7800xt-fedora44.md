# Bonsai 2 27B — community report: RX 7800 XT (gfx1101) — ROCm/HIP
<!-- Community benchmark for PrismML-Eng/Bonsai-demo.
     All numbers measured 2026-09-19 (standard + cold-prefill bench runs 2026-09-21) on the machine described in §Hardware.
     No numbers are estimated; every figure comes from a logged command output. -->

# AMD RX 7800 XT (16 GB, gfx1101) — ROCm/HIP — Bonsai 2 27B PQ2_0

## Summary

Fedora 44 + ROCm 7.1.1 userspace running the prebuilt **ROCm 7.2** fork binary
(`prism-b10709-9a9394a`). Bonsai 2 27B PQ2_0 runs well at short context:
**pp64 153 t/s, tg4 41.9 t/s** (llama-bench, ngl 99), ~50 t/s decode in server use,
and **262,144-token context loads and works on a 16 GB card** with
`BONSAI_KV4=1 BONSAI_MMPROJ_CPU=1 --parallel 1` (weights 6.7 GiB + KV4 ≈ 4.6 GiB;
q4_0 KV, no bias).
Needle-recall verified at 64K and 98K depth.

**Main observation → hypothesis (requesting maintainer attention):** decode speed
falls roughly linearly with context depth — ~0.55 µs per cached token. Our working
hypothesis: the q4_0 KV cache is streamed at ~33 GB/s, about 5% of this card's
624 GB/s peak bandwidth (98K depth → 11.4 t/s). Controlled A/B ruled out: thermals
(sclk/mclk at max throughout), system load (0.00 after closing all other processes;
identical 11.4 t/s), VRAM oversubscription. Hypothesised cause — offered for
maintainer confirmation, not an established finding: an unoptimized quantized-KV
flash-attention path for RDNA3/gfx1101 in the ROCm backend. Same file on the same card via the **Vulkan** build is far worse
(§Configuration), so ROCm is the usable backend here — it just loses ~3× at deep
context to what the bandwidth math predicts.

Also documented below: Vulkan PQ2_0 failure signature on gfx1101 (silent 0.8 t/s
prompt processing), and a successful 256K-context recipe on 16 GB.

## llama-bench Results

### Bonsai-2-27B — PQ2_0 (the default band)

```bash
BENCH=bin/rocm/llama-bench
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -p 512 -n 128   # standard run
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -p 64 -n 4      # short-ctx reference
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -p 11200 -n 0   # cold 11.2K prefill
```

| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |            pp64 |        153.30 ± 2.99 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |             tg4 |         41.92 ± 1.42 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |           pp512 |        316.29 ± 1.70 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |           tg128 |         46.75 ± 0.04 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |         pp11200 |        295.85 ± 0.14 |

build: 9a9394a89 (10709)

(Skipped: Q2_0_g64 for Bonsai 2 — not present in the repo; gen-1 Ternary/Bonsai families — not tested on this card. The dev-repo file `Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf` is, per the
maintainers, a **current testing format requiring the PrismML fork** (not a
deprecated legacy file). It was not benchmarked here.)

### Server-mode numbers (llama-server, same machine)

| Config | Measured |
|---|---|
| 32K ctx, KV4 (no bias), 4 slots, mmproj on GPU | 11.2K-token pi agent prompt prefill ≈ 0.4 s (**warm cache** — shared prefix reused across turns; cold prefill measured separately: pp11200 = 295.85 t/s → ≈ 37.9 s for 11.2K); 150 tok generated in 2.98 s (≈ 50 t/s decode) |
| 262,144 ctx (256K), KV4 (no bias), `--parallel 1`, mmproj on CPU | loads, healthy, effective n_ctx = 262,144 (per `/props`) |
| 64,405-tok prompt prefill (256K mode) | 294 s → **219 tok/s** sustained |
| 98,504-tok prompt prefill (256K mode) | 516 s → **191 tok/s** sustained |
| Needle recall at 64K and 98K depth | PASS (exact string retrieved from midpoint of filler) |
| Decode at depth | see depth ladder in §3 |

## Configuration

### 1. Vulkan backend (same release, same card) is not usable for PQ2_0 on gfx1101

- Prompt processing: **0.79 t/s** (33 tokens took 41.7 s) — identical under zero load and under load, so intrinsic, not contention.
- VRAM: ~15.9 GiB at 8K ctx (≈ 2× the expected footprint; group-128 PQ2_0 + FA).
- `llama-bench` loads then dies (no table).
- Workaround: use the ROCm build (`bin/rocm/`), which is fast and stable (numbers above).
- The launcher's backend search order checks `bin/rocm` before `bin/vulkan`, but
  `download_binaries.sh` auto-picked ROCm for this AMD card anyway — be aware both
  directories can exist after experimenting; stale `bin/vulkan` content silently
  loses to `bin/rocm`.

### 2. 256K context on a 16 GB card — recipe that works

```bash
BONSAI_HOST=0.0.0.0 BONSAI_CTX=262144 BONSAI_KV4=1 BONSAI_MMPROJ_CPU=1 \
  ./scripts/start_llama_server.sh --alias bonsai2-27b --parallel 1
```

- Loads and serves; `/props` reports effective n_ctx 262,144.
- FP16 KV at 256K does **not** fit 16 GB (16 GiB KV alone); KV4 is required
  (uncorrected q4_0, "no bias", in this report — the maintainers' calibrated
  mean-centering bias is recommended for quality; see Notes).
- Long-prefill throughput at depth: 191–256 tok/s (see server-mode table).
- At 191–256 tok/s, a ~214K-token prompt would take approximately 14–19 minutes
  to prefill (an estimate from the reported throughput, not a separate measurement).

### 3. q4_0 KV attention: decode speed vs context depth (hypothesis)

Depth ladder on the live 256K server (q4_0 KV, no bias; thinking off, 24–32 gen tokens, same machine,
controlled A/B with every other GPU-capable process closed — ollama service stopped,
CPU-only VL server stopped, load average 0.00):

| Context depth | Decode | Per-token cost |
|---|---|---|
| ~1.2K | 34.9 t/s | 28.7 ms |
| ~30K | 23.3 t/s | 42.9 ms |
| ~98K (real workload) | 11.4–11.8 t/s | 84.7 ms |

- Linear fit: **~0.55 µs per cached token** → implying, if the dominant cost is KV
  streaming, an effective rate of ≈ **33 GB/s** vs 624 GB/s peak (≈ 5%) — a
  hypothesis from timing extrapolation, not a profiled measurement. The FP16-KV shallow case (41.9 t/s bench) shows the card
  and weights path are fine; the cost is specific to the quantized-KV attention read.
- Isolation checks during the deep probe: sclk 2493–2538 MHz and mclk at max level
  (no power/clock throttle), zero memory-allocation errors in logs, results
  unchanged with all other processes closed.
- Thermals: edge 66–67 °C, **junction 96–97 °C** during sustained prefill — no
  throttle observed, but worth noting for 7800 XT owners (cooling headroom is thin).

**Question for maintainers:** is the q4_0-KV flash-attention kernel in the ROCm
backend known to be unoptimized on RDNA3 (gfx1101)? On CUDA/Metal the docs describe
KV4 as "slightly slower than FP16"; here it costs ~3× at depth. Any knob we missed
(e.g. different `-ub`, FA variants, a gfx1101-specific build flag), or is this a
candidate for kernel work / a call for RDNA3 ROCm testers?

### 3b. Controlled A/B: FP16 KV vs q4_0 KV decode at ~94K depth (2026-09-21)

Identical 93,906-token prompt, same machine, same build (`9a9394a89`), only the KV
cache dtype varied (fresh server instance per run, `ngl 99`, `-fa on`, ctx 98304).

| KV cache | KV VRAM @ 94K | Prefill | **Decode @ 93.9K depth** |
|---|---|---|---|
| **FP16** | ~5.7 GiB | 199.9 t/s | **29.79 t/s** |
| **q4_0** | ~1.7 GiB | 193.8 t/s | **12.03 t/s** |

- Decode with q4_0 KV is **2.48× slower** at identical depth; prefill is unaffected
  (~194–200 t/s both ways). The q4_0 baseline reproduces the §3 depth ladder
  (11.4–11.8 t/s at 98K on the live server), so the two methodologies agree.
- This isolates the deep-context cost to the **q4_0-KV attention read path during
  decode** — consistent with the §3 hypothesis — rather than deep-context attention
  in general.
- Practical note for 16 GB owners: FP16 KV is the speed option at moderate depth
  (weights + FP16 KV fit to roughly ~120K ctx); q4_0 KV remains the only way to
  reach 256K on this card.

### 4. Small notes

- The Qwen3.8-template thinking toggle works per-request via
  `chat_template_kwargs: {"enable_thinking": false}`; thinking streams as
  `reasoning_content` as documented.
- `download_binaries.sh` auto-detects "AMD" and downloads the ROCm build; on this
  card that is the right choice anyway (see §1), but a `BONSAI_BACKEND` override
  would have saved a 33 MB download.
- 27B repos (incl. Bonsai 2) were public, no token needed (2026-09-19).

## Notes

- ROCm userspace on the distro is 7.1.1 (Fedora packages); the prebuilt ROCm 7.2
  binary runs against it without issues for llama-bench and llama-server.
- The Ubuntu-built ROCm binary needs no additional runtime setup on Fedora beyond
  `LD_LIBRARY_PATH` (handled by the start script).
- All KV4 timings in this report are **uncorrected q4_0 ("no bias")** —
  `make_kv_bias.sh` was not run. Per maintainer guidance, the recommended workflow
  is the model-specific **calibrated mean-centering bias**: build once with
  `scripts/make_kv_bias.sh` (→ `*kv-bias*.gguf`); with `BONSAI_KV4=1` the start
  script auto-applies it (`--kv-mean-center` + `LLAMA_ATTN_ROT_DISABLE=1`), with
  matching calibration and inference settings. See the experimental
  [KV-cache guide](../../KV-CACHE.md) for the recommended quality-correction workflow.
  Its quality and performance effects were not measured in this report. Existing
  timings are retained as the "no bias" baseline; the long-context suite was not re-run.
- Vision: mmproj-Q8_0 loads (`BONSAI_MMPROJ_CPU=1` in 256K mode → CPU projector);
  image inference not benchmarked.

## Hardware

```
CPU   : AMD Ryzen 7 5700X 8C/16T (Zen 3)
RAM   : 62 GiB DDR4
GPU   : AMD Radeon RX 7800 XT 16 GB (Navi 32, gfx1101), 624 GB/s peak BW
OS    : Fedora Linux 44 (KDE), kernel 7.2.4-200.fc44
Stack : Mesa 26.1.8 / LLVM 22 (RADV), Vulkan 1.4.354; ROCm userspace 7.1.1-6.fc44
Binary: PrismML fork prebuilt ROCm 7.2, release prism-b10709-9a9394a
Model : Ternary-Bonsai-2-27B-PQ2_0.gguf (6.8 GiB on disk) + mmproj-Q8_0 (0.6 GiB)
```
