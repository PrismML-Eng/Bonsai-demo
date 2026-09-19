# DSpark drafter retraining pipeline

This directory holds the pipeline that trained the DSpark v2 drafter for Bonsai 2 27B:
`Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf`. The drafter gives 1.9x blended and
2.2-2.5x on code and math on a GB10 at temperature 0 (see
[SPECULATIVE.md](../../SPECULATIVE.md) for how the demo uses a drafter, and the
GB10 benchmark entry in `community-benchmarks/ternary-bonsai/` for the full table).

The pipeline is self-distillation: the target model writes its own greedy completions, the
same model is teacher-forced over them to record hidden states, and the drafter learns to
predict the next block of tokens from those states. Everything runs on one machine.

## Files

| File | Role |
|------|------|
| `build.sh` | Builds the three C++ tools against `llama.cpp/` and `bin/cuda/`. |
| `teacher_dump.cpp` | Dequantizes the target LM head and token embedding into `teacher/W_lm.bin` and `teacher/tok_embd.bin`. |
| `validate_wlm.cpp` | Validation gate: recomputes logits from `W_lm.bin` and compares them with the runtime. |
| `build_prompts_broad.py` | Assembles the broad-mix prompt set (math, reasoning, chat, code, long-form). |
| `gen_client.py` | Concurrent client for `llama-server`: writes greedy completions as token ids. |
| `extract_feats_tf.cpp` | Teacher-forced feature extraction into the `BON2` format. |
| `train_dspark_v2.py` | The trainer (block-parallel DSpark objective). |
| `convert_safetensors_to_dspark.py` | Step 1 of the GGUF conversion (safetensors to raw `dspark` GGUF). |
| `run_full_pipeline.sh` | Train, convert (two steps), quantize to Q4_K_M, sanity check. |
| `eval/spec_eval.sh` | Speculative decoding sweep (baseline and drafter on the same prompts). |

Work products (`teacher/`, `feats/`, `logs/`, prompt files, checkpoints) stay in this
directory and are ignored by git (`.gitignore` here). The feature files alone are 193 GB.

## Requirements

- The demo set up with `./setup.sh`: the target GGUF at
  `models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf` and the CUDA binaries and
  shared libraries in `bin/cuda/`. Use PQ2_0 as the target. PTQ1_0 decodes faster alone but
  its batched verify pass is slow, so it loses under speculation at every K.
