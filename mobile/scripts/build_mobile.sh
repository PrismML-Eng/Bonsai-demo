#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd -P)"
source_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid source commit" >&2; exit 65; }
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || {
  echo "Release packaging requires a clean source tree." >&2
  exit 65
}

exec xcodebuild -project "$REPO_ROOT/mobile/BonsaiMobile.xcodeproj" \
  -scheme BonsaiMobile -configuration Release -destination 'generic/platform=iOS' \
  "BONSAI_SOURCE_COMMIT=$source_commit" "$@"
