#!/bin/sh
# Install the Hermes agent (NousResearch/hermes-agent) at the exact commit the demo was recorded with,
# into ./.venv-hermes, plus the headless Chromium its browser tools use. Idempotent.
#
#   ./scripts/agent/install_hermes.sh            # pinned commit (default)
#   HERMES_REF=main ./scripts/agent/install_hermes.sh   # live main, at your own risk
set -e
DEMO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HERMES_REF="${HERMES_REF:-c387be0}"     # hermes-agent 0.18.2, 2026-07-16 — what recorded AGENT-DEMO.md
SRC="$DEMO_DIR/.hermes-agent"; VENV="$DEMO_DIR/.venv-hermes"
command -v uv >/dev/null 2>&1 || { echo "uv not found; install it first: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }
if [ ! -d "$SRC/.git" ]; then git clone -q https://github.com/NousResearch/hermes-agent.git "$SRC"; fi
git -C "$SRC" fetch -q origin && git -C "$SRC" checkout -q "$HERMES_REF"
echo "hermes-agent at $(git -C "$SRC" rev-parse --short HEAD): $(git -C "$SRC" log -1 --format=%s | cut -c1-70)"
[ -x "$VENV/bin/python" ] || uv venv -q --python 3.12 "$VENV"
uv pip install -q --python "$VENV/bin/python" -e "$SRC[all]" 2>/dev/null || uv pip install -q --python "$VENV/bin/python" -e "$SRC"
"$VENV/bin/python" -c "import hermes_cli.main" && echo "hermes importable"
# browser tools (browser_navigate / browser_vision) are Hermes's Node-based agent-browser (Playwright
# under the hood). Hermes resolves `agent-browser` from PATH first and only then falls back to an unversioned
# `npx agent-browser`, so the recorded version is installed into <demo>/.agent-browser and run_agent_demo.sh
# puts its bin directory first on PATH. agent-browser 0.38.1 declares Node >= 24.
command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || { echo "Node.js (node + npm) not found; install Node 24+ (https://nodejs.org) and rerun"; exit 1; }
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
[ "$NODE_MAJOR" -ge 24 ] || { echo "Node $(node --version) found; agent-browser 0.38.1 needs Node 24+"; exit 1; }
AB_VERSION=${AGENT_BROWSER_VERSION:-0.38.1}
AB_DIR="$DEMO_DIR/.agent-browser"
npm install --prefix "$AB_DIR" --no-package-lock --silent "agent-browser@${AB_VERSION}" \
  && echo "agent-browser $("$AB_DIR/node_modules/.bin/agent-browser" --version | awk '{print $NF}') installed in $AB_DIR" \
  || { echo "npm install agent-browser@${AB_VERSION} failed"; exit 1; }
"$AB_DIR/node_modules/.bin/agent-browser" install --with-deps >/dev/null 2>&1 && echo "chromium for agent-browser installed" \
  || echo "warning: 'agent-browser install --with-deps' failed; Hermes will try again at first browser use"
echo "ok: $VENV"
