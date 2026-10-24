# Speculative decoding benchmark

`spec_bench.py` measures llama-server decode speed with and without a DSpark
drafter, on one GPU, over chat, code, math, reasoning, long-form, tool-call
and agent prompts. It also measures multi-slot concurrency and GPU power, and
it checks that the drafter does not change the output. One run gives the
numbers that say whether a drafter is usable in practice. The tool needs
Python 3 and nothing else.

The tool lives in `scripts/spec_bench/`. It compares three configurations:

| Config | Drafter | Draft length |
| --- | --- | --- |
| `baseline` | none | - |
| `dspark-v1` | `--drafter-v1` file | K=4 |
| `dspark-v2` | `--drafter-v2` file | K=5 |

## Run it

The published numbers came from this command, run from the demo directory
after `./setup.sh`:

```bash
python3 scripts/spec_bench/spec_bench.py \
    --bin-dir bin/cuda \
    --model models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
    --drafter-v1 models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-Q4_0.gguf \
    --drafter-v2 models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf \
    --slots 1,2,4 --repeats 1 \
    --allow-busy-gpu \
    --out scripts/spec_bench/results/gb10
```

The run has two requirements:

- The patched runtime. Build `bin/cuda/llama-server` from prism commit
  `1a07bfa5f` with the fix of PrismML-Eng/llama.cpp PR #210 (branch
  `fix/dflash-borrowed-hadamard`) applied. The
  published run reports build `b10687-5d80cff0b` in `results.json`.
- An idle GPU. No other process may generate on the GPU during the run,
  because a shared GPU gives numbers that are not publishable. The tool
  refuses to launch a server while `nvidia-smi` lists other compute
  processes. `--allow-busy-gpu` disables that check and nothing else. The
  published run passed the flag because two idle llama-server processes held
  memory on the GPU at start; `results.json` records them under
  `environment.gpu_compute_apps`, with GPU utilization at 0%.

`--bin-dir` is the flag name; `--binary-dir` is accepted as an alias.
Relative paths resolve against the demo directory (the nearest ancestor of
the tool with `setup.sh` and `scripts/`, or `BONSAI_DEMO_DIR`). The tool
prints a plan with an ETA per run and the exact llama-server command for
each server before it starts.

The command above launches nine servers in sequence (three configs, three
slot counts) and never runs two at once. The printed plan gives an ETA of
about 78 minutes at the assumed rates (30 tok/s plain, 60 tok/s with a
drafter); `--plan-only` prints the plan and the server commands and exits.
The run needs these files:

| File | Default path |
| --- | --- |
| llama-server | `bin/cuda/llama-server` (`--bin-dir`) |
| Target model | `models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf` (`--model`) |
| DSpark v1 drafter | `models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-Q4_0.gguf` (`--drafter-v1`) |
| DSpark v2 drafter | `models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf` (`--drafter-v2`) |

`setup.sh` downloads the target model. It does not download the two drafter
files. PrismML ships no Bonsai 2 drafter. The v1 file is PrismML's
Ternary-Bonsai-27B drafter (GGUF header name `Bonsai-27B-dspark`,
`dflash.block_size` 4), re-converted against the Bonsai 2 target. Its block
size is 4, so the runtime clamps `--spec-draft-n-max` to 4; the `dspark-v1`
config runs at K=4 for that reason. The v2 file is the DSpark v2 drafter,
trained for the Bonsai 2 target; it has block size 7 and runs at K=5.

Useful flags:

- `--configs baseline,dspark-v2` runs a subset; the default runs every
  config. `--add-config dspark-v2-k7=path.gguf:7` adds a drafter config with
  another draft length; added configs always run.
- `--slots 1` (the default) skips the multi-slot runs.
- `--repeats 3` runs every prompt three times per server.
- `--no-single` skips the single-prompt passes; `--single-repeats`,
  `--single-n-predict` and `--single-prompt` change them.
- `--n-predict 256 --n-predict-long 1000` changes the token budgets. `--n-predict`
  covers the matrix, tool and agent sets.
- `--prompt-ids code-01,tool-01`, `--categories code,tool` or `--limit 3`
  select prompts for a smoke test.
