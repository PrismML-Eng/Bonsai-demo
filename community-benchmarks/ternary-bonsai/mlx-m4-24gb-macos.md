# Apple M4 24 GB — MLX (2-bit)

## Summary

Apple M4 MacBook Pro (14-inch, November 2024, 10-core GPU, 24 GB unified memory), macOS with MLX. Ternary-Bonsai-27B (MLX 2-bit): **~12.7 t/s generation, ~65 t/s prompt processing**, peak memory 8.8 GB — the 27B fits and runs comfortably on the 24 GB base M4.

## MLX Results (2-bit)

### Ternary-Bonsai-27B

```bash
.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-27B-mlx-2bit -p 512 -g 128
```

```
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=68.222, generation_tps=12.610, peak_memory=8.827, total_time=17.844
Trial 2:  prompt_tps=67.151, generation_tps=12.793, peak_memory=8.828, total_time=17.852
Trial 3:  prompt_tps=64.321, generation_tps=12.314, peak_memory=8.829, total_time=18.540
Trial 4:  prompt_tps=61.916, generation_tps=12.803, peak_memory=8.829, total_time=18.456
Trial 5:  prompt_tps=64.192, generation_tps=12.754, peak_memory=8.830, total_time=18.209
Averages: prompt_tps=65.160, generation_tps=12.655, peak_memory=8.829
```

Model: [Ternary-Bonsai-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-mlx-2bit)

## Configuration

- mlx 0.31.2.dev20260817+10b5fe43
- mlx-lm 0.31.2
- One external 4K display connected

## Hardware

```
machdep.cpu.brand_string: Apple M4
hw.memsize: 25769803776
hw.ncpu: 10
      Chipset Model: Apple M4
      Total Number of Cores: 10
      Metal Support: Metal 3
```
