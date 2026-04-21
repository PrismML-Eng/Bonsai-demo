#!/bin/sh
# Download Bonsai / Ternary-Bonsai models from HuggingFace.
#
# Usage:
#   ./scripts/download_models.sh                                         # Bonsai 8B (default)
#   BONSAI_MODEL=4B ./scripts/download_models.sh                         # Bonsai 4B
#   BONSAI_FAMILY=ternary ./scripts/download_models.sh                   # Ternary-Bonsai 8B
#   BONSAI_FAMILY=ternary BONSAI_MODEL=1.7B ./scripts/download_models.sh # Ternary-Bonsai 1.7B
#   BONSAI_MODEL=all ./scripts/download_models.sh                        # All sizes of the selected family
#   BONSAI_FAMILY=all ./scripts/download_models.sh                       # Both families, 8B size
#   BONSAI_FAMILY=all BONSAI_MODEL=all ./scripts/download_models.sh      # Full matrix (6 downloads)
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
# Third arg (optional) is a comma-separated allow_patterns filter — when set,
# only files matching any of those glob patterns are downloaded.
hf_download() {
    _repo="$1"
    _dest="$2"
    _patterns="${3:-}"
    "$PY" -c "
from huggingface_hub import snapshot_download
kwargs = {'repo_id': '$_repo', 'local_dir': '$_dest'}
_p = '$_patterns'
if _p:
    kwargs['allow_patterns'] = [p for p in _p.split(',') if p]
snapshot_download(**kwargs)
"
}

# ── Download GGUF + MLX for one (family, size) pair ──
download_one() {
    _family="$1"
    _size="$2"
    # Each GGUF repo ships multiple quants (e.g. F16 + Q2_0); we only want the
    # quant the demo is built around, so restrict the download via allow_patterns.
    case "$_family" in
        bonsai)
            _gguf_repo="prism-ml/Bonsai-${_size}-gguf"
            _mlx_repo="prism-ml/Bonsai-${_size}-mlx-1bit"
            _gguf_dir="models/gguf/${_size}"
            _mlx_dir="models/Bonsai-${_size}-mlx"
            _display="Bonsai-${_size}"
            _gguf_pattern="*Q1_0*.gguf"
            ;;
        ternary)
            _gguf_repo="prism-ml/Ternary-Bonsai-${_size}-gguf"
            _mlx_repo="prism-ml/Ternary-Bonsai-${_size}-mlx-2bit"
            _gguf_dir="models/ternary-gguf/${_size}"
            _mlx_dir="models/Ternary-Bonsai-${_size}-mlx"
            _display="Ternary-Bonsai-${_size}"
            _gguf_pattern="*Q2_0*.gguf"
            ;;
    esac

    # GGUF — stderr flows to the user so auth/network errors are visible.
    # Fast-path and post-download checks both filter on the target quant pattern
    # (not just any *.gguf) so a leftover F16 or other quant from an earlier
    # download doesn't get picked up at runtime.
    if [ -d "$_gguf_dir" ] && ls "$_gguf_dir"/$_gguf_pattern >/dev/null 2>&1; then
        info "GGUF ${_display} (${_gguf_pattern}) already present in ${_gguf_dir}/"
    else
        step "Downloading GGUF ${_display} (${_gguf_pattern}) from ${_gguf_repo} ..."
        mkdir -p "$_gguf_dir"
        if ! hf_download "$_gguf_repo" "$_gguf_dir" "$_gguf_pattern"; then
            err "Failed to download GGUF ${_display} from ${_gguf_repo}."
            exit 1
        fi
        if ! ls "$_gguf_dir"/$_gguf_pattern >/dev/null 2>&1; then
            err "Download reported success but no file matching ${_gguf_pattern} was written to ${_gguf_dir}/."
            exit 1
        fi
        info "GGUF ${_display} downloaded to ${_gguf_dir}/"
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

# Expand "all" for family and size into concrete lists, then iterate.
case "$BONSAI_FAMILY" in
    all) _families="bonsai ternary" ;;
    *)   _families="$BONSAI_FAMILY" ;;
esac
case "$BONSAI_MODEL" in
    all) _sizes="8B 4B 1.7B" ;;
    *)   _sizes="$BONSAI_MODEL" ;;
esac

for _f in $_families; do
    for _s in $_sizes; do
        download_one "$_f" "$_s"
    done
done

if [ "$(uname -s)" != "Darwin" ]; then
    info "Skipping MLX models (macOS only)."
elif bonsai_should_skip_mlx; then
    info "Skipping MLX weights (Intel macOS or BONSAI_SKIP_MLX=1)."
fi

echo ""
info "Model download complete."
