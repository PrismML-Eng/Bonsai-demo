#!/bin/sh
# Download Bonsai / Ternary-Bonsai models from HuggingFace.
#
# Usage:
#   ./scripts/download_models.sh                                        # Bonsai 8B (default)
#   BONSAI_MODEL=4B ./scripts/download_models.sh                        # Bonsai 4B
#   BONSAI_FAMILY=ternary ./scripts/download_models.sh                  # Ternary-Bonsai 8B
#   BONSAI_FAMILY=ternary BONSAI_MODEL=1.7B ./scripts/download_models.sh # Ternary-Bonsai 1.7B
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

VENV_PY="$DEMO_DIR/.venv/bin/python"


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
snapshot_download(
    repo_id='$_repo',
    local_dir='$_dest',
)
"
}

# ── Download GGUF + MLX for one model size ──
download_size() {
    _size="$1"
    case "$BONSAI_FAMILY" in
        bonsai)
            _gguf_repo="prism-ml/Bonsai-${_size}-gguf"
            _mlx_repo="prism-ml/Bonsai-${_size}-mlx-1bit"
            _gguf_dir="models/gguf/${_size}"
            _mlx_dir="models/Bonsai-${_size}-mlx"
            _display="Bonsai-${_size}"
            _gguf_optional=0
            ;;
        ternary)
            _gguf_repo="prism-ml/Ternary-Bonsai-${_size}-gguf"
            _mlx_repo="prism-ml/Ternary-Bonsai-${_size}-mlx-2bit"
            _gguf_dir="models/ternary-gguf/${_size}"
            _mlx_dir="models/Ternary-Bonsai-${_size}-mlx"
            _display="Ternary-Bonsai-${_size}"
            _gguf_optional=1   # GGUFs not yet public — skip gracefully on failure
            ;;
    esac

    # GGUF
    if [ -d "$_gguf_dir" ] && ls "$_gguf_dir"/*.gguf >/dev/null 2>&1; then
        info "GGUF ${_display} already present in ${_gguf_dir}/"
    else
        step "Downloading GGUF ${_display} from ${_gguf_repo} ..."
        mkdir -p "$_gguf_dir"
        if hf_download "$_gguf_repo" "$_gguf_dir" 2>/dev/null; then
            info "GGUF ${_display} downloaded to ${_gguf_dir}/"
        elif [ "$_gguf_optional" = 1 ]; then
            warn "GGUF ${_display} not available yet (coming soon — repo: ${_gguf_repo})."
            rmdir "$_gguf_dir" 2>/dev/null || true
        else
            err "Failed to download GGUF ${_display} from ${_gguf_repo}."
            exit 1
        fi
    fi

    # MLX (macOS Apple Silicon only; skipped on Intel or when BONSAI_SKIP_MLX=1)
    if [ "$(uname -s)" = "Darwin" ] && ! bonsai_should_skip_mlx; then
        if [ -d "$_mlx_dir" ] && [ -f "$_mlx_dir/config.json" ]; then
            info "MLX ${_display} already present in ${_mlx_dir}/"
        else
            step "Downloading MLX ${_display} from ${_mlx_repo} ..."
            hf_download "$_mlx_repo" "$_mlx_dir"
            info "MLX ${_display} downloaded to ${_mlx_dir}/"
        fi
    fi
}

mkdir -p models

download_size "$BONSAI_MODEL"

if [ "$(uname -s)" != "Darwin" ]; then
    info "Skipping MLX models (macOS only)."
elif bonsai_should_skip_mlx; then
    info "Skipping MLX weights (Intel macOS or BONSAI_SKIP_MLX=1)."
fi

echo ""
info "Model download complete."
