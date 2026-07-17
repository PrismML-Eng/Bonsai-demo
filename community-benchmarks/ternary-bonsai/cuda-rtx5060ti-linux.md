# RTX 5060 Ti 16 GB, CUDA (Ternary-Bonsai-27B)

## Summary

RTX 5060 Ti 16 GB (Blackwell sm_120, 448 GB/s, 180 W) in a 2013 desktop (i5-4670K, DDR3-1333, PCIe gen3 x8), Debian 13, driver 610.43.02. PrismML fork commit `62061f91` (b9591), CUDA 12.9.1 build for arch 120. **27B Q2_0: ~44.4 t/s tg128, ~1029 t/s pp512; with the DSpark Q4_1 drafter ~79 t/s single-stream (peaks 87).** Two identical cards; numbers are per card (GPU0/GPU1 within ~2%), replicated twice hours apart within ±0.4%, zero thermal throttle (1 s NVML telemetry throughout, max 76 °C).

Note: this is a 27B row; the results table currently tracks 8B/4B/1.7B. Happy to reformat if you would rather track 27B separately.

## llama-bench Results

### Ternary-Bonsai-27B (Q2_0, g128)

```bash
# Exact invocation. The container sees both GPUs (--gpus all) but every run is pinned to
# exactly ONE card with CUDA_VISIBLE_DEVICES (GPU=0 or 1; both cards identical, reported
# per card). $D = host dir holding the models and both engine builds.
docker run --rm --gpus all -e CUDA_VISIBLE_DEVICES=$GPU -v "$D":/w nvidia/cuda:12.9.1-devel-ubuntu24.04 \
  /w/llama.cpp-prism/build/bin/llama-bench -m /w/Ternary-Bonsai-27B-Q2_0.gguf \
  -p 512 -n 128 -ngl 999 -t 4 -r 10 -o json
```

