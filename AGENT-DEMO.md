# Agentic demo: Bonsai 2 builds a skateboard game

Bonsai 2 27B, running as a 2-bit GGUF on one GPU through this repo's llama.cpp fork, driving the
[Hermes](https://github.com/NousResearch/hermes-agent) agent: it writes a 3D game from a two-line brief,
loads it in a headless browser, plays it, looks at a screenshot, and ships it. Then it takes a round of
plain-English feedback. Everything here is what the model produced, unedited, and everything needed to
run it again is in this folder.

- 59-second clip: [`demos/skateboard/demo_clip_seed42_59s.mp4`](demos/skateboard/demo_clip_seed42_59s.mp4)
- Playable pages: [round 0](demos/skateboard/pages/round0.html) · [round 1, flips and coins](demos/skateboard/pages/round1.html)
- Replay page with the model's trace beside the game: [`demos/skateboard/replay/index.html`](demos/skateboard/replay/index.html) (open it from a clone; it embeds the trace and loads the pages above)

| round | prompt (verbatim) | result | calls | tokens | wall |
|---|---|---|---|---|---|
| 0 | `Make a simple 3d skateboard game in a single html file.` + `(Name the file skateboard.html in the current directory.)` | road, visible skater, trees, obstacles, distance HUD, game over and restart; the model verified it in its own browser | 8 | 23,239 | 4 min 8 s |
| 1 | `can you make it so that we do flips/tricks in the air? also would be nice to have some coins to collect` | F front flip, R spin, coins with a counter, trick HUD | 17 | 40,919 | 7 min 45 s |

The prompts are in [`demos/skateboard/prompts/`](demos/skateboard/prompts/). Feedback rounds hand the
model the previous round's `skateboard.html` in its working directory plus one sentence saying whose file it is.

## Run it

All commands below run from the repository root, the `Bonsai-demo` folder you cloned (the same place the
README's quick start runs `setup.sh`). Prerequisites beyond `setup.sh`: `git`, `uv` (Python packaging) and Node.js 24+ (Hermes's browser tool `agent-browser` 0.38.1 is a
Node package that declares Node >= 24; the installer pins that version in `.agent-browser/` and the runner puts it first on PATH). About 1.3 GB for the Hermes checkout and its browser build.

```bash
./setup.sh                              # once: fork binaries + Bonsai 2 27B PQ2_0 + vision projector
./scripts/agent/install_hermes.sh       # once: Hermes at the pinned commit into .venv-hermes, plus its headless browser

./scripts/start_agent_server.sh         # terminal 1: llama-server with the agent profile (below)
./scripts/agent/run_agent_demo.sh round0                                                        # terminal 2
./scripts/agent/run_agent_demo.sh feedback agent-runs/sk16_skateboard_1     demos/skateboard/prompts/round1-feedback.md sk16_skateboard_1_fb1
```

Hermes talks to llama-server directly; nothing sits in between and nothing in Hermes or llama.cpp is modified.
Each run writes `agent-runs/<name>/`: `workspace/skateboard.html` (the deliverable), `run.txt` (the settings the
run used), `server-props.json` (what llama-server reported), `stdout.log`. With `AGENT_TRACE=1` the runner also
puts a small logging proxy in the path and writes `wire.jsonl`, every request and response including the model's
thinking; that is how the recordings behind the replay page were captured. Follow a run with
`tail -f agent-runs/sk16_skateboard_1/stdout.log`; round 0 took 4 min 8 s on an
H200 from launch to the last model reply (most of it the 20,206-token first turn at about 100 tok/s); expect longer on
an M-series Mac. Times in the table are launch-to-last-reply wall clock.

Hermes runs with `--yolo`: it executes the commands the model writes on this machine, as your user, with no
confirmation. The private workspace keeps its files apart; it is not a sandbox. Run it on a machine where that is
acceptable.

## The settings

Server, from `scripts/start_agent_server.sh` on top of `start_llama_server.sh`:

```
llama-server -m Ternary-Bonsai-2-27B-PQ2_0.gguf --mmproj Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf \
  -ngl 99 -fa on -c 131072 --jinja \
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 \
  --reasoning-format deepseek --reasoning-budget 16384 --parallel 1 --alias bonsai2-27b-pq2-v16_2 -s 42
```

| setting | value | why |
|---|---|---|
| sampling | temp 1.0 · top_p 0.95 · top_k 20 · min_p 0 · presence 0 · repeat 1.0 | the model card's thinking-mode values. min_p must be passed: llama.cpp's default is 0.05 |
| reasoning | template default (`xhigh`), `--reasoning-format deepseek`, budget 16,384 thinking tokens per turn | thinking arrives in `reasoning_content`; Hermes sends only the visible answer back, so each turn thinks afresh. The budget caps runaway thinking |
| context | 131,072 for the exact recording; `BONSAI_CTX=262144` recommended | at 131k Hermes compresses the history on long runs; at 262k it never did in our tests |
| output | Hermes `max_tokens 32768` | the planning turn writes the whole page in one go and must fit |
| seed | 42, the server's `-s 42` (`AGENT_SERVER_SEED`, default 42); the runner refuses to start against a server whose seed differs from `AGENT_SEED` | a fixed seed keeps the sampler repeatable; one slot, so a server seed equals a per-request seed. The recording injected 42 per request through the trace proxy, same effect |
| Hermes | 0.18.2 at commit `c387be0`, browser tool `agent-browser` 0.38.1 (pinned in `.agent-browser/` by the installer, first on PATH at run time); `scripts/agent/hermes-config-round0.yaml` (context 131,072, max_tokens 32,768, coding mode off, verify-on-stop off, tools file · terminal · coding · web · search · browser); feedback rounds use `hermes-config-feedback.yaml` (8-turn limit) | the recorded configuration, verbatim; the workspace lives outside any git repo because Hermes changes profile inside one |
| model | `Ternary-Bonsai-2-27B-PQ2_0.gguf` 7,206,168,928 bytes, sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1` · `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` 629,246,976 bytes, sha256 `6807ede61d570bb86ba34b756a0fa109edc33668604de867c6ea6d8f1d631903` | |

## What to expect

Seed 42 is sent with every request, and the server runs one slot, so the model's output for a given transcript
is stable. Runs still differ from each other: the agent checks its page in a headless browser between turns, the
game is running while it looks, and a screenshot or a console read taken a second later says something else.
Runs therefore share the same opening and part ways in the verification steps, ending with pages that play the
same but are not necessarily identical files. Whether the page comes out well also depends on the system prompt
Hermes builds (model id, working directory, skill list). The scripts pin the model id to the recorded one; the working
directory is a fresh per-user path and the shipped skill text was tidied after the recording, so a run here is its own
sample, not a replay of the video.

On this brief without a seed, the same setting produced a good page in 2 to 4 of every 9 attempts in our runs.
The video is one attempt with seed 42.

## Knobs

- `AGENT_UPSTREAM=host:port` runs the agent against a server elsewhere (a GPU box) from your laptop.
- `AGENT_TRACE=1` records `wire.jsonl` through `scripts/agent/logproxy.py` and injects `AGENT_SEED` / `AGENT_EFFORT`
  into every request (Hermes sends neither to a custom provider). Off by default: the demo needs no proxy.
- `AGENT_EFFORT=medium` (with `AGENT_TRACE=1`) sends `reasoning_effort: medium` with every request; without the trace pass `--chat-template-kwargs '{"reasoning_effort":"medium"}'` to the server. On the skateboard brief this
  finished in seconds and produced weaker pages; keep the default for the demo.
- `AGENT_REASONING_BUDGET=20480` on the server: the setting that produced our best unseeded skateboard pages.
- `./scripts/agent/run_agent_demo.sh task my-brief.md my-run` runs any brief with the same harness.
