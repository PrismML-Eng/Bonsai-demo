#!/bin/sh
# Shared helpers for Bonsai demo scripts.
# Source this file: . "$(dirname "$0")/common.sh"

# ── Model selection ──
# Set BONSAI_MODEL to choose size:   27B (default), 8B, 4B, 1.7B, or all
# Set BONSAI_FAMILY to choose family: ternary (default), bonsai (1-bit), or all
# "all" is only meaningful for setup/download — it expands to every size / every family.
BONSAI_MODEL="${BONSAI_MODEL:-27B}"
BONSAI_FAMILY="${BONSAI_FAMILY:-ternary}"

# Derived paths default to empty so an invalid family or "all" never produces
# a stale/glob-able path (e.g. `ls /*.gguf`). Concrete paths are only set when
# the (family, size) pair is a valid concrete combination — runtime scripts
# call assert_*_downloaded which validates and gives a clear error.
GGUF_MODEL_DIR=""
MLX_MODEL_DIR=""
GGUF_QUANT_PATTERN=""
BONSAI_DISPLAY="(family=${BONSAI_FAMILY} size=${BONSAI_MODEL})"

case "$BONSAI_MODEL" in
    27B|8B|4B|1.7B)
        case "$BONSAI_FAMILY" in
            bonsai)
                GGUF_MODEL_DIR="models/gguf/${BONSAI_MODEL}"
                MLX_MODEL_DIR="models/Bonsai-${BONSAI_MODEL}-mlx"
                GGUF_QUANT_PATTERN="*-Q1_0.gguf"
                BONSAI_DISPLAY="Bonsai-${BONSAI_MODEL}"
                ;;
            ternary)
                GGUF_MODEL_DIR="models/ternary-gguf/${BONSAI_MODEL}"
                MLX_MODEL_DIR="models/Ternary-Bonsai-${BONSAI_MODEL}-mlx-2bit"
                GGUF_QUANT_PATTERN="*-Q2_0.gguf"
                BONSAI_DISPLAY="Ternary-Bonsai-${BONSAI_MODEL}"
                ;;
            # Anything else, including "all": paths stay empty; assert_valid_model
            # will reject invalid families when called.
        esac
        ;;
    # Anything else, including "all": paths stay empty until validated.
esac

# Validate BONSAI_MODEL + BONSAI_FAMILY — call at the top of every run/server script
assert_valid_model() {
    case "$BONSAI_MODEL" in
        27B|8B|4B|1.7B|all) ;;
        *)
            err "Unknown BONSAI_MODEL='${BONSAI_MODEL}'. Valid values: 27B, 8B, 4B, 1.7B, all"
            echo "  Example: export BONSAI_MODEL=27B"
            exit 1 ;;
    esac
    case "$BONSAI_FAMILY" in
        bonsai|ternary|all) ;;
        *)
            err "Unknown BONSAI_FAMILY='${BONSAI_FAMILY}'. Valid values: bonsai, ternary, all"
            echo "  Example: export BONSAI_FAMILY=ternary"
            exit 1 ;;
    esac
}

# Reject invalid values and the download-only "all" at runtime with a clear
# message. Called by assert_gguf_downloaded / assert_mlx_downloaded so they're
# safe to call even if the run script forgot to call assert_valid_model first.
_assert_concrete_model() {
    assert_valid_model
    if [ "$BONSAI_FAMILY" = "all" ] || [ "$BONSAI_MODEL" = "all" ]; then
        err "BONSAI_FAMILY='all' / BONSAI_MODEL='all' is only valid for setup/download."
        echo "  Pick a concrete family/size for run scripts, e.g.:"
        echo "    BONSAI_FAMILY=bonsai BONSAI_MODEL=8B ./scripts/run_llama.sh ..."
        exit 1
    fi
}

# True if the concrete GGUF file for the current family/size is present
# (matching GGUF_QUANT_PATTERN, excluding the mmproj/dspark/kv-bias extras --
# same filter run_llama.sh / start_llama_server.sh use to pick MODEL).
bonsai_gguf_present() {
    for _m in $GGUF_MODEL_DIR/$GGUF_QUANT_PATTERN; do
        [ -f "$_m" ] || continue
        case "$_m" in *mmproj*|*dspark*|*kv-bias*) continue ;; esac
        return 0
    done
    return 1
}

# True if the MLX model for the current family/size is present.
bonsai_mlx_present() {
    [ -f "$MLX_MODEL_DIR/config.json" ]
}

# True if the MLX model is present AND this machine can actually run it.
# MLX is Apple Silicon only, so an Intel Mac that happens to have MLX weights
# (copied over, or downloaded with BONSAI_SKIP_MLX=0) must not be pointed at
# the MLX scripts.
bonsai_mlx_usable() {
    [ "$(uname -s)" = "Darwin" ] || return 1
    [ "$(uname -m)" = "arm64" ] || return 1
    bonsai_mlx_present
}

