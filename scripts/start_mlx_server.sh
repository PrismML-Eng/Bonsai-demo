#!/bin/sh
# Start MLX OpenAI-compatible server (Apple Silicon only).
# Usage: ./scripts/start_mlx_server.sh
# Listens on port 8081.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

if [ "$(uname -s)" != "Darwin" ]; then
    err "MLX only runs on Apple Silicon (macOS). Use ./scripts/start_llama_server.sh instead."
    exit 1
fi

assert_mlx_downloaded

MODEL="$DEMO_DIR/$MLX_MODEL_DIR"
PORT=8081

ensure_venv "$DEMO_DIR"

export HF_HOME="$DEMO_DIR/.hf_cache"
mkdir -p "$HF_HOME/hub"

echo ""
echo "=== MLX server ==="
echo "  Model: ${BONSAI_DISPLAY}-mlx"
echo "  Port:  $PORT"
echo ""

# 27B ternary: serve with mlx-vlm for image input (the published MLX packs
# ship the FP16 vision tower). Needs the stock-mlx .venv-vlm from setup.sh —
# ternary 2-bit runs on stock mlx; binary 1-bit still needs the PrismML fork,
# so it stays on text-only mlx_lm below. Disable with BONSAI_MLX_VLM=0.
# The 27B is a thinking model and thinking stays on.
VLM_PY="$DEMO_DIR/.venv-vlm/bin/python"
if [ "$BONSAI_MODEL" = "27B" ] && [ "$BONSAI_FAMILY" = "ternary" ] \
    && [ "${BONSAI_MLX_VLM:-1}" != "0" ] && [ -x "$VLM_PY" ] \
    && "$VLM_PY" -c "import mlx_vlm" 2>/dev/null; then
    step "Serving with mlx-vlm (image input enabled)."
    exec "$VLM_PY" -m mlx_vlm.server \
        --model "$MODEL" \
        --port "$PORT" \
        --enable-thinking \
        "$@"
fi

# 27B: reference-demo sampling; thinking stays on (model default).
# Older sizes keep the exact flag set they were tested with.
if [ "$BONSAI_MODEL" = "27B" ]; then
    exec python -m mlx_lm.server \
        --model "$MODEL" \
        --port "$PORT" \
        --temp 0.7 --top-p 0.95 \
        "$@"
fi

exec python -m mlx_lm.server \
    --model "$MODEL" \
    --port "$PORT" \
    --temp 0.5 --top-p 0.85 \
    "$@"
