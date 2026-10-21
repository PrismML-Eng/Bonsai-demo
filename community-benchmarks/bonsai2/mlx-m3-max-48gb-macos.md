# Apple MacBook Pro M3 Max (48 GB) — MLX (Bonsai 2 27B)

## Summary

Bonsai 2 27B MLX 2-bit pack on an Apple M3 Max with 48 GB unified memory, macOS 27.2.
This is not `llama-bench`. Prompt and generation lengths match the table columns:
512 prompt tokens and 128 generated tokens, three trials.

| Format | Backend | PP512 (t/s) | TG128 (t/s) |
|--------|---------|------------:|------------:|
| 2-bit (MLX pack) | MLX 0.32.2, mlx-vlm 0.6.17 | 165.85 ± 8.92 | 27.09 ± 1.89 |

## Configuration

- MLX pack: `prism-ml/Ternary-Bonsai-2-27B-mlx-2bit` (Hadamard-rotated 2-bit, schema v2)
- Loader: the pack's `runtime/vision_artifact.py` (`load_vl_model`), then `mlx_vlm.generate.stream_generate`
- mlx 0.32.2, mlx-vlm 0.6.17
- Activations are cast to fp16 for the 2-bit GEMV and cast back. That is the local serve path (`bin/bonsai_qmv.py`).
- Greedy: temperature 0, top_p 1, top_k 0
- KV: 8-bit uniform, quantization starts at token 5000, so this 512+128 window stays fp16 KV
- Prefill chunk 1024
- Hardware: Apple M3 Max, 40-core GPU (`applegpu_g15s`), 16-core CPU, 48 GB unified memory, Metal 4
- OS: macOS 27.2 (build 26B5091g)
- Power: stock. One run, machine in normal desktop use, not a cooled idle bench

## Command

The harness builds a 512-token prompt from a repeated sentence, warms up with 16 tokens, then runs three generations of 128 tokens. Prompt tokens/s is time to the first token. Generation tokens/s is over the 128 completion tokens.

```bash
python /tmp/bonsai_tg128.py
```

## Results

Prompt tokens: 512. Generation tokens: 128. Peak 11.8 GB.

| Trial | PP512 (t/s) | TG128 (t/s) |
|------:|------------:|------------:|
| 1 | 178.27 | 28.22 |
| 2 | 161.56 | 24.43 |
| 3 | 157.72 | 28.63 |
| mean ± pstdev | 165.85 ± 8.92 | 27.09 ± 1.89 |

## Other lengths, same path

Not TG128. A separate 256-token greedy generation on a short prompt the same day measured 29.31 tok/s. A 512-token prompt in that run prefilled at 176.52 tok/s. Those are not the numbers in the summary table above.
