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

# ── Find model: select exactly the demo quant for the family ──
MODEL=""
for _m in $GGUF_MODEL_DIR/$GGUF_QUANT_PATTERN; do
    [ -f "$_m" ] || continue
    case "$_m" in *mmproj*|*dspark*|*kv-bias*) continue ;; esac
    MODEL="$_m" && break
done
if [ -z "$MODEL" ]; then
    err "No ${GGUF_QUANT_PATTERN} model found in ${GGUF_MODEL_DIR}/."
    echo "  Re-run ./scripts/download_models.sh to fetch the model weights."
    exit 1
fi

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
info "Using -ngl $NGL (override with BONSAI_NGL, 0 = CPU-only), -c $CTX_SIZE_DEFAULT (override with BONSAI_CTX)"

# 27B: reference-demo sampling, thinking stays enabled (model default).
# Older sizes keep the exact flag set they were tested with.
if [ "$BONSAI_MODEL" = "27B" ]; then
    "$BIN" -m "$MODEL" -ngl "$NGL" -fa on -c "$CTX_SIZE_DEFAULT" --log-disable \
        --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 \
        "$@" \
    || {
        _st=$?
        # This retry exists only for builds that reject auto-fit (-c 0); any
        # other failure must surface as-is instead of rerunning the prompt.
        [ "$CTX_SIZE_DEFAULT" = "0" ] || exit "$_st"
        CTX_SIZE=$(get_context_size_fallback)
        warn "Auto-fit not supported, falling back to -c $CTX_SIZE"
        "$BIN" -m "$MODEL" -ngl "$NGL" -fa on -c "$CTX_SIZE" --log-disable \
            --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 \
            "$@"
    }
    exit $?
fi

"$BIN" -m "$MODEL" -ngl "$NGL" -fa on -c "$CTX_SIZE_DEFAULT" --log-disable \
    --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
    --reasoning-budget 0 --reasoning-format none \
    --chat-template-kwargs '{"enable_thinking": false}' \
    "$@" \
|| {
    _st=$?
    # This retry exists only for builds that reject auto-fit (-c 0); any
    # other failure must surface as-is instead of rerunning the prompt.
    [ "$CTX_SIZE_DEFAULT" = "0" ] || exit "$_st"
    CTX_SIZE=$(get_context_size_fallback)
    warn "Auto-fit not supported, falling back to -c $CTX_SIZE"
    "$BIN" -m "$MODEL" -ngl "$NGL" -fa on -c "$CTX_SIZE" --log-disable \
        --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
        --reasoning-budget 0 --reasoning-format none \
        --chat-template-kwargs '{"enable_thinking": false}' \
        "$@"
}
