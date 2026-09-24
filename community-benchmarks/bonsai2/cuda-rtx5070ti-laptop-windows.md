# RTX 5070 Ti Laptop (12 GB) — CUDA

## Summary

RTX 5070 Ti Laptop GPU (Blackwell, sm_120, 12 GB, driver 616.56) paired with a Core Ultra 9 275HX (8P+16E) and 32 GB DDR5, Windows 11. Prism release binaries `prism-b10685-7dffb15`, CUDA build, `-ngl 99 -fa 1`.

Power limit: all absolute numbers below were measured with the GPU power limit enforced at 55 W (`enforced.power.limit`, default 65 W, max 140 W on this chassis). The same binary and file run roughly 1.6x higher at 140 W, so these figures are not comparable to laptops left at their default limit.

Bonsai 2 27B decode on this card is bandwidth-bound at about 49 t/s with either packing. Prompt processing strongly prefers PQ2_0: 1,135 t/s vs 527 t/s for PTQ1_0, a 2.15x gap.

Headline numbers (llama-bench, 8 CPU threads, batch 1):

| file | pp512 | tg128 |
|---|---:|---:|
| Ternary-Bonsai-2-27B-PTQ1_0.gguf (5.53 GiB) | 527.46 ± 7.21 | 48.97 ± 0.34 |
| Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf (7.12 GiB) | 1134.67 ± 38.75 | 48.97 ± 2.00 |

Extra findings on this machine, measured with llama-server timings:

- 4-bit KV cache + mean-centering bias (see below) fits a 131072-token context in 12 GB with 2.6 GB to spare; decode at that depth runs at 40.7 t/s.
- n-gram speculative decoding (`--spec-type ngram-cache`) is a net loss here: 38-39 t/s in chat (0% acceptance) and 39 t/s on a text-continuation workload (54% acceptance). Don't bother on this class of GPU unless your workload reproduces the prompt verbatim.
- The PQ2_0 file that ships with the community MTP head (`ProCreations/Ternary-Bonsai-2-27B-MTP`) loads fine as a plain model, but `--spec-type draft-mtp` fails on stock b10685/b10687 binaries: the loader reports `Hadamard-latent table 'token_embd.weight' is read without the inverse transform` when creating the MTP context. The MTP head itself needs a patched runtime (ProCreations ship one for Linux/CUDA).

## llama-bench Results

### Bonsai 2 27B — PTQ1_0

```
| model                          |       size |     params | backend    | ngl | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ------: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |       8 |   1 |           pp512 |        527.46 ± 7.21 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |       8 |   1 |           tg128 |         48.97 ± 0.34 |

build: 7dffb158d (10685)
```

### Bonsai 2 27B — PQ2_0 (file carries the community MTP head; head is skipped by the plain loader)

```
| model                          |       size |     params | backend    | ngl | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ------: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   7.12 GiB |    27.32 B | CUDA       |  99 |       8 |   1 |           pp512 |      1134.67 ± 38.75 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   7.12 GiB |    27.32 B | CUDA       |  99 |       8 |   1 |           tg128 |         48.97 ± 2.00 |

build: 7dffb158d (10685)
```

### Bonsai 2 27B — PTQ1_0 with 4-bit KV cache

llama-bench does not take `--kv-mean-center`, so this row is without the bias. At llama-bench's small depth the 4-bit cache costs almost nothing; the real tradeoff shows up at long context (next section).

```
| model                          |       size |     params | backend    | ngl | threads |    kv-k |    kv-v |   fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | ------: | ---: | ------: | ------: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |       8 |   q4_0 |   q4_0 |   1 |           pp512 |        525.68 ± 8.17 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |       8 |   q4_0 |   q4_0 |   1 |           tg128 |         48.33 ± 0.16 |

build: 7dffb158d (10685)
```

## 4-bit KV cache + mean-centering bias at 128K context (llama-server)

The 27B's KV cache lives on 16 of 64 layers, but a 131072-token context still needs about 4.5 GiB at q8_0, which does not fit next to the 5.53 GiB PTQ1_0 weights in 12 GB. With `--cache-type-k q4_0 --cache-type-v q4_0` plus a calibrated `--kv-mean-center` bias it does. See [KV-CACHE.md](../../KV-CACHE.md) for the full workflow and the calibration script that ships with the binaries.

