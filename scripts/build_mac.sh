#!/bin/sh
# Build llama.cpp for Mac — Apple Silicon (Metal) or Intel (CPU only).
# Prerequisites: Xcode command-line tools, cmake
# Usage: ./scripts/build_mac.sh [path_to_llama_cpp_repo]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

REPO_DIR="${1:-./llama.cpp}"
TARGETS="llama-completion llama-cli llama-server llama-quantize llama-perplexity"
DEST="./bin/mac"

# ── Clone if needed ──
if [ ! -d "$REPO_DIR" ]; then
    step "Cloning PrismML-Eng/llama.cpp (prism branch) ..."
    git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git "$REPO_DIR"
    info "Cloned to $REPO_DIR"
fi

# ── Remove old downloaded binaries if present ──
if [ -d "$DEST" ]; then
    step "Removing previously downloaded binaries in $DEST/ ..."
    rm -rf "$DEST"
fi

# ── Build (native for this Mac) ──
MAC_ARCH="$(uname -m)"
echo "  Repo:    $REPO_DIR"
echo "  Targets: $TARGETS"
echo "  Arch:    $MAC_ARCH"

cd "$REPO_DIR"
case "$MAC_ARCH" in
    arm64)
        step "Building llama.cpp (Apple Silicon + Metal) ..."
        cmake -B build-mac \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
            -DGGML_METAL=ON \
            -DGGML_METAL_EMBED_LIBRARY=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DGGML_STATIC=ON \
            -DLLAMA_OPENSSL=OFF
        ;;
    x86_64)
        step "Building llama.cpp (Intel macOS, CPU only — no Metal) ..."
        cmake -B build-mac \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES=x86_64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
            -DGGML_METAL=OFF \
            -DBUILD_SHARED_LIBS=OFF \
            -DGGML_STATIC=ON \
            -DLLAMA_OPENSSL=OFF
        ;;
    *)
        err "Unsupported Mac architecture: $MAC_ARCH"
        exit 1
        ;;
esac

cmake --build build-mac --target $TARGETS -j$(sysctl -n hw.logicalcpu)
cd - > /dev/null

# ── Copy binaries ──
step "Installing binaries to $DEST/ ..."
mkdir -p "$DEST"

for _bin in $TARGETS; do
    cp "$REPO_DIR/build-mac/bin/$_bin" "$DEST/"
    strip "$DEST/$_bin"
    codesign -s - --force --timestamp=none "$DEST/$_bin"
    info "$_bin  (stripped + signed)"
done

# ── Smoke test ──
step "Verifying build ..."
if "$DEST/llama-cli" --version >/dev/null 2>&1 || "$DEST/llama-cli" --help >/dev/null 2>&1; then
    info "Build verified — llama-cli runs."
else
    warn "llama-cli did not respond to --version or --help (may still work)."
fi

echo ""
echo "  Dynamic dependencies (should all be system libs):"
otool -L "$DEST/llama-cli" | tail -n +2
echo ""

info "Build complete! Binaries are in $DEST/"
echo ""
echo "  Run:"
echo "    ./scripts/run_llama.sh -p \"Hello!\""
echo "    ./scripts/start_llama_server.sh"
echo ""
