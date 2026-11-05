# NVIDIA DGX Spark (GB10) — CUDA — Ternary-Bonsai-2-27B

## Summary

NVIDIA DGX Spark with GB10 GPU (128 GB unified LPDDR5X memory), CUDA 13.0 on DGX OS (Ubuntu 24.04, aarch64). Ternary-Bonsai-2-27B `PQ2_0` reaches **27.79 t/s tg128** and **919.05 t/s pp512**. The `PTQ1_0` variant measures **32.83 t/s tg128** and **432.59 t/s pp512**. Plain decode speed is flat from 64 to 2,000 generated tokens (29.7-29.9 t/s on an idle GPU).

With the DSpark v2 drafter (`Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf`, a DSpark drafter trained for this target; exact-match verification, `--spec-draft-n-max 5`), single-prompt generation in `llama-speculative-simple` with a 2,000-token budget reaches a mean of **64.4 t/s over six prompts (2.16x)** and **71.8 t/s on math (2.41x)**. The llama-server workload matrix compares DSpark v2 and DSpark v1 (the Ternary-Bonsai-27B drafter, re-converted for this target) against the same server with no drafter. It covers 62 prompts. The two drafters tie on the blended 40-prompt set: **57.4 t/s (1.93x)** for DSpark v2 against **57.7 t/s (1.94x)** for DSpark v1. Both reach 2.52x on math; DSpark v2 reaches 2.22x on code. DSpark v2 leads on code (+4%) and on the 2,000-token long-form set (+2%) with more tokens per step. DSpark v1 leads on reasoning (+5%), tool calls (+17%) and agent turns (+14%). The DSpark v2 training data holds no tool-call turns. DSpark v2 is the drafter that this entry reproduces from an open recipe, with the better code and long-form profile. It is not the faster drafter. For context, the [Ternary-Bonsai-27B entry](cuda-gb10-27b-linux.md) on the same hardware reports 70.0 t/s (2.45x) for the older model with its own drafter on one 512-token code prompt.

Both drafters need a runtime fix. No released binary runs any drafter on this target without it: the released runtime accepts 0.4-2.0% of drafted tokens and gives no warning. See Configuration.

## llama-bench Results

```bash
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa on -r 3
```

| model | size | params | backend | ngl | fa | test | t/s |
| --- | ---: | ---: | --- | --: | --: | ---: | ---: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 919.05 ± 57.64 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 27.79 ± 0.71 |

build: 5d80cff0b (10687)

Decode speed does not fall with output length. On a second DGX Spark with an idle GPU, the same binary gives **tg64 29.68**, **tg1024 29.93**, and **tg2000 29.77 t/s**:

```bash
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa on -p 0 -n 64,1024,2000
```

The single-prompt DSpark speedups below use this 29.8 t/s figure as the no-drafter baseline.

## PTQ1_0 Results

```bash
# setup.sh downloads only the PQ2_0 file; fetch the PTQ1_0 file by hand
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-PTQ1_0.gguf --local-dir models/bonsai2-gguf/27B
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa on -r 3
```

| model | size | params | backend | ngl | fa | test | t/s |
| --- | ---: | ---: | --- | --: | --: | ---: | ---: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | pp512 | 432.59 ± 6.92 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA | 99 | 1 | tg128 | 32.83 ± 1.10 |

build: 5d80cff0b (10687)

`PTQ1_0` decodes 18% faster than `PQ2_0` and processes prompts at half the speed. In our sweeps it was also slower than `PQ2_0` under speculative decoding at every draft length, because the batched verify pass runs at prompt-processing speed. All DSpark numbers below use `PQ2_0`.

## DSpark Results

Three llama-server configurations ran with `-ngl 99 -fa on -c 16384 -np 1 --jinja`: no drafter, DSpark v2, and DSpark v1. The drafter flags:

```bash
# DSpark v2: trained for Ternary-Bonsai-2-27B (5 draft layers, block size 7, run at n-max 5)
-md models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf --spec-type draft-dspark --spec-draft-n-max 5 -ngld 999
# DSpark v1: the Ternary-Bonsai-27B drafter, re-converted for this target (6 draft layers, block size 4)
-md models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-Q4_0.gguf --spec-type draft-dspark --spec-draft-n-max 4 -ngld 999
```

