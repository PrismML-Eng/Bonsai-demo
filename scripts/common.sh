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

# Check GGUF model is downloaded — prompts to download if missing
assert_gguf_downloaded() {
    _assert_concrete_model
    if ! ls "$GGUF_MODEL_DIR"/*.gguf >/dev/null 2>&1; then
        err "GGUF model not found for ${BONSAI_DISPLAY} (expected in ${GGUF_MODEL_DIR}/)."
        echo "  Download it with:"
        echo "    BONSAI_FAMILY=${BONSAI_FAMILY} BONSAI_MODEL=${BONSAI_MODEL} ./scripts/download_models.sh"
        exit 1
    fi
}

# Check MLX model is downloaded — prompts to download if missing
assert_mlx_downloaded() {
    _assert_concrete_model
    if [ ! -f "$MLX_MODEL_DIR/config.json" ]; then
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

# ── Smart context size for llama.cpp ──
# Default: -c 0 lets llama.cpp's --fit auto-size KV cache to available memory.
# Fallback: if -c 0 is not supported, pick a safe value from system RAM.
# Max context: 65536.
# Memory = ~1.1 GB weights + ~140 bytes/token KV cache + activations.
#   8 GB  → -c  8192  (~2.5 GB total, leaves ~5 GB for OS)
#  16 GB  → -c 32768  (~5.9 GB total, leaves ~10 GB for OS)
#  24 GB+ → -c 65536  (~10.5 GB total, leaves ~13+ GB for OS)

CTX_SIZE_DEFAULT=0

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

get_context_size_fallback() {
    if [ "$(uname -s)" = "Darwin" ]; then
        _mem_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    else
        _mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
        _mem_gb=$(( ${_mem_kb:-0} / 1048576 ))
    fi

    if [ "$_mem_gb" -le 8 ] 2>/dev/null; then
        echo 8192
    elif [ "$_mem_gb" -le 18 ] 2>/dev/null; then
        echo 32768
    else
        echo 65536
    fi
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
