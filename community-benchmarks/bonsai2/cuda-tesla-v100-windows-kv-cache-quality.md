# Tesla V100-SXM2 16 GB - 4-bit KV cache quality (CUDA, Windows)

## Summary

Follow-up to [cuda-tesla-v100-windows.md](cuda-tesla-v100-windows.md) and to the suggestion in KV-CACHE.md: the parent report showed that quantizing the K/V cache to q4_0 costs nothing in speed on this card, but it did not show what it costs in quality. This report measures that, and whether the calibrated mean-centering bias recovers it.

Machine, model, fork commit and binaries are identical to the parent report (Tesla V100-SXM2 16 GB, Windows 11, driver 581.15, PrismML fork 9a9394a89 / prism-b10709, Ternary-Bonsai-2-27B-PQ2_0.gguf).

- The calibrated bias helps, and the mechanism is the basis. With the Hadamard K rotation active, mean logit KLD against an F16-cache reference over 12x512-token held-out chunks is 0.00150 -> 0.00129 (-14%) when a bias calibrated in the rotated basis is loaded. That follows the same pattern as the upstream table in tools/kv-mean-center/README.md (0.00144 -> 0.00111) on Volta.
- Centering alone is not the win. The same bias applied with the rotation disabled (LLAMA_ATTN_ROT_DISABLE=1 at both calibration and inference) measures 0.00195 - better than the mismatched basis (which the loader rejects outright), but worse than rotation alone (0.00150) and worse than the composed configuration (0.00129).
- A mismatched bias file is refused at context creation, not silently degraded - verified below.
- End-to-end perplexity on a 350 KB held-out WikiText-2 slice (20 x 4096-token chunks) moves very little, and the bias halves what little there is: F16 KV 7.2761 +/- 0.09, q4_0 KV 7.2881 +/- 0.09 (+0.16%), q4_0 + calibrated bias 7.2811 +/- 0.09 (+0.07%). Both deltas sit inside the chunk-to-chunk error bars, so the honest statement is "no measurable end-to-end loss on coherent text; the bias moves the number in the right direction".
- Long-context retrieval does not separate the arms either: every arm returns all eight codes at 32K and 128K, and at 250K both the biased and the unbiased `q4_0` cache still answer all eight individual questions correctly while dropping one code from the "list them all in one reply" question (7/8). Answer confidence degrades with context length, not with the KV format. Section C has the numbers - this one is a negative result and is reported as such.

## A. Logit KLD vs an F16 cache (12 x 512-token held-out chunks)

Protocol from tools/kv-mean-center/README.md: llama-perplexity --kl-divergence against logits saved from an F16-cache run over the same held-out text. Corpus: a 13K-token slice of the WikiText-2 raw test split (never used for calibration).

| configuration | mean KLD | delta vs no bias | mean PPL |
| --- | ---: | ---: | ---: |
| F16 KV (reference) | - | - | 10.3270 |
| q4_0 KV, rotation active, no bias | 0.001496 +/- 0.000040 | - | 10.3599 |
| q4_0 KV, rotation disabled + bias calibrated with rotation disabled (centering alone) | 0.001954 +/- 0.000068 | +31% | 10.3569 |
| q4_0 KV, rotation active + bias calibrated in the rotated basis | 0.00129 +/- 0.000037 | -14% | 10.3488 |
| q4_0 KV + bias calibrated with rotation disabled, rotation active (mismatch) | refused at load | - | - |

Upstream reference numbers from tools/kv-mean-center/README.md on the maintainers' hardware: 0.00144 (rotation alone), 0.00149 (centering alone), 0.00111 (rotation + rotated-basis bias). The same ranking reproduces (composed configuration first, mismatch last) and the absolute values are within ~30% of upstream, but the gap between centering alone and rotation alone is wider on this model (0.00195 vs 0.00150 here, 0.00149 vs 0.00144 upstream) - Bonsai 2 27B leans on the rotation more than the maintainers' hybrid-attention model does.

### The mismatched basis is rejected, not degraded

```text
load_kv_mean_center: bias file Bonsai-2-27B-kv-mean-center-norot.gguf was calibrated with the
K-cache rotation inactive, but it is active for this context - recalibrate with matching cache
settings (or set LLAMA_ATTN_ROT_DISABLE=1 consistently in both)
llama_init_from_model: failed to initialize the context: failed to load K-cache mean-centering bias file
```

The process exits before any evaluation (16.5 s including the failed common_fit_params retry), so a basis mismatch is a load-time error rather than a silent quality regression.

### The longer KLD rung is inconclusive at n=2

| configuration | mean KLD | mean PPL |
| --- | ---: | ---: |
| q4_0 KV, no bias | 0.001559 +/- 0.000049 | 9.4716 |
| q4_0 KV + rotated-basis bias | 0.001685 +/- 0.000159 | 9.4779 |