- `--reasoning-effort low` sets `chat_template_kwargs.reasoning_effort` on the
  chat requests. The default keeps the template default, which is `xhigh` on
  Bonsai 2.
- `--no-power` skips the nvidia-smi sampling; `--power-idle-s 20` lengthens the
  idle window; `--gpu-index 1` samples another GPU.
- `--plan-only` prints the plan, the ETA and every server command, then exits.
- `--server-extra "--threads 8"` appends flags to every launched server.
- `--note "text"` records a note in the results and the summary.

## Dry run against running servers

`--server-url NAME=URL` uses a running server for one configuration instead
of starting one. Use it to test the client without a GPU window:

```bash
python3 scripts/spec_bench/spec_bench.py \
    --server-url baseline=http://127.0.0.1:8080 \
    --server-url dspark-v2=http://127.0.0.1:8081 \
    --prompt-ids code-01,tool-01,agent-01 --n-predict 128 --warmup-tokens 0 \
    --note "dry run, not publishable"
```

A running server keeps its own flags and may be shared, so numbers from a
dry run are not publishable. The summary marks such servers as remote. In
this mode the power samples come from the client host, which may not be the
host that runs the server; the summary says so.

## What it measures

For every config and every slot count the tool starts a server, waits for
`/health`, samples idle power for 10 s, sends one short warm-up request, runs
the prompts, and stops the server by the process id it started.

| Config | Server flags in addition to `-ngl 999 -fa on -c 16384 -np <slots> --jinja` |
| --- | --- |
| `baseline` | none |
| `dspark-v1` | `-md <DSpark v1 drafter> --spec-type draft-dspark --spec-draft-n-max 4 -ngld 999` |
| `dspark-v2` | `-md <DSpark v2 drafter> --spec-type draft-dspark --spec-draft-n-max 5 -ngld 999` |

`--jinja` makes the server apply the model's own chat template, which the
tool and agent prompts need for the tools list. `-c` is the total context;
llama-server divides it over the slots, so a slot has 4096 tokens at
`-np 4`. The concurrency prompts fit in that.

### Single slot: the workload matrix

With one slot every selected prompt runs once per pass.

- Matrix and long prompts go to `POST /completion` with `temperature 0`,
  `seed 42`, `cache_prompt false` and `return_tokens true`. The client wraps
  the prompt in the ChatML template with no system message, so every server
  receives the same bytes. This matches the GB10 workload matrix in
  `community-benchmarks/`.
- Tool and agent prompts go to `POST /v1/chat/completions` with a `tools`
  list, `tool_choice auto`, `max_tokens 512`, `temperature 0`, `seed 42` and
  `cache_prompt false`. The server applies its template. On build b10687
  the chat response carries the same `timings` object as `/completion`, with
  `predicted_per_second` and the draft counters, so the speed comes from
  there. When a build omits `timings`, the row falls back to
  `usage.completion_tokens` over the request wall time (prefill included) and
  records `timings_source: wall`; the summary says when that happened.

From each response the tool records `timings.prompt_n`, `predicted_n`,
`predicted_ms` and `predicted_per_second` (decode only, prefill excluded),
and the draft counters `draft_n` and `draft_n_accepted`. llama-server puts
these counters in the response only when a drafter is loaded; the tool
warns when a drafter configuration returns none, because that means
speculation is not engaged. The test is the presence of the counters, not
a nonzero value: a short answer can report `draft_n` 0 with speculation
engaged. Only a response that carries `timings` can answer; a wall-timed
chat response leaves the state unknown.

The summary reports, per workload and per drafter configuration:

- `no drafter` and the drafter column: arithmetic means of
  `predicted_per_second` over the same prompts.
- `accept`: accepted / drafted tokens, aggregated over the workload.
- `tok/step`: generated tokens per verify step, `predicted_n / (predicted_n -
  draft_n_accepted)` over the workload. Every step yields one target-sampled
  token plus the accepted drafts, so a server without a drafter is at 1.00.
- `speedup`: the ratio of the two means.

