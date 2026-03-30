#!/bin/sh
# Run Bonsai model with MLX (Apple Silicon only)
# Usage: ./scripts/run_mlx.sh -p "Your prompt"
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

if [ "$(uname -s)" != "Darwin" ]; then
    err "MLX only runs on Apple Silicon (macOS). Use ./scripts/run_llama.sh instead."
    exit 1
fi

MODEL="$MLX_MODEL_DIR"
PROMPT=""
EXTRA_ARGS=""

while [ $# -gt 0 ]; do
    case "$1" in
        -p) PROMPT="$2"; shift 2 ;;
        -n) EXTRA_ARGS="$EXTRA_ARGS -n $2"; shift 2 ;;
        --temp) EXTRA_ARGS="$EXTRA_ARGS --temp $2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ -z "$PROMPT" ]; then
    PROMPT="What is Capital of France?"
fi

if [ ! -d "$MODEL" ]; then
    err "MLX model not found for ${BONSAI_MODEL}: $MODEL"
    echo "  Run ./setup.sh or: BONSAI_MODEL=${BONSAI_MODEL} ./scripts/download_models.sh"
    exit 1
fi

ensure_venv "$DEMO_DIR"

# shellcheck disable=SC2086
python "$SCRIPT_DIR/mlx_generate.py" \
    --model "$MODEL" \
    -p "$PROMPT" \
    $EXTRA_ARGS
