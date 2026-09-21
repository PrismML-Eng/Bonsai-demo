#!/bin/bash
# Build llama.cpp with CUDA on Linux (multi-arch)
# Prerequisites: CUDA toolkit (nvcc), cmake, ninja-build
# Output is always installed under this demo's bin/ folder.
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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEMO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

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

OUTPUT_DIR="${OUTPUT_DIR:-cuda}"
# --output names one child of bin/, never a path or a parent directory.
if [[ ! "$OUTPUT_DIR" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo "Error: --output must be a directory name containing only letters, digits, '_' or '-'."
    exit 1
fi
DEST="$DEMO_DIR/bin/$OUTPUT_DIR"

check_output_path() {
    if [ -L "$DEMO_DIR/bin" ] || [ -L "$DEST" ]; then
        echo "Error: refusing a symlinked output directory: $DEST"
        exit 1
    fi
}
check_output_path

REPO_DIR="${REPO_DIR:-$DEMO_DIR/llama.cpp}"

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
        CUDA_ARCHS="80;86;89;90;100;120a;121a"
    else
        CUDA_ARCHS="80;86;89;90;120a"
    fi
fi

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

# Limit build parallelism to avoid OOM during CUDA compilation.
MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
MEM_GB=$(( ${MEM_KB:-0} / 1048576 ))
if [ "$MEM_GB" -lt 16 ] 2>/dev/null; then
    BUILD_JOBS=2
    echo "  Low RAM (~${MEM_GB} GB) -- using -j $BUILD_JOBS"
else
    BUILD_JOBS=$(nproc)
    [ "$BUILD_JOBS" -gt 16 ] && BUILD_JOBS=16
    echo "  Using -j $BUILD_JOBS"
fi

# Build every target (the `all` target) so bin/ is entirely source-built and
# internally consistent — no mixing source-built and prebuilt binaries.
cmake --build "$BUILD_DIR" -j$BUILD_JOBS

cd - > /dev/null

echo ""
echo "=== Copying binaries to $DEST ==="
check_output_path
mkdir -p "$DEMO_DIR/bin"
STAGE=$(mktemp -d "$DEMO_DIR/bin/.llama-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# Preserve the complete runtime output, including symlinks and future helpers.
# Stage separately so a failed copy/patch leaves the existing install intact.
cp -a "$REPO_DIR/$BUILD_DIR/bin/." "$STAGE/"

echo ""
echo "=== Patching RUNPATH for portability ==="
if command -v patchelf &>/dev/null; then
    command -v file >/dev/null || { echo "Error: install 'file' to identify ELF runtime files."; exit 1; }
    while IFS= read -r -d '' f; do
        # find skips symlinks; patch their real targets once, regardless of name.
        kind=$(LC_ALL=C file -b "$f")
        if [[ "$kind" == ELF* ]] && [[ "$kind" == *executable* || "$kind" == *"shared object"* ]]; then
            patchelf --set-rpath '$ORIGIN' "$f"
        fi
    done < <(find "$STAGE" -type f -print0)
    echo "  Set RUNPATH to \$ORIGIN (binaries find bundled libs automatically)"
else
    echo "  Warning: patchelf not found. Install it (apt install patchelf) or use LD_LIBRARY_PATH."
fi

# Replace rather than overlay, so removed runtime libraries do not linger.
check_output_path
rm -rf -- "$DEMO_DIR/bin/$OUTPUT_DIR"
mv "$STAGE" "$DEST"
trap - EXIT

echo ""
echo "Done! CUDA $CUDA_VERSION Linux binaries are in: $DEST"
