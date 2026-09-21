"""MLX generate for Bonsai 2 packs, text and images.

Bonsai 2 stores its language weights in a rotated basis, so the matching transform has to be applied
to activations at run time. Stock MLX loaders skip it and return wrong output rather than an error,
which is why the pack ships its own loader in `runtime/` and this script uses it. The vision tower is
the stock Qwen tower and needs no transform.
"""
import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

# transformers does not recognise `prism_hadamard_qwen35` and says so loudly, and its tokenizer
# prints a Mistral regex note. Neither applies: the pack's loader builds the model itself and the
# tokenizer is the base model's own. Both read as errors to a first-time user, so quiet them before
# transformers is imported, which is when it reads this.
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

CYAN, DIM, RESET = "\033[36m", "\033[2m", "\033[0m"

DEFAULTS = {"temp": 1.0, "top_p": 0.95, "top_k": 20, "max_tokens": 2048}


MANIFEST = Path(__file__).resolve().parent / "bonsai2-runtime.sha256"


def read_manifest():
    entries = {}
    for line in MANIFEST.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        digest, name = line.split(None, 1)
        entries[name.strip()] = digest
    return entries


def verify_runtime(runtime):
    """Refuse to import loader code that is not the reviewed revision.

    The pack ships executable Python and this script imports it, so whatever is in
    runtime/ runs as the user. The model repo is a separate trust domain from this
    one; pinning the hashes here means a change over there cannot quietly become
    code execution here. BONSAI_SKIP_RUNTIME_CHECK=1 is the escape hatch for anyone
    editing the loader in place.
    """
    if os.environ.get("BONSAI_SKIP_RUNTIME_CHECK") == "1":
        print(f"{DIM}runtime checksum check skipped (BONSAI_SKIP_RUNTIME_CHECK=1){RESET}",
              file=sys.stderr)
        return
    if not MANIFEST.is_file():
        sys.exit(f"{MANIFEST} is missing; cannot verify the pack's loader code.")

    expected = read_manifest()
    found = {f.name for f in runtime.glob("*.py")}
    problems = []
    for name in sorted(set(expected) | found):
        if name not in expected:
            problems.append(f"  {name}: not in the manifest")
        elif name not in found:
            problems.append(f"  {name}: in the manifest but missing from the pack")
        else:
            digest = hashlib.sha256((runtime / name).read_bytes()).hexdigest()
            if digest != expected[name]:
                problems.append(f"  {name}: {digest} does not match {expected[name]}")
    if problems:
        sys.exit(
            "The pack's loader code does not match the revision this demo pinned, so it "
            "will not be imported.\n" + "\n".join(problems) + "\n\n"
            f"Re-download the pack, or if the change is expected, re-pin {MANIFEST.name}\n"
            f"  shasum -a 256 {runtime}/*.py"
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--prompt", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--image", action="append", default=[],
                        help="image file; repeat for more than one")
    parser.add_argument("-n", "--max-tokens", type=int, default=DEFAULTS["max_tokens"])
    parser.add_argument("--temp", type=float, default=DEFAULTS["temp"])
    parser.add_argument("--top-p", type=float, default=DEFAULTS["top_p"])
    parser.add_argument("--top-k", type=int, default=DEFAULTS["top_k"])
    parser.add_argument("--no-think", action="store_true", help="skip the thinking phase")
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
    runtime = pack / "runtime"
    if not (runtime / "vision_artifact.py").is_file():
        sys.exit(
            f"{runtime}/vision_artifact.py is missing. This pack predates vision support;\n"
            "re-download with ./scripts/download_models.sh."
        )
    verify_runtime(runtime)
    sys.path.insert(0, str(runtime))

    import warnings

    warnings.filterwarnings("ignore")

    import mlx.core as mx

    mx.set_default_device(mx.gpu)
    from vision_artifact import load_vl_model, chat_config  # noqa: E402
    from mlx_vlm import generate  # noqa: E402
    from mlx_vlm.prompt_utils import apply_chat_template  # noqa: E402

    if args.image:
        missing = [i for i in args.image if not Path(i).is_file()]
        if missing:
            sys.exit(f"Image not found: {missing[0]}")

    started = time.time()
    model, processor, config = load_vl_model(str(pack))
    print(f"{DIM}loaded {pack.name} in {time.time() - started:.0f}s{RESET}", file=sys.stderr)

    prompt = apply_chat_template(
        processor, chat_config(config), args.prompt, num_images=len(args.image)
    )
    if args.no_think:
        prompt += "<think>\n\n</think>\n\n"

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
        verbose=False,
    )
    text = out if isinstance(out, str) else getattr(out, "text", str(out))
    print(text.strip())
    print(f"\n{DIM}{time.time() - started:.1f}s{RESET}", file=sys.stderr)


if __name__ == "__main__":
    main()
