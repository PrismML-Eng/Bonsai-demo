# Local API smoke checks

`scripts/smoke_local_api.py` checks an already running server. It does not install
models, start a server, execute generated code, or access real inventory. It uses
only the Python standard library and is opt-in, not part of automatic GPU CI.

Start the appropriate Bonsai server first, then pass the exact model ID exposed
by `/v1/models`. `--base-url` is the server root, without `/v1`:

```bash
python3 scripts/smoke_local_api.py \
  --base-url http://127.0.0.1:8080 --model YOUR_MODEL_ID \
  --output smoke-medium.json
```

The default checks require a nonempty final text answer and a complete native
tool loop. The inventory tool deliberately returns a transient error once;
the model must retry the same lookup, consume synthetic stock/reserved values,
and return the calculated available quantity. Tool names and arguments are
validated; no model-supplied code or arbitrary function is executed.

The client sends fixed sampling settings on every chat request: `seed=42`,
`temperature=1.0`, `top_p=0.95`, `top_k=20`, `min_p=0.05`,
`presence_penalty=0.0`, and `repeat_penalty=1.0`, with `max_tokens=16384`.
These checks exercise those settings, not your usual client or UI settings.
`--reasoning-effort` selects `medium` (default) or `xhigh`.

For a protected endpoint, set `BONSAI_API_KEY`, or specify the name of an existing
environment variable with `--api-key-env`. Its value is not included in the JSON
report. Keep report files local unless you intend to share the model output.

## Optional context retrieval

This check additionally requires the llama-server `/tokenize` endpoint. It builds
a deterministic synthetic document with a target code near its middle, measures
the document token count, and asks for that code. It is not a general long-context
quality benchmark. The server context must fit the document, template, question,
and up to 16384 output tokens; use a 64K server for the 48K example.

```bash
python3 scripts/smoke_local_api.py \
  --base-url http://127.0.0.1:8080 --model YOUR_MODEL_ID \
  --reasoning-effort xhigh --cases context --context-tokens 48000 \
  --output smoke-context.json
```

`--cases` selects `text`, `tools`, and/or `context`. `--timeout` is the timeout for
each HTTP request (default 300 seconds), not a wall-clock limit for the whole run.
Tool execution is bounded to six model turns. Existing output files are refused
before any requests are sent. Exit status is zero only when all selected checks
pass; failures, including timeouts or truncated generations, are recorded and
return a nonzero status. Reports contain request timing and usage where supplied
by the server, final answers, and individual check results, not reasoning traces.
Every HTTP request, including tokenization and failed requests, records its path,
duration, HTTP status when available, and success flag. HTTP errors retain the
server response body. A failed context answer is saved alongside the measured
document token count so the report shows what the model actually returned.

These are model-dependent smoke checks. A wrong answer does not establish a
runtime defect, and a pass does not establish general reasoning accuracy. Run
deterministic harness tests without a server or GPU using:

```bash
python3 -m unittest discover -s tests -p test_smoke_local_api.py
```
