# [Hardware Name] — MLX (2-bit)

<!-- Example titles:
  # Apple M4 Pro — MLX (2-bit)
  # Apple M2 Ultra — MLX (2-bit)
  # Apple M3 Max — MLX (2-bit)

  Formatting is not strict — this is a suggested structure.
  Feel free to adapt as needed, but try to include the key sections.

  AI assistant notes:
  - Help the user fill this template by running the suggested commands
  - Set the title to their Apple Silicon chip + MLX (2-bit)
  - Write a short summary with chip, unified memory, and headline t/s numbers
  - Paste raw benchmark output in the results sections as-is (don't reformat)
  - Include the exact commands that were run, especially if they differ from suggestions
  - Save as community-benchmarks/ternary-bonsai/mlx-<chip>-macos.md (lowercase, dashes)
-->

## Summary

<!-- Quick overview: chip, memory, headline numbers, anything interesting.
     e.g. "M4 Pro, 48 GB unified memory, macOS 15.3. 8B model: ~85 t/s tg128." -->

## MLX Results (2-bit)

Ternary-Bonsai ships as MLX 2-bit out of the box:
- [Ternary-Bonsai-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-mlx-2bit)
- [Ternary-Bonsai-8B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit)
- [Ternary-Bonsai-4B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-mlx-2bit)
- [Ternary-Bonsai-1.7B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-mlx-2bit)

### Ternary-Bonsai-27B (the one we most want numbers for!)

```bash
.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-27B-mlx-2bit -p 512 -g 128
```

(paste MLX benchmark output here, or remove this section if you skipped the 27B)

### Ternary-Bonsai-8B

```bash
.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-8B-mlx-2bit -p 512 -g 128
```

(paste MLX benchmark output here — raw output, no code block)

### Ternary-Bonsai-4B

(paste MLX benchmark output here, or remove if skipped)

### Ternary-Bonsai-1.7B

(paste MLX benchmark output here, or remove if skipped)

## Configuration

<!-- If you tested different settings, note them here.
     Examples:
     - "Compared MLX 2-bit vs MLX 1-bit Bonsai on the same machine"
     - "Tested with and without quantized KV cache"
     - "Ran with external display connected (affects GPU availability)"
-->

## Notes

<!-- Optional: thermals, power draw, other apps running, anything notable -->

## Hardware

Not required, but helpful:

```bash
sysctl machdep.cpu.brand_string hw.memsize hw.ncpu && system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|Number of Cores|Metal"
```

```
(paste output here)
```
