# Apple M4 Pro (20-core GPU, 64 GB) - MLX (2-bit)

## Summary

Apple M4 Pro Mac mini with a 20-core GPU and 64 GB unified memory, running
macOS 26.5.2. Ternary-Bonsai-27B reached 119.78 t/s prompt processing and
24.82 t/s generation with the standard MLX 2-bit model.

On the same machine, the repository's prebuilt llama.cpp Metal runtime reached
115.99 t/s for pp512 and 19.01 t/s for tg128. MLX generation was 30.6% faster,
while prompt processing was 3.3% faster in these benchmark runs.

## MLX Results (2-bit)

### Ternary-Bonsai-27B

Command:

```bash
.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-27B-mlx-2bit -p 512 -g 128
```

```text
Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=133.651, generation_tps=25.547, peak_memory=8.976, total_time=8.984
Trial 2:  prompt_tps=127.598, generation_tps=25.133, peak_memory=8.976, total_time=9.254
Trial 3:  prompt_tps=114.624, generation_tps=24.695, peak_memory=8.977, total_time=9.794
Trial 4:  prompt_tps=111.659, generation_tps=24.147, peak_memory=8.977, total_time=10.022
Trial 5:  prompt_tps=111.378, generation_tps=24.590, peak_memory=8.978, total_time=9.937
Averages: prompt_tps=119.782, generation_tps=24.822, peak_memory=8.977
```

## Configuration

- `mlx==0.32.0`
- `mlx-lm==0.31.2`
- Standard PyPI MLX wheels
- Ternary-Bonsai-27B MLX 2-bit weights
- Two external 4K displays connected

The repository's MLX source build could not run because Xcode 26.4.1 reports a
missing Metal Toolchain and fails to download it due to an incompatible
`IDESimulatorFoundation` plugin. Standard official MLX wheels do not require a
local source build and ran the benchmark successfully.

## Hardware

```text
ProductName:            macOS
ProductVersion:         26.5.2
BuildVersion:           25F84
machdep.cpu.brand_string: Apple M4 Pro
hw.memsize: 68719476736
hw.ncpu: 14
hw.logicalcpu: 14
Chipset Model: Apple M4 Pro
Total Number of GPU Cores: 20
Metal Support: Metal 4
```
