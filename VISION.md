# Vision (image input)

The 27B models are vision-language models: they accept images alongside text. This works out of the box in three places:

- **Built-in llama-server web UI**: click `+` in the message box and upload a photo or screenshot.
- **Open WebUI**: same, in the agentic demo (`./scripts/start_openwebui.sh`).
- **OpenAI-compatible API**: send `image_url` content parts to `/v1/chat/completions`.

`setup.sh` / `setup.ps1` download the multimodal projector (`*mmproj*.gguf`) next to the 27B weights, and the start scripts load it automatically. Budget about 0.9 GiB of extra memory for the projector.

On a VRAM-tight card you can keep the projector in system RAM instead with `BONSAI_MMPROJ_CPU=1` (passes `--no-mmproj-offload`), reclaiming that ~0.9 GiB for KV/context. The trade-off is a slower image prompt — the projector then runs on CPU, adding tens of ms to a few seconds per image during prefill — while token generation and text-only requests are unaffected.

## How images are priced

An image is encoded into **vision tokens**: one token covers roughly a 32x32 pixel patch, and the model accepts up to ~4096 vision tokens (about a 4.2 MP image). Vision tokens are prefill: a large photo can add thousands of tokens before the first word of the answer.

Two things keep this fast in practice:

1. **Prompt cache**: the image is encoded once; follow-up questions about the same image are near-instant on llama.cpp. (The MLX backend has no cross-request prompt cache, so follow-ups re-process there.)
2. **The image-token cap** below.

## The image-token cap

The start scripts pass `--image-max-tokens` to llama-server so oversized images are downscaled before encoding:

| Backend | Default |
|---------|---------|
| Metal / Vulkan / CPU | 1024 tokens (large photos answer much faster without losing much quality) |
| CUDA / ROCm | uncapped |

Override with the `BONSAI_IMAGE_MAX_TOKENS` environment variable: a number for a custom cap, or `0` to disable capping entirely.

Quality guidance from testing:

- **1024 is the sweet spot for everyday photos and screenshots**: layout, objects, colors, and normal-size text survive.
- **Fine detail suffers under the cap**: small print, serial numbers, and dense documents lose accuracy as the cap shrinks. For OCR-style tasks use `BONSAI_IMAGE_MAX_TOKENS=0` (or 2048+), or crop the region you care about instead of sending the full image.
- Images already under the cap are unaffected.

```bash
BONSAI_IMAGE_MAX_TOKENS=0 ./scripts/start_llama_server.sh
```

## MLX backend

The ternary 27B also serves images on the MLX backend via `mlx-vlm` (installed into `.venv-vlm` by `setup.sh`; `start_mlx_server.sh` and `BONSAI_BACKEND=mlx ./scripts/start_openwebui.sh` use it automatically). The binary (1-bit) 27B is text-only on MLX for now.
