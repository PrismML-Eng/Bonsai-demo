#!/bin/sh
# Start MLX OpenAI-compatible server (Apple Silicon only).
# Usage: ./scripts/start_mlx_server.sh
# Listens on port 8081.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

if [ "$(uname -s)" != "Darwin" ]; then
    err "MLX only runs on Apple Silicon (macOS). Use ./scripts/start_llama_server.sh instead."
    exit 1
fi

MODEL="$DEMO_DIR/models/Bonsai-8B-mlx"
PORT=8081

if [ ! -d "$MODEL" ]; then
    err "MLX model not found: $MODEL"
    echo "  Run ./setup.sh or ./scripts/download_models.sh first."
    exit 1
fi

ensure_venv "$DEMO_DIR"

export HF_HOME="$DEMO_DIR/.hf_cache"
mkdir -p "$HF_HOME/hub"

echo ""
echo "=== MLX server ==="
echo "  Model: Bonsai-8B-mlx"
echo "  Port:  $PORT"
echo ""

exec python -m mlx_lm.server \
    --model "$MODEL" \
    --port "$PORT" \
    --temp 0.5 --top-p 0.85 \
    "$@"
