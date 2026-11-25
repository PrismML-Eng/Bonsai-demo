# Neon Racer

A 3D night-city street racer: rain-slick asphalt, neon signs, traffic, drift and nitro, three laps, a lap timer and a minimap. Four runs of the same prompt.

- Prompt, exactly as the model got it: [prompt.md](prompt.md). The "Operational notes" at the end were part of it.
- Play: [run 4](game-run4/racer.html) (newest) · [run 1](game-run1/racer.html) · [run 2](game-run2/racer.html) · [run 3](game-run3/racer.html)

| run | setting | notes |
|---|---|---|
| 1 | `game48`, reasoning dropped between turns, 90 calls | the run stopped at its call limit; the page is the last one it saved |
| 2 | `game48`, reasoning kept, 90 calls | logs a console error from the traffic loop on some loads; the game plays |
| 3 | `game48`, reasoning kept, 90 calls | made with an earlier version of the model weights, before the published ones. The model downloaded three.js r160 itself |
| 4 | `game16` with 32,768 tokens per reply, reasoning kept, 150 calls, MTP draft head on | finished on its own after 130 calls |

Game logic is unedited. The only change is that three.js loads from the shared copy in [`../vendor/`](../vendor/)
instead of the CDN the model linked (run 3: instead of the copy the model had downloaded next to the page).

## Settings per run

`./scripts/agent/run_agent_demo.sh game neon-racer` with `AGENT_PROFILE=game16 ./scripts/start_agent_server.sh` runs the
**current** game setting (150 calls, 16k thinking, 49,152 tokens per reply, compaction at ~200k, cut tool-call recovery
on; see [the games README](../README.md#the-game-setting)). **None of the four published runs used exactly that.** These
commands reproduce the settings of each run (terminal 1 the server, terminal 2 the run). They do not reproduce the
sample: the published runs used no fixed seed (hence `AGENT_SERVER_SEED=` and `AGENT_SEED=`), and any rerun writes a
different game.

Runs 1 and 2: 48k thinking budget, 65,536 tokens per reply, 90 calls, compaction at 0.85 × (262,144 − 65,536) ≈ 167k,
no cut tool-call recovery (it did not exist yet). Run 1 dropped reasoning between turns.

```bash
AGENT_PROFILE=game48 AGENT_SERVER_SEED= ./scripts/start_agent_server.sh
# run 1
AGENT_SEED= AGENT_PRESERVE=0 AGENT_MAX_TURNS=90 AGENT_COMPACT_THRESHOLD=0.85 HERMES_PRISM_CUT_RECOVERY=0 \
  ./scripts/agent/run_agent_demo.sh game neon-racer
# run 2
AGENT_SEED= AGENT_MAX_TURNS=90 AGENT_COMPACT_THRESHOLD=0.85 HERMES_PRISM_CUT_RECOVERY=0 \
  ./scripts/agent/run_agent_demo.sh game neon-racer
```

Run 3: the run 2 settings, but with earlier model weights that are not published, so it cannot be rerun with this
repo's model.

Run 4: 16k thinking budget, 32,768 tokens per reply, 150 calls, compaction at 0.872 × (262,144 − 32,768) ≈ 200k, no cut
tool-call recovery, served with the MTP draft head.

```bash
AGENT_PROFILE=game16 AGENT_N_PREDICT=32768 AGENT_MTP=1 AGENT_SERVER_SEED= ./scripts/start_agent_server.sh
AGENT_SEED= AGENT_COMPACT_THRESHOLD=0.872 HERMES_PRISM_CUT_RECOVERY=0 ./scripts/agent/run_agent_demo.sh game neon-racer
```

In every case `agent-runs/<name>/run.txt` shows the settings the run used (calls, compaction threshold, per-reply cap
in the config and per request, seed, cut recovery), and `server-props.json` the server's.
