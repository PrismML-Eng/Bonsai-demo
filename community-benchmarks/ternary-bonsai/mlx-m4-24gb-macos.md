# Apple M4 (10-core GPU, 24 GB)  — MLX (2-bit)

## Summary

Apple M4 Macbook Pro (14 inch , November 2024) with 10-core GPU.

  Chipset Model: Apple M4

  Type: GPU

  Bus: Built-In

  Total Number of Cores: 10

  Vendor: Apple (0x106b)

  Metal Support: Metal 3

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

Running warmup..

Timing with prompt_tokens=512, generation_tokens=128, batch_size=1.

Trial 1:  prompt_tps=68.222, generation_tps=12.610, peak_memory=8.827, total_time=17.844

Trial 2:  prompt_tps=67.151, generation_tps=12.793, peak_memory=8.828, total_time=17.852

Trial 3:  prompt_tps=64.321, generation_tps=12.314, peak_memory=8.829, total_time=18.540

Trial 4:  prompt_tps=61.916, generation_tps=12.803, peak_memory=8.829, total_time=18.456

Trial 5:  prompt_tps=64.192, generation_tps=12.754, peak_memory=8.830, total_time=18.209

Averages: prompt_tps=65.160, generation_tps=12.655, peak_memory=8.829

## Configuration

- mlx      0.31.2.dev20260817+10b5fe43
-  mlx-lm  0.31.2
- One external 4K diplay connected



## Notes



## Hardware

Not required, but helpful:

```bash
sysctl machdep.cpu.brand_string hw.memsize hw.ncpu && system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|Number of Cores|Metal"
```

```
machdep.cpu.brand_string: Apple M4
hw.memsize: 25769803776
hw.ncpu: 10
      Chipset Model: Apple M4
      Total Number of Cores: 10
      Metal Support: Metal 3
```

