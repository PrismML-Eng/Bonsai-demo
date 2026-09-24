# NVIDIA GeForce RTX 4070 Laptop GPU 8 GB — CUDA / Windows

## Summary

Bonsai 2 27B PTQ1_0 benchmark on an NVIDIA GeForce RTX 4070 Laptop GPU with 8 GB VRAM.

The PTQ1_0 model runs fully GPU-offloaded and achieves approximately **32.4 tokens/second** in the standardized TG128 benchmark.

In normal interactive use with a configured **64K context window** and **Q4_0 KV-cache quantization**, generation is approximately **22 tokens/second** without MTP or speculative decoding.

| Format | PP512 | TG128 |
| --- | ---: | ---: |
| PTQ1_0 | 435.60 ± 3.89 t/s | 32.44 ± 0.17 t/s |

## Model

- Model: `prism-ml/Ternary-Bonsai-2-27B-gguf`
- Quantization: `PTQ1_0`
- Reported architecture: `qwen35 27B`
- Parameters: 26.90B
- Model size: 5.53 GiB
- Quantization density: 1.75 bpw ternary, group size 128

## Hardware

- System: HP Victus by HP Gaming Laptop 16-s1xxx
- CPU: AMD Ryzen 7 8845HS w/ Radeon 780M Graphics
- GPU: NVIDIA GeForce RTX 4070 Laptop GPU
- GPU VRAM: 8187 MiB
- GPU power limit: 90 W
- GPU compute capability: 8.9
- System RAM: 32 GB

## Software

- OS: Microsoft Windows 11 Home
- Windows version: 10.0.26100
- Windows build: 26100
- NVIDIA driver: 592.82
- CUDA version reported by `nvidia-smi`: 13.1
- llama.cpp build: `d8f26eec7 (10683)`
- Backend: CUDA
- GPU offload: `-ngl 99`
- Flash attention: enabled

## Standard Benchmark Command

```powershell
.\bin\cuda\llama-bench.exe `
  -m models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PTQ1_0.gguf `
  -p 512 `
  -n 128 `
  -ngl 99 `
  -fa 1
```

## llama-bench Results

```text
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 8187 MiB):
Device 0: NVIDIA GeForce RTX 4070 Laptop GPU, compute capability 8.9, VMM: yes, VRAM: 8187 MiB

| model                                              |     size |  params | backend | ngl | fa |  test |           t/s |
| -------------------------------------------------- | -------: | ------: | ------- | --: | -: | ----: | ------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA    |  99 |  1 | pp512 | 435.60 ± 3.89 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA    |  99 |  1 | tg128 |  32.44 ± 0.17 |

build: d8f26eec7 (10683)
```

## Additional Real-World Long-Context Result

### 64K Context Configuration

For normal model usage, the server is configured with a **65,536-token context window** and both K and V KV caches quantized to **Q4_0**.

```powershell
.\bin\cuda\llama-server.exe `
  --models-dir .\models `
  -ngl 99 `
  -fa on `
  -c 65536 `
  --cache-type-k q4_0 `
  --cache-type-v q4_0 `
  -b 512 `
  -ub 256 `
  -np 1 `
  --jinja `
  --host 127.0.0.1 `
  --port 8080 `
  --reasoning-budget 500
```

With this configuration, observed generation speed during normal interactive use is approximately:

**22 tokens/second**

This result uses:

- 65,536-token configured context window
- Q4_0 K-cache quantization
- Q4_0 V-cache quantization
- Full GPU offload with `-ngl 99`
- Flash attention enabled
- Batch size 512
- Micro-batch size 256
- Single parallel sequence
- No MTP or speculative decoding

The long-context figure is an informal real-world observation rather than a standardized `llama-bench` result, so it should not be directly compared with TG128.

## Notes

This benchmark demonstrates that Bonsai 2 27B PTQ1_0 can run effectively on an 8 GB consumer laptop GPU while remaining fully GPU-offloaded.

The model itself occupies approximately 5.53 GiB. Quantizing the KV cache to Q4_0 substantially reduces long-context memory requirements and helps make a 64K context configuration practical within the GPU's 8 GB VRAM limit.