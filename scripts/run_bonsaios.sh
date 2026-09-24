#!/usr/bin/env sh
# Start the pinned local inference server and run all five BonsaiOS feedback rounds.
set -eu
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEMO_DIR="$REPO_ROOT/demos/bonsaios"
if [ ! -x "$DEMO_DIR/.venv/bin/python" ]; then
    echo "Run python3 demos/bonsaios/setup.py from the repository root first." >&2
    exit 1
fi
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
export no_proxy="$NO_PROXY"
exec "$DEMO_DIR/.venv/bin/python" "$DEMO_DIR/src/reproduce.py" \
    --output "$REPO_ROOT/bonsaios-runs/$(date +%Y%m%d-%H%M%S)" \
    --feedback scripted "$@"
