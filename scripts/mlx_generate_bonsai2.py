"""Generate text and images using native Bonsai 2 support in mlx-vlm."""
import argparse
import json
import os
import sys
import time
from pathlib import Path

# Keep tokenizer diagnostics out of normal generated output.
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

CYAN, DIM, RESET = "\033[36m", "\033[2m", "\033[0m"

# Matches the model card. The template reasons at xhigh effort by default, so a short token cap ends
# generation mid-thought with no answer; mlx-vlm samples with min_p 0.0 unless told otherwise.
DEFAULTS = {"temp": 1.0, "top_p": 0.95, "top_k": 20, "min_p": 0.05, "max_tokens": 16384}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--prompt", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--sampling-profile", choices=("27b", "small"), default="27b")
    parser.add_argument("--image", action="append", default=[],
                        help="image file; repeat for more than one")
    parser.add_argument("-n", "--max-tokens", type=int, default=DEFAULTS["max_tokens"])
    parser.add_argument("--temp", type=float)
    parser.add_argument("--top-p", type=float)
    parser.add_argument("--top-k", type=int, default=DEFAULTS["top_k"])
    parser.add_argument("--min-p", type=float)
    parser.add_argument("--presence-penalty", type=float)
    parser.add_argument("--presence-context-size", type=int, default=64)
    parser.add_argument("--repetition-penalty", type=float, default=1.0)
    parser.add_argument("--no-think", action="store_true", help="skip the thinking phase")
    parser.add_argument("--stats", action="store_true", help="show prompt and generation tokens/sec")
    args = parser.parse_args()

    pack = Path(args.model).resolve()
    config_path = pack / "config.json"
    if not config_path.is_file():
        sys.exit(f"No config.json in {pack}. Run ./scripts/download_models.sh first.")
    config = json.loads(config_path.read_text())
    if config.get("model_type") != "prism_hadamard_qwen35":
        sys.exit(
            f"{pack} is not a Bonsai 2 MLX pack (model_type={config.get('model_type')!r}).\n"
            "Use scripts/mlx_generate.py for the earlier families."
        )
    small = args.sampling_profile == "small"
    defaults = dict(DEFAULTS)
    if small:
        defaults.update(temp=0.7 if args.no_think else 1.0,
                        top_p=0.8 if args.no_think else 0.95, min_p=0.0)
    for key in ("temp", "top_p", "min_p"):
        if getattr(args, key) is None:
            setattr(args, key, defaults[key])
    if args.presence_penalty is None:
        args.presence_penalty = (1.5 if args.no_think else 1.0) if small else 0.0
    if args.presence_context_size < 1:
        parser.error("--presence-context-size must be positive")
    import warnings

    warnings.filterwarnings("ignore")

    import mlx.core as mx

    mx.set_default_device(mx.gpu)
    from mlx_vlm import generate, load  # noqa: E402
    from mlx_vlm.prompt_utils import apply_chat_template  # noqa: E402

    if args.image:
        missing = [i for i in args.image if not Path(i).is_file()]
        if missing:
            sys.exit(f"Image not found: {missing[0]}")

    started = time.time()
    model, processor = load(str(pack))
    print(f"{DIM}loaded {pack.name} in {time.time() - started:.0f}s{RESET}", file=sys.stderr)

    prompt = apply_chat_template(
        processor, model.config, args.prompt, num_images=len(args.image),
        enable_thinking=not args.no_think
    )

    print(f"{CYAN}{args.prompt}{RESET}\n")
    started = time.time()
    out = generate(
        model,
        processor,
        prompt,
        args.image,
        max_tokens=args.max_tokens,
        temperature=args.temp,
        top_p=args.top_p,
        top_k=args.top_k,
        min_p=args.min_p,
        presence_penalty=args.presence_penalty,
        presence_context_size=args.presence_context_size,
        repetition_penalty=args.repetition_penalty,
        verbose=False,
    )
    text = out if isinstance(out, str) else getattr(out, "text", str(out))
    print(text.strip())
    print(f"\n{DIM}{time.time() - started:.1f}s{RESET}", file=sys.stderr)
    if args.stats and not isinstance(out, str):
        print(
            f"{DIM}Prompt: {out.prompt_tokens} tokens @ {out.prompt_tps:.2f} t/s{RESET}",
            file=sys.stderr,
        )
        print(
            f"{DIM}Generation: {out.generation_tokens} tokens @ {out.generation_tps:.2f} t/s{RESET}",
            file=sys.stderr,
        )
        print(f"{DIM}Peak memory: {out.peak_memory:.2f} GB{RESET}", file=sys.stderr)


if __name__ == "__main__":
    main()
