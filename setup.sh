#!/bin/sh
# Bonsai Demo — One-command setup for macOS and Linux.
# Installs all dependencies, downloads models and binaries.
#
# Usage:
#   ./setup.sh                      (downloads 8B model by default)
#   BONSAI_MODEL=4B ./setup.sh      (download a different model size)
set -e

# ── Resolve paths ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
. "$SCRIPT_DIR/scripts/common.sh"
assert_valid_model

VENV_DIR="$SCRIPT_DIR/.venv"
VENV_PY="$VENV_DIR/bin/python"
PYTHON_VERSION="3.11"

# ────────────────────────────────────────────────────
#  Helpers
# ────────────────────────────────────────────────────

# Colors (only when stdout is a terminal)
if [ -t 1 ]; then
    _G="\033[32m" _Y="\033[33m" _R="\033[31m" _C="\033[36m" _0="\033[0m"
else
    _G="" _Y="" _R="" _C="" _0=""
fi
info()  { printf "${_G}[OK]${_0}   %s\n" "$*"; }
warn()  { printf "${_Y}[WARN]${_0} %s\n" "$*"; }
err()   { printf "${_R}[ERR]${_0}  %s\n" "$*" >&2; }
step()  { printf "\n${_C}==> %s${_0}\n" "$*"; }

# Download helper (curl or wget)
download() {
    if command -v curl >/dev/null 2>&1; then
        curl -LsSf "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        err "Neither curl nor wget found. Install one and re-run."
        exit 1
    fi
}

# Prompt with default (works even when piped: reads from /dev/tty)
ask() {
    _prompt="$1"
    _default="$2"
    printf "%s [%s]: " "$_prompt" "$_default"
    if [ -r /dev/tty ]; then
        read -r REPLY </dev/tty || REPLY=""
    else
        read -r REPLY || REPLY=""
    fi
    [ -z "$REPLY" ] && REPLY="$_default"
}

# Smart apt install (try without sudo, escalate if needed)
_smart_apt_install() {
    _pkgs="$*"

    apt-get update -y </dev/null >/dev/null || true
    apt-get install -y $_pkgs </dev/null >/dev/null || true

    _still_missing=""
    for _p in $_pkgs; do
        case "$_p" in
            build-essential) command -v gcc >/dev/null 2>&1 || _still_missing="$_still_missing $_p" ;;
            *) command -v "$_p" >/dev/null 2>&1 || _still_missing="$_still_missing $_p" ;;
        esac
    done
    _still_missing=$(echo "$_still_missing" | sed 's/^ *//')
    [ -z "$_still_missing" ] && return 0

    if command -v sudo >/dev/null 2>&1; then
        echo ""
        warn "Need elevated permissions to install: $_still_missing"
        printf "  Allow sudo? [Y/n] "
        if [ -r /dev/tty ]; then read -r _yn </dev/tty; else read -r _yn; fi
        case "$_yn" in
            [nN]*)
                echo "  Please install manually: sudo apt-get install -y $_still_missing"
                exit 1 ;;
            *)
                sudo apt-get update -y </dev/null
                sudo apt-get install -y $_still_missing </dev/null ;;
        esac
    else
        err "sudo not available. Install as root: apt-get install -y $_still_missing"
        exit 1
    fi
}

