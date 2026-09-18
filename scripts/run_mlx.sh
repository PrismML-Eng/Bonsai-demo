#!/bin/sh
# Run Bonsai model with MLX (Apple Silicon only)
# Usage: ./scripts/run_mlx.sh -p "Your prompt" [--image photo.jpg] [--stats]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"

if [ "$(uname -s)" != "Darwin" ]; then
    err "MLX only runs on Apple Silicon (macOS). Use ./scripts/run_llama.sh instead."
    exit 1
fi

assert_mlx_downloaded

MODEL="$MLX_MODEL_DIR"
PROMPT=""

# Only Bonsai 2 has a vision tower and a thinking phase, and only its generator takes
# top-k. The earlier families go to mlx_generate.py, which would abort in argparse on any
# of the three, so refuse them here with a message that says why.
_BONSAI2_ONLY=" --image --top-k --no-think --stats "

# Rebuild the passthrough flags as real positional parameters. Collecting them into a
# string and expanding it unquoted would split paths on whitespace, so `--image "my cat.jpg"`
# would arrive as two arguments.
# The marker stops the loop: rotated arguments land after it, so when it reaches the
# front every original argument has been seen and what follows is the collected set.
set -- "$@" "--end-of-args--"
while [ "$1" != "--end-of-args--" ]; do
    if [ "$BONSAI_FAMILY" != "bonsai2" ]; then
        case "$_BONSAI2_ONLY" in
            *" $1 "*)
                err "$1 is a Bonsai 2 option; ${BONSAI_DISPLAY} on MLX does not support it."
                echo "  Drop it, or use the default family:  BONSAI_FAMILY=bonsai2 $0 -p \"...\" $1" >&2
                exit 1
                ;;
        esac
    fi
    case "$1" in
        -p) PROMPT="$2"; shift 2 ;;
        --image|-n|--temp|--top-p|--top-k) set -- "$@" "$1" "$2"; shift 2 ;;
        --no-think|--stats) set -- "$@" "$1"; shift ;;
        *) shift ;;
    esac
done
shift

if [ -z "$PROMPT" ]; then
    PROMPT="What is Capital of France?"
fi

# Bonsai 2 packs carry their own Hadamard-aware loader and run on stock MLX through
# mlx-vlm, which lives in .venv-vlm; the fork in .venv is for the 1-bit family.
if [ "$BONSAI_FAMILY" = "bonsai2" ]; then
    _vlm_py="$DEMO_DIR/.venv-vlm/bin/python"
    if [ ! -x "$_vlm_py" ]; then
        err "Bonsai 2 on MLX needs the mlx-vlm venv (.venv-vlm)."
        echo "  Create it with:  ./setup.sh"
        echo "  Or by hand:      uv venv .venv-vlm && uv pip install --python .venv-vlm/bin/python -r \"$MODEL/runtime/requirements.txt\""
        exit 1
    fi
    exec "$_vlm_py" "$SCRIPT_DIR/mlx_generate_bonsai2.py" \
        --model "$MODEL" \
        -p "$PROMPT" \
        "$@"
fi

ensure_venv "$DEMO_DIR"

python "$SCRIPT_DIR/mlx_generate.py" \
    --model "$MODEL" \
    -p "$PROMPT" \
    "$@"