The rows are the five matrix categories, `tool`, `agent`, a blended row over
the 40 matrix prompts, and a row for the 6 long prompts. A second table lists
every long prompt on its own. `results.json` also carries a token-weighted
rate (total tokens / total decode time), the mean prompt length and the
tokens per step per row and per request.

### Single prompt

Every single-slot server also runs the quicksort prompt of the PrismML GB10
document ("Implement quicksort in Python with type hints, tests, and a
concise complexity explanation") for 3 passes at 256 tokens, on
`/completion` with the client-side ChatML template, after the prompt set.
The summary lists the rate of every pass, the mean, acceptance, tokens per
step and speedup per config. A pass that fails keeps its position and
prints as `n/a`; the mean, the acceptance and the speedup come from the
passes that completed. These rows are not part of the workload matrix,
but they take part in the exactness check, and the baseline passes are
compared with each other.

### Tool calls

The tool prompts ask for one of four functions: `get_weather`,
`search_docs`, `run_sql` and `create_ticket`, defined with JSON schema
parameters in `prompts.json`. Per response the tool records whether the
output is a well-formed tool call: the server's structured `tool_calls`
(name and a JSON object of arguments), or, when the server returned none,
`<tool_call>` blocks parsed from the text in the JSON form or the
`<function=name><parameter=k>v</parameter></function>` form of the Bonsai 2
template. A call is valid when every call is well formed and names a tool
from the list. The summary reports the valid count, how many answers called
the expected tool, the finish reasons and where the call came from
(`structured` or `text-*`). On build b10687 the server returns structured
`tool_calls` with `finish_reason: tool_calls`.

### Agent turns

The agent prompts are subagent-style turns: a shared system prompt of about
1,700 tokens (role, rules, tool list, house style, report format), a task,
one prior tool call and its result of 500 to 750 tokens (fake grep, ls, test,
git log, jest, docker, lint and curl output), then the assistant turn with
`max_tokens 512`. The templated prefix is about 3,000 tokens. This measures
generation after a long prefix; the summary states the mean prefix length.

### Multi-slot

For every slot count above 1 the tool launches the server with `-np N` (and
the drafter when the config has one) and fires a fixed 8-prompt subset (2
code, 2 chat, 2 reasoning, 2 tool) in waves of N concurrent requests. The
summary reports, per config and slot count:

- `prompts`: the requests the run attempted, failed ones included.
- `per stream`: the mean `predicted_per_second` that each request saw.
- `aggregate`: generated tokens over the wall time of all waves, prefill
  included. The `slots 1` row uses the same prompts from the single-slot run.
- `accept`: aggregated acceptance over the subset.
- `result`: `ok`, the exact error when the server refused, the count and
  the first error when some requests failed, a note when a drafter server
  returned no draft counters, or a note when every response was wall timed
  and the counters are unknown.

A server that exits at start with `-np N` and a drafter is a finding, not a
failure of the tool: the run records the last error lines of the server log
and continues with the next run.

### Power

While a server runs, a background thread samples
`nvidia-smi --query-gpu=power.draw,utilization.gpu,memory.used` at 1 Hz on
the host that runs the tool. Each sample carries a phase: `idle` (model
loaded, no request), `warmup` or `generation`. Per server the summary lists
idle W (mean over the idle window), mean and max W during generation, mean
GPU utilization, generated tokens, `gen tok/s` (tokens over the wall time of
the generation phase, prefill included) and energy per generated token in
mJ/token = mean W / gen tok/s x 1000. `memory.used` is `[N/A]` on a unified
memory GPU such as the GB10 and is then recorded as null.

## Prompt set

`prompts.json` holds 62 original prompts and the tool definitions:

- 40 matrix prompts, 8 each for code, math, reasoning, chat and long-form,
  with a 512 token budget.
- 6 long prompts (code and one math word problem) with a 2000 token budget.
- 8 tool prompts, 2 per function, with a 512 token budget and the expected
  function name.
- 8 agent prompts with the shared `agent_system` prompt, the `agent_tools`
  list (`run_shell`, `read_file`, `write_file`, `search_code`), one prior
  tool call and its result, with a 512 token budget.

Every matrix and long prompt is under 120 tokens with the Bonsai 2 tokenizer.
Bonsai 2 thinks before it answers, so most of a 512 token budget is reasoning
text; that is what the earlier matrix measured too. The chat template adds a
"reasoning effort xhigh" line to the system prompt of the chat requests
unless `--reasoning-effort` changes it. The agent-07 fixture text was edited
after the published run (two string constants); the other 61 prompts are
byte-identical to the run's prompts.json, whose sha256 is recorded in
results.json.

## Exactness

At temperature 0 a correct drafter must not change the output. The tool
compares every drafter output with the baseline output for the same prompt
and pass, from the single-slot runs. `/completion` outputs are identical when
their token id sequences are equal. Chat outputs (reasoning, answer and tool
calls) are compared as text, because `/v1/chat/completions` returns no token
ids. A `/completion` output from a server that ignores `return_tokens` has
no ids either; it is compared as text and its row records no token count.
For a different output the summary lists the 0-based index of the first
differing token or character; when one output is a prefix of the other, the
index equals the shorter length. For chat prompts the tool also hashes the
templated prompt from `/apply-template`, so a difference caused by a
different server template is marked as such. With `--repeats` above 1 the
tool also reports whether the baseline outputs were identical across passes.

## Output files

The output directory (`--out`; the default is
`scripts/spec_bench/results/<UTC timestamp>`, which git ignores) holds:

- `placeholders.json`: a flat map of printed strings for the document fill
  step, for example `code.v2.speedup: "2.06x"`, `tool.v1.accept: "52.1%"`,
  `single.baseline.p1: "61.5"`. The tool builds it with the same function
  as `fill_placeholders.py`, so both files have one schema. Keys:
  `labels.{baseline,v1,v2}`; `single.{baseline,v1,v2}.{p1,p2,p3,mean}` and
  `single.{v1,v2}.{speedup,accept,tps_step}`; `<W>.baseline` (also
  `<W>.baseline.tps`) and `<W>.{v1,v2}.{tps,accept,speedup,tps_step}` for
  `W` in code, math, reasoning, chat, longform, tool, agent, blended (the 40
  matrix prompts) and long2000 (the 6 long prompts);
  `slots.<N>.baseline.{stream,aggregate}` and
  `slots.<N>.{v1,v2}.{stream,aggregate,accept,speedup,aggregate_speedup}`
  (`speedup` is the per-stream ratio, `aggregate_speedup` the wall-clock
  throughput ratio; an `error` key holds the server's refusal, or the first
  request error of a run that completed in part); `power.source`,
  `power.idle.w`, `power.{baseline,v1,v2}.{w,mj}`; `exact.{v1,v2}.{identical,total}`.
  The workload values of every config cover the prompts and passes that
  the baseline and every config completed, so the printed rates and
  speedups agree with each other; a workload that a config did not
  complete at all is absent. A value the run could not compute prints as
  `n/a`; a key the run did not produce is absent (for example the power
  keys with `--no-power`). Configs added with `--add-config` use their own
  name as the key.
- `results.json`: the header (host, GPU name and driver from nvidia-smi,
  CUDA, GPU processes at start, llama-server version and build, every flag,
  the plan with the ETA, size and SHA-256 of every local model file, the
  prompt file hash), one record per server run (config, slots, mode, URL,
  exact server command, `/props` build, model, slots and context, drafter
  GGUF metadata such as `dflash.block_size`, load time, power summary), one
  row per request (category, set, config, slots, pass, wave, endpoint,
  prompt tokens, generated tokens, milliseconds, tok/s, drafted, accepted,
  finish reason, tool call fields, output hash and length), the summary
  tables, the long-form table, the single-prompt table, the tool-call
  summary, the multi-slot table, the power records, the placeholders map and
  the exactness report.
- `summary.md`: the workload matrix, the long-form table, the single-prompt
  table, the exactness section, the tool-call table, the multi-slot table,
  the power table, any request errors and the configuration with every
  server command line.
- `outputs.json`: the full output text (and token ids for `/completion`) of
  every request, for an offline diff.
- `server-<config>-np<slots>.log`: llama-server output for every launched
  server.

The tool writes the files after each server run, so a partial run keeps its
data. A configuration that fails before or between its requests (a missing
or unreadable drafter file, a server that does not start or exits, a failed
`/props` or warm-up request) is recorded with its error, and the run
continues with the next configuration. The exit code is 1 when any
configuration or request failed.

## Post-processing scripts

Three scripts next to the tool work from a run's output directory and never
touch `spec_bench.py`:

- `fill_placeholders.py <results_dir>` reads `results.json` (schema 2) and,
  when present, `single.json`, and writes `placeholders.json`: a flat map of
  printed strings for a document, with the schema listed under Output files.
  Workload figures come from the request rows over the prompts and passes
  that the baseline and every config completed; `tps_step` is
  `predicted_n / (predicted_n - draft_n_accepted)` over the workload. The
  script prints a note for every workload that covers fewer requests than
  the baseline completed, and for every workload it left out.
  `single.{baseline,v1,v2}.{p1,p2,p3,mean}` and
  `single.{v1,v2}.{speedup,accept,tps_step}` come from `single.json` (or from
  the tool's own single-prompt rows when `single.json` is absent); a failed
  pass keeps its position and prints as `n/a`. `slots.<N>.*`, `power.*` and
  `exact.*` come from the multi-slot, power and exactness sections. Config
  names map to keys as baseline, dspark-v1 -> v1, dspark-v2 -> v2;
  `labels.*` hold the document labels. The script lists every expected key
  the run did not produce; `--strict` makes that an error.
- `fill_doc.py <doc.md> <placeholders.json> [--check] [--out FILE] [--strict]`
  replaces every `{{BENCH:key}}` marker in a markdown document. It reports
  markers without a value, values without a marker and malformed markers
  (a bad character in the key, or a marker that never closes), and refuses
  to write when any marker would remain. `--check` writes nothing;
  `--strict` treats an `n/a` value as missing.
- `single_prompt_bench.py --out <results_dir> [--configs ...] [--add-config ...]`
  reuses the server launch and `/completion` client of `spec_bench.py` to run
  the quicksort prompt (256 tokens, temperature 0, seed 42) for 3 passes per
  config on a launched server, one server at a time, and writes `single.json`
  and `single-outputs.json` into the results directory. `--server-url NAME=URL`
  uses a running server instead. Per config, `passes` holds one rate per
  attempted pass (`null` for a failed pass), and `identical_to_baseline`
  counts the passes that both the config and the baseline completed; the
  script computes it after every config, so the order of `--configs` does
  not matter. A config that fails before its first request is recorded
  with its error and the script continues with the next one.

Order for a document: run `spec_bench.py`, run `single_prompt_bench.py` with
the same `--out`, run `fill_placeholders.py <out>`, then
`fill_doc.py doc.md <out>/placeholders.json --check` and, when the check is
clean, the same command without `--check`.

## Tests

Run from the demo directory:

```bash
python3 -m unittest tests.test_spec_bench tests.test_postprocess
```

`tests/test_spec_bench.py` checks the prompt set (including the tool and
agent sets), the tool-call parser, the power math, the tokens-per-step math,
the summary math, the single-prompt summary with a failed pass, the
placeholders map, the exactness rules with and without token ids, the
draft-counter presence test, the multi-slot table with a partial failure,
the markdown shape and, with a fake `llama-server`, the launch, poll and
stop path, the single-prompt passes, a failed single-prompt pass, the
multi-slot waves, a drafter server that refuses `-np 2`, a truncated
drafter file, a failed `/props` request, a server without token ids, and
the wall-time fallback for a chat response without `timings`.

`tests/test_postprocess.py` checks the three scripts against a synthetic
`results.json` that covers every key, a partial run (missing keys reported,
`--strict` fails, a workload that not every config completed), a document
with markers (check, refuse, fill in place and to a file, a marker that
never closes), and the single-prompt runner against the fake `llama-server`
(a failed pass, the baseline after the drafter, a truncated drafter file).

The tests need no GPU and no model files.