# Semver comparison: returns 0 if $1 >= $2
_version_ge() {
    _a=$1 _b=$2
    while [ -n "$_a" ] || [ -n "$_b" ]; do
        _ap=${_a%%.*} _bp=${_b%%.*}
        [ "$_a" = "$_ap" ] && _a="" || _a=${_a#*.}
        [ "$_b" = "$_bp" ] && _b="" || _b=${_b#*.}
        [ -z "$_ap" ] && _ap=0; [ -z "$_bp" ] && _bp=0
        [ "$_ap" -gt "$_bp" ] 2>/dev/null && return 0
        [ "$_ap" -lt "$_bp" ] 2>/dev/null && return 1
    done
    return 0
}

# ── Model selection ──
BONSAI_MODEL="${BONSAI_MODEL:-8B}"
BONSAI_FAMILY="${BONSAI_FAMILY:-bonsai}"

echo ""
echo "========================================="
echo "   Bonsai Demo Setup"
echo "   Family: ${BONSAI_FAMILY}"
echo "   Model:  ${BONSAI_MODEL}"
echo "========================================="
echo ""


# ────────────────────────────────────────────────────
#  2. Detect platform
# ────────────────────────────────────────────────────
OS="$(uname -s)"
step "Detected platform: $OS"

# ────────────────────────────────────────────────────
#  2. System dependencies
# ────────────────────────────────────────────────────
case "$OS" in
    Darwin)
        step "Checking Xcode Command Line Tools ..."
        if ! xcode-select -p >/dev/null 2>&1; then
            warn "Xcode CLT not installed. Installing now (a system dialog will appear) ..."
            xcode-select --install </dev/null || true
            echo ""
            echo "  After the Xcode CLT installation completes, please re-run:"
            echo "    ./setup.sh"
            exit 1
        fi
        info "Xcode CLT found at $(xcode-select -p)"
        ;;

    Linux)
        step "Checking system packages ..."
        _missing=""
        command -v git  >/dev/null 2>&1 || _missing="$_missing git"
        command -v gcc  >/dev/null 2>&1 || _missing="$_missing build-essential"
        command -v curl >/dev/null 2>&1 && true || {
            command -v wget >/dev/null 2>&1 || _missing="$_missing curl"
        }
        _missing=$(echo "$_missing" | sed 's/^ *//')

        if [ -n "$_missing" ]; then
            warn "Missing packages: $_missing"
            if command -v apt-get >/dev/null 2>&1; then
                _smart_apt_install $_missing
            else
                err "apt-get not found. Please install: $_missing"
                exit 1
            fi
        fi
        info "System packages OK."

        # GPU toolkit check (non-fatal)
        if command -v nvcc >/dev/null 2>&1 || command -v nvidia-smi >/dev/null 2>&1; then
            info "NVIDIA CUDA toolkit detected."
        elif command -v rocminfo >/dev/null 2>&1 || command -v rocm-smi >/dev/null 2>&1 || command -v hipcc >/dev/null 2>&1; then
            info "AMD ROCm toolkit detected."
        else
            warn "No GPU toolkit found (CUDA or ROCm). Pre-built binaries can still be downloaded,"
            echo "       but building from source requires a GPU toolkit."
            echo "       NVIDIA: https://developer.nvidia.com/cuda-downloads"
            echo "       AMD:    https://rocm.docs.amd.com/en/latest/deploy/linux/installer/install.html"
        fi
        ;;

    *)
        err "Unsupported OS: $OS. Use setup.ps1 on Windows."
        exit 1
        ;;
esac

# ────────────────────────────────────────────────────
#  3. Install uv
# ────────────────────────────────────────────────────
UV_MIN="0.7.0"

_uv_ok() {
    command -v uv >/dev/null 2>&1 || return 1
    _ver=$(uv --version 2>/dev/null | awk '{print $2}')
    [ -n "$_ver" ] && _version_ge "$_ver" "$UV_MIN"
}

step "Checking uv ..."
if _uv_ok; then
    info "uv $(uv --version 2>/dev/null | awk '{print $2}') found."
