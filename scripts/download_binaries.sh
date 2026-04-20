#!/bin/sh
# Download pre-built llama.cpp binaries from GitHub Release.
# Auto-detects OS and CUDA version.
#
# Usage:  ./scripts/download_binaries.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

RELEASE_TAG="prism-b8846-d104cf1"
BASE_URL="https://github.com/PrismML-Eng/llama.cpp/releases/download/$RELEASE_TAG"

OS="$(uname -s)"

case "$OS" in
    Darwin)
        _arch="$(uname -m)"
        if [ "$_arch" = "arm64" ]; then
            ASSET="llama-${RELEASE_TAG}-bin-macos-arm64.tar.gz"
        else
            ASSET="llama-${RELEASE_TAG}-bin-macos-x64.tar.gz"
        fi
        DEST="bin/mac"
        ;;
    Linux)
        # ── Detect architecture ──
        _arch="$(uname -m)"
        case "$_arch" in
            x86_64)  _arch_tag="x64" ;;
            aarch64) _arch_tag="arm64" ;;
            *)       err "Unsupported Linux architecture: $_arch (supported: x86_64, aarch64)"; exit 1 ;;
        esac

        # ── Detect GPU: NVIDIA (CUDA), AMD (ROCm), or Vulkan ──
        _gpu_type=""
        _cuda_ver=""

        # Check for NVIDIA first
        if command -v nvcc >/dev/null 2>&1; then
            _cuda_ver=$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p')
        elif command -v nvidia-smi >/dev/null 2>&1; then
            _cuda_ver=$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version:[[:space:]]*\([0-9]*\.[0-9]*\).*/\1/p')
        fi

        if [ -n "$_cuda_ver" ]; then
            _gpu_type="cuda"
        elif command -v rocminfo >/dev/null 2>&1 || command -v rocm-smi >/dev/null 2>&1 || command -v hipcc >/dev/null 2>&1; then
            _gpu_type="rocm"
        elif command -v vulkaninfo >/dev/null 2>&1; then
            _gpu_type="vulkan"
        fi

        # Guard CUDA/ROCm to x64 only (no arm64 builds available)
        if [ "$_arch_tag" != "x64" ] && { [ "$_gpu_type" = "cuda" ] || [ "$_gpu_type" = "rocm" ]; }; then
            warn "$_gpu_type detected but no $_gpu_type build available for $_arch_tag — falling back."
            _gpu_type=""
        fi

        # Resolve CUDA version tag
        if [ "$_gpu_type" = "cuda" ]; then
            _major="${_cuda_ver%%.*}"
            _minor="${_cuda_ver#*.}"
            if [ "$_major" -ge 13 ] || { [ "$_major" -eq 12 ] && [ "$_minor" -ge 8 ]; }; then
                _cuda_tag="12.8"
            elif [ "$_major" -eq 12 ]; then
                _cuda_tag="12.4"
            else
                warn "Detected CUDA $_cuda_ver — no matching build, falling back to CUDA 12.4"
                _cuda_tag="12.4"
            fi
            info "Detected CUDA $_cuda_ver → using build for CUDA $_cuda_tag"
        fi

        # Select asset
        if [ "$_gpu_type" = "cuda" ]; then
            ASSET="llama-${RELEASE_TAG}-bin-linux-cuda-${_cuda_tag}-x64.tar.gz"
            DEST="bin/cuda"
        elif [ "$_gpu_type" = "rocm" ]; then
            info "Detected AMD ROCm → using ROCm 7.2 build"
            ASSET="llama-${RELEASE_TAG}-bin-ubuntu-rocm-7.2-x64.tar.gz"
            DEST="bin/rocm"
        elif [ "$_gpu_type" = "vulkan" ]; then
            info "Detected Vulkan → using Vulkan build"
            ASSET="llama-${RELEASE_TAG}-bin-ubuntu-vulkan-${_arch_tag}.tar.gz"
            DEST="bin/vulkan"
        else
            info "No GPU detected → using CPU build ($_arch_tag)"
            ASSET="llama-${RELEASE_TAG}-bin-ubuntu-${_arch_tag}.tar.gz"
            DEST="bin/cpu"
        fi
        ;;
    *)
        err "Unsupported OS: $OS. Use setup.ps1 on Windows."
        exit 1
        ;;
esac

URL="$BASE_URL/$ASSET"

if [ -d "$DEST" ] && ls "$DEST"/llama-* >/dev/null 2>&1; then
    info "Binaries already present in $DEST/"
    exit 0
fi

step "Downloading $ASSET ..."
echo "  From: $URL"
_tmp=$(mktemp)
_download_ok=true
if command -v curl >/dev/null 2>&1; then
    curl -L --fail --progress-bar "$URL" -o "$_tmp" || _download_ok=false
elif command -v wget >/dev/null 2>&1; then
    wget --show-progress -qO "$_tmp" "$URL" || _download_ok=false
else
    err "Neither curl nor wget found."
    _download_ok=false
fi

if [ "$_download_ok" = false ] || [ ! -s "$_tmp" ]; then
    rm -f "$_tmp"
    err "Download failed."
    echo ""
    echo "  You can build from source instead:"
    case "$OS" in
        Darwin) echo "    ./scripts/build_mac.sh" ;;
        *)      echo "    ./scripts/build_cuda_linux.sh" ;;
    esac
    echo ""
    exit 1
fi

step "Extracting to $DEST/ ..."
mkdir -p "$DEST"
tar -xzf "$_tmp" -C "$DEST" --strip-components=1 2>/dev/null \
    || tar -xzf "$_tmp" -C "$DEST"
rm -f "$_tmp"

# ── macOS: clear Gatekeeper quarantine + ad-hoc codesign ──
if [ "$OS" = "Darwin" ]; then
    step "Clearing macOS Gatekeeper quarantine ..."
    xattr -cr "$DEST" 2>/dev/null || true

    for _f in "$DEST"/llama-*; do
        [ -f "$_f" ] && codesign -s - --force --timestamp=none "$_f" 2>/dev/null || true
    done

    # Smoke test
    _test_bin=""
    for _b in "$DEST/llama-cli" "$DEST/llama-server"; do
        [ -x "$_b" ] && _test_bin="$_b" && break
    done

    if [ -n "$_test_bin" ]; then
        if "$_test_bin" --version >/dev/null 2>&1 || "$_test_bin" --help >/dev/null 2>&1; then
            info "Binary smoke test passed."
        else
            warn "macOS security may have blocked the binary."
            echo ""
            echo "  Please do ONE of the following:"
            echo ""
            echo "  Option A (recommended): Build from source — avoids Gatekeeper entirely:"
            echo "    ./scripts/build_mac.sh"
            echo ""
            echo "  Option B: Manually allow in System Settings:"
            echo "    1. Open System Settings > Privacy & Security"
            echo "    2. Scroll down — you should see a message about \"llama-cli\""
            echo "    3. Click \"Allow Anyway\""
            echo "    4. Re-run: ./scripts/download_binaries.sh"
            echo ""
        fi
    fi
fi

info "Binaries installed to $DEST/"
ls -lh "$DEST"/llama-* 2>/dev/null || true
