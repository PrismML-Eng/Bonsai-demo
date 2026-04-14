#!/bin/sh
# Build llama.cpp for Linux (CPU only — no GPU dependencies).
# Prerequisites: cmake, a C/C++ compiler (gcc/g++ or clang)
# Usage: ./scripts/build_cpu_linux.sh [path_to_llama_cpp_repo]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

REPO_DIR="${1:-./llama.cpp}"
TARGETS="llama-completion llama-cli llama-server llama-quantize llama-perplexity"
DEST="./bin/cpu"

# ── Clone if needed ──
if [ ! -d "$REPO_DIR" ]; then
    step "Cloning PrismML-Eng/llama.cpp (prism branch) ..."
    git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git "$REPO_DIR"
    info "Cloned to $REPO_DIR"
fi

# ── Remove old binaries if present ──
if [ -d "$DEST" ]; then
    step "Removing previously built binaries in $DEST/ ..."
    rm -rf "$DEST"
fi

# ── Build ──
step "Building llama.cpp for Linux (CPU only) ..."
echo "  Repo:    $REPO_DIR"
echo "  Targets: $TARGETS"

cd "$REPO_DIR"
cmake -B build-cpu \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=ON \
    -DGGML_CUDA=OFF \
    -DGGML_METAL=OFF \
    -DGGML_VULKAN=OFF \
    -DGGML_HIP=OFF
cmake --build build-cpu --target $TARGETS -j$(nproc)
cd - > /dev/null

# ── Copy binaries ──
step "Installing binaries to $DEST/ ..."
mkdir -p "$DEST"

for _bin in $TARGETS; do
    if [ -f "$REPO_DIR/build-cpu/bin/$_bin" ]; then
        cp "$REPO_DIR/build-cpu/bin/$_bin" "$DEST/"
        info "$_bin"
    fi
done

# Copy shared libs if any
for _lib in "$REPO_DIR"/build-cpu/bin/lib*.so*; do
    [ -f "$_lib" ] && cp "$_lib" "$DEST/" || true
done

# ── Smoke test ──
step "Verifying build ..."
if "$DEST/llama-cli" --version >/dev/null 2>&1 || "$DEST/llama-cli" --help >/dev/null 2>&1; then
    info "Build verified — llama-cli runs."
else
    warn "llama-cli did not respond to --version or --help (may still work)."
fi

echo ""
info "Build complete! CPU binaries are in $DEST/"
echo ""
echo "  Run:"
echo "    ./scripts/run_llama.sh -p \"Hello!\""
echo "    ./scripts/start_llama_server.sh"
echo ""
