#!/bin/sh
# Download Bonsai models from HuggingFace.
#
# Usage:
#   BONSAI_MODEL=8B  ./scripts/download_models.sh   # download 8B (default)
#   BONSAI_MODEL=4B  ./scripts/download_models.sh   # download 4B
#   BONSAI_MODEL=all ./scripts/download_models.sh   # download all sizes
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

VENV_PY="$DEMO_DIR/.venv/bin/python"

# ┌──────────────────────────────────────────────────────────────────┐
# │ TOKEN SECTION — remove this block once models are public        │
# └──────────────────────────────────────────────────────────────────┘
if [ -z "$PRISM_HF_TOKEN" ] && [ -f "$DEMO_DIR/.prism_hf_token" ]; then
    PRISM_HF_TOKEN="$(cat "$DEMO_DIR/.prism_hf_token")"
fi
if [ -z "$PRISM_HF_TOKEN" ]; then
    echo ""
    echo "  Models are hosted on private HuggingFace repos."
    echo "  You need a read-only HF token — ask the team or create one at:"
    echo "    https://huggingface.co/settings/tokens"
    echo ""
    printf "  Paste your HuggingFace token (or press Enter to skip): "
    if [ -r /dev/tty ]; then read -r PRISM_HF_TOKEN </dev/tty; else read -r PRISM_HF_TOKEN; fi
fi

if [ -z "$PRISM_HF_TOKEN" ]; then
    warn "No PRISM_HF_TOKEN provided. Skipping model download."
    echo "  Set PRISM_HF_TOKEN and re-run, or download manually from:"
    echo "    https://huggingface.co/prism-ml"
    exit 0
fi

export PRISM_HF_TOKEN
export HF_TOKEN="$PRISM_HF_TOKEN"
_HF_TOKEN_ARG="token=os.environ['PRISM_HF_TOKEN'],"
# ┌──────────────────────────────────────────────────────────────────┐
# │ END TOKEN SECTION                                               │
# └──────────────────────────────────────────────────────────────────┘

# ── Find Python with huggingface_hub ──
PY=""
if [ -x "$VENV_PY" ]; then
    PY="$VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
    PY="python3"
fi

if [ -z "$PY" ] || ! "$PY" -c "import huggingface_hub" 2>/dev/null; then
    err "huggingface_hub not found."
    echo "  Run ./setup.sh first, or: uv pip install huggingface-hub"
    exit 1
fi

# ── Helper: download a HF repo via Python ──
hf_download() {
    _repo="$1"
    _dest="$2"
    "$PY" -c "
from huggingface_hub import snapshot_download
import os
snapshot_download(
    repo_id='$_repo',
    local_dir='$_dest',
    $_HF_TOKEN_ARG
)
"
}

# ── Download GGUF + MLX for one model size ──
download_size() {
    _size="$1"
    _gguf_repo="prism-ml/Bonsai-${_size}-gguf"
    _mlx_repo="prism-ml/Bonsai-${_size}-mlx-1bit"
    _gguf_dir="models/gguf/${_size}"
    _mlx_dir="models/Bonsai-${_size}-mlx"

    # GGUF
    if [ -d "$_gguf_dir" ] && ls "$_gguf_dir"/*.gguf >/dev/null 2>&1; then
        info "GGUF ${_size} already present in ${_gguf_dir}/"
    else
        step "Downloading GGUF ${_size} from ${_gguf_repo} ..."
        mkdir -p "$_gguf_dir"
        hf_download "$_gguf_repo" "$_gguf_dir"
        info "GGUF ${_size} downloaded to ${_gguf_dir}/"
    fi

    # MLX (macOS only)
    if [ "$(uname -s)" = "Darwin" ]; then
        if [ -d "$_mlx_dir" ] && [ -f "$_mlx_dir/config.json" ]; then
            info "MLX ${_size} already present in ${_mlx_dir}/"
        else
            step "Downloading MLX ${_size} from ${_mlx_repo} ..."
            hf_download "$_mlx_repo" "$_mlx_dir"
            info "MLX ${_size} downloaded to ${_mlx_dir}/"
        fi
    fi
}

mkdir -p models

if [ "$BONSAI_MODEL" = "all" ]; then
    for _s in $ALL_MODEL_SIZES; do
        download_size "$_s"
    done
else
    download_size "$BONSAI_MODEL"
fi

if [ "$(uname -s)" != "Darwin" ]; then
    info "Skipping MLX models (macOS only)."
fi

echo ""
info "Model download complete."
