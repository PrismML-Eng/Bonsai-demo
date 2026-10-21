# Prompt reuse and context checkpoints

Repeated prompts can reuse a prefix with the multimodal projector loaded. A warning
that `--cache-reuse` is unsupported does not mean all prompt reuse is disabled.
These are separate mechanisms; the distinction explains the configuration problem
and follow-up results in [issue #147](https://github.com/PrismML-Eng/Bonsai-demo/issues/147).

## The controls

| Control | Purpose |
| --- | --- |
| Request `cache_prompt: true` | Reuse an available common prefix instead of evaluating it again. |
| `--ctx-checkpoints N` | Retain snapshots needed to restore hybrid/recurrent state to earlier prompt positions. |
| `--cache-ram N` | Budget the server's prompt-cache storage in MiB. This is separate from the model's KV allocation. |
| `--cache-idle-slots` | Allow idle-slot state to be saved into the server prompt cache. |
| `--cache-reuse N` | Reuse matching chunks through cache shifting. This mechanism is disabled for multimodal or non-shiftable hybrid memory. |

An explicit command-line flag overrides its corresponding `LLAMA_ARG_*` environment
variable. Setting environment variables will not enable checkpoints if a custom
launcher still passes `--ctx-checkpoints 0`. Check the startup log and wrapper flags.
The demo launcher forwards extra arguments; use those for explicit overrides.

## Long, repeated conversations

To test the reporter's successful cache settings with the demo launcher:

```bash
./scripts/start_llama_server.sh \
  --parallel 1 --cache-ram 4096 --ctx-checkpoints 32 --cache-idle-slots
```

The cache budget is 4 GiB; choose a budget appropriate to available memory. Keep
speculative decoding disabled for this check: the demo's experimental speculative
path has separate prompt-cache restrictions. Loading the projector does not require
a separate text-only server to obtain prefix reuse.

Send the same request twice, to the same idle slot, with `cache_prompt: true`. Compare
the response's `timings.prompt_n` and `timings.prompt_ms`, and the server's checkpoint
restore messages. A hit can still evaluate a short suffix, including the final tokens
needed for logits; it need not report zero processed tokens. Changing a prompt's
leading text or tool ordering can reduce the common prefix.

Then repeat with `cache_prompt: false` as a full-recomputation control. Keep model,
KV precision, batch sizes, and sampling settings fixed. Do not infer reuse solely
from a warning about `--cache-reuse` or from completion latency, which includes decode.

## Short prompts and numerical comparisons

Checkpoint creation can split prefill at message boundaries and near the end of the
prompt. In the revision reported in #147, one boundary is four tokens before the
end. A 512-token prefill can therefore run as 508 + 4 tokens rather than one batch.
Extra batches and state copies can dominate a short request's prefill time.

`cache_prompt: false` prevents reading a previous prompt's prefix; it does not disable
the server's checkpoint creation or the associated batch splits. This explains why
turning checkpoints on can affect a fresh server's first request.

Different batch shapes can change floating-point results. Greedy sampling does not
guarantee identical output across those shapes: a small logit change can select a
different token and alter the continuation. The reporter's matching long-prompt
outputs are useful evidence for those requests, not a guarantee for every length.

For short independent requests, compare against a server with checkpoints disabled:

```bash
./scripts/start_llama_server.sh --parallel 1 --ctx-checkpoints 0
```

Vary only this flag initially. Disabling all three cache controls together obscures
the cause and removes the long-prefix benefit. Do not adopt
`--cache-ram 0 --ctx-checkpoints 0` as a general workaround for multimodal serving.

To investigate a numerical discrepancy, distinguish two comparisons: restored
checkpoint versus full recomputation under the same checkpoint settings, and
checkpoints on versus off with different prefill segmentation. Save exact requests,
generated token IDs, server version, batch/ubatch sizes, KV types, and verbose logs.
Compare logits before treating a changed completion hash as evidence of state corruption.
