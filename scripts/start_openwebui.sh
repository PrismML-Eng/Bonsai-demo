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

# ── Backend selection: exactly ONE backend, never both (two resident 27Bs
#    overwhelm consumer machines). BONSAI_BACKEND=llama (default) or mlx. ──
BONSAI_BACKEND="${BONSAI_BACKEND:-llama}"
case "$BONSAI_BACKEND" in
    llama|mlx) ;;
    *)
        err "Unknown BONSAI_BACKEND='${BONSAI_BACKEND}'. Valid values: llama, mlx"
        exit 1 ;;
esac
if [ "$BONSAI_BACKEND" = "mlx" ] && { [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; }; then
    err "BONSAI_BACKEND=mlx requires Apple Silicon (macOS arm64). Use the default llama backend."
    exit 1
fi

# ── Bind address guard. The UI runs with auth disabled and (by default) a
#    host-level code interpreter, so binding to a non-loopback address would let
#    anyone on the network execute code as you. Refuse it unless explicitly
#    opted in with BONSAI_ALLOW_REMOTE=1. ──
BONSAI_HOST="${BONSAI_HOST:-127.0.0.1}"
case "$BONSAI_HOST" in
    127.0.0.1|::1|localhost) ;;
    *)
        if [ "${BONSAI_ALLOW_REMOTE:-0}" != "1" ]; then
            err "Refusing to bind Open WebUI to '$BONSAI_HOST': the UI has authentication disabled and a host-level code interpreter, so a non-loopback bind exposes code execution as your user to the whole network."
            echo "  Safer options: keep the default localhost bind and use an SSH tunnel / reverse proxy,"
            echo "  or disable the code interpreter with BONSAI_CODE_INTERPRETER=0."
            echo "  To bind anyway on a trusted network, set BONSAI_ALLOW_REMOTE=1."
            exit 1
        fi
        warn "Binding Open WebUI to '$BONSAI_HOST' (BONSAI_ALLOW_REMOTE=1): auth is disabled and code execution may be enabled — trusted networks only."
        ;;
esac

# Assert the weights the selected backend actually needs (an MLX-only run must
# not require the GGUF, and vice versa).
if [ "$BONSAI_BACKEND" = "mlx" ]; then
    assert_mlx_downloaded
else
    assert_gguf_downloaded
fi

DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

LLAMA_PORT=8080
MLX_PORT=8081
BG_PIDS=""
_LLAMA_PREEXISTING=false
_MLX_PREEXISTING=false
_MLX_VISION=false

# ── Logs: each run writes fresh timestamped logs for the background services
#    (llama-server / MLX / Jupyter / Brave) under .openwebui/logs/. This is how
#    you inspect prefill/generation timing and errors after a run. Set
#    BONSAI_LOG=0 to discard them to /dev/null instead. ──
if [ "${BONSAI_LOG:-1}" = "0" ]; then
    _LLAMA_LOG=/dev/null; _MLX_LOG=/dev/null; _JUP_LOG=/dev/null; _BRAVE_LOG=/dev/null
    LOG_DIR=""
else
    LOG_DIR="$DEMO_DIR/.openwebui/logs"
    mkdir -p "$LOG_DIR"
    _RUN_TS="$(date +%Y%m%d-%H%M%S)"
    _LLAMA_LOG="$LOG_DIR/llama-server-$_RUN_TS.log"
    _MLX_LOG="$LOG_DIR/mlx-server-$_RUN_TS.log"
    _JUP_LOG="$LOG_DIR/jupyter-$_RUN_TS.log"
    _BRAVE_LOG="$LOG_DIR/brave-$_RUN_TS.log"
fi