# Check the GGUF model is downloaded; error out with a download hint if not.
#
# The two optional args let the error also offer the MLX backend when the GGUF
# is missing but a usable MLX model is already on disk (the BONSAI_SKIP_GGUF=1
# case) — so the user is told what they *can* run now, not just to download
# several GB of GGUF they may not want:
#   $1  MLX-equivalent script to suggest, e.g. "run_mlx.sh"
#   $2  env prefix, for callers where the MLX path is the *same* script driven
#       by an env var instead of a separate one, e.g. "BONSAI_BACKEND=mlx"
# Callers with no MLX equivalent (e.g. make_kv_bias.sh) pass nothing and get the
# plain "download the GGUF" message.
assert_gguf_downloaded() {
    _assert_concrete_model
    bonsai_gguf_present && return 0

    err "GGUF model not found for ${BONSAI_DISPLAY} (expected in ${GGUF_MODEL_DIR}/)."
    if [ -n "${1:-}" ] && bonsai_mlx_usable; then
        echo "  An MLX model for ${BONSAI_DISPLAY} is already downloaded. Either:"
        echo "    - run the MLX backend directly:"
        echo "        BONSAI_FAMILY=${BONSAI_FAMILY} BONSAI_MODEL=${BONSAI_MODEL} ${2:+$2 }./scripts/$1"
        echo "    - or download the GGUF weights for the llama.cpp backend:"
        echo "        BONSAI_FAMILY=${BONSAI_FAMILY} BONSAI_MODEL=${BONSAI_MODEL} ./scripts/download_models.sh"
    else
        echo "  Download it with:"
        echo "    BONSAI_FAMILY=${BONSAI_FAMILY} BONSAI_MODEL=${BONSAI_MODEL} ./scripts/download_models.sh"
    fi
    exit 1
}

# Check MLX model is downloaded — prompts to download if missing
assert_mlx_downloaded() {
    _assert_concrete_model
    if ! bonsai_mlx_present; then
        err "MLX model not found for ${BONSAI_DISPLAY} (expected in ${MLX_MODEL_DIR}/)."
        echo "  Download it with:"
        echo "    BONSAI_FAMILY=${BONSAI_FAMILY} BONSAI_MODEL=${BONSAI_MODEL} ./scripts/download_models.sh"
        exit 1
    fi
}

# ── Colors ──
if [ -t 1 ]; then
    _CLR_GREEN="\033[32m"
    _CLR_YELLOW="\033[33m"
    _CLR_RED="\033[31m"
    _CLR_CYAN="\033[36m"
    _CLR_RESET="\033[0m"
else
    _CLR_GREEN="" _CLR_YELLOW="" _CLR_RED="" _CLR_CYAN="" _CLR_RESET=""
fi

info()  { printf "${_CLR_GREEN}[OK]${_CLR_RESET}   %s\n" "$*"; }
warn()  { printf "${_CLR_YELLOW}[WARN]${_CLR_RESET} %s\n" "$*"; }
err()   { printf "${_CLR_RED}[ERR]${_CLR_RESET}  %s\n" "$*" >&2; }
step()  { printf "${_CLR_CYAN}==>    %s${_CLR_RESET}\n" "$*"; }

# ── Default context: a predictable RAM-tiered cap.
# We deliberately do NOT use llama.cpp's -c 0: that means "use the model's full
# training context" (262144 on the 27B) and is memory-unaware, so with -ngl it
# picks the maximum and OOMs constrained machines. Instead we size the cap to
# system RAM. Per-token FP16 KV cost differs by model: ~64 KiB on the 27B
# (hybrid attention) but ~140 KiB on the full-attention 8B, so a tier costs up
# to ~2.2x more KV on the older sizes. Every tier stays comfortably inside its
# RAM band for every size (worst case: 8B at 65536 is ~10.5 GB total on a
# 36 GB+ machine), and the 131072 top tier is 27B-only.
# Override with BONSAI_CTX=N (up to 262144). BONSAI_CTX=0 or unset both mean
# "auto" and resolve to the RAM-tiered default below; to force the full training
# context pass the explicit number (e.g. BONSAI_CTX=262144).
bonsai_ctx_default() {
    # Treat 0 the same as unset ("auto"): never emit -c 0 downstream.
    if [ -n "${BONSAI_CTX:-}" ] && [ "$BONSAI_CTX" != "0" ]; then
        echo "$BONSAI_CTX"
        return
    fi
    if [ "$(uname -s)" = "Darwin" ]; then
        _mem_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    else
        _mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
        _mem_gb=$(( ${_mem_kb:-0} / 1048576 ))
    fi
    if [ "$_mem_gb" -le 11 ] 2>/dev/null; then
        echo 8192
    elif [ "$_mem_gb" -le 23 ] 2>/dev/null; then
        echo 16384
    elif [ "$_mem_gb" -le 35 ] 2>/dev/null; then
        echo 32768
    elif [ "$_mem_gb" -le 71 ] 2>/dev/null; then
        echo 65536
    elif [ "$BONSAI_MODEL" = "27B" ]; then
        echo 131072
    else
        echo 65536  # older sizes are documented up to 65536
    fi
}
CTX_SIZE_DEFAULT=$(bonsai_ctx_default)

