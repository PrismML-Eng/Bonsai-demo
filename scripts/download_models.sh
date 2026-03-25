#!/bin/sh
# Download Bonsai models from HuggingFace.
# Requires PRISM_HF_TOKEN env var (private repos — will be made public later).
#
# Usage:  PRISM_HF_TOKEN=hf_xxx ./scripts/download_models.sh
#   or:   ./scripts/download_models.sh   (will prompt if PRISM_HF_TOKEN not set)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

VENV_PY="$DEMO_DIR/.venv/bin/python"

# ── HuggingFace repos ──
HF_GGUF_REPO="prism-ml/Bonsai-8B-gguf"
HF_MLX_REPO="prism-ml/Bonsai-8B-mlx-1bit"

# ── Resolve PRISM_HF_TOKEN: env var > saved file > prompt ──
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
    echo "  Set PRISM_HF_TOKEN and re-run, or download manually:"
    echo "    GGUF: https://huggingface.co/$HF_GGUF_REPO"
    echo "    MLX:  https://huggingface.co/$HF_MLX_REPO"
    exit 0
fi

export PRISM_HF_TOKEN
export HF_TOKEN="$PRISM_HF_TOKEN"

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
    token=os.environ['PRISM_HF_TOKEN'],
)
"
}

mkdir -p models

# ── Download GGUF model ──
if [ -d "models/gguf" ] && ls models/gguf/*.gguf >/dev/null 2>&1; then
    info "GGUF model already present in models/gguf/"
else
    step "Downloading GGUF model from $HF_GGUF_REPO ..."
    hf_download "$HF_GGUF_REPO" "models/gguf"
    info "GGUF model downloaded to models/gguf/"
fi

# ── Download MLX model (macOS only — skip on Linux/Windows) ──
if [ "$(uname -s)" = "Darwin" ]; then
    if [ -d "models/Bonsai-8B-mlx" ] && [ -f "models/Bonsai-8B-mlx/config.json" ]; then
        info "MLX model already present in models/Bonsai-8B-mlx/"
    else
        step "Downloading MLX model from $HF_MLX_REPO ..."
        hf_download "$HF_MLX_REPO" "models/Bonsai-8B-mlx"
        info "MLX model downloaded to models/Bonsai-8B-mlx/"
    fi
else
    info "Skipping MLX model (macOS only)."
fi

echo ""
info "Model download complete."
