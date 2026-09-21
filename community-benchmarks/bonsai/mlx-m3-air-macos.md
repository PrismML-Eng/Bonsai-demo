# Apple M3 MacBook Air — MLX

## Summary

Apple M3 MacBook Air with 16 GB unified memory, an 8-core CPU, and a 10-core GPU, running Bonsai 1-bit MLX benchmarks. Results use 512 prompt tokens and 128 generated tokens with batch size 1. Bonsai-27B reached 18.253 generation tokens/s; Bonsai-8B reached 56.410 generation tokens/s.

| Model size | Prompt tokens/s (512) | Generation tokens/s (128) | Reported peak memory (GB) |
|---|---:|---:|---:|
| 27B | 51.024 | 18.253 | 5.520 |
| 8B | 176.566 | 56.410 | 1.997 |
| 4B | 345.907 | 85.655 | 1.393 |
| 1.7B | 951.850 | 174.384 | 0.925 |

## MLX Results

### Bonsai-27B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Bonsai-27B-mlx -p 512 -g 128`

```text
Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=55.367, generation_tps=19.150, peak_memory=5.519, total_time=16.097
Trial 2:  prompt_tps=52.171, generation_tps=19.033, peak_memory=5.520, total_time=16.710
Trial 3:  prompt_tps=50.964, generation_tps=18.889, peak_memory=5.520, total_time=16.990
Trial 4:  prompt_tps=49.653, generation_tps=16.595, peak_memory=5.521, total_time=18.196
Trial 5:  prompt_tps=46.968, generation_tps=17.597, peak_memory=5.521, total_time=18.325
Averages: prompt_tps=51.024, generation_tps=18.253, peak_memory=5.520
```

### Bonsai-8B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Bonsai-8B-mlx -p 512 -g 128`

```text
Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=182.510, generation_tps=56.876, peak_memory=1.996, total_time=5.137
Trial 2:  prompt_tps=176.089, generation_tps=56.021, peak_memory=1.996, total_time=5.283
Trial 3:  prompt_tps=175.660, generation_tps=55.754, peak_memory=1.997, total_time=5.310
Trial 4:  prompt_tps=171.288, generation_tps=56.379, peak_memory=1.997, total_time=5.366
Trial 5:  prompt_tps=177.283, generation_tps=57.020, peak_memory=1.997, total_time=5.236
Averages: prompt_tps=176.566, generation_tps=56.410, peak_memory=1.997
```

### Bonsai-4B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Bonsai-4B-mlx -p 512 -g 128`

```text
Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=366.887, generation_tps=85.462, peak_memory=1.392, total_time=2.984
Trial 2:  prompt_tps=345.109, generation_tps=86.377, peak_memory=1.392, total_time=3.058
Trial 3:  prompt_tps=345.320, generation_tps=85.864, peak_memory=1.393, total_time=3.068
Trial 4:  prompt_tps=338.582, generation_tps=85.368, peak_memory=1.393, total_time=3.103
Trial 5:  prompt_tps=333.634, generation_tps=85.207, peak_memory=1.393, total_time=3.138
Averages: prompt_tps=345.907, generation_tps=85.655, peak_memory=1.393
```

### Bonsai-1.7B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Bonsai-1.7B-mlx -p 512 -g 128`

```text
Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=977.273, generation_tps=174.261, peak_memory=0.924, total_time=1.332
Trial 2:  prompt_tps=975.027, generation_tps=174.495, peak_memory=0.925, total_time=1.333
Trial 3:  prompt_tps=921.293, generation_tps=174.920, peak_memory=0.925, total_time=1.363
Trial 4:  prompt_tps=948.728, generation_tps=173.904, peak_memory=0.925, total_time=1.350
Trial 5:  prompt_tps=936.930, generation_tps=174.338, peak_memory=0.926, total_time=1.355
Averages: prompt_tps=951.850, generation_tps=174.384, peak_memory=0.925
```

## Configuration

- Backend: MLX 1-bit
- Prompt tokens: 512
- Generation tokens: 128
- Batch size: 1
- Five timed trials after warmup
- Models downloaded with `BONSAI_FAMILY=bonsai BONSAI_MODEL=all BONSAI_SKIP_GGUF=1`
- MLX built from the repository's pinned source during setup

## Notes

GGUF downloads were skipped because these benchmarks use the MLX backend only. All four Bonsai MLX model sizes downloaded successfully and completed their benchmark runs.

## Hardware

```text
machdep.cpu.brand_string: Apple M3
hw.memsize: 17179869184
hw.ncpu: 8
Chipset Model: Apple M3
Total Number of Cores: 10
Metal Support: Metal 4
```
