# Speculative decoding

## Bonsai 2.5 27B: built-in MTP draft head (default where it pays)

Every Bonsai 2.5 GGUF is also published as a `*-mtp.gguf` build that carries a
built-in multi-token-prediction (MTP) draft head: one extra layer that guesses
the next few tokens, which the model then checks itself in one pass. Output
matches plain decoding; only speed changes. There is no sidecar drafter file and
no conversion step, and unlike the DSpark path below it keeps prompt-cache reuse
working.

The demo downloads the `-mtp` build and `start_llama_server.sh` /
`start_llama_server.ps1` enable drafting by default where it measured faster:

| Backend | Default | Settings (`--spec-draft-n-max`, `--spec-draft-p-min`) | Measured decode gain |
|---|---|---|---|
| CUDA / ROCm | on | 3, 0.1 | ~1.5-1.8x |
| Metal (Apple Silicon) | on | 1, 0.6 | ~1.1x |
| Vulkan / CPU | off (opt in with `BONSAI_SPECULATIVE=1`) | 3, 0.1 | unmeasured |

Knobs: `BONSAI_SPECULATIVE=0` disables, `BONSAI_SPECULATIVE=1` forces it on,
`BONSAI_SPEC_NMAX` / `BONSAI_SPEC_PMIN` override the per-device settings. The
flags behind it are `--spec-type draft-mtp --spec-draft-n-max N
--spec-draft-p-min P` on the fork's `llama-server`.

Notes:
- Drafting makes its own pass over the prompt, so prefill is somewhat slower
  with it on; decode is where it pays. On long-prompt, short-answer workloads
  try `BONSAI_SPECULATIVE=0` and compare.
- Verify engagement via the API response `timings` (`draft_n` > 0).
- The head is inert when drafting is off: the `-mtp` file behaves exactly like
  the plain file (llama-cli included), at +0.2 GiB on disk.

## Earlier families (DSpark drafters)

**Bonsai 2 27B has no official DSpark drafter released yet.**
`BONSAI_SPECULATIVE=1` warns and runs without speculation when using the demo's
`bonsai2` family, even if a drafter file is present in its model directory.
The paired drafters and speed measurements below apply to the previous-generation
`ternary` and `bonsai` 27B families.

