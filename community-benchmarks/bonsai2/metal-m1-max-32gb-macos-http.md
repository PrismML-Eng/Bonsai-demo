# Apple M1 Max 32 GB — Bonsai 2 27B PQ2_0 over HTTP

This comparison uses the same Ternary-Bonsai-2-27B PQ2_0 weight file on the same
Mac, served by Ferrum and the PrismML llama.cpp fork. It measures streaming text
requests over a local OpenAI-compatible API. These are HTTP serving measurements,
not `llama-bench` PP512/TG128 results, and not results for the earlier
Ternary-Bonsai generation.

Disclosure: submitted by a Ferrum maintainer; preparation and writing are
AI-assisted. Both runtimes' results, errors, and configuration differences are
reported below.

## Hardware and software

| Item | Configuration |
|---|---|
| Machine | MacBookPro18,4, Apple M1 Max |
| CPU | 10 cores: 8 performance + 2 efficiency |
| GPU | 24-core integrated Apple GPU, Metal |
| Memory | 32 GiB unified memory (34,359,738,368 bytes) |
| OS | macOS 15.1.1, build 24B91 |
| Power | AC power; Low Power Mode off |
| Ferrum server and benchmark client | [0.12.1](https://github.com/sizzlecar/ferrum-infer-rs/releases/tag/v0.12.1), source `42f3f381049c8e3d8e6161bfbbdde4ef0823ae86`, prebuilt Metal binary |
| Prism server | [prism-b10709-9a9394a](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10709-9a9394a), source `9a9394a895b96003ca842a6041cb28ac49a108f7`, prebuilt macOS ARM64 `llama-server` |
| Measurement date | 2026-09-19 |
| Background load / thermal observations | Normal desktop background; AC power, Low Power Mode off. `pmset` reported no warnings; temperature and throttling were not continuously monitored. |

## Model identity and matched configuration

Both servers load exactly the same file:

- Model: [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/tree/6ed5e12bf84b7a63069882c91dd9e9218647d17b).
- File: `Ternary-Bonsai-2-27B-PQ2_0.gguf`.
- Model revision: `6ed5e12bf84b7a63069882c91dd9e9218647d17b`.
- File SHA-256: `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`.
- Ferrum tokenizer and semantic metadata: [Qwen/Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B/tree/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0), revision `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`.
- Client `tokenizer.json` SHA-256: `0997f410c57a1f4e53b09e4be8f4a172d90edd9564368fb0847030937229b9f3`.
- Ferrum `chat_template.jinja` SHA-256: `c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041`.
- Ferrum executable SHA-256: `ea05e07276e8c9cc1cb185aa5f6d7dca056c915aeeeac9291857e1306997a7c2`.
- Prism `llama-server` executable SHA-256: `1ad69ebaada923760c52c1dc50daf198a22c2adb4a9dcccd25779fa7079f353b`.

Prism was given the same `chat_template.jinja` explicitly. Its `/props` response
returns that template byte-for-byte, with the same SHA-256 above. This establishes
template-file equality; each server's actual `usage.prompt_tokens` remains the
evidence for its rendered input length.

| Setting | Ferrum | Prism llama-server |
|---|---|---|
| Weight format | PQ2_0 | Same PQ2_0 file |
| Execution | Metal | Metal, all model layers offloaded |
| Attention KV precision | FP16 | F16 K and V |
| Context ceiling | 16,384 tokens | 16,384 tokens |
| Maximum active sequences / slots | 1 | 1 |
| Batch limit | 512 tokens | Logical batch 512, microbatch 512 |
| Cross-request prompt/prefix reuse | Disabled | Disabled |
| Thinking | Disabled in server defaults and request template kwargs | Disabled in server defaults and request template kwargs |
| Speculative decoding | Off | Off |
| Attention / arithmetic implementation | Portable attention; `qwen3_5.f32-master` selected | Flash Attention `auto`, enabled by runtime; recurrent R/S buffers F32 |
| CPU threads | Engine defaults | 8 inference threads, 8 batch threads, as reported at startup |
| Diagnostic output | INFO startup/request logs; structured profiling off | Log verbosity 4 |

The explicit limits above are comparison controls. Ferrum's normal `run` and
`serve` commands fit unset limits to the machine. This report does not compare
automatic sizing policies. FP16 KV does not imply that both engines use identical
internal arithmetic, attention kernels, or allocation strategies.

## Workload and method

- One server runs at a time. Final Ferrum measurements were taken without
  competing model, build, or local Metal CI work, with normal desktop applications
  remaining open. The retained Ferrum measurement order was 8K then 2K; the
  Prism order was 2K then 8K.
- Use the same Ferrum 0.12.1 `bench-serve` client and tokenizer for both servers.
  Requests use loopback HTTP, pooled connections, streaming Chat Completions,
  and closed-loop concurrency 1.
- Generate random token-aware user-message bodies of 2,048 and 8,192 tokens.
  Both runtimes use prompt-generation seed `20260919`; the client deterministically
  derives each repeat's seed from that value, the repeat index, and concurrency
  cell. The same client binary, tokenizer, input length, seed, and cell reproduce
  the same user-message bodies. This is a deterministic construction guarantee;
  exact HTTP request-body hashes were not captured.
- Request up to 128 output tokens. EOS remains enabled; `ignore_eos` is not sent.
  Record each server's actual output-token count. An early stop remains visible
  in that count rather than being counted as a 128-token response. The client
  report does not retain `finish_reason`; no stop reason is inferred from length.
- Sampling: temperature 0, top-k 1, top-p 1, repetition penalty 1, generation
  seed 0. Disable thinking with `chat_template_kwargs.enable_thinking=false`.
- For each runtime and body length: 3 repeats, each containing 1 discarded
  warmup request followed by 1 measured request. Warmups have the same shape as
  the measured request. Three measured requests are a small sample; report
  individual observations and mean / sample standard deviation.
- User-message token counts exclude chat-template tokens. Report both the body
  count and the server's `usage.prompt_tokens`, which can differ across templates
  or tokenizer implementations. Do not present the body count as total prefill.
- TTFT is client request dispatch to first textual output. End-to-end latency is
  the client-observed request duration. Both include HTTP and server overhead;
  model loading and the discarded warmups are excluded.
- Output throughput is server-reported output tokens divided by measured request
  wall time. It includes prefill waiting and must not be labeled decode TG128.
  TPOT is `(end_to_end_ms - TTFT_ms) / (usage_output_tokens - 1)`. The derived
  decode rate is `1000 / TPOT_ms` for each request; its reported mean and sample
  standard deviation are calculated from those per-request rates, not by
  inverting the mean TPOT. This is a client-observed rate after first output,
  including transport/completion overhead, not an isolated GPU-kernel benchmark.
  SSE events are not necessarily individual tokens. Event-derived ITL is separate
  and requires matching output-event, usage-token, interval, and transport checks.
- Random-prompt protocol checks do not establish reasoning or coding quality.
  Any Orchestral task result must be reported separately, with its exact task,
  output, tool operations, and independent acceptance result.

The preliminary Ferrum 2K run that overlapped local Metal CI is excluded. It is
not a comparison result and is not used to select a favorable timing.

## Commands

The arguments below reflect the recorded invocations. Paths are user-selected
locations for the verified binaries, model, and metadata above.

Start only one server at a time. For Ferrum:

```sh
FERRUM=/path/to/ferrum-0.12.1
MODEL=bonsai2:27b

"$FERRUM" serve --model "$MODEL" \
  --backend metal --kv-dtype fp16 \
  --max-model-len 16384 --kv-capacity 16384 \
  --max-num-seqs 1 --max-num-batched-tokens 512 \
  --disable-prefix-cache --session-cache off --disable-thinking \
  --served-model-name bonsai --host 127.0.0.1 --port 18191 \
  --effective-config-json ferrum-effective.json
```

For the official Prism prebuilt binary:

```sh
MODEL=/path/to/Ternary-Bonsai-2-27B-PQ2_0.gguf
META=/path/to/Qwen3.8-27B-pinned-metadata
LLAMA_SERVER=/path/to/prism-b10709-9a9394a/llama-server

"$LLAMA_SERVER" --model "$MODEL" --n-gpu-layers 99 \
  --ctx-size 16384 --parallel 1 --batch-size 512 --ubatch-size 512 \
  --cache-type-k f16 --cache-type-v f16 \
  --no-cache-prompt --cache-ram 0 --slot-prompt-similarity 0 \
  --repeat-penalty 1 --chat-template-file "$META/chat_template.jinja" \
  --jinja --reasoning off --chat-template-kwargs '{"enable_thinking":false}' \
  --alias bonsai --host 127.0.0.1 --port 18192 --log-verbosity 4
```

After the active server is ready, run the same client command for each input
length, changing `BASE_URL` and the output filename for the other server:

```sh
FERRUM=/path/to/ferrum-0.12.1
META=/path/to/Qwen3.8-27B-pinned-metadata
BASE_URL=http://127.0.0.1:18191
SERVER_COMMIT=42f3f381049c8e3d8e6161bfbbdde4ef0823ae86
SERVER_TAG=ferrum-0.12.1
INPUT_TOKENS=2048
RESULT=ferrum-input2048.json

"$FERRUM" bench-serve --base-url "$BASE_URL" --model bonsai \
  --tokenizer "$META" --target-backend metal \
  --dataset random --random-input-len "$INPUT_TOKENS" --random-output-len 128 \
  --concurrency 1 --num-prompts 1 --warmup-requests 1 --n-repeats 3 \
  --seed 20260919 --sampling-seed 0 \
  --temperature 0 --top-k 1 --top-p 1 --repetition-penalty 1 \
  --enable-thinking false --timeout 900 --fail-on-error \
  --hw-id apple-m1-max-32gb --commit-sha "$SERVER_COMMIT" --tag "$SERVER_TAG" \
  --output json --out "$RESULT"
```

For Prism, use port `18192`, server commit
`9a9394a895b96003ca842a6041cb28ac49a108f7`, and tag `prism-b10709-9a9394a`.
For the longer prompt, set `INPUT_TOKENS=8192` and choose a distinct result file.
The client remains the same Ferrum executable in every run. Its JSON `env.rust`
field describes the client build, not the Prism server toolchain. The overridden
`env.commit_sha` records the server under test.

## Results

Values are mean ± sample standard deviation across three measured requests per
cell. One measured request per repeat means the report's per-repeat percentile
fields all refer to that one request; they are not meaningful tail estimates.
On this hardware and workload, Prism has lower TTFT and higher derived decode
rates at both input lengths. All paired server-reported prompt-token counts
match, and all measured outputs contain 128 usage tokens.

| Runtime | Body tokens | Server prompt tokens | Usage output tokens | TTFT, s | End-to-end, s | Completed / errors |
|---|---:|---|---|---|---|---|
| Ferrum 0.12.1 | 2,048 | 2,060–2,061 | 128 each | 36.642 ± 0.126 | 48.556 ± 0.257 | 3 / 0 |
| Prism b10709 | 2,048 | 2,060–2,061 | 128 each | 21.275 ± 0.397 | 30.263 ± 0.496 | 3 / 0 |
| Ferrum 0.12.1 | 8,192 | 8,204–8,205 | 128 each | 163.000 ± 0.040 | 176.010 ± 0.051 | 3 / 0 |
| Prism b10709 | 8,192 | 8,204–8,205 | 128 each | 86.556 ± 1.105 | 95.860 ± 1.009 | 3 / 0 |

| Runtime | Body tokens | TPOT, ms | Derived decode, tokens/s | Output tokens / wall second |
|---|---:|---|---|---|
| Ferrum 0.12.1 | 2,048 | 93.811 ± 1.119 | 10.661 ± 0.127 | 2.6362 ± 0.0139 |
| Prism b10709 | 2,048 | 70.772 ± 0.784 | 14.131 ± 0.157 | 4.2303 ± 0.0699 |
| Ferrum 0.12.1 | 8,192 | 102.437 ± 0.085 | 9.762 ± 0.008 | 0.72723 ± 0.00021 |
| Prism b10709 | 8,192 | 73.254 ± 1.669 | 13.656 ± 0.307 | 1.3354 ± 0.0140 |

### Individual measured requests

| Runtime / body tokens | Repeat | Server prompt tokens | Output tokens | TTFT, s | End-to-end, s | TPOT, ms | Derived decode, tokens/s |
|---|---:|---:|---:|---:|---:|---:|---:|
| Ferrum / 2,048 | 1 | 2,060 | 128 | 36.534780 | 48.408997 | 93.497773 | 10.695442 |
| Ferrum / 2,048 | 2 | 2,061 | 128 | 36.780488 | 48.852249 | 95.053238 | 10.520420 |
| Ferrum / 2,048 | 3 | 2,060 | 128 | 36.610451 | 48.406402 | 92.881497 | 10.766407 |
| Prism / 2,048 | 1 | 2,060 | 128 | 20.818927 | 29.695941 | 69.897744 | 14.306613 |
| Prism / 2,048 | 2 | 2,061 | 128 | 21.545960 | 30.615495 | 71.413664 | 14.002923 |
| Prism / 2,048 | 3 | 2,060 | 128 | 21.459822 | 30.477507 | 71.005391 | 14.083438 |
| Ferrum / 8,192 | 1 | 8,205 | 128 | 163.045747 | 176.067343 | 102.532250 | 9.753029 |
| Ferrum / 8,192 | 2 | 8,204 | 128 | 162.985536 | 175.991344 | 102.407939 | 9.764868 |
| Ferrum / 8,192 | 3 | 8,204 | 128 | 162.969946 | 175.970869 | 102.369469 | 9.768538 |
| Prism / 8,192 | 1 | 8,205 | 128 | 85.997705 | 95.544459 | 75.171292 | 13.302951 |
| Prism / 8,192 | 2 | 8,204 | 128 | 85.842951 | 95.045859 | 72.463843 | 13.799986 |
| Prism / 8,192 | 3 | 8,204 | 128 | 87.828818 | 96.988938 | 72.126928 | 13.864447 |

All six measured Ferrum requests and all six discarded warmups completed with
zero reported errors or protocol-quality issues: no malformed streams, missing
or duplicate `[DONE]`, zero-token outputs, bulk flushes, HTTP 500s, or panics.
Every measured response reports 128 usage output tokens. The JSON does not retain
full response text or finish reason, so these checks establish protocol validity
and token accounting, not semantic quality.

The six measured Prism requests and their six discarded warmups likewise have
zero reported errors or protocol-quality issues. Measured inputs are
2,060 / 2,061 / 2,060 server tokens at 2K and 8,205 / 8,204 / 8,204 at 8K,
exactly matching the paired Ferrum runs; each response reports 128 output tokens.

### One Orchestral coding task

This is a separate, single-case check using **Orchestral 0.4.1** against each
server. The task is to implement `unique_tags`: split comma-separated
fields, trim whitespace, remove empty entries, lowercase ASCII letters only,
and deduplicate in first-occurrence order. The source starts with a deliberately
incorrect implementation. Command execution is disabled for the agent; only
file tools are available.

| Observation | Ferrum | Prism |
|---|---|---|
| Agent process wall time | 242.354 s | 143.189 s |
| Model HTTP requests | 4, all HTTP 200 | 4, all HTTP 200 |
| File tool calls | Read specification; read source; edit source; read source | Same four calls |
| Independent validator before editing | Exit 1 | Exit 1 |
| Independent validator after editing | Exit 0 | Exit 0 |
| Protected specification, Cargo manifest, and acceptance contract unchanged | Yes | Yes |
| Harness acceptance | `accepted: true` | `accepted: true` |

The acceptance result comes from independent Rust tests applied to the edited
source, not the model's final message. The two tests exercise normalization,
first-occurrence ordering, empty/whitespace fields, and preservation of non-ASCII
letter case. The harness performs no repair rounds. This one result does not
establish a coding benchmark score or generalize to other tasks.

The agent workload differs from the random-prompt timing workload: it allows
up to 512 output tokens per model request and uses top-k 0, temperature 0,
top-p 1, min-p 0, repetition penalty 1, presence/frequency penalties 0, seed 0,
with thinking off. Its elapsed time includes model turns and file-tool execution.

Both runs produced the same edited Rust source and the same final assistant text.
Output usage by request was 53 / 172 / 27 / 61 tokens for both. Input usage was
2,633 / 2,871 / 3,093 / 3,252 for Ferrum and 2,631 / 2,869 / 3,091 / 3,250 for
Prism. Unlike the random-prompt timing rows, these agent requests were not
byte-identical: the system context names separate `semantic-ferrum/task` and
`semantic-prism/task` workspaces, and later turns carry each server's own native
tool-call IDs. The first requests differ only in those workspace paths; their
tool schemas match. We disclose the two-token input difference rather than
attribute it to a particular rendering implementation without proof.

Evidence: [specification](evidence/metal-m1-max-32gb-macos-http/semantic-ferrum/SPEC.md),
[initial source](evidence/metal-m1-max-32gb-macos-http/semantic-ferrum/initial.rs),
[edited Rust source](evidence/metal-m1-max-32gb-macos-http/semantic-ferrum/candidate.rs),
[independent acceptance tests](evidence/metal-m1-max-32gb-macos-http/semantic-ferrum/acceptance.rs),
and [selected harness observations](evidence/metal-m1-max-32gb-macos-http/semantic-ferrum/observations.json).
The same specification, initial/final source, and acceptance contract apply to
both runs; [Prism harness observations](evidence/metal-m1-max-32gb-macos-http/semantic-prism/observations.json)
and the [request-comparison record](evidence/metal-m1-max-32gb-macos-http/semantic-request-comparison.json)
record that match and the request differences above.

### Memory

There is no established total-RAM winner. The macOS `/usr/bin/time -l` process
footers report:

| OS process counter, bytes | Ferrum | Prism |
|---|---:|---:|
| Maximum resident set size | 487,456,768 | 2,373,206,016 |
| Peak memory footprint | 1,078,913,088 | 1,685,871,488 |

These counters do not capture all GPU-mapped model weights: Ferrum separately
imports approximately 7.19 GB of weight buffers, and Prism reports a similarly
sized mapped Metal model buffer below. The OS figures cannot support a sub-2GB
model-fit or total-memory claim, and cannot be added to GPU buffers as independent
allocations. They cover each server process's lifetime, including its agent task;
Ferrum's lifetime also includes the excluded preliminary timing run.

The following is a **backend buffer inventory**, not a peak-memory comparison.
Ferrum combines its startup imported-weight accounting with the final `/health`
snapshot at `2026-09-19T11:11:24.559363+00:00`. Dynamic pools are counted once by
distinct pool ID, using `resident_bytes` rather than their configured ceilings.

| Ferrum buffer scope | Bytes | Observation |
|---|---:|---|
| Static imported weights | 7,189,893,120 | Startup log `imported_bytes` |
| Activation U8 pool `18bf84ae…` | 248,320 | Final pool resident bytes |
| Binding U8 pool `38d4b31b…` | 2,097,152 | Final pool resident bytes |
| State F16 pool `6354a0c9…` | 2,949,120 | Final pool resident bytes |
| Activation F32 pool `734945ab…` | 21,964,816 | Final pool resident bytes |
| State F32 pool `80b01043…` | 150,994,944 | Final pool resident bytes |
| Scratch U8 pool `93e39604…` | 89,128,976 | Final pool resident bytes |
| Activation F16 pool `cadf5f30…` | 10,485,760 | Final pool resident bytes |
| State F16 pool `e5b74403…` | 546,308,096 | Final pool resident bytes |
| Activation U32 pool `eeae5efc…` | 67,616 | Final pool resident bytes |
| Sum of nine distinct dynamic pools | 824,244,800 | Derived from the rows above |
| Static imports plus dynamic pools | 8,014,137,920 | Backend-accounted buffers, about 7,642.88 MiB |

The last row already equals `/health`'s `dynamic_pools.process_claimed_bytes`;
that aggregate is not another allocation to add. It is not whole-machine usage,
an OS residency measurement, or a sampled peak over the workload.

Prism reports the following separate buffer categories at startup:

| Prism buffer scope | Reported MiB | Observation |
|---|---:|---|
| `CPU_Mapped` model buffer | 322.07 | File-backed model view |
| `MTL0_Mapped` model buffer | 6,861.73 | GPU model view, 65/65 layers offloaded |
| MTL0 KV buffer | 1,024.00 | 16K context, F16 K and V |
| MTL0 recurrent-state buffer | 149.62 | F32 R and S |
| MTL0 compute buffer | 183.28 | Startup reservation |
| CPU output buffer | 0.95 | Startup reservation |
| CPU compute buffer | 36.02 | Startup reservation |

`CPU_Mapped` and `MTL0_Mapped` can refer to shared file-backed pages, so they are
not blindly summed. The engines' categories and observation phases differ;
these rows describe their reported buffers, not interchangeable peak totals.

Evidence: [Ferrum final health snapshot](evidence/metal-m1-max-32gb-macos-http/ferrum-health-final.json),
[Ferrum memory log excerpt](evidence/metal-m1-max-32gb-macos-http/ferrum-memory-log-excerpt.txt),
and [Prism buffer/process-counter log excerpt](evidence/metal-m1-max-32gb-macos-http/prism-startup-buffers.txt).

The machine already had swap in use: `vm.swapusage` reported `used = 3175.50M`
before the Ferrum measurements and `3167.50M` afterward. The `vm_stat` observations
contain cumulative VM counters. These snapshots do not establish zero swapping
during individual requests, and the report makes no such claim.
After the Prism agent task, `vm.swapusage` reported `used = 2371.12M`; this is a
whole-machine observation at a different time, not an engine memory comparison.

### Evidence and limits

The retained client JSON is included unchanged:

| Evidence | SHA-256 |
|---|---|
| [Ferrum 2K](evidence/metal-m1-max-32gb-macos-http/ferrum-input2048.json) | `a50ab5f60cc55f33848671be2aa08b2d8fcf9679eee6db6330d0507076f96ed5` |
| [Ferrum 8K](evidence/metal-m1-max-32gb-macos-http/ferrum-input8192.json) | `157c7cac4055c3606507c203b757e2fca7de41019beaab806da8e188fcd65a6c` |
| [Prism 2K](evidence/metal-m1-max-32gb-macos-http/prism-input2048.json) | `73edfd8e31cafeb22d47e2bb737574adf2d58dc8ee0efe78046ee3dc14cb8009` |
| [Prism 8K](evidence/metal-m1-max-32gb-macos-http/prism-input8192.json) | `f2d7efe1e54dfb21250bce6bd021e4badd4271804348f3889dbd7772180d466a` |

The [evidence checksum list](evidence/metal-m1-max-32gb-macos-http/SHA256SUMS)
also covers the health snapshot, labeled log excerpts, and semantic-task files.
The semantic observations file is a selected-field export from the harness
report, with the source report's SHA-256 recorded; it omits local paths and the
model's final self-report. The Rust source and acceptance tests are unchanged.

Also included are the [Ferrum effective configuration](evidence/metal-m1-max-32gb-macos-http/ferrum-effective.json),
[Prism properties and template](evidence/metal-m1-max-32gb-macos-http/prism-props-before.json),
and [hardware/measurement order](evidence/metal-m1-max-32gb-macos-http/hardware.json).
Large logs, model weights, and binaries remain outside this repository.

Prism was faster in the two HTTP timing cases and in this one coding task. Both
servers passed that task's independent acceptance checks. No total-RAM advantage
is established. This scope excludes PTQ1_0, vision, other hardware, concurrent
serving, cached multi-turn conversations, and contexts beyond the configured 16K
ceiling; it does not establish a general model-quality or engine-performance ranking.