else
    step "Installing uv ..."
    _tmp=$(mktemp)
    download "https://astral.sh/uv/install.sh" "$_tmp"
    sh "$_tmp" </dev/null
    rm -f "$_tmp"
    [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
    export PATH="$HOME/.local/bin:$PATH"
    if ! _uv_ok; then
        err "uv installation failed. Install manually: https://docs.astral.sh/uv/"
        exit 1
    fi
    info "uv installed."
fi

# ────────────────────────────────────────────────────
#  4. Create Python venv
# ────────────────────────────────────────────────────
step "Setting up Python environment ..."
if [ -x "$VENV_PY" ]; then
    info "Existing venv found at $VENV_DIR"
else
    uv venv "$VENV_DIR" --python "$PYTHON_VERSION"
    info "Created venv with Python $PYTHON_VERSION"
fi

# ────────────────────────────────────────────────────
#  5. Install Python deps (cmake, ninja, huggingface-hub, etc.)
# ────────────────────────────────────────────────────
step "Installing base Python dependencies ..."
uv sync
info "Base deps installed (cmake, ninja, setuptools, huggingface-cli)."

# ────────────────────────────────────────────────────
#  6. Download models from HuggingFace
# ────────────────────────────────────────────────────
step "Model download (BONSAI_FAMILY=${BONSAI_FAMILY} BONSAI_MODEL=${BONSAI_MODEL}) ..."
BONSAI_FAMILY="$BONSAI_FAMILY" BONSAI_MODEL="$BONSAI_MODEL" sh "$SCRIPT_DIR/scripts/download_models.sh"

# ────────────────────────────────────────────────────
#  7. llama.cpp pre-built binaries
# ────────────────────────────────────────────────────
_has_binaries=false
for _d in bin/mac bin/cuda bin/rocm bin/hip bin/vulkan bin/cpu; do
    ls "$_d"/llama-* >/dev/null 2>&1 && _has_binaries=true && break
done

if [ "$_has_binaries" = true ]; then
    info "llama.cpp binaries already present."
else
    sh "$SCRIPT_DIR/scripts/download_binaries.sh"
fi

chmod +x "$SCRIPT_DIR"/scripts/*.sh 2>/dev/null || true

echo ""
if [ "$OS" = "Darwin" ] && ! bonsai_should_skip_mlx; then
    info "llama.cpp is ready! You can start using it now while MLX builds."
elif [ "$OS" = "Darwin" ]; then
    info "llama.cpp is ready! (MLX skipped — Intel Mac or BONSAI_SKIP_MLX=1; use ./scripts/run_llama.sh)"
else
    info "llama.cpp is ready!"
fi

# ────────────────────────────────────────────────────
#  8. MLX (macOS only, Apple Silicon) — clone and build from source
# ────────────────────────────────────────────────────
if [ "$OS" = "Darwin" ] && ! bonsai_should_skip_mlx; then
    step "Setting up MLX (Apple Silicon) ..."

    # MLX builds Metal GPU kernels, which requires the full Xcode app *and*
    # the Metal Toolchain component. Two user-facing failure modes are handled:
    #   1. Only CLT installed (no metal binary at all)
    #   2. 'metal' compiler present but unusable (e.g. xcodebuild first-launch
    #      not completed or Metal Toolchain component not downloaded)
    _metal_ok=false
    if xcrun metal --version >/dev/null 2>&1; then
        _metal_ok=true
    fi

    if [ "$_metal_ok" = false ]; then
        # Distinguish: binary missing vs. present-but-broken
        if ! xcrun --find metal >/dev/null 2>&1; then
            err "The 'metal' shader compiler is not available."
            echo ""
            echo "  MLX requires the full Xcode app (not just Command Line Tools)."
            echo "  1. Install Xcode from the App Store:"
            echo "       https://developer.apple.com/xcode/"
            echo "  2. Switch the active developer directory to Xcode:"
            echo "       sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
            echo "  3. Accept the Xcode license and complete first-launch setup:"
            echo "       sudo xcodebuild -license accept"
            echo "       xcodebuild -runFirstLaunch"
            echo "  4. Download the Metal Toolchain component:"
            echo "       xcodebuild -downloadComponent MetalToolchain"
            echo "  5. Re-run ./setup.sh"
        else
            err "The 'metal' compiler is present but cannot execute."
            echo ""
            echo "  The Metal Toolchain component may not be installed."
            echo "  Run the following commands, then re-run ./setup.sh:"
            echo ""
            echo "    sudo xcodebuild -license accept"
            echo "    xcodebuild -runFirstLaunch"
            echo "    xcodebuild -downloadComponent MetalToolchain"
        fi
        exit 1
    fi

    if [ -d "mlx" ]; then
        info "MLX repo already present."
    else
        step "Cloning PrismML-Eng/mlx (prism branch) ..."
        git clone -b prism https://github.com/PrismML-Eng/mlx.git mlx
    fi

    step "Building MLX from source (this takes 2-5 minutes on first install) ..."
    # --no-build-isolation required: MLX's C++/Metal build needs pre-installed setuptools
    uv pip install --python "$VENV_PY" -e mlx/ --no-build-isolation
    step "Installing MLX Python deps (mlx-lm, torch, transformers, ...) ..."
    uv pip install --python "$VENV_PY" \
        "mlx-lm==0.30.7" "torch==2.10.0" "transformers==5.2.0" \
        "safetensors==0.7.0" "tokenizers==0.22.2" "sentencepiece==0.2.1" \
        "protobuf==7.34.0" "numpy==2.4.2" "gguf==0.18.0"
    info "MLX installed."
fi

# ────────────────────────────────────────────────────
#  Done!
# ────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "   Setup complete! (BONSAI_FAMILY=${BONSAI_FAMILY} BONSAI_MODEL=${BONSAI_MODEL})"
echo "========================================="
echo ""
echo "  See README.md for usage examples."
echo ""
