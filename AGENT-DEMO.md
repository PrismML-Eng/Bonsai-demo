# Agentic demo: BonsaiOS

Bonsai 2 27B drives Hermes to write a browser desktop from this prompt:

> Using HTML, JS and CSS, generate a browser-based OS.

Five feedback messages address startup, usable apps, dragging/calculator input,
file editing/window focus, and finally BonsaiOS branding. Bonsai writes and patches
all HTML through file tools. The same Hermes conversation continues throughout.

[Open the generated BonsaiOS page](demos/bonsaios/os.html). It includes Files,
Terminal, Notes, Calculator, Settings, About, theme changes, and window management.

## Clone, set up, run

Run these commands on **Linux x86_64 with an NVIDIA GPU**. Exact reproduction has
been verified on **one H200 with NVIDIA driver 570.172.08**. Other GPUs or drivers
may generate different bytes. Prerequisites: Git, Python 3.11+, and
[uv](https://docs.astral.sh/uv/getting-started/installation/). Allow about 12 GB of
free disk space for downloads, dependencies, and a complete recorded run.

```bash
git clone --branch agent-demo-bonsaios https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo
python3 demos/bonsaios/setup.py
./scripts/run_bonsaios.sh --output bonsaios-runs/my-os
```

Open `bonsaios-runs/my-os/os.html` when the run finishes. To serve it locally:

```bash
python3 -m http.server 8000 --bind 127.0.0.1 --directory bonsaios-runs/my-os
```

Open <http://127.0.0.1:8000/os.html> in your browser. To view the included result
without running generation, use `--directory demos/bonsaios` instead. The saved
HTML is self-contained and can also be opened directly; viewing it requires no GPU.

The demo-specific setup downloads the pinned model and PrismML inference binaries,
checks their hashes, clones the pinned Hermes commit, and creates an isolated Python
environment. It does not need the repository's general `setup.sh`, a hosted API key,
a vision projector, a browser automation installation, or a job scheduler. The run
script starts and stops its own inference server.

To use a different idle GPU: `CUDA_VISIBLE_DEVICES=1 ./scripts/run_bonsaios.sh`.
The runner checks that exactly one GPU is visible and has no existing compute
processes. Each run needs a new output directory.

## What is pinned

| Component | Value |
| --- | --- |
| Model | `Ternary-Bonsai-2-27B-PQ2_0.gguf` |
| Model revision | `6ed5e12bf84b7a63069882c91dd9e9218647d17b` |
| PrismML llama.cpp | `9a9394a895b96003ca842a6041cb28ac49a108f7`, CUDA 12.8 release |
| Hermes | `3d1c00e1e8d3ed95853f46148ce543dd5d0aaa28` |
| Python | 3.13.14, with locked dependencies |
| Seed / temperature | 42 / 1.0 |
| Top-p / top-k / min-p | 0.95 / 20 / 0 |
| Presence / frequency / repeat penalty | 0 / 0 / 1.0 |
| Reasoning | xhigh, 16,384-token budget per main request |
| Output cap | 32,768 tokens per main request, including reasoning |
| Context | 131,072 tokens |
| Turns | Initial: 16; feedback 1-4: 8 each; branding feedback: 16 |
| Runtime | One inference slot, full GPU offload, flash attention, batch 2,048, microbatch 128, 8 CPU threads |
| Tools | File read, write, patch, search; skills and memory disabled |

[config.json](demos/bonsaios/config.json) contains editable defaults.
[versions.json](demos/bonsaios/repro/versions.json) contains immutable downloads and
checksums; [requirements.lock](demos/bonsaios/repro/requirements.lock) pins Python
packages. This uses the **PrismML llama.cpp branch**, not vLLM or stock llama.cpp.

Hermes compresses history at threshold 0.5, targeting ratio 0.2 and protecting the
first 3 and last 20 messages. Auxiliary summaries use seed 0, medium reasoning, and
a 1,024-token reasoning budget. The server restarts before feedback 4 and branding,
matching the recorded workflow. A short startup probe checks reasoning-budget
support; it does not change the main generation budget.

## Why environment pinning matters

Seed 42 is only repeatable for the same model input. Hermes includes dates,
directories, host/toolchain descriptions, and session metadata in that input.
[environment.json](demos/bonsaios/repro/environment.json) pins these values and the
transport tool IDs that appear in context summaries.

The historical paths are virtual identifiers. Users need neither the original
username nor those directories: the file-tool adapter maps the virtual workspace
to a new local directory and performs real file operations there. It preserves
relative path spelling and maps paths back in live tool results. The generated
workspace sits outside Git so the repository's own `AGENTS.md` and Git metadata
cannot enter the model's context.

Only the task's `AGENTS.txt` is placed in the initial workspace. The supplied
[Bonsai logo](demos/bonsaios/assets/bonsai-logo.svg) is added at the branding round.
No recorded model answer, previous HTML, or conversation checkpoint is loaded.
The included `os.html` is for viewing and is outside the agent's permitted workspace.
There are no divergence checks or output-matching gates in the runner.

## Use your own feedback or task

The default submits the following prompts in order in one continuing Hermes
conversation. Feedback describes observations from the original page, rather than
automated browser observations about a new run.

| Phase | Exact prompt | Turn cap |
| --- | --- | ---: |
| Initial creation | [00.txt](demos/bonsaios/prompts/00.txt) | 16 |
| Feedback 1: startup | [01.txt](demos/bonsaios/prompts/01.txt) | 8 |
| Feedback 2: app labels and windows | [02.txt](demos/bonsaios/prompts/02.txt) | 8 |
| Feedback 3: dragging and calculator | [03.txt](demos/bonsaios/prompts/03.txt) | 8 |
| Feedback 4: focus and file saving | [04.txt](demos/bonsaios/prompts/04.txt) | 8 |
| Feedback 5: BonsaiOS branding | [05.txt](demos/bonsaios/prompts/05.txt) | 16 |

For interactive feedback:

```bash
./scripts/run_bonsaios.sh --feedback interactive --output bonsaios-runs/custom
# In another terminal after inspecting the page:
demos/bonsaios/.venv/bin/python demos/bonsaios/src/feedback.py \
  bonsaios-runs/custom --text 'Describe what you want changed.'
```

Use `--file message.txt` instead of `--text`, or `--stop` to finish. `--feedback none`
runs only initial creation. Edit the config and prompts freely, or pass `--config`
and `--prompts` pointing to your own copies. Set `pin_environment` to `false` to
expose native dates/paths instead. Changing inputs intentionally changes the result.

## Reproduction evidence and saved output

Two independent runs started empty, used different install paths and host timezones
(Asia/Shanghai and UTC), and matched all 68 model responses, including reasoning and
tool arguments. Random API transport IDs are excluded from the response comparison.
All six HTML stages were byte-identical, including the final 55,962-byte file:

```text
65c35a906ad20845bc3fd1374159fc5c5cc555e3390ed64d07e1f2d3ae280e07  os.html
```

A third run used a fresh clone of this branch, downloaded all pinned dependencies
from their public sources, and ran the documented setup and launcher. Its final
HTML also matched the SHA-256 above byte-for-byte.

The first two final pages loaded without JavaScript page errors or external asset requests.
Each run generated 263,084 tokens including reasoning and summaries, at about
95.8-95.9 decode tokens/second. This establishes reproduction on the tested H200
configuration, not identical output across every backend or device. Selected app
interactions were checked; file saving remains incomplete.

A run saves the final page, per-round HTML snapshots and prompts, the Hermes session,
raw requests/responses, readable reasoning, terminal logs, settings, and token
metrics in its output directory. These run directories and downloaded dependencies
are Git-ignored. The only generated page included in the demo is `os.html`; the
remaining demo files provide the inputs and tooling to reproduce it.
