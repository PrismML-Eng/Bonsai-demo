# AMD Radeon RX 9070 XT — ROCm/HIP

## Summary

**Bonsai 2 27B** (`Ternary-Bonsai-2-27B`, Qwen3.8-based) on an AMD Radeon RX 9070 XT 16 GB
(RDNA4, **gfx1201**) via llama.cpp ROCm, using the prebuilt `bin/rocm` binaries from release
`prism-b10683-d8f26ee`. Fedora-based immutable host (Bazzite), ROCm 7.2.1.

Headline, both current Bonsai 2 bands, 27B:

| Band | Size | PP512 (t/s) | TG128 (t/s) |
|------|-----:|------------:|------------:|
| `PQ2_0` (2.13 bpw, group 128) | 6.70 GiB | **1046.35** | **50.69** |
| `PTQ1_0` (1.75 bpw, group 128) | 5.53 GiB | 955.90 | 34.05 |

**`PQ2_0` is decisively faster on this hardware — ~49% higher decode (50.69 vs 34.05 t/s)
and ~9% higher prefill — despite being 1.17 GiB larger.** The docs say neither packing is
uniformly faster; on RDNA4/ROCm that is not a close call. On this card `PTQ1_0` is worth
choosing only when the 1.17 GiB genuinely decides whether the model fits. (It does on
smaller cards — see Notes.)

Note this is **Bonsai 2 27B**, not the earlier `Ternary-Bonsai-27B` the table above is built
from, so it is not strictly apples-to-apples with the existing rows.

## llama-bench Results

### Bonsai 2 27B — `PQ2_0` (6.70 GiB)

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |   1 |           pp512 |       1046.35 ± 7.82 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |   1 |           tg128 |         50.69 ± 0.22 |

### Bonsai 2 27B — `PTQ1_0` (5.53 GiB)

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | ROCm       |  99 |   1 |           pp512 |        955.90 ± 9.45 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | ROCm       |  99 |   1 |           tg128 |         34.05 ± 0.06 |

### Commands run

```bash
# host has no ROCm installed (immutable OS), so everything runs inside a
# distrobox container with the ROCm userspace:
distrobox enter marker -- bash -lc '
  cd $HOME/Bonsai-demo
  HIP_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=$HOME/Bonsai-demo/bin/rocm \
    bin/rocm/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1
  HIP_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=$HOME/Bonsai-demo/bin/rocm \
    bin/rocm/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1
'
```

## Configuration

| | |
|---|---|
| GPU | AMD Radeon RX 9070 XT 16 GB (RDNA4, gfx1201) |
| CPU | AMD Ryzen 7 7800X3D (8c/16t) |
| RAM | 32 GB |
| OS | Bazzite (Fedora-based, immutable), kernel 7.2.4-ogc3.1.fc44.x86_64 |
| Mesa | 26.2.2 |
| ROCm | 7.2.1 (inside container; host has none) |
| Binaries | `prism-b10683-d8f26ee`, `llama-prism-b10683-d8f26ee-bin-ubuntu-rocm-7.2-x64.tar.gz` |
| Thermals | GPU stayed ~72 °C @ ~100 W under sustained load |

Prebuilt `libggml-hip.so` from this release targets: `gfx908 gfx942 gfx1030 gfx1100 gfx1101
gfx1102 gfx1150 gfx1151 gfx1200 gfx1201`. **gfx1201 is included — no override needed on
RDNA4**, it works out of the box.

## Notes

**Running on an immutable / no-ROCm host.** Bazzite has no ROCm userspace. Everything runs
inside a `distrobox` container built from `rocm/dev-ubuntu-24.04` (ROCm 7.2.1, matching the
binaries' ROCm 7.2). Worth knowing: `scripts/download_binaries.sh` selects its backend by
probing for `rocminfo` / `rocm-smi` / `hipcc` **on PATH**. On a host without ROCm those are
absent, so it silently falls back to the **Vulkan** build. Running `setup.sh` *inside* the
ROCm container makes it correctly report `Detected AMD ROCm → using ROCm 7.2 build`.

**If you hand-roll the run outside the demo scripts, put `/opt/rocm/lib` on
`LD_LIBRARY_PATH`.** With only the binary directory on the path, `libamdhip64.so.7`,
`librocblas.so.5` and `libhipblas.so.3` fail to resolve, the HIP backend never loads, and
**llama-server still starts, reports "model loaded" and serves requests — on CPU, ~3x slower,
with no error in the log.** The only reliable tell is VRAM usage
(`/sys/class/drm/card0/device/mem_info_vram_used`). The demo's own `start_llama_server.sh`
sets this correctly; this only bites hand-rolled invocations.

**`HIP_VISIBLE_DEVICES=0` is advisable on APU-equipped systems.** Without it `llama-bench`
enumerates two ROCm devices — the discrete card *and* the 7800X3D's integrated gfx1036 —
and reports a combined 31,893 MiB of "VRAM". Here it made no measurable difference
(unpinned: 1043.12 pp / 50.70 tg vs pinned: 1046.35 / 50.69), because the model fits
entirely on the dGPU and no layers were split. On a larger model or a smaller dGPU it
plausibly would matter, so pinning makes the result unambiguous.

**Same model on a much smaller AMD card, for reference.** `PTQ1_0` was also run on an
**RX 6600 8 GB (gfx1032)** on another machine. That architecture has **no kernels in the
prebuilt `libggml-hip.so`** (gfx1030 is its only RDNA2 target), but it runs correctly with
`HSA_OVERRIDE_GFX_VERSION=10.3.0`, which presents Navi 23 as Navi 21. Verified not silently
wrong: exact recall of a fact planted at the start of a 14k-token prompt, coherent reasoning,
and a 9/9 score on a local tool-calling/prompt-injection suite. It sustains ~9–11 t/s decode
at 64k context with `--cache-type-k q4_0 --cache-type-v q4_0` (6.4–7.7 GiB of 8 GiB used).
That is the case where `PTQ1_0`'s smaller footprint is the whole point. Happy to submit that
as a separate entry if useful.

**One harness oddity.** One `PTQ1_0` run exited cleanly (status 0) after printing only the
`pp512` row, never running `tg128` — no error, no crash, nothing in the log beyond the
backend-load lines. Two subsequent identical runs both completed normally, so it is a
one-off rather than something about that file or that band, and `PQ2_0` never did it.
Flagging in case anyone else sees a silently truncated benchmark.

**Reproducibility.** Both bands were benchmarked with the same command shape and llama-bench's
default repetition count; the numbers above are from those runs. `PTQ1_0` was additionally run
with `-r 3` as a cross-check and agreed within error (pp512 951.11 ± 13.09, tg128 34.13 ± 0.06),
as did `PQ2_0` unpinned without `HIP_VISIBLE_DEVICES` (pp512 1043.12 ± 8.85, tg128 50.70 ± 0.22).