The F16 reference on the same two windows measured PPL 9.4456 +/- 0.3937.

Two chunks of 4096 tokens are not enough to resolve a difference of this size: the intervals overlap and the sign is opposite to the 12x512 rung above. The reference-logits file costs 2 bytes per (token, vocabulary entry) and is written for every scored token: here it measured 1.52 GB for the 12x512 rung and 2.03 GB for the 2x4096 rung (~248 KB per scored token), and llama-perplexity keeps the window's float logits (4 bytes) in host RAM at the same time. Extending the 4096 rung to the 12 chunks used upstream would need ~12 GB of reference file and ~24 GB of RAM; a 32K window would need ~8 GB per chunk. Treat the 12x512 rung as the number that matches upstream's protocol, and section C as the measurement that covers the regime where a 4-bit cache actually matters.

## B. Perplexity (20 x 4096-token chunks)

Held-out corpus: 350 KB of the WikiText-2 raw test split (SHA256 `4b78e05ec1830a0a58caab5fddd17e0fb0edddf310c2cac2f85fb2aa8c0a3487`), 20 chunks at `-c 4096`, `-b 512 -ub 512 -ngl 99 -fa on`. Unlike the KLD runs this needs no reference-logits file, so the whole corpus is evaluated in one pass, which makes the error bars small enough to compare.

| configuration | PPL | vs F16 |
| --- | ---: | ---: |
| F16 KV | 7.2761 +/- 0.0916 | - |
| `q4_0` KV, no bias | 7.2881 +/- 0.0918 | +0.16% |
| `q4_0` KV + rotated-basis bias | 7.2811 +/- 0.0916 | +0.07% |

The chunk-to-chunk standard error (about +/-0.09) is larger than either delta, so this table should
be read as "the 4-bit cache does not visibly damage perplexity on ordinary text, and the bias does
not make it worse" rather than as a precise ranking. The KLD measurement in section A is the one
with enough resolution to separate the arms.

## C. Long-context retrieval (multi-needle, one haystack per length)

`llama-server` plus its OpenAI-compatible endpoint (`-np 1 --jinja --reasoning off`). One haystack per length contains 8 unique "vault access code" facts at evenly spaced depths; the model is asked once to list every code (a single full prefill) and then 8 times for one specific vault. All questions share the identical haystack prefix, so only the first request pays the prefill, and the harness records `prompt_n` for every request to prove the later ones reused the cache instead of silently re-prefilling - they evaluate ~515 tokens each, 2-6 s per question.

The 250K rung appends a 500 kB slice of the train split to the test file (the test file alone is ~245K tokens); the two files are byte-identical up to that point. Greedy decoding, 64-token answers.

| arm | haystack tokens | codes in one reply | single-fact hits | mean answer logprob | first-token logprob | prefill t/s | decode t/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| F16 KV, 32K | 30,000 | 8/8 | 8/8 | -0.0045 | -0.0167 | 576.5 | 23.0 |
| `q4_0`, 32K, no bias | 30,000 | 8/8 | 8/8 | -0.0038 | -0.0168 | 625.6 | 22.0 |
| `q4_0` + bias, 32K | 30,000 | 8/8 | 8/8 | -0.0042 | -0.0174 | 606.8 | 21.5 |
| `q4_0`, 128K, no bias | 122,000 | 8/8 | 8/8 | -0.0043 | -0.0261 | 327.4 | 15.8 |
| `q4_0` + bias, 128K | 122,000 | 8/8 | 8/8 | -0.0043 | -0.0270 | 367.5 | 15.4 |
| `q4_0`, 250K, no bias | 250,000 | 7/8 | 8/8 | -0.0450 | -0.0343 | 246.4 | 10.3 |
| `q4_0` + bias, 250K | 250,000 | 7/8 | 8/8 | -0.0435 | -0.0376 | 233.1 | 10.3 |

`prefill t/s` is llama-server's own timing for the full 30,220 / 122,220 / 250,220-token prompt;
`decode t/s` is the median of the eight single-fact answers. `first-token logprob` is the mean log
probability of the first answer token averaged over those eight answers (log scale, so -0.0167 is
~98.3% probability and -0.0343 is ~96.6%); `mean answer logprob` is the mean over all answer tokens
of the "list them all" reply.

What this shows:

- **Retrieval pass/fail does not separate the two KV formats** at 32K or 128K: every arm answers
  every question correctly. At 250K both arms answer all eight individual questions correctly but
  drop one code from the single "list them all" reply, so the long-context failure mode here is
  attention budget on a 200-token enumeration, not lost facts.
