#!/bin/sh
# Download Bonsai / Ternary-Bonsai models from HuggingFace.
#
# Usage:
#   ./scripts/download_models.sh                                         # Ternary-Bonsai 27B (default)
#   BONSAI_MODEL=4B ./scripts/download_models.sh                         # Ternary-Bonsai 4B
#   BONSAI_FAMILY=bonsai ./scripts/download_models.sh                    # Bonsai (1-bit) 27B
#   BONSAI_FAMILY=ternary BONSAI_MODEL=1.7B ./scripts/download_models.sh # Ternary-Bonsai 1.7B
#   BONSAI_MODEL=all ./scripts/download_models.sh                        # All sizes of the selected family
#   BONSAI_FAMILY=all ./scripts/download_models.sh                       # Both families, 27B size
#   BONSAI_FAMILY=all BONSAI_MODEL=all ./scripts/download_models.sh      # Full matrix (8 downloads)
#
# Set BONSAI_TOKEN (a read-only HF token) if you need to pull a repo that is
# still private; public repos download anonymously with no token.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

VENV_PY="$DEMO_DIR/.venv/bin/python"

# ── HuggingFace auth ──
# Use BONSAI_TOKEN (env, or the gitignored .bonsai_token file) if present.
# It is only needed for a repo that is still private; public repos download
# anonymously. We never hard-skip on a missing token: HF surfaces a clear 401
# if a repo genuinely needs auth, and once a repo goes public no token is
# required at all.
if [ -z "$BONSAI_TOKEN" ] && [ -f "$DEMO_DIR/.bonsai_token" ]; then
    BONSAI_TOKEN="$(tr -d '\r\n' < "$DEMO_DIR/.bonsai_token")"
fi
# Offer (never require) an interactive prompt when a tty is attached and no
# token is set. Declining is fine. `|| true`: EOF must not abort under set -e.
if [ -z "$BONSAI_TOKEN" ] && [ -r /dev/tty ]; then
    printf "  Optional HuggingFace token for any still-private repo (press Enter to skip): "
    { read -r BONSAI_TOKEN </dev/tty; } 2>/dev/null || true
fi
if [ -n "$BONSAI_TOKEN" ]; then
    export BONSAI_TOKEN
    export HF_TOKEN="$BONSAI_TOKEN"
fi

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
import os
from huggingface_hub import snapshot_download
kwargs = {'repo_id': '$_repo', 'local_dir': '$_dest'}
_p = '$_patterns'
if _p:
    kwargs['allow_patterns'] = [p for p in _p.split(',') if p]
# Private-repo auth (27B until launch); falls back to anonymous when unset.
if os.environ.get('BONSAI_TOKEN'):
    kwargs['token'] = os.environ['BONSAI_TOKEN']
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
            _gguf_pattern="*-Q1_0.gguf"
            ;;
        ternary)
            _gguf_repo="prism-ml/Ternary-Bonsai-${_size}-gguf"
            _mlx_repo="prism-ml/Ternary-Bonsai-${_size}-mlx-2bit"
            _gguf_dir="models/ternary-gguf/${_size}"
            _mlx_dir="models/Ternary-Bonsai-${_size}-mlx-2bit"
            _display="Ternary-Bonsai-${_size}"
            _gguf_pattern="*-Q2_0.gguf"
            ;;
    esac

    # 27B extras: the mmproj (multimodal projector) for image input, and the
    # paired dspark drafter GGUF for optional speculative decoding
    # (BONSAI_SPECULATIVE=1 in start_llama_server.sh). The hqq4 Q4_1 drafter is
    # the smallest/fastest variant and accepts identically to bf16.
    _dl_patterns="$_gguf_pattern"
    _mmproj_pattern=""
    _drafter_pattern=""
    if [ "$_size" = "27B" ]; then
        _mmproj_pattern="*mmproj*.gguf"
        _drafter_pattern="*dspark-Q4_1*.gguf"
        _dl_patterns="$_gguf_pattern,$_mmproj_pattern,$_drafter_pattern"
    fi

    # GGUF — stderr flows to the user so auth/network errors are visible.
    # Fast-path and post-download checks both filter on the target quant pattern
    # (not just any *.gguf) so a leftover F16 or other quant from an earlier
    # download doesn't get picked up at runtime. For 27B the fast-path also
    # requires the mmproj and drafter so a re-run backfills vision + speculative.
    _gguf_present=false
    if [ -d "$_gguf_dir" ] && ls "$_gguf_dir"/$_gguf_pattern >/dev/null 2>&1; then
        if { [ -z "$_mmproj_pattern" ] || ls "$_gguf_dir"/$_mmproj_pattern >/dev/null 2>&1; } \
            && { [ -z "$_drafter_pattern" ] || ls "$_gguf_dir"/$_drafter_pattern >/dev/null 2>&1; }; then
            _gguf_present=true
        fi
    fi
    if [ "$_gguf_present" = true ]; then
        info "GGUF ${_display} (${_gguf_pattern}) already present in ${_gguf_dir}/"
    else
        step "Downloading GGUF ${_display} (${_dl_patterns}) from ${_gguf_repo} ..."
        mkdir -p "$_gguf_dir"
        if ! hf_download "$_gguf_repo" "$_gguf_dir" "$_dl_patterns"; then
            err "Failed to download GGUF ${_display} from ${_gguf_repo}."
            exit 1
        fi
        if ! ls "$_gguf_dir"/$_gguf_pattern >/dev/null 2>&1; then
            err "Download reported success but no file matching ${_gguf_pattern} was written to ${_gguf_dir}/."
            exit 1
        fi
        if [ -n "$_mmproj_pattern" ] && ! ls "$_gguf_dir"/$_mmproj_pattern >/dev/null 2>&1; then
            warn "No ${_mmproj_pattern} file in ${_gguf_repo} — image input will be disabled for ${_display}."
        fi
        if [ -n "$_drafter_pattern" ] && ! ls "$_gguf_dir"/$_drafter_pattern >/dev/null 2>&1; then
            warn "No ${_drafter_pattern} file in ${_gguf_repo}; speculative decoding (BONSAI_SPECULATIVE=1) will be unavailable for ${_display}."
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
    all) _sizes="27B 8B 4B 1.7B" ;;
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
