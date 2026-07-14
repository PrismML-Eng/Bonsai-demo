# Speculative decoding (experimental)

⚠️ **Highly experimental.** Try it for fun and only if you know what you are doing; expect it to change and be polished in later releases. The path is currently stable and fast on CUDA; Apple Silicon (Metal) support will be improved in a later release, so do not expect a speedup on Macs yet.

The 27B models ship with a paired **dspark drafter**: a small companion GGUF (`*dspark-Q4_1*.gguf`, downloaded automatically with the 27B weights) that drafts blocks of tokens for the target model to verify. On code and reasoning workloads this gives roughly **1.8-2x faster decode** on CUDA; acceptance is workload-dependent, so casual chat gains less. Output at temperature 0 is identical to normal decoding.

Drafters are **target-specific**: each one only accelerates the exact model it was trained against. The demo downloads the matching drafter for whichever 27B family you use.

## Enable it

```bash
BONSAI_SPECULATIVE=1 ./scripts/start_llama_server.sh
```

Windows:

```powershell
$env:BONSAI_SPECULATIVE = "1"
.\scripts\start_llama_server.ps1
```

Under the hood the script adds `-md <drafter> --spec-type draft-dspark --spec-draft-n-max 4 -ngld 999 -np 1` and raises the context to 16384 (speculative runs re-prefill each request, and the model likes room to think).

## Manual llama-server invocation (tested on CUDA)

If you run llama-server directly instead of through the start script, this is the equivalent invocation (tested working on CUDA):

```bash
bin/cuda/llama-server \
  -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf \
  -md models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-Q4_1.gguf \
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

- `--spec-draft-n-max` must equal the drafter's block size (4 for the current drafters); a smaller value crashes at the first draft round.
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
  -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf \
  -md models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-Q4_1.gguf \
  --spec-type draft-dspark --spec-draft-n-max 4 \
  -ngl 999 -ngld 999 -c 8192 -n 400 --temp 0 -e \
  -p "<|im_start|>user\nImplement binary search in Python.<|im_end|>\n<|im_start|>assistant\n"
```

The prompt must be hand-chat-templated as above (raw prompts make the instruct model stop immediately). It prints decode speed plus `n_drafted` / `n_accept` / accept rate at the end.
