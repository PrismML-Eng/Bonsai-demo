# Games: one prompt, one HTML file

Each folder here is a game (or page) written end to end by Bonsai 27B working as an agent in
[Hermes](https://github.com/NousResearch/hermes-agent), served by this repo's llama.cpp build. Every page is the
model's output, unedited. The one change is that three.js loads from the shared local copy in [`vendor/`](vendor/)
(one folder per three.js version, with its MIT license) instead of a CDN, so the games play offline. Each folder holds
the exact prompt (`prompt.md`), the playable pages and the settings each one was made with.

| game | prompt | setting | play |
|---|---|---|---|
| [Neon Racer](neon-racer/) | 3D night-city street racer, three laps | 48k thinking budget (runs 1–3), 16k with 150 calls (run 4) | [run 4](neon-racer/game-run4/racer.html) · [run 1](neon-racer/game-run1/racer.html) · [run 2](neon-racer/game-run2/racer.html) · [run 3](neon-racer/game-run3/racer.html) |

Open the pages from a local clone. If your browser restricts local files (run 1 loads three.js as an ES module, which
Chrome blocks from `file://`), serve this folder with `python3 -m http.server 8768` and open `http://localhost:8768/`.

## Run one yourself

```bash
./setup.sh                                   # once: binaries + model + vision projector
./scripts/agent/install_hermes.sh            # once: Hermes c387be0 + the four patches in scripts/agent/patches/

# terminal 1: the server, game setting (16k thinking budget, 49,152 tokens per reply)
AGENT_PROFILE=game16 ./scripts/start_agent_server.sh
# terminal 2
./scripts/agent/run_agent_demo.sh game neon-racer
grep -m1 -o '"max_tokens": [0-9]*' agent-runs/neon-racer_*/wire.jsonl   # 49152
```

`run_agent_demo.sh game <folder>` gives the model that folder's `prompt.md` as `TASK.md` in a fresh workspace and
uses the game setting below. The deliverable lands in `agent-runs/<name>/workspace/`, the full wire log (every
request and response, thinking included) in `agent-runs/<name>/wire.jsonl`, and the settings the run actually used in
`agent-runs/<name>/run.txt`.

**This command gives the current game setting, not the settings the published games were made with.** Those differ
per run; the game's README lists the exact overrides that reproduce each one's settings (for Neon Racer:
[neon-racer/README.md](neon-racer/README.md#settings-per-run)). A rerun is a new sample either way: sampling is random,
so the same settings write a different game.

## The game setting

| | `game16` (default) | `game48` |
|---|---|---|
| server | `AGENT_PROFILE=game16`: context 262,144, thinking budget 16,384, **49,152 tokens per reply** (`-n`) | `AGENT_PROFILE=game48`: context 262,144, thinking budget 49,152, 65,536 tokens per reply |
| per-reply cap | the server's `-n`, also written into the Hermes config (`model.max_tokens`) and sent by the proxy as every request's `max_tokens`, so all three agree | same (65,536) |
| tool calls | up to 150 (`agent.max_turns`) | same |
| compaction | once the prompt reaches 0.93907518 × (262,144 − 49,152) ≈ 200k tokens | 0.93907518 × (262,144 − 65,536) ≈ 185k |
| sampling | temp 1.0 · top-p 0.95 · top-k 20 · **min-p 0** | same |
| reasoning effort | `xhigh` | same |
| reasoning across turns | **kept** (`AGENT_PRESERVE=1`): Hermes drops earlier reasoning from its history, so `scripts/agent/logproxy.py` re-inserts it and the template renders it (`preserve_thinking`) | same |
| Hermes | `c387be0` + the four patches, two of them switched on by `game` mode: empty replies are resampled (`HERMES_EMPTY_RECOVERY=resample`), and a tool call cut by the per-reply cap is not executed or resent unchanged; the model is told to split the work into smaller calls (`HERMES_PRISM_CUT_RECOVERY=1`) | same |
| MTP draft head | off; `AGENT_MTP=1` on the server turns on the GGUF's built-in draft head (faster decode on CUDA/ROCm, same sampling settings; see [SPECULATIVE.md](../../SPECULATIVE.md)) | same |

The proxy injects seed 42 into every request (`AGENT_SEED`, empty for none). An empty-reply resample is the identical
request, and with the same seed the server would return the same empty reply again. The patched Hermes therefore marks
each resample request (header `X-Agent-Resample: <n>`), and the proxy sends only those with a new seed (42 + n for the
n-th resample) and drops the header. Every other request keeps its seed, even when it repeats an earlier one.
`AGENT_RESEED=0` turns the re-seeding off. Each run records the resamples in
`agent-runs/<name>/empty_recovery.jsonl` and the cut tool calls in `agent-runs/<name>/cut_recovery.jsonl`.

Knobs for other settings: `AGENT_N_PREDICT` and `AGENT_MTP` on the server; `AGENT_MAX_TURNS`,
`AGENT_COMPACT_THRESHOLD`, `AGENT_PRESERVE`, `AGENT_SEED`, `HERMES_PRISM_CUT_RECOVERY` and `HERMES_EMPTY_RECOVERY` on
the runner. With reasoning kept across turns the history grows by about 2.5k tokens per call, so long runs reach
compaction; with `AGENT_PRESERVE=0` it grows about half as fast.

The published runs were picked from several runs of the same prompt, so they show what the model can do, not a success
rate.