One trap worth writing down: the bias must be calibrated with the same K-rotation state as the serving context. `llama-kv-mean-center` runs with the rotation inactive by default (f16 cache), but any quantized K cache enables the rotation, and the loader refuses a mismatched bias file. Calibrate with `--cache-type-k q4_0` on the tool as well and it lines up.

```
llama-kv-mean-center -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -f corpus.txt -o Ternary-Bonsai-2-27B-kv-bias.gguf -ngl 99 -c 512 --cache-type-k q4_0

llama-server -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa on -c 131072 -np 1 \
  -ctk q4_0 -ctv q4_0 -b 2048 -ub 512 --jinja \
  --kv-mean-center Ternary-Bonsai-2-27B-kv-bias.gguf
```

Results: model + 128K context fits with 2647 MiB still free on the card. The 40.7 t/s figure is the full 131072-token configuration in a single server slot (`-np 1`, so the whole context budget belongs to one conversation); the context was filled to 131072 tokens before decoding and the timing window is 174 generated tokens. Short smoke tests (arithmetic, Italian prose) stayed correct with the bias attached.

## Speculative decoding

### n-gram cache (stock binary): no benefit

`--spec-type ngram-cache --spec-draft-n-max 8 -np 1` (PQ2_0, 65536 ctx): chat prompts 0% acceptance, decode 38.06 t/s; a "continue this text" prompt with heavy verbatim repetition reached 54% acceptance and still only 39.07 t/s. Both below the 48-49 t/s baseline. The verification overhead outweighs the accepted drafts at this bandwidth utilization.

### MTP draft head: refused on stock, works with the patched runtime

Stock release binaries refuse the MTP context. `prism-b10685-7dffb15` and `b10687` (5d80cff) both stop while creating it with:

```
Hadamard-latent table 'token_embd.weight' is read without the inverse transform
```

The head needs the runtime patch the drafter authors ship:
[ProCreations/Ternary-Bonsai-2-27B-MTP](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP) → `runtime/bonsai-mtp-embedding.patch` (12 lines in `src/models/qwen35.cpp`). It applies on top of the fork HEAD. The numbers below come from a local build of fork HEAD plus that patch, not from a release binary.

Same file (`Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf`), `-ngl 99 -fa on -c 65536 -ctk q8_0 -ctv q8_0 -np 1 --spec-type draft-mtp --spec-draft-n-max 2`:

| workload | draft acceptance | MTP off | MTP on |
|---|---:|---:|---:|
| code / structured | 60-75% | 49 t/s | 70-75 t/s |
| open-ended chat | 35-50% | 49 t/s | 49-57 t/s |

The MTP-off column is the same file and settings without `--spec-type draft-mtp`. `--spec-draft-n-max 2` beat 4 on this card, and `-np 1` is required by the MTP context.

## Commands

```
BENCH=bin/llama-bench
$BENCH -m models/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1 -t 8 -p 512 -n 128 -r 3
$BENCH -m models/Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf -ngl 99 -fa 1 -t 8 -p 512 -n 128 -r 3
$BENCH -m models/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1 -t 8 -p 512 -n 128 -r 3 -ctk q4_0 -ctv q4_0
```

## Test environment

- GPU: NVIDIA RTX 5070 Ti Laptop, 12 GB GDDR7, driver 616.56, CUDA build of prism-b10685-7dffb15
- CPU: Core Ultra 9 275HX (Arrow Lake-HX, 8P+16E), 32 GB DDR5
- OS: Windows 11 (10.0.26200)
- Files: `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from prism-ml/Ternary-Bonsai-2-27B-gguf (sha256 verified); `Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf` from ProCreations/Ternary-Bonsai-2-27B-MTP
- All numbers measured on 2026-09-18, rep counts as printed by llama-bench. The patched-MTP numbers are from 2026-09-20 on the fork HEAD + `bonsai-mtp-embedding.patch` build.