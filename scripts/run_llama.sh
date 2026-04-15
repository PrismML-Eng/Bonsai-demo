#!/bin/sh
# Run Bonsai model with llama.cpp
# Usage: ./scripts/run_llama.sh -p "Your prompt" -n 100
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"
assert_gguf_downloaded

# ── Find model ──
MODEL=""
for _m in $GGUF_MODEL_DIR/*.gguf; do
    [ -f "$_m" ] && MODEL="$_m" && break
done

# ── Find binary (search all known locations) ──
BIN=""
for _d in bin/mac bin/cuda bin/rocm bin/hip bin/vulkan bin/cpu llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
    [ -f "$DEMO_DIR/$_d/llama-cli" ] && BIN="$DEMO_DIR/$_d/llama-cli" && break
done
if [ -z "$BIN" ]; then
    err "llama-cli not found. Run ./setup.sh or ./scripts/download_binaries.sh first."
    exit 1
fi

# ── Library path for bundled shared libs (needed on Linux CUDA, harmless elsewhere) ──
BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

NGL=$(bonsai_llama_ngl)

info "Model:  $MODEL"
info "Binary: $BIN"
info "Using -ngl $NGL, -c 0 (auto-fit to available memory)"

"$BIN" -m "$MODEL" -ngl "$NGL" -c "$CTX_SIZE_DEFAULT" --log-disable \
    --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
    --reasoning-budget 0 --reasoning-format none \
    --chat-template-kwargs '{"enable_thinking": false}' \
    "$@" \
|| {
    CTX_SIZE=$(get_context_size_fallback)
    warn "Auto-fit not supported, falling back to -c $CTX_SIZE"
    "$BIN" -m "$MODEL" -ngl "$NGL" -c "$CTX_SIZE" --log-disable \
        --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
        --reasoning-budget 0 --reasoning-format none \
        --chat-template-kwargs '{"enable_thinking": false}' \
        "$@"
}
