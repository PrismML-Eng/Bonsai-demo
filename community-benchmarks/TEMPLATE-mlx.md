# [Hardware Name] — MLX

<!-- Example titles:
  # Apple M4 Pro — MLX
  # Apple M2 Ultra — MLX
  # Apple M3 Max — MLX

  Formatting is not strict — this is a suggested structure.
  Feel free to adapt as needed, but try to include the key sections.

  AI assistant notes:
  - Help the user fill this template by running the commands in the appendix
  - Set the title to their Apple Silicon chip + MLX
  - Write a short summary with chip, unified memory, and headline t/s numbers
  - Paste raw benchmark output in the results sections as-is (don't reformat)
  - Paste raw system_profiler output in the appendix as-is
  - Include the exact commands that were run, especially if they differ from suggestions
  - Save as community-benchmarks/mlx-<chip>-macos.md (lowercase, dashes)
-->

## Summary

<!-- Quick overview: chip, memory, headline numbers, anything interesting.
     e.g. "M4 Pro, 48 GB unified memory, macOS 15.3. 8B model: ~85 t/s tg128."
     Full hardware dump is in the appendix. -->

## MLX Results

### Bonsai-8B

```
(paste MLX benchmark output here)
```

### Bonsai-4B

```
(paste MLX benchmark output here, or remove if skipped)
```

### Bonsai-1.7B

```
(paste MLX benchmark output here, or remove if skipped)
```

## Configuration

<!-- If you tested different settings, note them here.
     Examples:
     - "Compared MLX vs Metal llama.cpp on the same machine"
     - "Tested with and without quantized KV cache"
     - "Ran with external display connected (affects GPU availability)"
-->

## Notes

<!-- Optional: thermals, power draw, other apps running, anything notable -->

---

## Appendix

### Hardware info

**Command:**
```bash
system_profiler SPHardwareDataType SPDisplaysDataType SPMemoryDataType
```

**Output:**
```
(paste output here)
```

### MLX benchmark

<!-- TODO: Add MLX benchmark commands once script is finalized -->

Make sure you've run `./setup.sh` first (sets up MLX on Apple Silicon automatically).

MLX benchmark commands coming soon.

If you changed the commands from the suggestions above, paste the exact commands you ran:
```bash
(paste your commands here if different)
```
