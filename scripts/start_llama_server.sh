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

# Bind to localhost by default; override with BONSAI_HOST=0.0.0.0 for LAN/remote.
HOST="${BONSAI_HOST:-127.0.0.1}"
PORT=8080

# ── Check port is free ──
if curl -s --max-time 2 "http://localhost:$PORT/health" >/dev/null 2>&1; then
    warn "llama-server is already running on port $PORT."
    echo "  Stop it first with:  kill \$(lsof -ti TCP:$PORT)"
    exit 1
fi

# ── Find model: select exactly the demo quant for the family
#    (a leftover F16 or g64 file must never be picked up) ──
MODEL=""
for _m in $GGUF_MODEL_DIR/$GGUF_QUANT_PATTERN; do
    [ -f "$_m" ] || continue
    case "$_m" in *mmproj*|*dspark*|*kv-bias*) continue ;; esac
    MODEL="$DEMO_DIR/$_m" && break
done
if [ -z "$MODEL" ]; then
    err "No ${GGUF_QUANT_PATTERN} model found in ${GGUF_MODEL_DIR}/."
    echo "  Re-run ./scripts/download_models.sh to fetch the model weights."
    exit 1
fi

# ── Vision: use the multimodal projector when present (27B is a VLM) ──
MMPROJ=""
for _mp in $GGUF_MODEL_DIR/*mmproj*.gguf; do
    [ -f "$_mp" ] && MMPROJ="$DEMO_DIR/$_mp" && break
done
if [ "$BONSAI_MODEL" = "27B" ] && [ -z "$MMPROJ" ]; then
    warn "No mmproj file found in ${GGUF_MODEL_DIR}/ — image input disabled."
    echo "  Re-run ./scripts/download_models.sh to fetch it."
fi

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
[ -n "$MMPROJ" ] && echo "  Vision:  $(basename "$MMPROJ")"
echo "  Binary:  $BIN"
echo ""
echo "  Open http://localhost:$PORT in your browser to chat."
echo "  API:  http://localhost:$PORT/v1/chat/completions"
echo "  Press Ctrl+C to stop."
echo ""

NGL=$(bonsai_llama_ngl)
if [ -n "${BONSAI_NGL:-}" ]; then
    echo "  GPU:     -ngl $NGL (set via BONSAI_NGL)"
else
    echo "  GPU:     -ngl $NGL (auto-detected; override with BONSAI_NGL, 0 = CPU-only)"
fi
echo ""

# 27B: --jinja enables native OpenAI-style tool calling; --mmproj enables
# image input; sampling matches the 27B reference demo (temp 0.7, top-p 0.95).
# The 27B is a thinking model and thinking stays on; use the web UI's
# Reasoning-effort picker per chat, or pass llama-server flags (e.g.
# --reasoning-budget N) as extra args to this script.
# Older sizes keep the exact flag set they were tested with.
if [ "$BONSAI_MODEL" = "27B" ]; then
    _imt=$(bonsai_image_max_tokens)
    # Default MCP tool servers for the built-in web UI (admin defaults — the
    # user can still edit/disable them in Settings -> MCP Client).
    _webui_cfg="$SCRIPT_DIR/webui-config.json"

    # Speculative decoding (opt-in, BONSAI_SPECULATIVE=1): pair the target with
    # its dspark drafter for ~1.8-2x decode on code/reasoning workloads. It
    # disables prompt-cache reuse and forces a single slot (-np 1), so it is off
    # by default and lives on this standalone server, not the agentic Open WebUI
    # path (which relies on the prompt cache).
    MD=""
    _spec_flags=""
    _ctx="$CTX_SIZE_DEFAULT"
    if [ "${BONSAI_SPECULATIVE:-0}" = "1" ]; then
        for _md in "$GGUF_MODEL_DIR"/*dspark-Q4_1*.gguf; do
            [ -f "$_md" ] && MD="$DEMO_DIR/$_md" && break
        done
        if [ -n "$MD" ]; then
            _nmax=$(bonsai_dspark_block_size "$MD")
            _spec_flags="--spec-type draft-dspark --spec-draft-n-max $_nmax -ngld 999 -np 1"
            # dspark re-prefills every request; give the model room to think
            # (it drafts 1.5-2k tokens; a small context truncates answers).
            # An explicit BONSAI_CTX still wins.
            [ -z "${BONSAI_CTX:-}" ] && _ctx=16384
            echo "  Speculative: $(basename "$MD") (draft-dspark, n-max $_nmax)"
        else
            warn "BONSAI_SPECULATIVE=1 but no *dspark-Q4_1*.gguf drafter in ${GGUF_MODEL_DIR}/; running without speculation."
            echo "  Re-run ./scripts/download_models.sh to fetch it."
        fi
    fi

    # 4-bit KV cache (opt-in, BONSAI_KV4=1): stores the KV cache in Q4_0 to cut
    # KV memory for very long contexts on tight machines (decode is slightly
    # slower than F16 KV). If a mean-centering bias built by
    # scripts/make_kv_bias.sh is present it is applied automatically for
    # better quality.
    _kv_args=""
    KV_BIAS=""
    if [ "${BONSAI_KV4:-0}" = "1" ]; then
        _kv_args="--cache-type-k q4_0 --cache-type-v q4_0"
        for _kb in "$GGUF_MODEL_DIR"/*kv-bias*.gguf; do
            [ -f "$_kb" ] && KV_BIAS="$DEMO_DIR/$_kb" && break
        done
        if [ -n "$KV_BIAS" ]; then
            # The bias is calibrated with K-rotation off; inference must match
            # (the loader rejects a mismatch by design).
            export LLAMA_ATTN_ROT_DISABLE=1
            echo "  KV cache: q4_0 + mean-centering ($(basename "$KV_BIAS"))"
        else
            echo "  KV cache: q4_0 (no bias; run ./scripts/make_kv_bias.sh for better quality)"
        fi
    fi

    echo "  Context: -c $_ctx (override with BONSAI_CTX, 0 = auto-fit)"
    # shellcheck disable=SC2086
    exec "$BIN" -m "$MODEL" --host "$HOST" --port "$PORT" -ngl "$NGL" -fa on -c "$_ctx" \
        --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 \
        --jinja \
        ${MMPROJ:+--mmproj "$MMPROJ"} \
        ${_imt:+--image-max-tokens "$_imt"} \
        ${MD:+-md "$MD"} $_spec_flags \
        $_kv_args ${KV_BIAS:+--kv-mean-center "$KV_BIAS"} \
        --webui-config-file "$_webui_cfg" \
        "$@"
fi

echo "  Context: -c $CTX_SIZE_DEFAULT (override with BONSAI_CTX, 0 = auto-fit)"
exec "$BIN" -m "$MODEL" --host "$HOST" --port "$PORT" -ngl "$NGL" -fa on -c "$CTX_SIZE_DEFAULT" \
    --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
    --reasoning-budget 0 --reasoning-format none \
    --chat-template-kwargs '{"enable_thinking": false}' \
    "$@"