# Vision projector placement (27B VLM only). By default the mmproj is offloaded
# to VRAM with the rest of the model. BONSAI_MMPROJ_CPU=1 adds --no-mmproj-offload
# so it stays in system RAM instead, freeing ~0.9 GiB of VRAM for KV/context on
# tight cards. Cost: image prompt-processing runs on CPU (tens of ms to seconds
# per image); token generation and text-only requests are unaffected. Echoes the
# flag when enabled, empty otherwise; callers add it only when an mmproj is used.
bonsai_mmproj_offload_flag() {
    case "${BONSAI_MMPROJ_CPU:-0}" in
        1|true|yes|on) echo "--no-mmproj-offload" ;;
        *) echo "" ;;
    esac
}

# GPU layer offload: 99 = offload all layers to GPU, 0 = CPU only.
# Override with BONSAI_NGL env var if needed.
bonsai_llama_ngl() {
    if [ -n "${BONSAI_NGL:-}" ]; then
        echo "$BONSAI_NGL"
    elif [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "x86_64" ]; then
        echo 0  # Intel Mac — no Metal
    elif command -v nvidia-smi >/dev/null 2>&1 || command -v nvcc >/dev/null 2>&1; then
        echo 99  # CUDA
    elif command -v rocminfo >/dev/null 2>&1 || command -v hipcc >/dev/null 2>&1; then
        echo 99  # ROCm/HIP
    elif command -v vulkaninfo >/dev/null 2>&1; then
        echo 99  # Vulkan
    elif [ "$(uname -s)" = "Darwin" ]; then
        echo 99  # Apple Silicon — Metal
    else
        echo 0   # CPU only
    fi
}

# Image-token cap for the 27B vision models (llama-server --image-max-tokens).
# Big images cost a lot of prefill on slower hardware (a 12 MP photo is
# ~4000 vision tokens); capping at 1024 makes them much faster with little
# quality loss outside fine detail / OCR. Fast datacenter GPUs
# (CUDA/ROCm) run uncapped. Override with BONSAI_IMAGE_MAX_TOKENS
# (a number, or 0 to disable the cap entirely).
bonsai_image_max_tokens() {
    if [ -n "${BONSAI_IMAGE_MAX_TOKENS:-}" ]; then
        [ "$BONSAI_IMAGE_MAX_TOKENS" = "0" ] || echo "$BONSAI_IMAGE_MAX_TOKENS"
    elif command -v nvidia-smi >/dev/null 2>&1 || command -v nvcc >/dev/null 2>&1; then
        :  # CUDA — uncapped
    elif command -v rocminfo >/dev/null 2>&1 || command -v hipcc >/dev/null 2>&1; then
        :  # ROCm/HIP — uncapped
    else
        echo 1024  # Metal / Vulkan / CPU — cap for latency
    fi
}

# Read a dspark drafter's block_size, which MUST equal --spec-draft-n-max (a
# mismatch assert-crashes llama-server on the first draft round). Falls back to
# 4, the n_blocks=4 packing standard, if the metadata can't be read (e.g. gguf
# module missing). Arg: path to the drafter GGUF.
bonsai_dspark_block_size() {
    _py=".venv/bin/python"
    [ -x "$_py" ] || _py="python3"
    _bs="$("$_py" - "$1" 2>/dev/null <<'PYEOF'
import sys
try:
    import gguf
    r = gguf.GGUFReader(sys.argv[1])
    f = r.get_field('dspark.dspark.block_size')
    print(int(f.contents()) if f else '')
except Exception:
    print('')
PYEOF
)"
    case "$_bs" in
        ''|*[!0-9]*) echo 4 ;;
        *) echo "$_bs" ;;
    esac
}

# MLX is Apple Silicon only; skip on Intel Mac or when BONSAI_SKIP_MLX=1.
bonsai_should_skip_mlx() {
    case "${BONSAI_SKIP_MLX:-}" in
        1|true|yes) return 0 ;;
        0|false|no) return 1 ;;
        *)
            [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "x86_64" ] && return 0
            return 1 ;;
    esac
}

# GGUF is downloaded by default (needed for the llama.cpp backend); skip it
# with BONSAI_SKIP_GGUF=1 when you only intend to run the MLX backend and
# want to save disk space / download time.
bonsai_should_skip_gguf() {
    case "${BONSAI_SKIP_GGUF:-}" in
        1|true|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Resolve DEMO_DIR (parent of scripts/) ──
resolve_demo_dir() {
    _script_dir="$(cd "$(dirname "$0")" && pwd)"
    echo "$(cd "$_script_dir/.." && pwd)"
}

# ── Ensure .venv is active (for MLX / Python scripts) ──
ensure_venv() {
    _demo="$1"
    if [ -z "$VIRTUAL_ENV" ] && [ -f "$_demo/.venv/bin/activate" ]; then
        . "$_demo/.venv/bin/activate"
    fi
    if [ -z "$VIRTUAL_ENV" ]; then
        err "Python venv not found. Run ./setup.sh first."
        exit 1
    fi
}