The full solo / simultaneous / swapped matrix (and the mainline cross-check below) is one script:
[`scripts/bench_phase3.sh`](https://github.com/Astezelex/bonsai-27b-16gb-bench/blob/main/scripts/bench_phase3.sh) in the results repo.

| model | size | params | backend | ngl | test | t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA | 999 | pp512 | 1028.53 ± 0.16 |
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA | 999 | tg128 | 44.44 ± 0.02 |

(Table constructed from `llama-bench -o json` output, first repetition discarded, mean ± sd of 9; raw JSONs linked below. flash_attn was auto (-1), not `-fa 1`.)

Second card (GPU1, same box, simultaneous run): pp512 1004.68 ± 0.11, tg128 44.20 ± 0.04.

## Configuration

- **DSpark drafter** (`--spec-type draft-dspark`, Q4_1 drafter, `--spec-draft-n-max 4`: the server refuses to start without it): **1.78x average single-stream speedup** (79.1 t/s mean over 512-token generations, range 72-87 by prompt). The Q4_1 drafter beat the bf16 drafter (67.8 t/s) and their outputs are byte-identical at temp 0 (5/5 prompts), confirming the precision-affects-speed-only claim.
- Solo vs simultaneous (one model per card) vs swapped cards: identical within noise at batch 1.
- KV/context fit (NVML resident, single slot): 4k f16 = 7,627 MiB; 100k f16 = 13,867 MiB; **full 262k with q4_0 KV = 13,213 MiB**: fits the 16 GB card with ~3 GiB to spare.
- Comparison vs Qwen3.6-27B-UD-IQ2_XXS (9.39 GB) on the same cards: ternary decodes +24% faster (44.4 vs 35.8 t/s, each on its best engine: mainline `12127de` runs the IQ2_XXS file ~4.5% faster than this fork does).

## Exact invocations for the rows above

**DSpark drafter** (target server; only the drafter flags change between the three configs;
harness script + the 5 fixed prompts: [`scripts/phase3b_drafter.sh`](https://github.com/Astezelex/bonsai-27b-16gb-bench/blob/main/scripts/phase3b_drafter.sh),
[`scripts/drafter_prompts.jsonl`](https://github.com/Astezelex/bonsai-27b-16gb-bench/blob/main/scripts/drafter_prompts.jsonl)):

```bash
# baseline (no drafter):
docker run -d --gpus all -e CUDA_VISIBLE_DEVICES=0 -p 8090:8080 -v "$D":/w nvidia/cuda:12.9.1-devel-ubuntu24.04 \
  /w/llama.cpp-prism/build/bin/llama-server -m /w/Ternary-Bonsai-27B-Q2_0.gguf \
  -ngl 999 -c 4096 -np 1 --host 0.0.0.0 --port 8080
# DSpark Q4_1 row: same command plus
#   --spec-type draft-dspark -md /w/Ternary-Bonsai-27B-dspark-Q4_1.gguf --spec-draft-ngl 999 --spec-draft-n-max 4
# bf16 drafter row: same plus the same flags with -md /w/Ternary-Bonsai-27B-dspark-bf16.gguf
```

Harness: each prompt via `/v1/chat/completions`, `max_tokens` 512, `top_p` 0.95, `top_k` 20,
`cache_prompt: false`; temp 0 for the byte-equivalence check, temp 0.7 (2 reps) for speed;
t/s taken from the server's native `timings.predicted_per_second`.

**KV/context fit** (per config: start the server, wait for `/health`, read NVML resident VRAM
on that card, tear down; script: [`scripts/phase3c_fit.sh`](https://github.com/Astezelex/bonsai-27b-16gb-bench/blob/main/scripts/phase3c_fit.sh)):

```bash
docker run -d --gpus all -e CUDA_VISIBLE_DEVICES=0 -p 8091:8080 -v "$D":/w nvidia/cuda:12.9.1-devel-ubuntu24.04 \
  /w/llama.cpp-prism/build/bin/llama-server -m /w/Ternary-Bonsai-27B-Q2_0.gguf \
  -ngl 999 --host 0.0.0.0 --port 8080 $CONFIG
# 4k f16:    CONFIG='-c 4096   -np 1'
# 100k f16:  CONFIG='-c 102400 -np 1'
# 262k q4_0: CONFIG='-c 262144 -np 1 -ctk q4_0 -ctv q4_0'
```

**Comparison-engine runs** (same wrapper and flags as the headline bench, only the binary and
model change):

```bash
# IQ2_XXS best-engine row: pinned mainline llama.cpp 12127de
docker run --rm --gpus all -e CUDA_VISIBLE_DEVICES=0 -v "$D":/w nvidia/cuda:12.9.1-devel-ubuntu24.04 \
  /w/llama.cpp-main/build/bin/llama-bench -m /w/Qwen3.6-27B-UD-IQ2_XXS.gguf \
  -p 512 -n 128 -ngl 999 -t 4 -r 10 -o json
# fork-runs-IQ2_XXS-slower datum (~4.5%): identical command with /w/llama.cpp-prism/build/bin/llama-bench
```

## Notes

- Built in a CUDA devel container; a GPU-less configure caches `CUDA_DRIVER=NOTFOUND` in CMakeCache and later builds keep failing: wipe the cache and configure with the GPU attached.
- Host is deliberately old (2013): decode is GPU-bandwidth-bound and does not care; prefill and cold load reflect the host.
- Full quality anchors (AIME26 / MMLU-Redux / LiveCodeBench with cap-rates and budgets), energy per solved problem, raw eval JSONs, telemetry, and the raw llama-bench JSONs for every row here: https://github.com/Astezelex/bonsai-27b-16gb-bench

## Hardware

```
CPU: Intel(R) Core(TM) i5-4670K CPU @ 3.40GHz (4c/4t, Haswell)
RAM: 32 GB DDR3-1333
GPU: 2x NVIDIA GeForce RTX 5060 Ti 16 GB (16311 MiB, 180 W limit), PCIe gen3 x8 per card under load
OS:  Debian 13, kernel 7.0.6-2, driver 610.43.02 (open module)
```
