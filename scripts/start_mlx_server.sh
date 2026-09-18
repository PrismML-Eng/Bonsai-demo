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
PORT="${PORT:-8081}"

# Bonsai 2 on mlx-serve. The pack's rotated basis needs a server that applies
# the Hadamard activation transform itself; mlx-serve does from v26.9.5
# (ddalcu/mlx-serve@89eeb24, "Prism Bonsai 2 lands"). Opt-in only
# (BONSAI_MLX_SERVE=/path/to/mlx-serve), never auto-detected: an older
# mlx-serve loads the same bytes and returns wrong output with no error.
# No Python venv is needed on this path.
if [ "$BONSAI_FAMILY" = "bonsai2" ] && [ -n "${BONSAI_MLX_SERVE:-}" ]; then
    if [ ! -x "$BONSAI_MLX_SERVE" ]; then
        err "BONSAI_MLX_SERVE=$BONSAI_MLX_SERVE is not an executable."
        exit 1
    fi
    echo ""
    echo "=== MLX server (mlx-serve) ==="
    echo "  Model: ${BONSAI_DISPLAY}-mlx"
    echo "  Port:  $PORT"
    echo "  Needs an mlx-serve build with Prism Hadamard support (mlx-serve v26.9.5+, ddalcu/mlx-serve@89eeb24)."
    echo "  Thinking is on by default; pass reasoning_effort per request (xhigh|medium|low)."
    echo ""
    exec "$BONSAI_MLX_SERVE" --model "$MODEL" --serve --host 127.0.0.1 --port "$PORT" \
        --temp 0.7 --top-p 0.95 --top-k 20 \
        "$@"
fi

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
# Bonsai 2 packs are rotated and need the Hadamard-aware loader they ship in runtime/.
# Neither mlx_vlm.server nor mlx_lm.server knows about it: they would load the weights and
# return wrong output with no error. Refuse until a server path exists.
if [ "$BONSAI_FAMILY" = "bonsai2" ]; then
    err "No MLX server for Bonsai 2 yet."
    echo "  Its MLX pack needs the loader bundled in the pack, which mlx_lm.server and"
    echo "  mlx_vlm.server do not use; serving through them would return wrong output."
    echo ""
    echo "  One-shot MLX instead:   ./scripts/run_mlx.sh -p \"...\" [--image photo.jpg]"
    echo "  Or serve with llama.cpp: ./scripts/start_llama_server.sh"
    echo "  Or with an mlx-serve build that has Prism Hadamard support (mlx-serve v26.9.5+, ddalcu/mlx-serve@89eeb24):"
    echo "    BONSAI_MLX_SERVE=/path/to/mlx-serve ./scripts/start_mlx_server.sh"
    exit 1
fi

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
