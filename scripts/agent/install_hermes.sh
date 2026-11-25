#!/bin/sh
# Install the Hermes agent (NousResearch/hermes-agent) at the exact commit the demo was recorded with,
# into ./.venv-hermes, plus the headless Chromium its browser tools use. Idempotent.
#
#   ./scripts/agent/install_hermes.sh            # pinned commit (default)
#   HERMES_REF=main ./scripts/agent/install_hermes.sh   # live main, at your own risk
#   HERMES_PRISM_PATCHES=0 ./scripts/agent/install_hermes.sh   # stock c387be0, as AGENT-DEMO.md recorded it
#
# On the pinned commit the four patches in scripts/agent/patches/ are applied, in this order (idempotently). All four are
# used by `run_agent_demo.sh game`; the skateboard recordings in AGENT-DEMO.md predate them:
#   hermes_prism_empty_recovery.patch    HERMES_EMPTY_RECOVERY=resample: an empty model reply is resampled instead of
#                                        stacking empty assistant messages (inactive unless that variable is set)
#   hermes_prism_browser_keepalive.patch the local browser session is kept alive across long thinking gaps, so a
#                                        screenshot after >120 s idle is not of about:blank (HERMES_BROWSER_LOCAL_KEEPALIVE=0 turns it off)
#   hermes_prism_oneshot_max_turns.patch `hermes -z` honours agent.max_turns (stock one-shot always stops at 90 calls);
#                                        the game config allows 150, the other modes are pinned to 90 by run_agent_demo.sh
#   hermes_prism_cut_recovery.patch      HERMES_PRISM_CUT_RECOVERY=1: a tool call cut by the output limit is not executed
#                                        or resent unchanged; the model is told to split the work (inactive unless set)
#
# .hermes-agent is managed by this script. When it already is the pinned commit with this patch stack applied it is left
# as it is. Otherwise any local changes (an older version of the patches, a switch of HERMES_REF or HERMES_PRISM_PATCHES,
# your own edits) are stashed, never discarded, before the checkout: `git -C .hermes-agent stash list` shows them.
set -e
DEMO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HERMES_REF="${HERMES_REF:-c387be0}"     # hermes-agent 0.18.2, 2026-07-16 — what recorded AGENT-DEMO.md
PATCHES="hermes_prism_empty_recovery hermes_prism_browser_keepalive hermes_prism_oneshot_max_turns hermes_prism_cut_recovery"
SRC="$DEMO_DIR/.hermes-agent"; VENV="$DEMO_DIR/.venv-hermes"
command -v uv >/dev/null 2>&1 || { echo "uv not found; install it first: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }
if [ ! -d "$SRC/.git" ]; then git clone -q https://github.com/NousResearch/hermes-agent.git "$SRC"; fi
git -C "$SRC" fetch -q origin
WANT_PATCHES=0; [ "${HERMES_PRISM_PATCHES:-1}" = 1 ] && [ "$HERMES_REF" = c387be0 ] && WANT_PATCHES=1
stack_applied() {   # every patch of the stack reverse-applies on the current tree
  for p in $PATCHES; do git -C "$SRC" apply --reverse --check "$DEMO_DIR/scripts/agent/patches/$p.patch" 2>/dev/null || return 1; done
}
if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
  TARGET=$(git -C "$SRC" rev-parse -q --verify "$HERMES_REF^{commit}" 2>/dev/null || echo none)
  if [ "$WANT_PATCHES" = 1 ] && [ "$(git -C "$SRC" rev-parse HEAD)" = "$TARGET" ] && stack_applied; then
    : # already the requested state; the loop below reports each patch as applied
  else
    git -C "$SRC" -c user.name=install_hermes -c user.email=install_hermes@localhost stash push -q --include-untracked -m "install_hermes.sh $(date -u +%FT%TZ): local changes before checkout of $HERMES_REF"
    echo "local changes in $SRC stashed (git -C $SRC stash list; git -C $SRC stash pop to restore)"
  fi
fi
git -C "$SRC" checkout -q "$HERMES_REF"
echo "hermes-agent at $(git -C "$SRC" rev-parse --short HEAD): $(git -C "$SRC" log -1 --format=%s | cut -c1-70)"
if [ "$WANT_PATCHES" = 1 ]; then
  for name in $PATCHES; do
    p="$DEMO_DIR/scripts/agent/patches/$name.patch"
    if git -C "$SRC" apply --reverse --check "$p" 2>/dev/null; then echo "patch already applied: $name.patch"
    else git -C "$SRC" apply "$p" && echo "patch applied: $name.patch" || { echo "patch failed: $name.patch (HERMES_PRISM_PATCHES=0 for stock)"; exit 1; }; fi
  done
elif [ "${HERMES_PRISM_PATCHES:-1}" = 1 ]; then echo "note: patches are for c387be0 only; HERMES_REF=$HERMES_REF installed unpatched"
fi
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
