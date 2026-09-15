# Apple M3 MacBook Air — MLX (2-bit)

## Summary

Apple M3 MacBook Air with 16 GB unified memory and 10 CPU cores, running MLX 2-bit benchmarks. Results use 512 prompt tokens and 128 generated tokens with batch size 1. The 27B model reached 9.119 generation tokens/s; the 8B model reached 34.775 generation tokens/s.

## MLX Results (2-bit)

### Ternary-Bonsai-27B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-27B-mlx-2bit -p 512 -g 128`

Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=51.107, generation_tps=10.964, peak_memory=8.827, total_time=21.878
Trial 2:  prompt_tps=49.537, generation_tps=11.013, peak_memory=8.828, total_time=22.154
Trial 3:  prompt_tps=48.011, generation_tps=9.829, peak_memory=8.829, total_time=23.886
Trial 4:  prompt_tps=48.244, generation_tps=7.991, peak_memory=8.829, total_time=26.834
Trial 5:  prompt_tps=45.179, generation_tps=5.800, peak_memory=8.830, total_time=33.641
Averages: prompt_tps=48.416, generation_tps=9.119, peak_memory=8.829

### Ternary-Bonsai-8B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-8B-mlx-2bit -p 512 -g 128`

Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=182.350, generation_tps=35.464, peak_memory=2.923, total_time=6.522
Trial 2:  prompt_tps=176.955, generation_tps=35.697, peak_memory=2.923, total_time=6.591
Trial 3:  prompt_tps=173.632, generation_tps=34.971, peak_memory=2.924, total_time=6.722
Trial 4:  prompt_tps=172.348, generation_tps=34.134, peak_memory=2.924, total_time=6.854
Trial 5:  prompt_tps=170.758, generation_tps=33.608, peak_memory=2.924, total_time=6.956
Averages: prompt_tps=175.209, generation_tps=34.775, peak_memory=2.924

### Ternary-Bonsai-4B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-4B-mlx-2bit -p 512 -g 128`

Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=373.653, generation_tps=60.798, peak_memory=1.737, total_time=3.573
Trial 2:  prompt_tps=347.391, generation_tps=61.608, peak_memory=1.737, total_time=3.645
Trial 3:  prompt_tps=334.953, generation_tps=61.631, peak_memory=1.737, total_time=3.695
Trial 4:  prompt_tps=327.192, generation_tps=60.258, peak_memory=1.738, total_time=3.794
Trial 5:  prompt_tps=322.265, generation_tps=59.176, peak_memory=1.738, total_time=3.871
Averages: prompt_tps=341.091, generation_tps=60.694, peak_memory=1.737

### Ternary-Bonsai-1.7B

Command:

`.venv/bin/python -m mlx_lm.benchmark --model models/Ternary-Bonsai-1.7B-mlx-2bit -p 512 -g 128`

Running warmup..
Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.
Trial 1:  prompt_tps=709.584, generation_tps=84.371, peak_memory=1.144, total_time=2.340
Trial 2:  prompt_tps=702.371, generation_tps=86.348, peak_memory=1.144, total_time=2.345
Trial 3:  prompt_tps=673.301, generation_tps=87.097, peak_memory=1.144, total_time=2.348
Trial 4:  prompt_tps=670.190, generation_tps=89.377, peak_memory=1.144, total_time=2.319
Trial 5:  prompt_tps=684.434, generation_tps=89.920, peak_memory=1.145, total_time=2.300
Averages: prompt_tps=687.976, generation_tps=87.423, peak_memory=1.144

## Configuration

- Backend: MLX 2-bit
- Prompt tokens: 512
- Generation tokens: 128
- Batch size: 1
- Five timed trials after warmup
- Models downloaded with `BONSAI_FAMILY=ternary`
- MLX built from the repository's pinned source during setup

## Notes

The unauthenticated Hugging Face downloads encountered rate limiting while fetching the 8B and 4B model metadata, but setup completed successfully and all benchmark runs finished normally.

## Hardware

```text
machdep.cpu.brand_string: Apple M3
hw.memsize: 17179869184
hw.ncpu: 8
Chipset Model: Apple M3
Total Number of Cores: 10
Metal Support: Metal 4
```
