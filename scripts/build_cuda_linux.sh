#!/bin/bash
# Build llama.cpp with CUDA on Linux (multi-arch)
# Prerequisites: CUDA toolkit (nvcc), cmake, ninja-build
# Run from the demo/ folder.
#
# Usage:
#   ./scripts/build_cuda_linux.sh [options] [path_to_llama_cpp_repo]
#
# Options:
#   --cuda-path PATH    Path to CUDA toolkit (default: auto-detect)
#   --archs ARCHS       Semicolon-separated CUDA architectures (default: all supported)
#   --output DIR        Output directory name under bin/ (default: cuda)
#
# Examples:
#   ./scripts/build_cuda_linux.sh                                  # auto-detect everything
#   ./scripts/build_cuda_linux.sh --cuda-path /usr/local/cuda-12.8 # use specific CUDA
#   ./scripts/build_cuda_linux.sh --archs "80;86;89;90"            # custom architectures

set -e

CUDA_PATH=""
CUDA_ARCHS=""
OUTPUT_DIR=""
REPO_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --cuda-path) CUDA_PATH="$2"; shift 2 ;;
        --archs)     CUDA_ARCHS="$2"; shift 2 ;;
        --output)    OUTPUT_DIR="$2"; shift 2 ;;
        *)           REPO_DIR="$1"; shift ;;
    esac
done

REPO_DIR="${REPO_DIR:-./llama.cpp}"
TARGETS="llama-completion llama-cli llama-server llama-quantize llama-perplexity llama-bench"

if [ ! -d "$REPO_DIR" ]; then
    echo "llama.cpp not found at $REPO_DIR — cloning from PrismML-Eng..."
    git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git "$REPO_DIR"
fi

# Auto-detect CUDA path
if [ -z "$CUDA_PATH" ]; then
    if command -v nvcc &>/dev/null; then
        CUDA_PATH="$(dirname "$(dirname "$(command -v nvcc)")")"
    elif [ -d /usr/local/cuda ]; then
        CUDA_PATH="/usr/local/cuda"
    else
        echo "Error: CUDA toolkit not found. Use --cuda-path to specify."
        exit 1
    fi
fi

NVCC="$CUDA_PATH/bin/nvcc"
if [ ! -f "$NVCC" ]; then
    echo "Error: nvcc not found at $NVCC"
    exit 1
fi

# Detect CUDA major version
CUDA_VERSION=$("$NVCC" --version | grep -oP 'release \K[0-9]+\.[0-9]+')
CUDA_MAJOR=$(echo "$CUDA_VERSION" | cut -d. -f1)

# Set default architectures: build a fat binary covering all supported GPUs
if [ -z "$CUDA_ARCHS" ]; then
    if [ "$CUDA_MAJOR" -ge 13 ]; then
        CUDA_ARCHS="80;86;89;90;100;120a"
    else
        CUDA_ARCHS="80;86;89;90;120a"
    fi
fi

OUTPUT_DIR="${OUTPUT_DIR:-cuda}"
DEST="./bin/$OUTPUT_DIR"

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: llama.cpp repo not found at $REPO_DIR and clone failed."
    exit 1
fi

echo "=== Building llama.cpp with CUDA $CUDA_VERSION (multi-arch) ==="
echo "Repo:    $REPO_DIR"
echo "CUDA:    $CUDA_PATH (v$CUDA_VERSION)"
echo "Archs:   $CUDA_ARCHS"
echo "Output:  $DEST"

BUILD_DIR="build-cuda"

export PATH="$CUDA_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_PATH/lib64:${LD_LIBRARY_PATH:-}"
export CUDACXX="$CUDA_PATH/bin/nvcc"

cd "$REPO_DIR"
cmake -B "$BUILD_DIR" -G Ninja \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_COMPILER="$CUDA_PATH/bin/nvcc" \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS" \
    -DCMAKE_BUILD_TYPE=Release

cmake --build "$BUILD_DIR" --target $TARGETS -j$(nproc)

cd - > /dev/null

echo ""
echo "=== Copying binaries to $DEST ==="
mkdir -p "$DEST"

for bin in $TARGETS; do
    cp "$REPO_DIR/$BUILD_DIR/bin/$bin" "$DEST/"
    echo "  Copied $bin"
done

echo ""
echo "=== Copying shared libraries ==="
cp -a "$REPO_DIR/$BUILD_DIR"/bin/libllama.so* "$DEST/"
cp -a "$REPO_DIR/$BUILD_DIR"/bin/libggml.so* "$DEST/"
cp -a "$REPO_DIR/$BUILD_DIR"/bin/libggml-base.so* "$DEST/"
cp -a "$REPO_DIR/$BUILD_DIR"/bin/libggml-cpu.so* "$DEST/"
cp -a "$REPO_DIR/$BUILD_DIR"/bin/libggml-cuda.so* "$DEST/"
cp -a "$REPO_DIR/$BUILD_DIR"/bin/libmtmd.so* "$DEST/" 2>/dev/null || true
echo "  Copied shared libraries (libllama, libggml, libggml-base, libggml-cpu, libggml-cuda, libmtmd)"

echo ""
echo "=== Patching RUNPATH for portability ==="
if command -v patchelf &>/dev/null; then
    for f in "$DEST"/llama-* "$DEST"/lib*.so.*.*; do
        [ -f "$f" ] && patchelf --set-rpath '$ORIGIN' "$f"
    done
    echo "  Set RUNPATH to \$ORIGIN (binaries find bundled libs automatically)"
else
    echo "  Warning: patchelf not found. Install it (apt install patchelf) or use LD_LIBRARY_PATH."
fi

echo ""
echo "Done! CUDA $CUDA_VERSION Linux binaries are in: $DEST"
