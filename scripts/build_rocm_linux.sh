#!/bin/bash
# Build llama.cpp with ROCm/HIP on Linux.
# Prerequisites: ROCm toolkit (hipcc), cmake, ninja-build or make.
#
# Usage:
#   ./scripts/build_rocm_linux.sh [options] [path_to_llama_cpp_repo]
#
# Options:
#   --rocm-path PATH     ROCm install prefix (default: /opt/rocm if present)
#   --targets TARGETS    AMDGPU targets (default: gfx1151)
#   --output DIR         Output directory name under bin/ (default: rocm)
#
# Examples:
#   ./scripts/build_rocm_linux.sh
#   ./scripts/build_rocm_linux.sh --targets gfx1151
#   ./scripts/build_rocm_linux.sh --rocm-path /opt/rocm-7.2.1 --output rocm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

ROCM_PATH=""
AMDGPU_TARGETS="${AMDGPU_TARGETS:-gfx1151}"
OUTPUT_DIR=""
REPO_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rocm-path) ROCM_PATH="$2"; shift 2 ;;
        --targets) AMDGPU_TARGETS="$2"; shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        *) REPO_DIR="$1"; shift ;;
    esac
done

REPO_DIR="${REPO_DIR:-./llama.cpp}"
TARGETS="llama-completion llama-cli llama-server llama-quantize llama-perplexity llama-bench test-quantize-fns"
OUTPUT_DIR="${OUTPUT_DIR:-rocm}"
DEST="./bin/$OUTPUT_DIR"
BUILD_DIR="build-rocm"

if [ ! -d "$REPO_DIR" ]; then
    step "Cloning PrismML-Eng/llama.cpp (prism branch) ..."
    git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git "$REPO_DIR"
fi

if [ -z "$ROCM_PATH" ]; then
    if [ -d /opt/rocm ]; then
        ROCM_PATH="/opt/rocm"
    elif command -v hipcc >/dev/null 2>&1; then
        ROCM_PATH="$(cd "$(dirname "$(command -v hipcc)")/.." && pwd)"
    else
        err "ROCm toolkit not found. Install ROCm or pass --rocm-path."
        exit 1
    fi
fi

export PATH="$ROCM_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if ! command -v hipcc >/dev/null 2>&1; then
    err "hipcc not found after adding $ROCM_PATH/bin to PATH."
    exit 1
fi

if [ ! -f "$ROCM_PATH/lib/cmake/hip-lang/hip-lang-config.cmake" ]; then
    err "hip-lang CMake package not found. Install hip-dev and rocm-cmake."
    exit 1
fi

if [ ! -f "$ROCM_PATH/lib/cmake/hipblas/hipblas-config.cmake" ]; then
    err "hipBLAS CMake package not found. Install hipblas-dev and rocblas-dev."
    exit 1
fi

step "Building llama.cpp with ROCm/HIP"
echo "  Repo:    $REPO_DIR"
echo "  ROCm:    $ROCM_PATH"
echo "  Targets: $AMDGPU_TARGETS"
echo "  Output:  $DEST"

cd "$REPO_DIR"
cmake -B "$BUILD_DIR" \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS="$AMDGPU_TARGETS" \
    -DCMAKE_BUILD_TYPE=Release

BUILD_JOBS="$(nproc)"
cmake --build "$BUILD_DIR" --target $TARGETS -j"$BUILD_JOBS"
cd - >/dev/null

step "Installing binaries to $DEST/ ..."
rm -rf "$DEST"
mkdir -p "$DEST"

for bin in $TARGETS; do
    if [ -f "$REPO_DIR/$BUILD_DIR/bin/$bin" ]; then
        cp "$REPO_DIR/$BUILD_DIR/bin/$bin" "$DEST/"
        info "$bin"
    fi
done

for lib in "$REPO_DIR/$BUILD_DIR"/bin/lib*.so*; do
    [ -f "$lib" ] && cp -a "$lib" "$DEST/" || true
done

if command -v patchelf >/dev/null 2>&1; then
    for f in "$DEST"/llama-* "$DEST"/test-* "$DEST"/lib*.so*; do
        [ -f "$f" ] && patchelf --set-rpath '$ORIGIN' "$f" || true
    done
fi

step "Verifying build ..."
if "$DEST/llama-cli" --version >/dev/null 2>&1 || "$DEST/llama-cli" --help >/dev/null 2>&1; then
    info "Build verified: llama-cli runs."
else
    warn "llama-cli did not respond to --version or --help."
fi

echo ""
info "Build complete. ROCm binaries are in $DEST/"
