#!/bin/sh
# Start Open WebUI with a ChatGPT-like interface.
# Auto-starts llama-server and MLX server if they're not already running.
# Ctrl+C stops everything cleanly.
#
# Usage: ./scripts/start_openwebui.sh
# Then open http://localhost:3001 in your browser.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
assert_gguf_downloaded
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

LLAMA_PORT=8080
MLX_PORT=8081
BG_PIDS=""
_LLAMA_PREEXISTING=false
_MLX_PREEXISTING=false

# ── Find a free port for Open WebUI ──
# Use 9090+ range to avoid conflicts with Cursor port-forwarding and RunPod
PORT=9090
_max_port=9099
while [ "$PORT" -le "$_max_port" ]; do
    if ! lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
        break
    fi
    PORT=$((PORT + 1))
done
if [ "$PORT" -gt "$_max_port" ]; then
    err "No free port found in range 9090-$_max_port."
    exit 1
fi

# ── Cleanup: stop any servers we started ──
cleanup() {
    echo ""
    if [ -n "$BG_PIDS" ]; then
        step "Shutting down servers we started ..."
        for _pid in $BG_PIDS; do
            kill "$_pid" 2>/dev/null && info "Stopped PID $_pid" || true
        done
        wait 2>/dev/null || true
    fi
    if [ "$_LLAMA_PREEXISTING" = true ]; then
        info "llama-server on port $LLAMA_PORT was already running — leaving it up."
    fi
    if [ "$_MLX_PREEXISTING" = true ]; then
        info "MLX server on port $MLX_PORT was already running — leaving it up."
    fi
    info "Done."
}
trap cleanup EXIT INT TERM

ensure_venv "$DEMO_DIR"

if ! command -v open-webui >/dev/null 2>&1; then
    err "open-webui is not installed."
    echo ""
    echo "  Install it with:"
    echo "    source .venv/bin/activate"
    echo "    uv pip install open-webui"
    exit 1
fi

# ── Start llama-server if not running ──
if curl -s --max-time 2 "http://localhost:$LLAMA_PORT/health" >/dev/null 2>&1; then
    _LLAMA_PREEXISTING=true
    info "llama-server already running on port $LLAMA_PORT"
else
    # Find model + binary
    _model=""
    for _m in $GGUF_MODEL_DIR/*.gguf; do
        [ -f "$_m" ] && _model="$DEMO_DIR/$_m" && break
    done
    _bin=""
    for _d in bin/mac bin/cuda bin/rocm bin/hip bin/vulkan bin/cpu llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
        [ -f "$DEMO_DIR/$_d/llama-server" ] && _bin="$DEMO_DIR/$_d/llama-server" && break
    done

    if [ -n "$_model" ] && [ -n "$_bin" ]; then
        step "Starting llama-server on port $LLAMA_PORT ..."
        _bin_dir="$(cd "$(dirname "$_bin")" && pwd)"
        _ngl=$(bonsai_llama_ngl)
        LD_LIBRARY_PATH="$_bin_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$_bin" -m "$_model" --host 0.0.0.0 --port "$LLAMA_PORT" -ngl "$_ngl" -c "$CTX_SIZE_DEFAULT" \
            --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
            --reasoning-budget 0 --reasoning-format none \
            --chat-template-kwargs '{"enable_thinking": false}' \
            > /dev/null 2>&1 &
        BG_PIDS="$BG_PIDS $!"
        # Wait for it to be ready
        _tries=0
        while [ "$_tries" -lt 30 ]; do
            if curl -s --max-time 1 "http://localhost:$LLAMA_PORT/health" >/dev/null 2>&1; then
                break
            fi
            _tries=$((_tries + 1))
            sleep 1
        done
        info "llama-server started on port $LLAMA_PORT"
    else
        warn "Could not start llama-server (model or binary not found)."
    fi
fi

# ── Start MLX server if not running (macOS only) ──
if [ "$(uname -s)" != "Darwin" ]; then
    warn "MLX server skipped — only available on Apple Silicon (macOS)."
elif [ "$(uname -s)" = "Darwin" ]; then
    if curl -s --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
        _MLX_PREEXISTING=true
        info "MLX server already running on port $MLX_PORT"
    elif [ -d "$DEMO_DIR/$MLX_MODEL_DIR" ] && python -c "import mlx_lm" 2>/dev/null; then
        step "Starting MLX server on port $MLX_PORT (Bonsai-${BONSAI_MODEL}) ..."
        export HF_HOME="$DEMO_DIR/.hf_cache"
        mkdir -p "$HF_HOME/hub"
        python -m mlx_lm.server \
            --model "$DEMO_DIR/$MLX_MODEL_DIR" \
            --port "$MLX_PORT" \
            --temp 0.5 --top-p 0.85 \
            > /dev/null 2>&1 &
        BG_PIDS="$BG_PIDS $!"
        # Wait for MLX server to be ready (model loading can take 30-60s)
        step "Waiting for MLX server to load model ..."
        _tries=0
        while [ "$_tries" -lt 60 ]; do
            if curl -s --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
                break
            fi
            _tries=$((_tries + 1))
            sleep 2
        done
        if curl -s --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
            info "MLX server ready on port $MLX_PORT"
        else
            warn "MLX server did not become ready in time (may still be loading)."
        fi
    else
        warn "Skipping MLX server (model or mlx_lm not found)."
    fi
fi

# ── Build Open WebUI backend list ──
BACKENDS=""
KEYS=""

if curl -s --max-time 2 "http://localhost:$LLAMA_PORT/health" >/dev/null 2>&1; then
    BACKENDS="http://localhost:$LLAMA_PORT/v1"
    KEYS="none"
fi

if curl -s --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
    if [ -n "$BACKENDS" ]; then
        BACKENDS="$BACKENDS;http://localhost:$MLX_PORT/v1"
        KEYS="$KEYS;none"
    else
        BACKENDS="http://localhost:$MLX_PORT/v1"
        KEYS="none"
    fi
fi

if [ -z "$BACKENDS" ]; then
    err "No backends available. Run ./setup.sh first."
    exit 1
fi

step "Starting Open WebUI ..."

export OPENAI_API_BASE_URLS="$BACKENDS"
export OPENAI_API_KEYS="$KEYS"
export WEBUI_AUTH=false
export ENABLE_OLLAMA_API=false
export RAG_EMBEDDING_ENGINE=""
export ENABLE_RAG_WEB_SEARCH=false
export DATA_DIR="$DEMO_DIR/.openwebui"

mkdir -p "$DATA_DIR"

# Print the URL and open browser only AFTER the server is ready
(
    _tries=0
    while [ "$_tries" -lt 90 ]; do
        if curl -s --max-time 2 "http://localhost:$PORT" >/dev/null 2>&1; then
            echo ""
            echo "========================================="
            echo "   Open WebUI ready!"
            echo "   http://localhost:$PORT"
            echo "========================================="
            echo ""
            echo "  Press Ctrl+C to stop everything."
            echo ""
            if [ "$(uname -s)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
                open "http://localhost:$PORT"
            fi
            exit 0
        fi
        _tries=$((_tries + 1))
        sleep 2
    done
) &

open-webui serve --port "$PORT" "$@"