Community experiments are described in [#188](https://github.com/PrismML-Eng/Bonsai-demo/pull/188)
and [#189](https://github.com/PrismML-Eng/Bonsai-demo/pull/189); these have not yet been
fully reviewed or validated by the maintainers and require their documented runtime
changes. Converting an older drafter alone does not establish Bonsai 2 compatibility.
For those experiments, follow the contributor's manual launch instructions. The shell
launcher's explicit `BONSAI_GGUF` custom-model path also retains drafter discovery;
it does not validate that the drafter matches the target.

> Note (prism-v7): the published previous-generation 27B DSpark drafter GGUFs
> predate the v7 format convergence and do not load on v7 builds as-is. Convert
> them once with the two commands below.

## Converting the published drafter (older models)

The converter ships with the fork (gguf-py, command `gguf-dspark-to-dflash`).
Convert from the published bf16 drafter (NOT the Q4_1, which contains a legacy
tensor), using the target model as the tokenizer donor, then quantize:

```
gguf-dspark-to-dflash --drop-shared-tensors \
    models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-bf16.gguf \
    models/ternary-gguf/27B/Ternary-Bonsai-27B-PQ2_0.gguf \
    /tmp/drafter-conv.gguf
llama-quantize /tmp/drafter-conv.gguf \
    models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-dflash-Q4_0.gguf Q4_0
```

The output name must keep `dspark-dflash` in it, which is what
`BONSAI_SPECULATIVE=1` looks for. `--drop-shared-tensors` omits the embedding
and lm head (the runtime borrows the target's), shrinking the drafter to about
0.6 GB with unchanged acceptance.

As of prism-v7, dspark rides on mainline llama.cpp's own DSpark implementation (upstream `draft-dspark`, [#25173](https://github.com/ggml-org/llama.cpp/pull/25173)) with a few fork-side patches on top (log-SNR conditioning, layout auto-detection from the model, the drafter converter; some of these will be proposed upstream). The fork supports DSpark on CUDA and Apple Silicon. Measured decode gains on the 27B are strongly workload-dependent (code and math draft best, casual chat worst). On an L40S (CUDA): 1.8-2.4x for the ternary 27B (2.06x blended) and 1.4-1.75x for the 1-bit 27B (1.60x blended). On an M5 Max (Metal) only ternary code/math workloads gain (~1.2x); chat/reasoning and the 1-bit family come out slower, so it is not recommended on Apple Silicon. Full per-workload tables: [community-benchmarks](community-benchmarks/README.md).

The previous-generation Bonsai-27B and Ternary-Bonsai-27B models have paired DSpark drafters. The downloader fetches the BF16 drafter with the 27B weights. Use the conversion above for a legacy drafter. On code and math workloads the measured CUDA decode gain is roughly **1.75-2.4x**. Acceptance varies by workload.

DSpark uses exact token matching against batched target verification at temperature 0. The [GB10 Bonsai 2 experiment](community-benchmarks/ternary-bonsai/cuda-gb10-bonsai2-27b-linux.md#exactness) matched plain generation in 37 of 65 outputs per drafter. Both drafters first diverged at the same positions in the other 28 outputs.

Drafters are **target-specific**: each one only accelerates the exact model it is paired with. The demo downloads the matching drafter for the `ternary` or `bonsai` 27B family you select.

## Enable it

```bash
BONSAI_FAMILY=ternary BONSAI_MODEL=27B BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh
```

Windows:

```powershell
$env:BONSAI_FAMILY = "ternary"
$env:BONSAI_MODEL = "27B"
$env:BONSAI_SPECULATIVE = "1"
.\scripts\start_llama_server.ps1
```

Under the hood the script adds `-md <drafter> --spec-type draft-dspark --spec-draft-n-max 4 -ngld 999 -np 1` and raises the context to 16384 (speculative runs re-prefill each request, and the model likes room to think).

## Manual llama-server invocation (tested on CUDA)

If you run llama-server directly instead of through the start script, this is the equivalent invocation (tested working on CUDA):

```bash
bin/cuda/llama-server \
  -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_g64.gguf \
  -md models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-dflash-Q4_0.gguf \
  --spec-type draft-dspark --spec-draft-n-max 4 \
  -ngl 999 -ngld 999 -fa on -c 16384 -np 1 \
  --host 127.0.0.1 --port 8080
```

Then check that speculation is engaged and measure the speed from any request's `timings`:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Implement quicksort in Python."}],"max_tokens":400}' \
  | jq '.timings | {predicted_per_second, draft_n, draft_n_accepted}'
```

On a datacenter-class CUDA GPU, a code prompt like this measured roughly 70 tok/s without the drafter and 135 tok/s with it, at about 0.9 acceptance.

Notes:

- Use n-max 4 for the paired previous-generation drafters in this guide. The separate [GB10 Bonsai 2 experiment](community-benchmarks/ternary-bonsai/cuda-gb10-bonsai2-27b-linux.md#illustrative-server-configuration) measured n-max 5 with a block-size-7 drafter and the runtime fix.
- Use a roomy `-c` (16384+): the model regularly thinks 1.5-2k tokens before the visible answer, and small contexts truncate responses mid-answer.

## Trade-offs (why it is off by default)

- **Cross-request prompt-cache reuse is disabled**: every request re-processes the full conversation history, so multi-turn chat gets slower first tokens.
- **Single slot** (`-np 1`): one request at a time.
- Because of both, the Open WebUI agentic demo intentionally stays on the normal cached path; speculative lives on the standalone chat server only.

## Verify it is engaged

Each API response's `timings` object includes `draft_n` and `draft_n_accepted`. If `draft_n` is missing or zero, speculation is not active. For a before/after showcase, run a second plain server on another port and compare tok/s on the same prompt.

## CLI one-shot

`llama-cli` has no draft-model support. The one-shot speculation binary is `llama-speculative-simple` (included in the prebuilt binaries):

```bash
bin/mac/llama-speculative-simple \
  -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_g64.gguf \
  -md models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-dflash-Q4_0.gguf \
  --spec-type draft-dspark --spec-draft-n-max 4 \
  -ngl 999 -ngld 999 -c 8192 -n 400 --temp 0 -e \
  -p "<|im_start|>user\nImplement binary search in Python.<|im_end|>\n<|im_start|>assistant\n"
```

The prompt must be hand-chat-templated as above (raw prompts make the instruct model stop immediately). It prints decode speed plus `n_drafted` / `n_accept` / accept rate at the end.
