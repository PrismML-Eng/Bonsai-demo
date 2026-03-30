#!/bin/sh
# Start an OpenAI-compatible chat server with the Bonsai model.
# Usage: ./scripts/start_llama_server.sh
# Then open http://localhost:8080 in your browser.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

HOST="0.0.0.0"
PORT=8080

# ── Find model ──
MODEL=""
for _m in $GGUF_MODEL_DIR/*.gguf; do
    [ -f "$_m" ] && MODEL="$DEMO_DIR/$_m" && break
done
if [ -z "$MODEL" ]; then
    err "GGUF model not found for ${BONSAI_MODEL}. Run ./setup.sh or: BONSAI_MODEL=${BONSAI_MODEL} ./scripts/download_models.sh"
    exit 1
fi

# ── Find binary (search all known locations) ──
BIN=""
for _d in bin/mac bin/cuda llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
    [ -f "$DEMO_DIR/$_d/llama-server" ] && BIN="$DEMO_DIR/$_d/llama-server" && break
done
if [ -z "$BIN" ]; then
    err "llama-server not found. Run ./setup.sh or ./scripts/download_binaries.sh first."
    exit 1
fi

BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo ""
echo "=== llama.cpp server (GGUF) ==="
echo "  Model:   $(basename "$MODEL")"
echo "  Binary:  $BIN"
echo "  Context: auto-fit (-c 0)"
echo ""
echo "  Open http://localhost:$PORT in your browser to chat."
echo "  API:  http://localhost:$PORT/v1/chat/completions"
echo "  Press Ctrl+C to stop."
echo ""

exec "$BIN" -m "$MODEL" --host "$HOST" --port "$PORT" -ngl 99 -c "$CTX_SIZE_DEFAULT" \
    --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
    --reasoning-budget 0 --reasoning-format none \
    --chat-template-kwargs '{"enable_thinking": false}' \
    "$@"
