# Bonsai 2 small models

Use `BONSAI_FAMILY=bonsai2` and `BONSAI_MODEL=2B`, `4B`, or `9B`. The default remains 27B. See below for setup and sampling profiles.

```sh
BONSAI_MODEL=2B ./setup.sh
BONSAI_MODEL=2B BONSAI_CTX=8192 ./scripts/start_llama_server.sh -np 1
BONSAI_MODEL=2B ./scripts/run_mlx.sh -p 'Suggest three names for a tiny robot gardener.' -n 1024
```

The launchers use Prism llama.cpp for GGUF and native mlx-vlm for these MLX checkpoints. Do not substitute `mlx_lm.server`: its model loader does not recognize their `prism_hadamard_qwen35` architecture. The native stack pins mlx-vlm 0.7.8 and mlx-lm 0.32.0 in `scripts/requirements-mlx-vlm.txt`. mlx-lm is a dependency, not the entry point for these packs. The bundled model `runtime/` loader is only a fallback for older mlx-vlm; this demo uses native `mlx_vlm.load`.

## Sampling

| Mode | Temperature | Top-p | Top-k | Min-p | Presence penalty | Repetition penalty | Penalty window |
|---|---:|---:|---:|---:|---:|---:|---:|
| Thinking on | 1.0 | 0.95 | 20 | 0 | 1.0 | 1.0 (off) | 64 |
| Thinking off | 0.7 | 0.8 | 20 | 0 | 1.5 | 1.0 (off) | 64 |

For new small models, the GGUF CLI/server and MLX one-shot launcher select these profiles. Use `BONSAI_THINKING=0` for the non-thinking profile, or `--no-think` with `run_mlx.sh`. Explicit sampling arguments override launcher defaults. Existing 27B sampling defaults are preserved.

For API calls, set the whole profile explicitly. Changing thinking mode alone does not automatically change sampling. Browser and app settings can override server defaults; set these values in the app when supported.

### llama-server

Start the server with `BONSAI_MODEL=2B ./scripts/start_llama_server.sh`. A thinking request:

```json
{
  "messages": [{"role": "user", "content": "Suggest three names for a tiny robot gardener."}],
  "max_tokens": 2048,
  "temperature": 1.0, "top_p": 0.95, "top_k": 20, "min_p": 0,
  "presence_penalty": 1.0, "repeat_penalty": 1.0, "repeat_last_n": 64,
  "chat_template_kwargs": {"enable_thinking": true}
}
```

For thinking off, use temperature 0.7, top-p 0.8, presence penalty 1.5, and `chat_template_kwargs.enable_thinking=false`.
The equivalent GGUF flags are `--presence-penalty 1.0 --repeat-penalty 1.0 --repeat-last-n 64`; one history window controls the repetition/presence/frequency penalties.

### Native mlx-vlm server

Start with `BONSAI_MODEL=2B ./scripts/start_mlx_server.sh` (port 8081). Send sampling in each `/v1/chat/completions` request:

```json
{
  "model": "models/Ternary-Bonsai-2-2B-mlx-2bit",
  "messages": [{"role": "user", "content": "Suggest three names for a tiny robot gardener."}],
  "max_tokens": 2048,
  "temperature": 1.0, "top_p": 0.95, "top_k": 20, "min_p": 0,
  "presence_penalty": 1.0, "presence_context_size": 64, "repetition_penalty": 1.0,
  "enable_thinking": true
}
```

Use the served model ID from `/v1/models` if your client needs an exact ID. For thinking off, use temperature 0.7, top-p 0.8, presence penalty 1.5, and top-level `enable_thinking=false`. This server does not use mlx-lm's `--temp`/`--top-p` flags or its `chat_template_kwargs` toggle. `BONSAI_THINKING` does not configure the mlx-vlm server's per-request profile.

mlx-vlm 0.7.8 server reads temperature, top-p, and top-k defaults from `generation_config.json`, but not min-p or presence penalty. Send the full profile above on every request. Direct Python `mlx_vlm.generate()` defaults to greedy decoding unless you pass sampling arguments; our one-shot launcher passes them explicitly. In contrast, the current `mlx_lm.server` defaults to temperature 0 and gets sampling from CLI/request arguments. Recommendations for mlx-lm only apply to checkpoints its loader supports.

Matching these values does not make output identical across runtimes: sampler ordering, numerical kernels, and RNG differ. MLX uses a separate `presence_context_size` (default 20), so explicitly setting 64 matters. Do not use 0 as a portable way to disable a history window; repetition penalty 1.0 disables that penalty directly.

## Scope

Use the standalone chat/API launchers for the new sizes. The optional Open WebUI agentic launcher still needs its small-model profiles and loader routing updated; it stops with guidance instead of falling back to the older model path.

Automatic draft/MTP selection is not enabled here. Test the base model first. New small models have projectors available; the GGUF launcher discovers one when present. Image quality, draft decoding, and Windows execution still need validation. Keep the existing image-token cap for lightweight Mac use; large images may lose fine detail.
