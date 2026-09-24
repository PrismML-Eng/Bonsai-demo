# Skatepark: from first draft to rider and controls

**A separate run from the H200 skateboard recording and the other skateboard examples in this repository.** This example was generated on an RTX PRO 6000 with Bonsai 2 27B PQ2_0. It starts from the original skateboard brief, then follows three user requests. It is not a continuation or reproduction of Hajir’s saved games.

- [Watch the edited clip](skatepark-iteration.mp4): gameplay recorded afterward on a Mac, with native game audio and the feedback shown beneath each round.
- [Open the recorded trace replay](replays/pro6000/index.html): select a round and response to inspect the recorded reasoning, answer and tool-call arguments beside that round’s final page.
- Play [round 0](games/pro6000-round0/skateboard.html), [round 1](games/pro6000-round1/skateboard.html), [round 2](games/pro6000-round2/skateboard.html), or [round 3](games/pro6000-round3/skateboard.html).
- [Exact prompts](prompts/) and [structured response traces](replays/pro6000/replay-data.json).

Open from a local clone; the games bundle Three.js and its MIT license. If local-file restrictions interfere, serve this directory with `python3 -m http.server 8768` and open `http://localhost:8768/replays/pro6000/index.html`. Click the game before using the arrow keys, Space, J and K.

## The four rounds

| Round | Request | Result | Recorded responses | Output tokens | Elapsed |
|---|---|---|---:|---:|---:|
| 0 | Make a simple 3D skateboard game in one HTML file. | Skateboard, ramps and airborne tricks; no clearly visible rider. | 6 | 40,875 | 6m 48s |
| 1 | Add flips/tricks and coins to collect. | Coins and refined tricks, after a lengthy repair/verification loop. | 33 | 99,503 | 21m 15s |
| 2 | The skater is not visible; add a rider while keeping the existing features. | Visible rider with a red cap, torso, arms and legs. | 68 | 137,010 | 24m 53s |
| 3 | Left/right controls are swapped; fix them and keep everything else. | Corrected movement direction. | 24 | 55,384 | 9m 06s |

Requests above are summaries; the prompt files contain the exact text. Elapsed time is launch to last captured model response, including tool execution and recovery. Response/token counts include auxiliary calls, not just main agent turns. Total time was approximately 62 minutes. These are not standardized inference throughput measurements.

## Recorded configuration

- Demo checkout: `61060a8542318772f7f6c80e9d6bc9c16e7a3054`.
- Runtime: `prism-b10709-9a9394a`, CUDA 12.8 binaries, RTX PRO 6000 Blackwell 96 GB.
- Target: `Ternary-Bonsai-2-27B-PQ2_0.gguf`, SHA-256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`.
- Vision projector: `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`, SHA-256 `6807ede61d570bb86ba34b756a0fa109edc33668604de867c6ea6d8f1d631903`.
- Hermes `c387be08b9`; agent-browser `0.38.1`.
- Temperature 1.0, top-p 0.95, top-k 20, **min-p 0**, seed 42 injected per request through the trace proxy.
- Context 131,072; one slot; thinking budget 16,384; maximum output 32,768 tokens per response; template reasoning effort `xhigh`.
- Original run identifiers: `sk16_skateboard_1`, followed by `_fb1`, `_fb2`, `_fb3`.

These are historical settings, not a recommendation to replace current defaults. Workspace paths, tool observations, hardware and prompt construction affect the transcript; a seed alone does not reproduce the same result. This is one selected successful sequence, not a success-rate comparison.

## Artifact provenance

The game folders, replay HTML/JSON and video are copied byte-for-byte from the existing reviewed export. The export had already replaced the external Three.js URL with a bundled library and normalized known host/workspace paths in response data. No game logic or trace content was edited for this PR.

The replay is a **recorded response viewer**, not a live model session or a reconstruction of intermediate HTML revisions. It displays each final saved page throughout that round’s trace. Agent claims in the trace remain the agent’s claims. The video is a condensed capture of saved gameplay, not real-time generation; its audio alignment was measured by matching simultaneous canvas/full-page recordings.

Raw request logs, system prompts, environment dumps, model weights and inference binaries are not included. The export contains response text and tool-call arguments; the source raw logs remain separate. The video editing kit and other hardware/sampler experiments are not part of this example.