# Debug: BONSAI_LLAMA_VERBOSE=1 runs llama-server with -v, which logs the full
# converted request body per request ("converted request: {...}") plus generation
# to the llama-server log — use it to diff what Open WebUI sends across tool-call
# rounds (e.g. to see whether prior-turn reasoning is stripped). Very noisy.
_LLAMA_VERBOSE=""
[ "${BONSAI_LLAMA_VERBOSE:-0}" = "1" ] && _LLAMA_VERBOSE="-v"

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
    echo "    uv pip install \".[webui]\""
    exit 1
fi

# ── Vision: use the multimodal projector when present (27B is a VLM) ──
MMPROJ=""
for _mp in $GGUF_MODEL_DIR/*mmproj*.gguf; do
    [ -f "$_mp" ] && MMPROJ="$DEMO_DIR/$_mp" && break
done

# ── Start llama-server if not running ──
if [ "$BONSAI_BACKEND" != "llama" ]; then
    : # mlx backend selected — llama-server not managed by this script
elif curl -fsS --max-time 2 "http://localhost:$LLAMA_PORT/health" >/dev/null 2>&1; then
    _LLAMA_PREEXISTING=true
    info "llama-server already running on port $LLAMA_PORT"
else
    # Find model + binary: select exactly the demo quant for the family
    # (a leftover F16 or g64 file must never be picked up).
    _model=""
    for _m in $GGUF_MODEL_DIR/$GGUF_QUANT_PATTERN; do
        [ -f "$_m" ] || continue
        case "$_m" in *mmproj*|*dspark*|*kv-bias*) continue ;; esac
        _model="$DEMO_DIR/$_m" && break
    done
    _bin=""
    for _d in bin/mac bin/cuda bin/rocm bin/hip bin/vulkan bin/cpu llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
        [ -f "$DEMO_DIR/$_d/llama-server" ] && _bin="$DEMO_DIR/$_d/llama-server" && break
    done

    if [ -n "$_model" ] && [ -n "$_bin" ]; then
        step "Starting llama-server on port $LLAMA_PORT ..."
        _bin_dir="$(cd "$(dirname "$_bin")" && pwd)"
        _ngl=$(bonsai_llama_ngl)
        # 27B: --jinja enables native OpenAI-style tool calling; --mmproj
        # enables image input; reference-demo sampling. The 27B is a thinking
        # model and thinking stays on. Older sizes keep their tested flag set.
        if [ "$BONSAI_MODEL" = "27B" ]; then
            _imt=$(bonsai_image_max_tokens)
            # shellcheck disable=SC2086
            LD_LIBRARY_PATH="$_bin_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            "$_bin" -m "$_model" --host 127.0.0.1 --port "$LLAMA_PORT" -ngl "$_ngl" -fa on -c "$CTX_SIZE_DEFAULT" \
                --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 \
                --jinja \
                ${MMPROJ:+--mmproj "$MMPROJ"} \
                ${_imt:+--image-max-tokens "$_imt"} \
                $_LLAMA_VERBOSE \
                > "$_LLAMA_LOG" 2>&1 &
        else
            LD_LIBRARY_PATH="$_bin_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            "$_bin" -m "$_model" --host 127.0.0.1 --port "$LLAMA_PORT" -ngl "$_ngl" -fa on -c "$CTX_SIZE_DEFAULT" \
                --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
                --jinja \
                --reasoning-budget 0 --reasoning-format none \
                --chat-template-kwargs '{"enable_thinking": false}' \
                $_LLAMA_VERBOSE \
                > "$_LLAMA_LOG" 2>&1 &
        fi
        BG_PIDS="$BG_PIDS $!"
        # Wait for it to be ready
        _tries=0
        while [ "$_tries" -lt 30 ]; do
            if curl -fsS --max-time 1 "http://localhost:$LLAMA_PORT/health" >/dev/null 2>&1; then
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

# ── Start MLX server if selected (BONSAI_BACKEND=mlx, macOS only) ──
if [ "$BONSAI_BACKEND" = "mlx" ]; then
    if curl -fsS --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
        _MLX_PREEXISTING=true
        info "MLX server already running on port $MLX_PORT"
    elif [ -d "$DEMO_DIR/$MLX_MODEL_DIR" ] && python -c "import mlx_lm" 2>/dev/null; then
        step "Starting MLX server on port $MLX_PORT (${BONSAI_DISPLAY}) ..."
        export HF_HOME="$DEMO_DIR/.hf_cache"
        mkdir -p "$HF_HOME/hub"
        # 27B ternary: mlx-vlm gives the MLX backend image input (stock-mlx
        # .venv-vlm from setup.sh). Binary 1-bit needs the fork -> text-only.
        # Disable with BONSAI_MLX_VLM=0.
        _VLM_PY="$DEMO_DIR/.venv-vlm/bin/python"
        # The 27B is a thinking model and thinking stays on.
        if [ "$BONSAI_MODEL" = "27B" ] && [ "$BONSAI_FAMILY" = "ternary" ] \
            && [ "${BONSAI_MLX_VLM:-1}" != "0" ] && [ -x "$_VLM_PY" ] \
            && "$_VLM_PY" -c "import mlx_vlm" 2>/dev/null; then
            _MLX_VISION=true
            "$_VLM_PY" -m mlx_vlm.server \
                --model "$DEMO_DIR/$MLX_MODEL_DIR" \
                --port "$MLX_PORT" \
                --enable-thinking \
                > "$_MLX_LOG" 2>&1 &
        elif [ "$BONSAI_MODEL" = "27B" ]; then
            python -m mlx_lm.server \
                --model "$DEMO_DIR/$MLX_MODEL_DIR" \
                --port "$MLX_PORT" \
                --temp 0.7 --top-p 0.95 \
                > "$_MLX_LOG" 2>&1 &
        else
            python -m mlx_lm.server \
                --model "$DEMO_DIR/$MLX_MODEL_DIR" \
                --port "$MLX_PORT" \
                --temp 0.5 --top-p 0.85 \
                > "$_MLX_LOG" 2>&1 &
        fi
        BG_PIDS="$BG_PIDS $!"
        # Wait for MLX server to be ready (a 27B load can take a few minutes)
        step "Waiting for MLX server to load model ..."
        _tries=0
        while [ "$_tries" -lt 120 ]; do
            if curl -fsS --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
                break
            fi
            _tries=$((_tries + 1))
            sleep 2
        done
        if curl -fsS --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
            info "MLX server ready on port $MLX_PORT"
        else
            warn "MLX server did not become ready in time (may still be loading)."
        fi
    else
        warn "Skipping MLX server (model or mlx_lm not found)."
    fi
fi

# ── Build Open WebUI backend list (single backend by design) ──
BACKENDS=""
KEYS=""
_LLAMA_URL=""
_MLX_URL=""

if [ "$BONSAI_BACKEND" = "llama" ] && curl -fsS --max-time 2 "http://localhost:$LLAMA_PORT/health" >/dev/null 2>&1; then
    _LLAMA_URL="http://localhost:$LLAMA_PORT/v1"
    BACKENDS="$_LLAMA_URL"
    KEYS="none"
fi

if [ "$BONSAI_BACKEND" = "mlx" ] && curl -fsS --max-time 2 "http://localhost:$MLX_PORT/v1/models" >/dev/null 2>&1; then
    _MLX_URL="http://localhost:$MLX_PORT/v1"
    BACKENDS="$_MLX_URL"
    KEYS="none"
    # A pre-existing MLX server's implementation is unknown (it may be a
    # text-only mlx_lm server even when .venv-vlm exists), so never infer
    # vision for it. Set BONSAI_MLX_VISION=1 explicitly if the server you
    # started yourself is mlx-vlm.
    if [ "$_MLX_PREEXISTING" = true ] && [ "${BONSAI_MLX_VISION:-0}" = "1" ]; then
        _MLX_VISION=true
    fi
fi

if [ -z "$BACKENDS" ]; then
    err "No ${BONSAI_BACKEND} backend available. Run ./setup.sh first."
    exit 1
fi

step "Starting Open WebUI ..."

# Open WebUI persists config in its DB and ignores env vars after the first
# boot; the demo treats env (this script) as the source of truth instead, so
# backend switches and task settings apply on every start.
export ENABLE_PERSISTENT_CONFIG=false

export OPENAI_API_BASE_URLS="$BACKENDS"
export OPENAI_API_KEYS="$KEYS"
export WEBUI_AUTH=false
export ENABLE_OLLAMA_API=false
export RAG_EMBEDDING_ENGINE=""
export ENABLE_RAG_WEB_SEARCH=false
export DATA_DIR="$DEMO_DIR/.openwebui"

# Open WebUI fires background LLM calls after each reply (chat title, tags,
# follow-up suggestions). Against a single heavy 27B each one is a slow extra
# generation that keeps the UI spinning after the answer is done, so disable
# them for the demo (both backends). Users can re-enable in Admin Settings.
export ENABLE_TITLE_GENERATION=false
export ENABLE_TAGS_GENERATION=false
export ENABLE_FOLLOW_UP_GENERATION=false

# Cap on the native tool-call loop. Open WebUI defaults this to 256. We set a
# generous-but-finite 30: enough for the agentic DB-analyst scenario
# (multi-step query_database investigations run ~15-25 calls) without leaving a
# truly unbounded loop that could run for minutes / overheat on a public clone.
# There is no in-chat "continue" once it stops, so the cap must fit the workload.
# Set BONSAI_MAX_TOOL_ITERS=-1 for unlimited, or a smaller number to tighten.
export CHAT_RESPONSE_MAX_TOOL_CALL_ITERATIONS="${BONSAI_MAX_TOOL_ITERS:-30}"

# ── Code interpreter: back Open WebUI's code execution with a local Jupyter
#    kernel (matplotlib plots, pandas/numpy, yfinance market data). Uses the
#    .venv-jupyter that setup.sh builds; falls back to browser Pyodide if it's
#    missing. Skip with BONSAI_CODE_INTERPRETER=0. ──
BONSAI_CODE_INTERPRETER="${BONSAI_CODE_INTERPRETER:-1}"
_JUP_PY="$DEMO_DIR/.venv-jupyter/bin/jupyter"
if [ "$BONSAI_CODE_INTERPRETER" != "0" ] && [ -x "$_JUP_PY" ]; then
    _JUP_PORT="${BONSAI_JUPYTER_PORT:-8888}"
    _JUP_TOKEN="$(head -c 24 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo "bonsai-jupyter-$$")"
    step "Starting Jupyter kernel for the code interpreter on port $_JUP_PORT ..."
    # Sandbox (portable, best-effort): run the kernel from a dedicated empty work
    # dir and scrub secrets from its environment, so model-executed code can't
    # trivially read the repo (.brave_key / .bonsai_token) via relative paths or
    # pull secrets out of os.environ. This is HARDENING, not a jail — code still
    # runs as your user with network + absolute-path access. For true isolation,
    # run the whole demo in a container/VM (see AGENTS.md). Bound to 127.0.0.1.
    _JUP_WORK="$DATA_DIR/jupyter-work"
    mkdir -p "$_JUP_WORK"
    (
        cd "$_JUP_WORK" || exit 1
        unset BRAVE_API_KEY BONSAI_TOKEN HF_TOKEN PRISM_HF_TOKEN
        exec "$_JUP_PY" server --ip 127.0.0.1 --port "$_JUP_PORT" --no-browser \
            --ServerApp.root_dir="$_JUP_WORK" \
            --ServerApp.token="$_JUP_TOKEN" --ServerApp.disable_check_xsrf=True
    ) > "$_JUP_LOG" 2>&1 &
    _JUP_PID=$!
    BG_PIDS="$BG_PIDS $_JUP_PID"
    # Wait for the kernel to accept authenticated requests before advertising the
    # code tool — otherwise a port clash, missing dependency, or startup crash
    # would surface only at first use. Fall back to code-exec off if it never
    # comes up (or the process already exited).
    _jup_ready=false
    _tries=0
    while [ "$_tries" -lt 20 ]; do
        kill -0 "$_JUP_PID" 2>/dev/null || break   # process exited — startup failed
        if curl -fsS --max-time 2 "http://127.0.0.1:$_JUP_PORT/api/status?token=$_JUP_TOKEN" >/dev/null 2>&1; then
            _jup_ready=true
            break
        fi
        _tries=$((_tries + 1))
        sleep 1
    done
    if [ "$_jup_ready" = true ]; then
        export ENABLE_CODE_EXECUTION=true
        export ENABLE_CODE_INTERPRETER=true
        export CODE_EXECUTION_ENGINE=jupyter
        export CODE_INTERPRETER_ENGINE=jupyter
        export CODE_EXECUTION_JUPYTER_URL="http://127.0.0.1:$_JUP_PORT"
        export CODE_EXECUTION_JUPYTER_AUTH=token
        export CODE_EXECUTION_JUPYTER_AUTH_TOKEN="$_JUP_TOKEN"
        export CODE_EXECUTION_JUPYTER_TIMEOUT=120
        export CODE_INTERPRETER_JUPYTER_URL="http://127.0.0.1:$_JUP_PORT"
        export CODE_INTERPRETER_JUPYTER_AUTH=token
        export CODE_INTERPRETER_JUPYTER_AUTH_TOKEN="$_JUP_TOKEN"
        export CODE_INTERPRETER_JUPYTER_TIMEOUT=120
        info "Code interpreter ready (Jupyter on 127.0.0.1:$_JUP_PORT)."
        BONSAI_CODE_INTERPRETER_ON=1
    else
        warn "Jupyter kernel did not become ready — disabling the code interpreter for this run."
        kill "$_JUP_PID" 2>/dev/null || true
        BONSAI_CODE_INTERPRETER_ON=0
    fi
else
    BONSAI_CODE_INTERPRETER_ON=0
fi
export BONSAI_CODE_INTERPRETER_ON

# ── MCP tool servers (same set as the hosted HF demo) ──
# Hugging Face + DeepWiki are remote and keyless. Brave Search (web search) is
# opt-in: provide a key via BRAVE_API_KEY (env) or a gitignored .brave_key file,
# and install the bridge (npm i -g @brave/brave-search-mcp-server). The key stays
# local - it is never committed. (ENABLE_PERSISTENT_CONFIG=false -> read every boot.)
_ACCESS='"access_grants":[{"principal_type":"user","principal_id":"*","permission":"read"}]'
_MCP_BRAVE=""
BONSAI_MCP_IDS="huggingface,deepwiki"
if [ -z "${BRAVE_API_KEY:-}" ] && [ -f "$DEMO_DIR/.brave_key" ]; then
    BRAVE_API_KEY="$(tr -d '\r\n' < "$DEMO_DIR/.brave_key")"
fi
if [ -n "${BRAVE_API_KEY:-}" ]; then
    export BRAVE_API_KEY
    if command -v brave-search-mcp-server >/dev/null 2>&1; then
        step "Starting Brave Search MCP bridge on 127.0.0.1:8001 ..."
        # Limit to the search tools the demo needs. Brave's full tool set is ~29k
        # tokens of schemas (brave_place_search alone is ~20k!); these three are
        # ~2.9k. Override with BONSAI_BRAVE_TOOLS if you want a different set.
        _brave_tools="${BONSAI_BRAVE_TOOLS:-brave_web_search brave_news_search brave_summarizer}"
        # shellcheck disable=SC2086
        brave-search-mcp-server --transport http --host 127.0.0.1 --port 8001 \
            --enabled-tools $_brave_tools > "$_BRAVE_LOG" 2>&1 &
        BG_PIDS="$BG_PIDS $!"
        _MCP_BRAVE=',{"id":"brave","type":"mcp","url":"http://127.0.0.1:8001/mcp","path":"","auth_type":"none","key":"","config":{"enable":true,'$_ACCESS'},"info":{"id":"brave","name":"Brave Search","description":"Web search via Brave"}}'
        BONSAI_MCP_IDS="$BONSAI_MCP_IDS,brave"
    else
        warn "BRAVE_API_KEY is set but brave-search-mcp-server is not installed - skipping Brave MCP."
    fi
fi
export TOOL_SERVER_CONNECTIONS='[
  {"id":"huggingface","type":"mcp","url":"https://huggingface.co/mcp","path":"","auth_type":"none","key":"","config":{"enable":true,'$_ACCESS'},"info":{"id":"huggingface","name":"Hugging Face","description":"Search models, datasets and Spaces on the HF Hub"}},
  {"id":"deepwiki","type":"mcp","url":"https://mcp.deepwiki.com/mcp","path":"","auth_type":"none","key":"","config":{"enable":true,'$_ACCESS'},"info":{"id":"deepwiki","name":"DeepWiki","description":"Ask questions about any public GitHub repository"}}'"$_MCP_BRAVE"'
]'
export BONSAI_MCP_IDS

mkdir -p "$DATA_DIR"

# ── Demo SQL database for the demo_db tool (generated once, gitignored) ──
export BONSAI_DEMO_DB="$DATA_DIR/demo.db"
python "$SCRIPT_DIR/openwebui/make_demo_db.py" "$BONSAI_DEMO_DB" || \
    warn "Could not build the demo database — the demo_db tool will return errors."

# ── Seed tools + model settings, print the URL and open browser only AFTER
#    the server is ready ──
_SEED_ARGS="--url http://localhost:$PORT"
[ -n "$_LLAMA_URL" ] && _SEED_ARGS="$_SEED_ARGS --llama-url $_LLAMA_URL"
[ -n "$_LLAMA_URL" ] && [ -n "$MMPROJ" ] && _SEED_ARGS="$_SEED_ARGS --llama-vision"
[ -n "$_MLX_URL" ] && _SEED_ARGS="$_SEED_ARGS --mlx-url $_MLX_URL"
[ -n "$_MLX_URL" ] && [ "$_MLX_VISION" = true ] && _SEED_ARGS="$_SEED_ARGS --mlx-vision"

(
    _tries=0
    while [ "$_tries" -lt 90 ]; do
        if curl -fsS --max-time 2 "http://localhost:$PORT" >/dev/null 2>&1; then
            # shellcheck disable=SC2086
            python "$SCRIPT_DIR/openwebui/seed_openwebui.py" $_SEED_ARGS
            echo ""
            echo "========================================="
            echo "   Open WebUI ready!"
            echo "   http://localhost:$PORT"
            echo "========================================="
            echo ""
            echo "  Demo tools seeded: weather, web fetch, SQL demo database."
            echo "  MCP servers available (per-chat opt-in): ${BONSAI_MCP_IDS}."
            [ "$BONSAI_CODE_INTERPRETER_ON" = "1" ] && \
                echo "  Code interpreter: Jupyter (plots, pandas/numpy, yfinance)."
            [ -n "$LOG_DIR" ] && \
                echo "  Logs (this run): $LOG_DIR/  (llama-server / mlx / jupyter / brave; BONSAI_LOG=0 to disable)."
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

# Bind address resolved + guarded above (BONSAI_HOST, default 127.0.0.1;
# non-loopback requires BONSAI_ALLOW_REMOTE=1).
export HOST="$BONSAI_HOST"
open-webui serve --host "$HOST" --port "$PORT" "$@"
