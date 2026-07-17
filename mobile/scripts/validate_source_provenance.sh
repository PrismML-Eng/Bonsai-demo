#!/bin/bash
set -euo pipefail

if [[ "${CONFIGURATION:-}" == "Release" ]]; then
  [[ "${BONSAI_SOURCE_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Release builds require BONSAI_SOURCE_COMMIT as an exact lowercase Git commit." >&2
    exit 65
  }
fi