- **Answer confidence is driven by context length, not by the KV format.** The first-token logprob
  moves from ~-0.017 at 32K to ~-0.026 at 128K to ~-0.034/-0.038 at 250K, and the 4-bit cache with
  and without the bias land within run-to-run noise of each other at every length.
- **Throughput shows no systematic effect from the bias** (it is one subtract on cache write):
  prefill lands at 577-626 t/s at 32K, 327-368 t/s at 128K and 233-246 t/s at 250K across the arms,
  with the bias faster at 128K and slower at 250K - single-run variance, not a trend. Decode is
  21-23 t/s at 32K, ~15.5 t/s at 128K and 10.3 t/s with and without the bias at 250K. The 250K
  prefill/decode also line up with the parent report's independent long-context row (252.6 t/s
  prefill, 11.2 t/s decode).

The honest summary of section C is a negative result: on this model and card, the `q4_0` K/V cache
does not measurably damage long-context retrieval, and the calibrated bias neither helps nor hurts
there. The bias's measurable benefit is in the short-window logit KLD of section A.

## Reproducer commands

```bash
# 1) calibrate the bias in the basis you will serve with (the rotation is active for a quantized K cache)
./bin/cuda/llama-kv-mean-center -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -f calib.txt -o models/bonsai2-gguf/27B/Bonsai-2-27B-kv-mean-center-rot.gguf \
    -ngl 99 -c 512 -ctk q4_0 -fa on

# 2) reference logits with an F16 cache, then the two candidate runs
./bin/cuda/llama-perplexity -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -f heldout.txt -c 512 -b 512 -ub 512 -ngl 99 -fa on -ctk f16 -ctv f16 \
    --chunks 12 --save-all-logits base-f16.dat

./bin/cuda/llama-perplexity -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -f heldout.txt -c 512 -b 512 -ub 512 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 --chunks 12 \
    --kl-divergence --kl-divergence-base base-f16.dat

./bin/cuda/llama-perplexity -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -f heldout.txt -c 512 -b 512 -ub 512 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 --chunks 12 \
    --kv-mean-center models/bonsai2-gguf/27B/Bonsai-2-27B-kv-mean-center-rot.gguf \
    --kl-divergence --kl-divergence-base base-f16.dat

# 3) perplexity over the whole held-out corpus (no reference file needed)
./bin/cuda/llama-perplexity -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -f wiki.test.raw -c 4096 -b 512 -ub 512 -ngl 99 -fa on -ctk q4_0 -ctv q4_0

# 4) long context: serve with and without the bias against the same haystack
./bin/cuda/llama-server -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -ngl 99 -c 262144 -b 2048 -ub 512 -ctk q4_0 -ctv q4_0 -fa on -np 1 --jinja --reasoning off
#   add --kv-mean-center models/bonsai2-gguf/27B/Bonsai-2-27B-kv-mean-center-rot.gguf for the biased arm
```

## Notes and limitations

- The calibration corpus was ~500 KB of mixed text (this repository's documentation, local working notes and a few C++ sources) run as 289 chunks at `-c 512`. KV-CACHE.md notes that the per-channel K mean is dominated by model-intrinsic structure rather than corpus content, so the exact corpus matters less than the basis, but it is not a standard academic calibration set either.
- KLD is only measurable at short windows on this model (see above); the retrieval probe is the long-context substitute.
- Retrieval pass/fail saturates at 32K, so the 32K row is a regression check rather than a discriminating measurement. The per-question answer logprob is reported alongside as a softer signal.
- There is no F16 arm at 250K: an F16 KV cache needs ~15.6 GB for the cache alone against this card's 16 GB, which is exactly the situation the `q4_0` cache exists for.
- All runs are fully on-GPU (`-ngl 99`) with flash attention on, the service stopped, and ~1.3-2 GB of VRAM held by desktop applications (this machine's normal state).
- The retrieval harness is a small local script: it plants the eight `vault <name>: <code>` sentences
  in the haystack text, then sends one OpenAI-compatible chat request per question ("list every access
  code" with a 200-token budget, then "what is the access code for vault <name>?" with 64 tokens) and
  scores the replies by exact substring match. Its per-request timings are what the two throughput
  columns above report.
- Every arm was measured once, serially, with the serving llama-server stopped. One early 32K no-bias
  pass was disturbed by a concurrent process on the GPU (prefill 185 s instead of ~50 s) and is not
  used - the table reports its clean re-measurement.

## Hardware

See [cuda-tesla-v100-windows.md](cuda-tesla-v100-windows.md) for the full `Win32_*` output. Same machine: Tesla V100-SXM2-16GB (16384 MiB, 300 W, ECC on, P0), Xeon E5-2682 v4, 64 GB, Windows 11 Pro for Workstations 10.0.26200, NVIDIA driver 581.15.
