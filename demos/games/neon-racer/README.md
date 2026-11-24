# Neon Racer

A 3D night-city street racer: rain-slick asphalt, neon signs, traffic, drift and nitro, three laps, a lap timer and a minimap. Four runs of the same prompt.

- Prompt, exactly as the model got it: [prompt.md](prompt.md). The "Operational notes" at the end were part of it.
- Play: [run 4](game-run4/racer.html) (newest) · [run 1](game-run1/racer.html) · [run 2](game-run2/racer.html) · [run 3](game-run3/racer.html)

| run | setting | notes |
|---|---|---|
| 1 | `game48`, reasoning dropped between turns (`AGENT_PRESERVE=0`) | the run stopped at its turn limit; the page is the last one it saved |
| 2 | `game48`, reasoning kept | logs a console error from the traffic loop; the game plays |
| 3 | `game48`, reasoning kept | an earlier checkpoint of the same model. The model downloaded three.js itself, so its files are unchanged |
| 4 | `game16`, reasoning kept, call limit raised to 150 (`agent.max_turns: 150`), compaction at ~200k | finished on its own after 130 calls; served with the MTP draft head |

Run it yourself: see [the games README](../README.md#run-one-yourself). Game logic is unedited. The only change is that
three.js loads from a local `vendor/` copy instead of the CDN the model linked.
