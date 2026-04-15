# [Hardware Name] — MLX

<!-- Example titles:
  # Apple M4 Pro — MLX
  # Apple M2 Ultra — MLX
  # Apple M3 Max — MLX

  Formatting is not strict — this is a suggested structure.
  Feel free to adapt as needed, but try to include the key sections.

  AI assistant notes:
  - Help the user fill this template by running the suggested commands
  - Set the title to their Apple Silicon chip + MLX
  - Write a short summary with chip, unified memory, and headline t/s numbers
  - Paste raw benchmark output in the results sections as-is (don't reformat)
  - Include the exact commands that were run, especially if they differ from suggestions
  - Save as community-benchmarks/mlx-<chip>-macos.md (lowercase, dashes)
-->

## Summary

<!-- Quick overview: chip, memory, headline numbers, anything interesting.
     e.g. "M4 Pro, 48 GB unified memory, macOS 15.3. 8B model: ~85 t/s tg128." -->

## MLX Results

### Bonsai-8B

<!-- TODO: Add MLX benchmark commands once script is finalized -->

(paste MLX benchmark output here — raw output, no code block)

### Bonsai-4B

(paste MLX benchmark output here, or remove if skipped)

### Bonsai-1.7B

(paste MLX benchmark output here, or remove if skipped)

## Configuration

<!-- If you tested different settings, note them here.
     Examples:
     - "Compared MLX vs Metal llama.cpp on the same machine"
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
