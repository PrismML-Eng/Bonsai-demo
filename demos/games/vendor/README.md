# three.js, vendored

Byte-identical copies of the published `three` npm package, one folder per version the games load, each with that
version's MIT license (`LICENSE`). Paths inside a folder follow the package layout.

| folder | npm version | used by |
|---|---|---|
| `three-r127/` | `three@0.127.0`: `build/three.min.js` | Neon Racer run 2 |
| `three-r128/` | `three@0.128.0`: `build/three.min.js` | Neon Racer run 4 |
| `three-r160/` | `three@0.160.0`: `build/three.min.js`, `build/three.module.js`, the postprocessing and shader modules under `examples/jsm/` | Neon Racer runs 1 (ES modules) and 3 (`three.min.js`) |
