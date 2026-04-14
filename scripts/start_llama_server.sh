#!/bin/sh
# Start an OpenAI-compatible chat server with the Bonsai model.
# Usage: ./scripts/start_llama_server.sh
# Then open http://localhost:8080 in your browser.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"
assert_gguf_downloaded

HOST="0.0.0.0"
PORT=8080

# ── Check port is free ──
if curl -s --max-time 2 "http://localhost:$PORT/health" >/dev/null 2>&1; then
    warn "llama-server is already running on port $PORT."
    echo "  Stop it first with:  kill \$(lsof -ti TCP:$PORT)"
    exit 1
fi

# ── Find model ──
MODEL=""
for _m in $GGUF_MODEL_DIR/*.gguf; do
    [ -f "$_m" ] && MODEL="$DEMO_DIR/$_m" && break
done

# ── Find binary (search all known locations) ──
BIN=""
for _d in bin/mac bin/cuda bin/rocm bin/hip bin/vulkan bin/cpu llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
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

NGL=$(bonsai_llama_ngl)

exec "$BIN" -m "$MODEL" --host "$HOST" --port "$PORT" -ngl "$NGL" -c "$CTX_SIZE_DEFAULT" \
    --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
    --reasoning-budget 0 --reasoning-format none \
    --chat-template-kwargs '{"enable_thinking": false}' \
    "$@"
