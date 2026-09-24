#!/bin/sh
# Run Bonsai model with llama.cpp
# Usage: ./scripts/run_llama.sh -p "Your prompt" -n 100
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"
assert_gguf_downloaded run_mlx.sh

# ── Find binary first (its backend decides the ternary quant; see common.sh) ──
BIN=""
for _d in bin/mac bin/cuda bin/rocm bin/hip bin/vulkan bin/cpu llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
    [ -f "$DEMO_DIR/$_d/llama-cli" ] && BIN="$DEMO_DIR/$_d/llama-cli" && break
done
if [ -z "$BIN" ]; then
    err "llama-cli not found. Run ./setup.sh or ./scripts/download_binaries.sh first."
    exit 1
fi
BACKEND="$(backend_from_bin "$BIN")"

# ── Find model: backend-aware selection ──
MODEL="$(select_model_gguf "$GGUF_MODEL_DIR" "$BACKEND" || true)"
if [ -z "$MODEL" ]; then
    err "No model file found in ${GGUF_MODEL_DIR}/."
    echo "  Re-run ./scripts/download_models.sh to fetch the model weights."
    exit 1
fi

# ── Library path for bundled shared libs (needed on Linux CUDA, harmless elsewhere) ──
BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

NGL=$(bonsai_llama_ngl)
CTX_SIZE_DEFAULT=$(bonsai_ctx_default "$BACKEND" "$NGL")

info "Model:  $MODEL"
info "Binary: $BIN"
info "Using -ngl $NGL (override with BONSAI_NGL, 0 = CPU-only), -c $CTX_SIZE_DEFAULT (override with BONSAI_CTX, 0 = auto)"

# A prompt given with -p is a one-shot request, so finish and exit. Without -st,
# llama-cli drops into an interactive session after answering and never returns.
_ONESHOT=""
for _a in "$@"; do
    case "$_a" in -p|--prompt) _ONESHOT="-st" ;; esac
done

# Bonsai 2: the base model's own sampling defaults (temp 1.0, top-p 0.95, top-k 20),
# thinking stays enabled.
if [ "$BONSAI_FAMILY" = "bonsai2" ]; then
    # shellcheck disable=SC2086
    exec "$BIN" -m "$MODEL" -ngl "$NGL" -fa on -c "$CTX_SIZE_DEFAULT" --log-disable \
        --temp 1.0 --top-p 0.95 --top-k 20 \
        $_ONESHOT "$@"
fi

# 27B: reference-demo sampling, thinking stays enabled (model default).
# Older sizes keep the exact flag set they were tested with.
if [ "$BONSAI_MODEL" = "27B" ]; then
    # shellcheck disable=SC2086
    exec "$BIN" -m "$MODEL" -ngl "$NGL" -fa on -c "$CTX_SIZE_DEFAULT" --log-disable \
        --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 \
        $_ONESHOT "$@"
fi

# shellcheck disable=SC2086
exec "$BIN" -m "$MODEL" -ngl "$NGL" -fa on -c "$CTX_SIZE_DEFAULT" --log-disable \
    --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
    --reasoning-budget 0 --reasoning-format none \
    --chat-template-kwargs '{"enable_thinking": false}' \
    $_ONESHOT "$@"
