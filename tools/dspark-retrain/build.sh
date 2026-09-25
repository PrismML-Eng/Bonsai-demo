#!/usr/bin/env bash
# Build the three C++ tools against the PrismML llama.cpp checkout (headers) and the
# prebuilt bin/cuda libraries (libllama, libggml-base). Link-time only; the GPU is not used.
# Usage: build.sh [out_dir]   (default: this directory)
# Env:   BONSAI_ROOT  the Bonsai-demo checkout (default: two levels above this script)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="${BONSAI_ROOT:-$(cd "$HERE/../.." && pwd)}"
OUT="${1:-$HERE}"
LLAMA=$ROOT/llama.cpp
LIB=$ROOT/bin/cuda
mkdir -p "$OUT"
for t in teacher_dump validate_wlm extract_feats_tf; do
  g++ -O2 -std=c++17 -fopenmp -I "$LLAMA/include" -I "$LLAMA/ggml/include" -I "$LLAMA/src" \
      "$HERE/$t.cpp" -o "$OUT/$t" -L "$LIB" -lllama -lggml-base -Wl,-rpath,"$LIB"
  echo "built $OUT/$t"
done