- The PrismML llama.cpp fork at `llama.cpp/` (branch `prism`, at or after
  [PR #179](https://github.com/PrismML-Eng/llama.cpp/pull/179)). The C++ tools need its
  headers and the converters need its `gguf-py`. Clone it with
  `git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git llama.cpp`.
- To run the converted drafter, the runtime also needs the fix "dflash: apply the target's
  Hadamard transforms to borrowed embeddings and head" (branch `fix/dflash-borrowed-hadamard`
  on top of `1a07bfa5f`). Without it, every drafter that borrows the target's `token_embd`
  and `output` gets 0.4-2.0% acceptance on Bonsai 2, on the release binaries as well.
- `g++` with OpenMP.
- Python 3 with `datasets` (prompt building), `torch` with CUDA, `numpy` and `safetensors`
  (training and conversion). `run_full_pipeline.sh` runs the trainer with `python3` by
  default, so the current Python environment must have a `torch` where
  `torch.cuda.is_available()` is true. We ran the trainer in a container built on a vLLM
  image for the GB10 (CUDA 13, aarch64) plus `pip install datasets`. The image is not
  public. To run the trainer in a container, set `DSPARK_TRAINER` to the docker command in
  the table below.
- The warm-start checkpoint `RadixArk/Qwen3.8-27B-DSpark` (`model.safetensors`, 3.7 GB) at
  `models/qwen38-dspark/`: `hf download RadixArk/Qwen3.8-27B-DSpark --local-dir
  models/qwen38-dspark`. The trainer accepts every tensor of that checkpoint.
- A GB10 or a CUDA GPU with 24 GB or more. Training uses 18.7 GB at batch size 2.
- Disk for features: 123 KB per token. The data set below is 1.57 M tokens, 193 GB.

Environment variables read by the scripts:

| Variable | Default | Purpose |
|----------|---------|---------|
| `BONSAI_ROOT` | the checkout that contains this directory | Base for every default path (`models/`, `bin/cuda/`, `llama.cpp/`). The C++ tools default to the current directory when it is unset, so run them from the checkout or set it. |
| `DSPARK_TRAINER` | `python3` | Command that runs `train_dspark_v2.py` in `run_full_pipeline.sh`. Example for a CUDA container: `sudo docker run --rm --gpus all -v $BONSAI_ROOT:$BONSAI_ROOT -v <feats_dir>:<feats_dir> <image> python3`. The checkout and the feats directory must be mounted at the same paths; the feats directory may live outside the checkout. |

All commands below run from the checkout root.

## Recipe

### 1. Build the tools

```bash
tools/dspark-retrain/build.sh
```

This runs, for each of the three sources:

```bash
g++ -O2 -std=c++17 -fopenmp -I llama.cpp/include -I llama.cpp/ggml/include -I llama.cpp/src \
    tools/dspark-retrain/<tool>.cpp -o tools/dspark-retrain/<tool> \
    -L bin/cuda -lllama -lggml-base -Wl,-rpath,$PWD/bin/cuda
```

`extract_feats_tf` calls `llama_set_embeddings_layer_inp` from `llama.cpp/src/llama-ext.h`,
so the `-I llama.cpp/src` include is required. `-fopenmp` parallelizes the teacher dump
and the validation matmul over the CPU cores.

### 2. Teacher dump and validation gate

The drafter borrows the target's LM head and token embedding. The runtime stores both in
the PQ2_0 latent basis and applies a block Hadamard transform with a sign vector. The dump
applies the same fold on the CPU and writes f16 matrices (`[vocab, embd]`, 2.5 GB each)
behind an 8-byte header (`vocab u32, embd u32`).

```bash
tools/dspark-retrain/teacher_dump models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf tools/dspark-retrain/teacher
tools/dspark-retrain/validate_wlm models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf tools/dspark-retrain/teacher/W_lm.bin
```

The dump checks every write. On a short write (for example a full disk) or a failed
close, it removes the partial file and exits with status 1.

`validate_wlm` runs the model on a prompt, recomputes `final_hidden @ W_lm.T`, and compares
the argmax and the top-1 logit at every position with the runtime. The gate passes when
more than 95% of the positions agree on the argmax and more than 95% of the top-1 values
agree within 1%. Measured: 22/22 positions match (100% argmax, 100% top-1 within 1%),
`GATE: PASS`. Do not train on a failed gate.

### 3. Prompts

Round 1 used the first 2,000 rows of `sahil2801/CodeAlpaca-20k`, one user message per row,
in the `{"messages": [{"role": "user", "content": ...}]}` format:

```bash
python3 - <<'PY'
import json
from datasets import load_dataset
d = load_dataset("sahil2801/CodeAlpaca-20k", split="train")
with open("tools/dspark-retrain/prompts_batch1.jsonl", "w") as f:
    for i in range(2000):
        r = d[i]
        text = r["instruction"] + ("\n" + r["input"] if r["input"] else "")
        f.write(json.dumps({"id": f"codealpaca_{i}", "messages": [{"role": "user", "content": text}]}) + "\n")
PY
```

Round 2 used the broad mix: 2,500 prompts, 25% math, 25% reasoning, 20% chat, 15% code,
15% long-form, from public data sets (GSM8K train, MATH, Open-Platypus, ARC-Challenge,
LogiQA, StrategyQA, no_robots, Dolly, UltraChat, CodeAlpaca, Evol-Instruct-Code) plus a
small template share. The set is deduplicated against the round-1 prompts.

```bash
python3 tools/dspark-retrain/build_prompts_broad.py tools/dspark-retrain/prompts_broad.jsonl \
    --total 2500 --seed 0 --dedupe tools/dspark-retrain/prompts_batch1.jsonl
```

The script writes `prompts_broad.jsonl.counts.json` with the per-source counts. A source
that fails to download is replaced by the other sources of its category, then by templates.
Every category has a template generator. When a category still falls short of its target,
the script writes no output and exits with status 1, so the corpus always holds exactly
`--total` prompts in the requested mix.

### 4. Self-distillation with llama-server continuous batching

Start the target as a server with many slots. Then run the client. The client tokenizes the
chat-templated user turn through `/tokenize`, requests a greedy completion through
`/completion` with `return_tokens`, and writes `{"tokens": prompt_ids + gen_ids,
"n_prompt": len(prompt_ids)}` per line. Prompts over 768 tokens are skipped. The client
keeps at most 2 x `workers` requests in flight and submits no further prompt once the
accepted count plus the in-flight count reaches the cap, so the server generates at most
the cap plus the skipped candidates.

Round 1 (code only, 256-token completions, 12 slots):

```bash
LD_LIBRARY_PATH=bin/cuda bin/cuda/llama-server -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -ngl 99 -fa on -np 12 -c 12288 --host 127.0.0.1 --port 8095 &
python3 tools/dspark-retrain/gen_client.py 8095 12 256 tools/dspark-retrain/prompts_gen_batch2.jsonl 2000 55 tools/dspark-retrain/prompts_batch1.jsonl
```

We stopped this run by hand at 856 samples (the cap was not reached). The first 55 rows
were used by an earlier 47-sample batch (batch 1), which is why the client skips them. To
reproduce without batch 1, run the client with skip 0 and a cap of 903 and extract one file.

Round 2 (broad mix, 512-token completions, 24 slots):

```bash
LD_LIBRARY_PATH=bin/cuda bin/cuda/llama-server -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    -ngl 99 -fa on -np 24 -c 36864 --host 127.0.0.1 --port 8095 &
python3 tools/dspark-retrain/gen_client.py 8095 24 512 tools/dspark-retrain/prompts_gen_broad.jsonl 100000 0 tools/dspark-retrain/prompts_broad.jsonl
```

Stop the server by its PID when the client finishes (`kill <pid>`; the shell prints it for
`&`). Measured on a GB10: round 1, 856 samples, 209 k generated tokens at 86.7 tok/s
aggregate with `-np 12` (40 min); round 2, 2,498 samples, 1.11 M generated tokens at
136.7 tok/s aggregate with `-np 24` (2 h 16 min). Two of the 2,500 broad prompts were
skipped for exceeding 768 tokens. 66.5% of the round-2 answers hit the 512-token cap.
Single-stream generation is 7.4 tok/s, so the batched server is the only practical
route.

### 5. Teacher-forced feature extraction

The extractor runs each full sequence (prompt plus completion) through the target once, with
embeddings on and five layer-input taps on, and writes the `BON2` file:

```
header : "BON2" | embd u32 | n_taps u32 = 5 | tap_layers u32[5] = {6, 20, 34, 48, 62}
sample : n u32 | tokens i32[n] | loss_mask u8[n] | taps f32[n * 5 * embd] | final_hidden f32[n * embd]
```

`loss_mask` is 1 on completion tokens. The taps are the inputs of layers 6, 20, 34, 48 and
62, which are the outputs of the drafter's `target_layers` 5, 19, 33, 47 and 61.
`final_hidden` is the post-final-norm state that feeds the LM head. Free the GPU first: stop
the generation server, then run:

```bash
mkdir -p tools/dspark-retrain/feats
LD_LIBRARY_PATH=bin/cuda tools/dspark-retrain/extract_feats_tf models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    tools/dspark-retrain/prompts_gen_batch2.jsonl tools/dspark-retrain/feats/batch2.bin 100000
LD_LIBRARY_PATH=bin/cuda tools/dspark-retrain/extract_feats_tf models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    tools/dspark-retrain/prompts_gen_broad.jsonl tools/dspark-retrain/feats/batch3_broad.bin 100000
```

Measured on a GB10: 237 k tokens in 311 s (762 tok/s, 29 GB) for round 1 and 1.32 M tokens
in 1,498 s (879 tok/s, 162 GB) for round 2. The extractor checks every write. On a short
write (for example a full disk) or a failed close, it reports the sample, removes the
partial output file, and exits with status 1. Write to a temporary name and rename on
success if a waiter watches the file. The trainer reads every `*.bin` in `--feats-dir`.

### 6. Training

`train_dspark_v2.py` implements the DSpark block-parallel objective from the SpecForge
reference and mirrors the llama.cpp runtime forward: the five taps go through `fc` and
`hidden_norm` to form the context, each draft layer projects that context to K/V, and a
Qwen3-style decoder runs over `[anchor, mask x 6]` noise tokens with block size 7. Each block
hidden state goes through the borrowed `W_lm` and the Markov head bias. The loss is
`0.1 * CE + 0.9 * L1 + 1.0 * confidence BCE`, token-normalized over the supervised block
positions. `--max-seq-len` (default 512) keeps the first 512 positions of each sample. The
generator accepts prompts up to 768 tokens, so a sample whose completion starts at or
after position 511 keeps no supervised pair inside the window. The trainer skips such
samples at index time, prints the count, and never feeds them to a batch. The synthetic
dry run checks shapes, the loss trend, the converter keys and this truncation skip on the
CPU:

```bash
python3 tools/dspark-retrain/train_dspark_v2.py --dry-run
```

Round 1, from the RadixArk warm start on the code data (`feats_full/` = batch 1 + batch 2,
903 samples, 250 k tokens):

```bash
mkdir -p tools/dspark-retrain/feats_full
ln tools/dspark-retrain/feats/batch1.bin tools/dspark-retrain/feats/batch2.bin tools/dspark-retrain/feats_full/
tools/dspark-retrain/run_full_pipeline.sh full1 tools/dspark-retrain/feats_full 2
```

If you took the route without batch 1 in section 4, you have one combined file instead of
`batch1.bin` and `batch2.bin`. Link that file alone into `feats_full/`, and in round 2 link
it together with `batch3_broad.bin` into `feats_all/`. The trainer reads every `*.bin` in
the directory it is given, so one file works. Do not pass `feats/` itself: after section 5
it also holds `batch3_broad.bin`, which does not belong in round 1.

This trains with batch size 2, lr 1e-4, 512 anchors, chunk 64, cosine schedule, then
converts and quantizes (steps 2-5 of the script). The script removes the previous
checkpoint of the tag before training, checks the exit status and the output size of
every stage, and stops at the first failure. We stopped round 1 after epoch 1 (452
steps): train-set accuracy kept rising in epoch 2 while held-out acceptance did not move.

Round 2 continues from the round-1 checkpoint on all data (3,401 samples, 1.57 M tokens)
for one epoch with a lower rate and 256 anchors, and saves a checkpoint every 300 steps.
Run it from the checkout root in the trainer environment (the container or a Python
environment with CUDA torch):

```bash
mkdir -p tools/dspark-retrain/feats_all
ln tools/dspark-retrain/feats/batch1.bin tools/dspark-retrain/feats/batch2.bin tools/dspark-retrain/feats/batch3_broad.bin tools/dspark-retrain/feats_all/
python3 -u tools/dspark-retrain/train_dspark_v2.py \
    --feats-dir tools/dspark-retrain/feats_all --teacher-dir tools/dspark-retrain/teacher \
    --warm-start models/bonsai2-dspark/bonsai2_dspark_full1.safetensors \
    --out models/bonsai2-dspark/bonsai2_dspark_full2.safetensors \
    --epochs 1 --batch-size 2 --lr 6e-5 --num-anchors 256 --chunk-blocks 64 --log-every 10 --save-every 300
```

Measured on a GB10: 22-23 s per step at batch 2 with 256 anchors (910 steps in 355 min),
18.7 GB of VRAM. Round 1 ran at 21.7 s per step with 512 anchors. The checkpoints at steps
300, 600 and 900 give the same acceptance within noise; the step-600 checkpoint is the
shipped drafter. A probe that continued from step 600 at lr 2e-4 for 200 steps lowered
acceptance by 5-8 points on every workload.

### 7. Conversion to GGUF

The conversion is two steps plus quantization. `run_full_pipeline.sh` runs them after
training; run them by hand for a step checkpoint:

```bash
CK=models/bonsai2-dspark/bonsai2_dspark_full2_step600.safetensors
python3 tools/dspark-retrain/convert_safetensors_to_dspark.py "$CK" /tmp/drafter-raw.gguf
python3 llama.cpp/gguf-py/gguf/scripts/gguf_dspark_to_dflash.py /tmp/drafter-raw.gguf \
    models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf /tmp/drafter-conv.gguf --drop-shared-tensors
LD_LIBRARY_PATH=bin/cuda bin/cuda/llama-quantize /tmp/drafter-conv.gguf \
    models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf Q4_K_M
```

Step 1 writes the SpecForge tensor names into a raw `arch=dspark` GGUF with the Bonsai 2
hyperparameters (5 blocks, block size 7, target layers 5-61, Markov rank 256, mask token
248070, vocab 248320). Every tensor of the name map is required: when one is missing, step
1 writes no GGUF and exits with status 1. Step 2 rewrites it to the `arch=dflash` convention the runtime
loads, injects the tokenizer from the target as donor, shifts `target_layers` by one (the
runtime taps a layer's input), and drops `token_embd` and `output` because the runtime
borrows them from the target. The Q4_K_M file is 1.1 GB. A one-shot converter (safetensors
straight to `dflash`) is not used: its donor-tokenizer injection writes a wrong KV type
tag, and the file fails to load in every environment we tried. The
`general.name` in the output is inherited from step 1 (`Qwen3.8-27B-DSpark`).

Check the result:

```bash
LD_LIBRARY_PATH=bin/cuda bin/cuda/llama-gguf models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf r n \
    | grep -E 'general.architecture|dflash.block_size|dflash.target_layers|mask_token_id'
```

Expect `dflash`, block size 7, target layers `[6, 20, 34, 48, 62]`.

Two notes for `BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh`:

- The launcher picks the first `*dspark-dflash*.gguf` in the model directory in sorted
  order. The file name above matches that glob, but the published
  `...-dspark-dflash-Q4_0.gguf` sorts before `...-dspark-dflash-v2-Q4_K_M.gguf`. If both
  files are present, the launcher starts the published one. Move it out of the directory,
  or start `llama-server` by hand with `-md <file>` and the flags from section 8:
  `--spec-type draft-dspark --spec-draft-n-max 5 -ngld 999 -fa on -ngl 99`.
- Set `BONSAI_SPEC_NMAX=5`. The launcher reads the block size from the key
  `dspark.dspark.block_size`, which the converted file does not carry, and falls back to
  4. The results below are measured at K=5.

### 8. Evaluation

Measure on an idle GPU. Acceptance does not depend on load; tok/s does. The sweep harness
runs the baseline and the drafter on the same four prompts for a list of `n-max` and
`p-min` values and writes JSON:

```bash
tools/dspark-retrain/eval/spec_eval.sh models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf /tmp/spec_eval.json 200 '4 5 7' '0.0'
```

The harness writes `<out_json>.partial` while it runs and renames it to `<out_json>` at
the end. A llama command that exits non-zero, or a metric that does not parse, stops the
harness with exit status 1: the partial file stays for inspection, `<out_json>` is not
written, and `WROTE` is not printed.

The numbers in the next section come from `llama-speculative-simple` directly:

```bash
export LD_LIBRARY_PATH=bin/cuda
B=models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf
D=models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf
bin/cuda/llama-speculative-simple -m $B -md $D --spec-type draft-dspark --spec-draft-n-max 5 --spec-draft-p-min 0 \
    -fa on -ngl 99 -ngld 999 -c 4096 -n 200 --temp 0 -e \
    -p '<|im_start|>user\n<prompt><|im_end|>\n<|im_start|>assistant\n'
```

The tool prints `decoded ... speed: <tok/s>` and `n_drafted`, `n_accept` and `accept`.
Match `accept` with its `%` sign; `n_accept` also matches the bare word. The three
200-token prompts:

- math: `A train leaves city A at 9:00 traveling 80 km/h toward city B, 300 km away. A second train leaves B at 9:30 traveling 100 km/h toward A. At what time and where do they meet? Show your reasoning step by step.`
- code: `Write a Python function that parses a CSV file of transactions (date, amount, category) and returns the total spent per category as a dict, with error handling for malformed rows and a small unit test.`
- code2: `Implement binary search in Python with type hints, a docstring, and three assert-based tests.`

The long-form rows use `-n 2000` on six prompts:

- the code prompt above, followed by ```` Put all code in one ```python block that runs the tests when executed. ````
- `Implement an LRU cache class in Python with get/put in O(1), a docstring, and unit tests that run when the file is executed.`
- `Write a Python script that reads a log file, counts requests per IP, prints the top 10, and includes tests with a temporary file.`
- `Implement Dijkstra's shortest path in Python over an adjacency dict, with a small graph example and assert-based tests.`
- `Write a Python function to validate and normalize email addresses, with edge cases and unit tests.`
- the math prompt above

## Results

Clean GB10, target PQ2_0, K=5, `p-min 0`, temperature 0. Baseline is plain decoding on the
same GPU: 29.8-29.9 tok/s.

| Workload | Tokens | Acceptance | tok/s | Speedup |
|----------|-------:|-----------:|------:|--------:|
| math | 200 | 52.1% | 61.5 | 2.06x |
| code | 200 | 42.9% | 53.9 | 1.80x |
| code2 | 200 | 49.5% | 59.8 | 2.00x |
| long-form, mean of 6 prompts | 2,000 | - | 64.4 | 2.15x |
| long-form, math | 2,000 | - | 71.8 | 2.40x |

Acceptance is exact match (`n_accept / n_drafted`) against the batched verify logits. On the
62-prompt benchmark in `community-benchmarks/ternary-bonsai/`, 37 of 65 drafter outputs are
byte-identical to plain single-row decoding, and the 28 first-difference positions are the
same for this drafter and for the older Ternary-Bonsai-27B drafter, so the differences come
from the batched verify pass rounding differently at near-tie tokens, not from the draft.
That benchmark (512-token prompts, server timings) gives 57.4 tok/s blended over 40 prompts
(1.93x), 74.7 on math (2.52x), 65.7 on code (2.22x), 44.8 on chat (1.51x) and 66.8 on the six
2,000-token prompts (2.26x); the older drafter, re-converted for Bonsai 2, ties it blended.
The six long-form prompts of the `llama-speculative-simple` rows, in the order listed in
section 8:

| Prompt | tok/s |
|--------|------:|
| code: CSV transaction parser with tests | 60.8 |
| code: LRU cache class with tests | 59.7 |
| code: log file top-10 IP script with tests | 68.9 |
| code: Dijkstra over an adjacency dict with tests | 66.7 |
| code: email validator with tests | 58.8 |
| math: two trains meeting problem | 71.8 |

## Measured hardware and time

One NVIDIA DGX Spark (GB10, 20 cores, 128 GB unified memory, CUDA 13.0), one stage at a
time on the GPU.

| Stage | Measured |
|-------|----------|
| Teacher validation gate | 22/22 argmax match, 22/22 top-1 within 1% (100%) |
| Round-1 generation | 856 samples, 209 k tokens, 86.7 tok/s aggregate, `-np 12`, 40 min |
| Round-2 generation | 2,498 samples, 1.11 M tokens, 136.7 tok/s aggregate, `-np 24`, 2 h 16 min |
| Feature extraction | 762-879 tok/s; 237 k tokens in 311 s, 1.32 M tokens in 1,498 s |
| Round-1 training | 21.7 s/step, batch 2, 512 anchors, 18.7 GB VRAM, 452 steps per epoch |
| Round-2 training | 22-23 s/step, batch 2, 256 anchors, 18.7 GB VRAM, 1,701 steps per epoch (stopped at 910) |
| Feature storage | 123 KB per token; 31 GB (round 1) + 162 GB (round 2) |

## Lessons

- The objective decides everything. A trainer that regresses the same-position layer-62
  state (an autoencoder, no token shift, no LM-head cross-entropy, no block rollout) stalls
  at 12-30% acceptance no matter how much data it sees. The block-parallel next-token
  objective through the borrowed LM head tripled code acceptance with 0.2% of the data.
- Validate the teacher before training. The borrowed LM head and embedding must reproduce
  the runtime logits (100% argmax on the gate). Every downstream number depends on it.
- Data breadth beats data volume. Code-only data caps math acceptance near 44%; 19x more
  code-only data moved acceptance 1-3 points. 2,500 broad prompts lifted math to 52% in the
  first 300 steps of round 2, and the curve is flat after that. A higher learning rate
  made it worse.
- K=5. The drafter is trained with block size 7. K=4 and K=5 are the operating points
  on this GPU; K=7 loses because the verify pass grows faster than the accepted tokens.
- Q4_K_M. The draft step must stay small on 273 GB/s unified memory; the 1.1 GB file keeps
  it near 8 ms per step. We did not compare the drafter quantizations on an idle GPU, so
  this is a size choice, not a measured optimum. `--drop-shared-tensors` removes the two
  largest tensors at unchanged acceptance.
- Kill by PID. Never stop a server or a client with `pkill -f <pattern>`: the pattern also
  matches the calling shell and any watcher that has the script name on its command line.
  Record the PID at launch and kill that PID.
- Gate waiters on file size and a settled mtime. A waiter once picked up a Q4_K_M file
  at 543 MB while `llama-quantize` was still writing it.
- Report tok/s from an idle GPU only. A co-resident job changes tok/s but not acceptance.
