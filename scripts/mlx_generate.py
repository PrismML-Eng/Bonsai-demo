"""Streaming MLX generate with colored prompt and stats table."""
import argparse
import os
import sys

import mlx.core as mx
from mlx_lm import load, stream_generate
from mlx_lm.generate import make_sampler

_VALID_SIZES = ("8B", "4B", "1.7B")
_VALID_FAMILIES = ("bonsai", "ternary")

_SIZE = os.environ.get("BONSAI_MODEL", "8B")
_FAMILY = os.environ.get("BONSAI_FAMILY", "bonsai")

if _FAMILY == "all":
    sys.exit(
        "BONSAI_FAMILY='all' is only valid for setup/download. "
        "Runtime requires a concrete family: bonsai or ternary."
    )
if _FAMILY not in _VALID_FAMILIES:
    sys.exit(
        f"Unknown BONSAI_FAMILY={_FAMILY!r}. Valid values: bonsai, ternary"
    )

if _SIZE == "all":
    sys.exit(
        "BONSAI_MODEL='all' is only valid for setup/download. "
        "Runtime requires a concrete model size: 8B, 4B, or 1.7B."
    )
if _SIZE not in _VALID_SIZES:
    sys.exit(
        f"Unknown BONSAI_MODEL={_SIZE!r}. Valid values: 8B, 4B, 1.7B"
    )

_DEFAULT_MODEL = (
    f"models/Ternary-Bonsai-{_SIZE}-mlx-2bit"
    if _FAMILY == "ternary"
    else f"models/Bonsai-{_SIZE}-mlx"
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--prompt", required=True)
    parser.add_argument("-n", "--max-tokens", type=int, default=256)
    parser.add_argument("--model", default=_DEFAULT_MODEL)
    parser.add_argument("--temp", type=float, default=0.5)
    parser.add_argument("--top-p", type=float, default=0.85)
    args = parser.parse_args()

    model, tokenizer = load(args.model)

    messages = [{"role": "user", "content": args.prompt}]
    chat_prompt = tokenizer.apply_chat_template(
        messages,
        add_generation_prompt=True,
        enable_thinking=False,
        tokenize=False,
    )

    CYAN = "\033[36m"
    RESET = "\033[0m"

    print("\n")
    print("=" * 20 + " MLX " + "=" * 20)
    sys.stdout.write(f"{CYAN}> {args.prompt}{RESET}\n\n")
    sys.stdout.flush()

    sampler = make_sampler(temp=args.temp, top_p=args.top_p)

    last = None
    for response in stream_generate(
        model,
        tokenizer,
        prompt=chat_prompt,
        max_tokens=args.max_tokens,
        sampler=sampler,
    ):
        sys.stdout.write(response.text)
        sys.stdout.flush()
        last = response

    print("\n")

    if last:
        peak_gb = mx.get_peak_memory() / (1024**3)
        print(f"| {'Metric':<12} | {'Tokens':>8} | {'Speed (t/s)':>12} |")
        print(f"|{'-' * 14}|{'-' * 10}|{'-' * 14}|")
        print(f"| {'Prompt':<12} | {last.prompt_tokens:>8} | {last.prompt_tps:>12.2f} |")
        print(f"| {'Generation':<12} | {last.generation_tokens:>8} | {last.generation_tps:>12.2f} |")
        print(f"\nPeak memory: {peak_gb:.3f} GB")


if __name__ == "__main__":
    main()
