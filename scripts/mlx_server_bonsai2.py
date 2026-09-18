"""OpenAI-compatible MLX server for Bonsai 2 packs.

Bonsai 2 stores its language weights in a rotated basis, so the matching transform has to be
applied to activations at run time. Stock `mlx_vlm.server` loads weights straight and returns
wrong output rather than an error, which is why the pack ships its own loader in `runtime/` (see
`scripts/mlx_generate_bonsai2.py`, the one-shot equivalent of this script). The server has a single
model-loading seam, `mlx_vlm.server.generation.load`, imported by name and looked up as a module
global at call time; this script monkeypatches that name to the pack's loader before handing
control to the stock server, so every other server code path (routing, batching, sampling, the
OpenAI-compatible endpoints) stays exactly as mlx_vlm ships it.

It also fixes up `model.config.model_type` after loading. The server's prompt templating
(`mlx_vlm.prompt_utils.apply_chat_template`) branches on `model.config.model_type`, and the pack's
type (`prism_hadamard_qwen35`) is not a type mlx_vlm knows, so an unpatched model_type would push
every request onto the text-only branch and silently drop images. Rewriting it to
`base_model_type` (`qwen3_5`, the pack's underlying chat model) is exactly what the one-shot's
`chat_config()` does, and the vision tower is the stock Qwen tower, so this is safe.
"""
import argparse
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

DIM, RESET = "\033[2m", "\033[0m"

# `verify_runtime` (and its manifest/hashing helpers) live in the one-shot script; import it
# instead of duplicating the checksum logic here.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mlx_generate_bonsai2 import verify_runtime  # noqa: E402


def _is_bonsai2_pack(path: Path) -> bool:
    config_path = path / "config.json"
    if not config_path.is_file():
        return False
    return json.loads(config_path.read_text()).get("model_type") == "prism_hadamard_qwen35"


def reload_flag(passthrough):
    """Return the passthrough token that would turn on uvicorn's --reload, or None.

    argparse's abbreviation matching (`allow_abbrev`, on by default) lets any unambiguous
    prefix of a long option through, so `--relo` reaches `cli.main()` exactly like
    `--reload` does. `reload` is the only server flag starting with `r`, so any token of
    length >= 3 that could still be an abbreviation of it (ignoring an `=value` suffix) is
    treated as the same request.
    """
    for token in passthrough:
        name = token.split("=", 1)[0]
        if len(name) >= 3 and "--reload".startswith(name):
            return token
    return None


def eval_arrays(raw_inputs):
    """Force evaluation of every mx.array nested in raw_inputs, in place.

    See the cross-thread workaround comment in main() for why this matters. Kept at module
    level (rather than a closure) so it can be exercised directly in tests.
    """
    import mlx.core as mx

    arrays = []

    def _collect(value):
        if isinstance(value, mx.array):
            arrays.append(value)
        elif isinstance(value, (list, tuple)):
            for item in value:
                _collect(item)
        elif isinstance(value, dict):
            for item in value.values():
                _collect(item)

    for value in raw_inputs.values():
        _collect(value)
    if arrays:
        mx.eval(*arrays)
    return raw_inputs


def main():
    parser = argparse.ArgumentParser(
        description="Serve a Bonsai 2 MLX pack with mlx_vlm.server, using the pack's own "
        "Hadamard-aware loader instead of the stock one."
    )
    parser.add_argument("--model", required=True, help="Bonsai 2 MLX pack directory")
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--host", default="127.0.0.1")
    args, passthrough = parser.parse_known_args()

    bad_flag = reload_flag(passthrough)
    if bad_flag is not None:
        sys.exit(
            f"{bad_flag} is not supported here: uvicorn's reloader re-imports the server in "
            "a fresh subprocess, and the patch that swaps in the pack's loader would not "
            "survive into it, so the reloaded process falls back to the stock loader, which "
            "raises 'Model type prism_hadamard_qwen35 not supported' and never starts."
        )

    pack = Path(args.model).resolve()
    config_path = pack / "config.json"
    if not config_path.is_file():
        sys.exit(f"No config.json in {pack}. Run ./scripts/download_models.sh first.")
    if not _is_bonsai2_pack(pack):
        model_type = json.loads(config_path.read_text()).get("model_type")
        sys.exit(
            f"{pack} is not a Bonsai 2 MLX pack (model_type={model_type!r}).\n"
            "Use scripts/start_mlx_server.sh with a different BONSAI_FAMILY for the earlier "
            "families."
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

    from vision_artifact import load_vl_model  # noqa: E402
    import mlx_vlm.server.generation as generation  # noqa: E402

    # Keep a reference to the stock loader so a request naming some other model (not this
    # Bonsai 2 pack) still behaves exactly as stock mlx_vlm would.
    _stock_load = generation.load

    def load_bonsai2_pack(model_path, adapter_path=None, **kwargs):
        path = Path(model_path).resolve()
        if not _is_bonsai2_pack(path):
            # Not this pack: behave exactly as stock mlx_vlm would, adapter and all.
            return _stock_load(model_path, adapter_path, **kwargs)
        if adapter_path:
            raise ValueError("Adapters are not supported for Bonsai 2 packs.")

        started = time.time()
        model, processor, pack_config = load_vl_model(str(path))
        model.config.model_type = pack_config["base_model_type"]
        print(f"{DIM}loaded {path.name} in {time.time() - started:.0f}s{RESET}", file=sys.stderr)
        return model, processor

    generation.load = load_bonsai2_pack

    # --- Workaround for an mlx 0.32 cross-thread stream bug -----------------------------------
    #
    # Every Python thread gets its own lazily-created default GPU stream in mlx 0.32, and a
    # lazy graph built on one thread cannot be evaluated on another. ResponseGenerator.submit()
    # calls _cpu_preprocess() on the request thread, which builds input_ids/attention_mask/
    # pixel_values/image_grid_thw etc. as mx.array values with a pending (un-evaluated) graph
    # tied to that thread's stream. _gpu_embed() later runs on the separate GPU thread
    # (ResponseGenerator._run) and, for image requests, ends up calling `.tolist()` on one of
    # these arrays inside qwen3_5's get_rope_index(); evaluating that graph from the GPU
    # thread raises "There is no Stream(gpu, N) in current thread." Text-only requests never
    # hit that code path, so they work unpatched.
    #
    # Fix: force evaluation of every mx.array _cpu_preprocess() returns while still on the
    # request thread that owns their stream. An array with no pending graph has nothing left to
    # evaluate lazily, so the GPU thread can read it (including via .tolist()) without touching
    # the request thread's stream. This is a targeted workaround for the upstream bug and can be
    # removed once mlx fixes cross-thread evaluation.
    _stock_cpu_preprocess = generation.ResponseGenerator._cpu_preprocess

    def _cpu_preprocess_eval_on_request_thread(self, prompt, images=None, audio=None):
        raw_inputs = _stock_cpu_preprocess(self, prompt, images=images, audio=audio)
        return eval_arrays(raw_inputs)

    generation.ResponseGenerator._cpu_preprocess = _cpu_preprocess_eval_on_request_thread
    # --- end workaround --------------------------------------------------------------------------

    from mlx_vlm.server import cli

    sys.argv = [
        "mlx_vlm.server",
        "--model", str(pack),
        "--host", args.host,
        "--port", str(args.port),
        "--enable-thinking",
        *passthrough,
    ]
    cli.main()


if __name__ == "__main__":
    main()
