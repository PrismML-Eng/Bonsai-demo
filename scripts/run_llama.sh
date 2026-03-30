#!/bin/sh
# Run Bonsai model with llama.cpp
# Usage: ./scripts/run_llama.sh -p "Your prompt" -n 100
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

# ── Find model ──
MODEL=""
for _m in $GGUF_MODEL_DIR/*.gguf; do
    [ -f "$_m" ] && MODEL="$_m" && break
done
if [ -z "$MODEL" ]; then
    err "GGUF model not found for ${BONSAI_MODEL}. Run ./setup.sh or: BONSAI_MODEL=${BONSAI_MODEL} ./scripts/download_models.sh"
    exit 1
fi

# ── Find binary (search all known locations) ──
BIN=""
for _d in bin/mac bin/cuda llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
    [ -f "$DEMO_DIR/$_d/llama-cli" ] && BIN="$DEMO_DIR/$_d/llama-cli" && break
done
if [ -z "$BIN" ]; then
    err "llama-cli not found. Run ./setup.sh or ./scripts/download_binaries.sh first."
    exit 1
fi

# ── Library path for bundled shared libs (needed on Linux CUDA, harmless elsewhere) ──
BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

info "Model:  $MODEL"
info "Binary: $BIN"
info "Using -c 0 (auto-fit to available memory)"

"$BIN" -m "$MODEL" -ngl 99 -c "$CTX_SIZE_DEFAULT" --log-disable \
    --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
    --reasoning-budget 0 --reasoning-format none \
    --chat-template-kwargs '{"enable_thinking": false}' \
    "$@" 2>/dev/null \
|| {
    CTX_SIZE=$(get_context_size_fallback)
    warn "Auto-fit not supported, falling back to -c $CTX_SIZE"
    "$BIN" -m "$MODEL" -ngl 99 -c "$CTX_SIZE" --log-disable \
        --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
        --reasoning-budget 0 --reasoning-format none \
        --chat-template-kwargs '{"enable_thinking": false}' \
        "$@" 2>/dev/null
}