PrismML ships no drafter for Bonsai 2: `scripts/download_models.sh` fetches none for this family, and the Bonsai 2 GGUF repositories hold none. The DSpark v1 file is the Ternary-Bonsai-27B drafter (`Ternary-Bonsai-27B-dspark-bf16.gguf`, trained for the older model), re-converted against the Bonsai 2 `PQ2_0` target with `gguf_dspark_to_dflash.py --drop-shared-tensors` and quantized to `Q4_0`. It borrows the token embedding and the output head from the Bonsai 2 target. With the runtime fix, it transfers to this target. Its GGUF header keeps `general.name = Bonsai-27B-dspark`, `dflash.target_layers = [2, 17, 32, 47, 62]` and block size 4. Its rows show a cross-generation drafter for comparison, and the tables label it "DSpark v1 (Ternary-Bonsai-27B drafter, K=4)". `--spec-draft-n-max 5` clamps to its block size 4 with a warning, so the n-max 4 numbers stand for both settings.

Notes for `BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh`:

- The launcher takes the first `*dspark-dflash*.gguf` in the model directory in glob order. `...-dspark-dflash-Q4_0.gguf` sorts before `...-dspark-dflash-v2-Q4_K_M.gguf`, so with both files present the launcher picks DSpark v1. Keep one drafter in the directory, or pass `-md` directly.
- The launcher reads the draft length from the GGUF key `dspark.dspark.block_size` (`bonsai_dspark_block_size` in `scripts/common.sh`). A converted file carries `dflash.block_size` instead, so the launcher falls back to n-max 4. Set `BONSAI_SPEC_NMAX=5` for DSpark v2 (the central environment reference still lists this variable as PowerShell-only; the Linux launcher reads it too). `scripts/common.sh` and [SPECULATIVE.md](../../SPECULATIVE.md) state that n-max must equal the block size and that a smaller value crashes; that rule reflects an earlier runtime. On prism `1a07bfa5f` plus the fix, DSpark v2 (block size 7) ran at n-max 5 through the whole benchmark. Every draft round drafted 5 tokens, and no run crashed. An n-max above the block size is clamped to the block size with a warning. n-max 5 gave the best rate for DSpark v2 in our sweeps.

Three passes sent the same prompt to `POST /completion` in the ChatML template, at temperature 0 and seed 42, with a 256-token budget. The prompt: "Implement quicksort in Python with type hints, tests, and a concise complexity explanation".

| Mode | Pass 1 | Pass 2 | Pass 3 | Mean | Speedup | Draft acceptance |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| No drafter | 29.7 | 29.6 | 29.5 | 29.6 t/s | 1.00x | n/a |
| DSpark v1 (Ternary-Bonsai-27B drafter, K=4) | 51.2 | 51.2 | 51.3 | 51.2 t/s | 1.73x | 40.7% |
| DSpark v2 | 52.1 | 52.0 | 51.9 | 52.0 t/s | 1.76x | 39.6% |

### Single-prompt runs with llama-speculative-simple

These are bare-loop numbers, not server numbers. They read higher than the server tables on the same hardware (see the harness note in the [index](../README.md)). DSpark v2, `PQ2_0` target, exact-match verification, `--spec-draft-n-max 5`, temperature 0, idle GPU. Acceptance is accepted/drafted tokens. The speedup is the rate divided by the 29.8 t/s llama-bench baseline above.

```bash
LD_LIBRARY_PATH="$PWD/bin/cuda" bin/cuda/llama-speculative-simple -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -md models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf --spec-type draft-dspark --spec-draft-n-max 5 --spec-draft-p-min 0 -fa on -ngl 99 -ngld 999 -c 4096 -n 200 --temp 0 -e -p "<|im_start|>user\n<prompt><|im_end|>\n<|im_start|>assistant\n"
```

200-token budget (`-n 200`):

