#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
DEPS="$ROOT/.build-dependencies"
PATCH="$ROOT/Patches/mlx-swift-lm-local-mlx.patch"
MLX_SHA=e40e0a57a6f7ad08dc3fd87ad598a7aa6407d230
LM_SHA=4ca25fd901e2db2703cbe5a6ea339b29642c754f

clone_at() {
  local url="$1" sha="$2" destination="$3"
  if [[ ! -d "$destination/.git" ]]; then
    git clone --filter=blob:none "$url" "$destination"
  fi

  if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
    echo "unexpected local changes in $destination" >&2
    return 1
  fi

  git -C "$destination" fetch --depth 1 origin "$sha"
  git -C "$destination" checkout --detach "$sha"
  test "$(git -C "$destination" rev-parse HEAD)" = "$sha"
  test -z "$(git -C "$destination" status --porcelain)"
}

restore_lm_manifest_if_patched() {
  local destination="$1"
  [[ -d "$destination/.git" ]] || return 0

  if git -C "$destination" apply --reverse --check "$PATCH"; then
    git -C "$destination" apply --reverse "$PATCH"
  elif ! git -C "$destination" apply --check "$PATCH"; then
    echo "mlx-swift-lm Package.swift has unexpected local changes" >&2
    return 1
  fi

  test -z "$(git -C "$destination" status --porcelain)"
}

mkdir -p "$DEPS"
clone_at https://github.com/PrismML-Eng/mlx-swift.git "$MLX_SHA" "$DEPS/mlx-swift"
git -C "$DEPS/mlx-swift" submodule update --init --recursive

restore_lm_manifest_if_patched "$DEPS/mlx-swift-lm"
clone_at https://github.com/ml-explore/mlx-swift-lm.git "$LM_SHA" "$DEPS/mlx-swift-lm"
git -C "$DEPS/mlx-swift-lm" apply --check "$PATCH"
git -C "$DEPS/mlx-swift-lm" apply "$PATCH"

test "$(git -C "$DEPS/mlx-swift" rev-parse HEAD)" = "$MLX_SHA"
test "$(git -C "$DEPS/mlx-swift-lm" rev-parse HEAD)" = "$LM_SHA"
git -C "$DEPS/mlx-swift-lm" apply --reverse --check "$PATCH"
