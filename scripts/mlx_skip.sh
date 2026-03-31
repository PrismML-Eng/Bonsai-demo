#!/bin/sh
# Sourced by setup.sh and download_models.sh (not run directly).
# MLX is Apple Silicon only; Intel macOS cannot build or run it.

# Return 0 = skip MLX (no weights download, no pip build).
bonsai_should_skip_mlx() {
    case "${BONSAI_SKIP_MLX:-}" in
        1|true|yes) return 0 ;;
        0|false|no) return 1 ;;
        *)
            [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "x86_64" ] && return 0
            return 1 ;;
    esac
}