| prompt | + DSpark v2 | accept | speedup |
| --- | ---: | ---: | ---: |
| math (two trains) | 61.5 | 0.521 (148/284) | **2.06x** |
| code (CSV parser) | 53.9 | 0.429 (137/319) | **1.81x** |
| code (binary search) | 59.8 | 0.495 (143/289) | **2.01x** |

2,000-token budget (`-n 2000`), six prompts:

| prompt | generated | + DSpark v2 | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| CSV parser with tests | 1,477 | 60.8 | 0.492 (1050/2135) | **2.04x** |
| LRU cache | 2,006 | 59.7 | 0.483 (1418/2936) | **2.00x** |
| log file, top 10 IPs | 2,005 | 68.9 | 0.589 (1497/2540) | **2.31x** |
| Dijkstra | 2,006 | 66.7 | 0.569 (1484/2606) | **2.24x** |
| email validator | 2,004 | 58.8 | 0.475 (1410/2970) | **1.97x** |
| math (two trains) | 1,451 | 71.8 | 0.627 (1100/1755) | **2.41x** |
| mean over 6 | | 64.4 | 0.533 (7959/14942) | **2.16x** |

The prompts, in table order:

1. Write a Python function that parses a CSV file of transactions (date, amount, category) and returns the total spent per category as a dict, with error handling for malformed rows and a small unit test. Put all code in one ```python block that runs the tests when executed.
2. Implement an LRU cache class in Python with get/put in O(1), a docstring, and unit tests that run when the file is executed.
3. Write a Python script that reads a log file, counts requests per IP, prints the top 10, and includes tests with a temporary file.
4. Implement Dijkstra's shortest path in Python over an adjacency dict, with a small graph example and assert-based tests.
5. Write a Python function to validate and normalize email addresses, with edge cases and unit tests.
6. A train leaves city A at 9:00 traveling 80 km/h toward city B, 300 km away. A second train leaves B at 9:30 traveling 100 km/h toward A. At what time and where do they meet? Show your reasoning step by step.

The 200-token set uses prompt 6, prompt 1 without its last sentence, and "Implement binary search in Python with type hints, a docstring, and three assert-based tests."

## Detailed DSpark workload matrix

A broader deployed-server comparison used 62 prompts on the same single-slot servers as above:

- 40 matrix prompts, eight each for code, math, reasoning, chat and long-form, with a 512-token budget. The client wraps each prompt in the ChatML template with no system message and sends it to `POST /completion`.
- 8 tool prompts with a 512-token budget. Each request carries four tool definitions and asks for one tool call. These go to `POST /v1/chat/completions` with the server's own template.
- 8 agent turns with a 512-token budget. Each request carries a shared coding-agent system prompt, one task, one prior tool call with its result, and four tool definitions. These also go to `POST /v1/chat/completions`.
- The six long-form prompts listed above with a 2,000-token budget, through `POST /completion`.

Every request used temperature 0, seed 42, and `cache_prompt: false`. One unrecorded warm-up request ran per configuration. Rates are arithmetic means of the server decode-only `predicted_per_second`; acceptance is aggregated `draft_n_accepted / draft_n` from the response `timings` object; the speedup is the drafter mean divided by the no-drafter mean for the same prompts. Bonsai 2 thinks before it answers, so most of a 512-token budget is reasoning text. The blended row covers the 40 matrix prompts.

DSpark v1 (Ternary-Bonsai-27B drafter, K=4):

| workload | no drafter | + DSpark v1 | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| code | 29.7 | 62.9 | 55.2% | **2.12x** |
| math | 29.7 | 74.7 | 71.5% | **2.52x** |
| reasoning | 29.7 | 60.9 | 51.5% | **2.05x** |
| chat | 29.7 | 44.4 | 29.8% | **1.50x** |
| long-form (8 prompts, 512 tokens) | 29.7 | 45.5 | 32.8% | **1.53x** |
| tool (8 prompts, one tool call each) | 29.5 | 58.2 | 45.7% | **1.97x** |
| agent (8 turns) | 28.8 | 53.3 | 51.9% | **1.85x** |
| blended (40 matrix prompts) | 29.7 | 57.7 | 45.2% | **1.94x** |
| long-form (6 prompts, 2,000 tokens) | 29.5 | 65.2 | 58.7% | **2.21x** |

DSpark v2, n-max 5:

| workload | no drafter | + DSpark v2 | accept | speedup |
| --- | ---: | ---: | ---: | ---: |
| code | 29.7 | 65.7 | 54.8% | **2.22x** |
| math | 29.7 | 74.7 | 65.9% | **2.52x** |
| reasoning | 29.7 | 57.8 | 44.5% | **1.95x** |
| chat | 29.7 | 44.8 | 29.8% | **1.51x** |
| long-form (8 prompts, 512 tokens) | 29.7 | 43.9 | 29.5% | **1.48x** |
| tool (8 prompts, one tool call each) | 29.5 | 49.6 | 37.3% | **1.68x** |
| agent (8 turns) | 28.8 | 46.6 | 40.8% | **1.62x** |
| blended (40 matrix prompts) | 29.7 | 57.4 | 42.0% | **1.93x** |
| long-form (6 prompts, 2,000 tokens) | 29.5 | 66.8 | 57.0% | **2.26x** |

The speedup in every row is the drafter rate divided by the no-drafter rate for the same prompts on the same server.

Verdict. The two drafters tie on the blended 40-prompt set: 57.4 t/s for DSpark v2 against 57.7 t/s for DSpark v1. DSpark v2 leads on code (+4%, 65.7 against 62.9) and on the 2,000-token long-form set (+2%, 66.8 against 65.2). Its block holds seven positions and runs at n-max 5, so it advances more tokens per verify step. Tokens per step: 3.71 against 3.19 on code, 3.85 against 3.34 on the 2,000-token set, 3.08 against 2.79 blended. DSpark v1 leads on reasoning (+5%, 60.9 against 57.8), tool calls (+17%, 58.2 against 49.6) and agent turns (+14%, 53.3 against 46.6). The DSpark v2 training data holds no tool-call turns, and the tool and agent rows show that gap. Tokens per step is generated tokens divided by verify steps, `predicted_n / (predicted_n - draft_n_accepted)`; a server with no drafter is at 1.00.

Tool calls. A tool answer is valid when it holds at least one well-formed call: a name from the tools list and a JSON object of arguments. Every configuration, the no-drafter server included, gave 6 valid calls out of 8, and each valid call named the tool that the prompt asked for. The other two prompts hit the 512-token budget inside the reasoning block on every configuration (`finish_reason: length`). The drafter does not change tool-call validity. The tool and agent requests go through the server's chat template, which injects its default reasoning effort (`xhigh` on Bonsai 2). The matrix rows use plain ChatML with no system message. The two request types are not like for like, so compare the tool and agent rows with each other and not with the matrix rows.

## Multi-slot

All three servers ran with `-np 1`, `-np 2` and `-np 4`, with the other flags unchanged. Each run sends the same 8 prompts, two each of code, reasoning, chat and tool. The prompts go out in waves of one concurrent request per slot. "Per stream" is the mean `predicted_per_second` that one request saw. "Aggregate" is the total of generated tokens divided by the wall time of all waves, prefill included. Acceptance is the DSpark v2 server's aggregated `draft_n_accepted / draft_n`. The speedup is the DSpark v2 per-stream rate divided by the no-drafter per-stream rate at the same slot count. On the aggregate rate it is 1.83x, 1.45x and 1.31x.

| slots | no drafter, per stream | no drafter, aggregate | + DSpark v2, per stream | + DSpark v2, aggregate | accept | speedup |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 29.7 | 28.8 | 58.3 | 52.6 | 47.7% | **1.96x** |
| 2 | 25.3 | 45.7 | 40.3 | 66.3 | 48.5% | **1.59x** |
| 4 | 20.3 | 56.9 | 30.1 | 74.4 | 47.2% | **1.48x** |

Neither drafter refused a request at 2 or 4 slots. The DSpark v1 server ran the same way. It gave 62.4 / 53.5 t/s (per stream / aggregate) at 1 slot, 43.2 / 67.2 at 2 slots and 31.7 / 74.8 at 4 slots. Its acceptance was 52.2%, 53.3% and 51.8%. The 1-slot row uses the same 8 prompts from the single-slot run.

## Power

Power readings come from `nvidia-smi --query-gpu=power.draw`, sampled at 1 Hz by a background thread on node 2 while the server ran. "Idle" is the mean reading over 10 s with the model loaded and no request in flight. Across the nine server runs it was 14.5-16.3 W. "Mean W" is the mean reading during the generation phase of the single-slot run. Energy per generated token is mean W divided by generated tokens per wall second of that phase, prefill included, times 1,000, in millijoules.

| configuration | mean W | mJ per generated token |
| --- | ---: | ---: |
| idle, model loaded | 14.5 | n/a |
| no drafter | 60.9 | 2135 |
| + DSpark v2 | 78.1 | 1495 |

DSpark v2 draws 28% more power than the no-drafter server and uses 30% less energy per generated token. DSpark v1 measured 77.0 W and 1,458 mJ per token. At 4 slots the no-drafter server measured 1,150 mJ per token and DSpark v2 823 mJ per token (DSpark v1: 788).

## Exactness

Both drafters run with exact-match verification. The server accepts a drafted token only when it equals the token the target picks at temperature 0 from the batched verify logits. The drafter changes the speed, not the sampling rule. We measured exactness on all 65 outputs of the single-slot runs (62 prompts, with three passes of the quicksort prompt). For each output we compared the drafter output with the no-drafter output for the same prompt and pass, both at temperature 0 and seed 42. A `/completion` output is identical when its token id sequence equals the no-drafter sequence. A chat output (reasoning, answer, tool calls) is compared as text, because that endpoint returns no token ids. Result: 37 of 65 outputs are identical for DSpark v1, and 37 of 65 for DSpark v2. The 28 outputs that differ are the same 28 for both drafters. The first difference is at the same 0-based position for both. Examples: reasoning-06 at token 1, long-form-03 at token 9, code-06 at token 59, math-01 at token 255 and tool-05 at character 1773. Two different drafters do not produce the same 28 divergence points if the draft causes them. The position depends on the prompt, not on the draft. The cause is the verify pass. It scores several positions in one batch, and the batched kernels round differently from single-row decode. At a near-tie token the argmax flips. Given the batched logits, acceptance is exact. The no-drafter server gives identical output across repeated passes. So this entry does not claim byte-identical output. Speculative decoding on this runtime is exact given the batched logits, and identical to plain greedy decoding on 37 of 65 outputs here. The 200-token probes in Configuration reproduce count for count and byte for byte across the two patched builds. That is a different claim: the same fix on two binaries on the same code path, not drafter output against a plain run.

## How the DSpark v2 drafter was trained

DSpark v2 is a DSpark drafter trained for this target. It uses the standard `dflash` runtime path; the only runtime change is the fix in Configuration, which both drafters need.

- Teacher: the LM head and the token embedding were dequantized from the `PQ2_0` target with the Hadamard fold applied. The dequantized head reproduces the logits of `llama.cpp` on the validation set (100% argmax match, top-1 values within 0.06%).
- Objective: the DSpark block-parallel objective. Next-token cross-entropy through the borrowed LM head, an L1 match to the target's token distribution, and a confidence-head loss.
- Data: self-distilled. The target answered 3,401 prompts (code, math, reasoning, chat, long-form) at temperature 0 through `llama-server`; the drafter trains on the target's hidden states and the target's own tokens. The data holds no tool-call turns.
- Checkpoint: warm start from the Qwen3.8-27B DSpark drafter weights (5 draft layers, block size 7), one pass over the data, checkpoint at step 600 of 1,701. The step 900 checkpoint gave the same acceptance counts. Converted to the `dflash` GGUF layout and quantized to `Q4_K_M` (1.03 GiB). The file carries no token embedding and no output head; it borrows both from the target. The GGUF header keeps `general.name = Qwen3.8-27B-DSpark` from the warm-start checkpoint. The DSpark v1 file is 0.59 GiB at `Q4_0`.

## Configuration

- All layers offloaded; flash attention enabled; one server slot unless the Multi-slot section says otherwise; the server applied the model's chat template (`--jinja`)
- llama-bench: PrismML-Eng/llama.cpp `prism` commit `5d80cff0b` (build 10687), built for CUDA architecture `121a`
- DSpark runs: PrismML-Eng/llama.cpp `prism` commit `1a07bfa5f` (build 10706) plus the fix of [PrismML-Eng/llama.cpp#210](https://github.com/PrismML-Eng/llama.cpp/pull/210) ("dflash: apply the target's Hadamard transforms to borrowed embeddings and head", branch `fix/dflash-borrowed-hadamard`, commit `288859a96`), same build flags. `--version` prints `build 10706, commit 1a07bfa5f` for clean and patched binaries alike, so tell them apart by path. The patched build reproduces the acceptance counts and the output text of every 200-token probe above bit for bit (148/284, 137/319, 143/289). This compares the same fix on two builds on the same code path. It is not a claim that drafter output equals no-drafter output (see Exactness). The bare-loop speeds were recorded on build 10687 with an earlier form of the same fix.
- Why the fix: both drafters borrow the token embedding and the output head from the target, and the `PQ2_0` target stores both in the Hadamard-rotated basis. Without the fix the draft graph skips the transforms. Clean `1a07bfa5f` and the release tag `prism-b10683-d8f26ee` that `setup.sh` installs give 0.4-2.0% acceptance for any borrowed-embedding drafter on this target, with no error and no warning. Exact-match verification keeps the output correct, so only the acceptance counter and the speed show the defect. Build from source with the fix.
- Measured acceptance, `llama-speculative-simple`, 200 tokens, temperature 0, the three prompts of the 200-token table, clean `1a07bfa5f` against `1a07bfa5f` plus the fix:

| drafter | n-max | prompt | clean `1a07bfa5f` | `1a07bfa5f` + fix |
| --- | ---: | --- | ---: | ---: |
| DSpark v2 | 5 | math | 1.6% (15/924) | 52.1% (148/284) |
| DSpark v2 | 5 | code (CSV parser) | 0.4% (4/978) | 42.9% (137/319) |
| DSpark v2 | 5 | code (binary search) | 1.2% (11/940) | 49.5% (143/289) |
| DSpark v1 (Ternary-Bonsai-27B drafter, K=4) | 4 | math | 2.0% (15/741) | 56.0% (140/250) |
| DSpark v1 (Ternary-Bonsai-27B drafter, K=4) | 4 | code (CSV parser) | 0.9% (7/772) | 46.4% (130/280) |
| DSpark v1 (Ternary-Bonsai-27B drafter, K=4) | 4 | code (binary search) | 1.7% (13/746) | 56.6% (142/251) |

- NVIDIA driver 580.178.04; CUDA toolkit 13.0.88
- Two DGX Spark nodes with the same image; llama-bench ran on node 1, the DSpark runs on node 2 with an idle GPU. Runs that overlapped other GPU work were discarded.

## Reproduction

Run these commands from the demo checkout after `BONSAI_FAMILY=bonsai2 BONSAI_MODEL=27B ./setup.sh`. The setup installs release binaries without the fix, so step 2 builds the runtime from source. The download location of the DSpark v2 file is not published yet; replace `<HF-REPO>` when it is.

```bash
# 1. drafter (1.03 GiB); keep it as the only *dspark-dflash*.gguf in the directory (see the launcher notes)
hf download <HF-REPO> Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf --local-dir models/bonsai2-gguf/27B

