# Neon Racer

A 3D night-city street racer: rain-slick asphalt, neon signs, traffic, drift and nitro, three laps, a lap timer and a minimap. Three runs of the same prompt.

- Prompt, exactly as the model got it: [prompt.md](prompt.md). The "Operational notes" at the end were part of it.
- Play: [run 1](game-run1/racer.html) · [run 2](game-run2/racer.html) · [run 3](game-run3/racer.html)

| run | setting | notes |
|---|---|---|
| 1 | `game48`, reasoning dropped between turns (`AGENT_PRESERVE=0`) | the run stopped at its turn limit; the page is the last one it saved |
| 2 | `game48`, reasoning kept | logs a console error from the traffic loop; the game plays |
| 3 | `game48`, reasoning kept | an earlier checkpoint of the same model. The model downloaded three.js itself, so its files are unchanged |

Run it yourself: see [the games README](../README.md#run-one-yourself). Game logic is unedited. The only change is that
three.js loads from a local `vendor/` copy instead of the CDN the model linked.
