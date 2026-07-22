# Open WebUI: the full agentic demo

[Open WebUI](https://github.com/open-webui/open-webui) gives you a ChatGPT-like interface on top of the local 27B: chat with images, tool calling against live tools, a server-side code interpreter (plots + market data), and a hidden-story database to investigate. Everything is configured automatically, no clicking through settings.

`setup.sh` installs Open WebUI into the venv for you (skip with `BONSAI_OPENWEBUI=0`). If you skipped it, install manually from the repo root with `uv pip install ".[webui]"` (this uses the pinned version the demo is validated against).

## Run (one command)

```bash
./scripts/start_openwebui.sh
```

This starts llama-server if needed, seeds the demo (tools, model settings, demo database), and opens **http://localhost:9090**. First boot takes a minute (database migrations); Ctrl+C stops everything it started.

Prefer the MLX backend on a Mac? Same thing with:

```bash
BONSAI_BACKEND=mlx ./scripts/start_openwebui.sh
```

On an MLX-only setup (you ran `BONSAI_SKIP_GGUF=1`), the default llama.cpp backend has no GGUF to load, so a plain `./scripts/start_openwebui.sh` stops with an error pointing you at this `BONSAI_BACKEND=mlx` command.

It always runs exactly one backend (two resident 27Bs is too heavy for most machines). Note the MLX backend is noticeably slower per token and takes longer to first response on a fresh chat. It also has no cross-request prompt cache, so each follow-up re-processes the whole conversation (including image tokens), so multi-turn chats are slower than on llama.cpp, which caches the prefix. For interactive multi-turn use, prefer the default llama.cpp backend.

## What to try

- **Vision:** click the `+` in the message box and upload a photo or screenshot. Follow-up questions about the same image are near-instant (prompt cache).
- **Tools:** live weather and web fetch are attached by default; Hugging Face Hub and DeepWiki MCP servers are connected and opt-in per chat from the tool menu. More in [TOOLS.md](TOOLS.md).
- **Code interpreter** (server-side Python via Jupyter, on by default): calculations, data analysis, market data via yfinance, and inline matplotlib plots.
- **The agentic analyst:** the demo ships a SQLite sales database of a fictional B2B company with a hidden story in it. Ask the model to investigate a revenue change and watch it explore the schema, run focused queries, verify its numbers, and piece the answer together.
- **Thinking:** answers show a collapsible thought block; the 27B reasons before answering.

## How it works / customizing

- The three tools live in [scripts/openwebui/](scripts/openwebui/) as plain Python (Open WebUI "Tools") and are re-seeded on every start; edit them and restart to change the demo.
- The demo database is generated into `.openwebui/demo.db` on first start (`make_demo_db.py`).
- Chats persist in `.openwebui/` between runs; delete that directory for a factory-fresh demo (everything reseeds).
- Configuration comes from `start_openwebui.sh` env vars on every launch (auth disabled, single backend, background title/tag/follow-up generation off so the UI doesn't keep running the 27B after each reply; re-enable in Admin Settings if you want auto-titles).
- MCP servers (including the optional Brave Search) and adding your own: [TOOLS.md](TOOLS.md).
- The code interpreter runs server-side in a Jupyter kernel (`.venv-jupyter`, built by `setup.sh` with matplotlib / pandas / numpy / scipy / sympy / yfinance). `start_openwebui.sh` launches it on `127.0.0.1:8888` and stops it on Ctrl+C. Disable with `BONSAI_CODE_INTERPRETER=0` (code execution is then turned off).