# 2. runtime: prism 1a07bfa5f plus the fix of PR #210, CUDA build for the GB10
git clone https://github.com/PrismML-Eng/llama.cpp.git
git -C llama.cpp fetch https://github.com/usmaneth/llama.cpp fix/dflash-borrowed-hadamard
git -C llama.cpp checkout 288859a96   # prism 1a07bfa5f plus the fix of PR #210; use the merge commit once the PR lands
cmake -S llama.cpp -B llama.cpp/build-cuda -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=121a \
  -DGGML_CUDA_FA=ON -DGGML_NATIVE=ON -DCMAKE_BUILD_TYPE=Release
cmake --build llama.cpp/build-cuda -j 18 --target llama-speculative-simple llama-server llama-bench
export LD_LIBRARY_PATH=$PWD/llama.cpp/build-cuda/bin

# 3. acceptance check, temperature 0, 200 tokens (the "math" row of the 200-token table)
llama.cpp/build-cuda/bin/llama-speculative-simple \
  -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  -md models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf \
  --spec-type draft-dspark --spec-draft-n-max 5 --spec-draft-p-min 0 \
  -fa on -ngl 99 -ngld 999 -c 4096 -n 200 --temp 0 -e \
  -p '<|im_start|>user\nA train leaves city A at 9:00 traveling 80 km/h toward city B, 300 km away. A second train leaves B at 9:30 traveling 100 km/h toward A. At what time and where do they meet? Show your reasoning step by step.<|im_end|>\n<|im_start|>assistant\n'
