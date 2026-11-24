# Games: one prompt, one HTML file

Each folder here is a game (or page) written end to end by Bonsai 27B working as an agent in
[Hermes](https://github.com/NousResearch/hermes-agent), served by this repo's llama.cpp build. Every page is the
model's output, unedited. The one change is that three.js loads from a local `vendor/` copy instead of a CDN, so the
games play offline. Each folder holds the exact prompt (`prompt.md`), the playable page and the
settings to run it again.

| game | prompt | setting | play |
|---|---|---|---|
| [Neon Racer](neon-racer/) | 3D night-city street racer, three laps | 48k thinking budget (runs 1–3), 16k with 150 calls (run 4) | [run 4](neon-racer/game-run4/racer.html) · [run 1](neon-racer/game-run1/racer.html) · [run 2](neon-racer/game-run2/racer.html) · [run 3](neon-racer/game-run3/racer.html) |

Open the pages from a local clone. If your browser restricts local files, serve this folder with
`python3 -m http.server 8768` and open `http://localhost:8768/`.

## Run one yourself

```bash
./setup.sh                                   # once: binaries + model + vision projector
./scripts/agent/install_hermes.sh            # once: Hermes c387be0 + the patches in scripts/agent/patches/

# terminal 1: the server (Neon Racer was made with game48: 48k thinking budget, 64k replies; game16 is enough for most prompts)
AGENT_PROFILE=game48 ./scripts/start_agent_server.sh
# terminal 2
./scripts/agent/run_agent_demo.sh game neon-racer
grep -m1 -o '"max_tokens": [0-9]*' agent-runs/neon-racer_*/wire.jsonl   # 32768 for game16, 65536 for game48
```


`run_agent_demo.sh game <folder>` gives the model that folder's `prompt.md` as `TASK.md` in a fresh workspace and
uses the game settings below. The per-reply cap comes from the running server's profile: the proxy sets it as `max_tokens` on every request (a request's `max_tokens` overrides the server's `-n`). The deliverable lands in `agent-runs/<name>/workspace/`, and the full wire log (every
request and response, thinking included) in `agent-runs/<name>/wire.jsonl`.

## The settings

`game` mode now runs with up to 120 tool calls and compaction at about 200k tokens. The published games were made
with the earlier setting (90 calls, compaction at about 167k, everything else the same); in our runs the new limits
ended fewer runs at the call cap. A rerun is a new sample either way, so we did not remake the published games.

| | 16k games | 48k games |
|---|---|---|
| server | `AGENT_PROFILE=game16`: context 262,144, thinking budget 16,384, 32,768 tokens per reply | `AGENT_PROFILE=game48`: context 262,144, thinking budget 49,152, 65,536 tokens per reply |
| sampling | temp 1.0 · top-p 0.95 · top-k 20 · **min-p 0** | same |
| reasoning effort | `xhigh` | `xhigh` |
| reasoning across turns | **kept** (`AGENT_PRESERVE=1`, the `game` default): Hermes drops earlier reasoning from its history, so `scripts/agent/logproxy.py` re-inserts it and the template renders it (`preserve_thinking`) | kept, except Neon Racer run 1 (`AGENT_PRESERVE=0`) |
| Hermes | `c387be0` + `hermes_prism_empty_recovery.patch` (empty replies are resampled, `HERMES_EMPTY_RECOVERY=resample`) + `hermes_prism_browser_keepalive.patch` (the browser session survives long thinking gaps) + `hermes_prism_oneshot_max_turns.patch` (one-shot mode honours the configured call limit) | same |
| Hermes config | `scripts/agent/hermes-config-games.yaml`: up to 120 tool calls; compaction once the prompt reaches 0.872 × (context − 32,768), about 200k tokens (published games: 90 calls, ~167k) | same, but compaction at 0.872 × (context − 65,536), about 171k, so a 64k reply still fits |

What to expect when you run one: with the patched Hermes and these configs the model writes a working game most of the
time, but never the same one twice. The `game16` profile (16k thinking, 32k per reply) is enough for most prompts in
our runs; Neon Racer runs 1–3 come from `game48`, run 4 from `game16` with the call limit raised to 150. With reasoning kept across turns (the `game`
default) the history grows by about 2.5k tokens per call, so longer runs are compacted at about 200k (roughly 40% of
runs in our 120-call tests). With `AGENT_PRESERVE=0` it grows about half as fast and compaction is rarely needed.

The published runs were picked from several runs of the same prompt, so they show what the model can do, not a success
rate. Sampling is random: a rerun with the same settings writes a different game.