# expect in the log: n_drafted = 284, n_accept = 148, accept = 52.113%

# 4. server with the flags the benchmark used
llama.cpp/build-cuda/bin/llama-server \
  -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  -md models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf \
  --spec-type draft-dspark --spec-draft-n-max 5 \
  -ngl 99 -ngld 999 -fa on -c 16384 -np 1 --jinja \
  --host 127.0.0.1 --port 8080

# 5. one matrix-style request; the response "timings" object carries draft_n and draft_n_accepted
curl -s http://127.0.0.1:8080/completion -H 'Content-Type: application/json' -d '{
  "prompt": "<|im_start|>user\nImplement binary search in Python with type hints, a docstring, and three assert-based tests.<|im_end|>\n<|im_start|>assistant\n",
  "n_predict": 512, "temperature": 0, "seed": 42, "cache_prompt": false
}' | python3 -c 'import sys, json; t = json.load(sys.stdin)["timings"]; print("accepted", t["draft_n_accepted"], "of", t["draft_n"], "drafted;", round(t["predicted_per_second"], 1), "tok/s")'
```

Acceptance for a server run is `timings.draft_n_accepted / timings.draft_n` from the `/completion` response; `/v1/chat/completions` carries the same object. The server puts these counters in the response only when a drafter is loaded. Through the chat template (`--jinja`) the model thinks first, so a short `max_tokens` ends inside the reasoning block with `finish_reason: length`.

To run through the demo launcher instead of step 4, copy the patched binaries over the release ones and set the draft length by hand:

```bash
mkdir -p bin/cuda   # the setup installs CPU binaries on aarch64, so this directory may not exist
cp llama.cpp/build-cuda/bin/llama-server llama.cpp/build-cuda/bin/llama-speculative-simple \
   llama.cpp/build-cuda/bin/llama-bench llama.cpp/build-cuda/bin/*.so* bin/cuda/
LD_LIBRARY_PATH=bin/cuda bin/cuda/llama-server --version      # expect commit 1a07bfa5f
BONSAI_SPECULATIVE=1 BONSAI_SPEC_NMAX=5 ./scripts/start_llama_server.sh
```

To rebuild the DSpark v1 file for the comparison rows:

```bash
BONSAI_FAMILY=ternary BONSAI_MODEL=27B ./scripts/download_models.sh   # fetches Ternary-Bonsai-27B-dspark-bf16.gguf
python3 llama.cpp/gguf-py/gguf/scripts/gguf_dspark_to_dflash.py --drop-shared-tensors \
  models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-bf16.gguf \
  models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  Ternary-Bonsai-2-27B-dspark-conv.gguf
llama.cpp/build-cuda/bin/llama-quantize Ternary-Bonsai-2-27B-dspark-conv.gguf \
  models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-Q4_0.gguf Q4_0
```

## Hardware

```text
Architecture: aarch64
CPU(s): 20 (10 Cortex-X925 / 10 Cortex-A725)
Mem: 121 GiB unified LPDDR5X
OS: Ubuntu 24.04 LTS (DGX OS, kernel 7.0.0-1019-nvidia)
GPU: NVIDIA GB10 (compute capability 12.1)
```
