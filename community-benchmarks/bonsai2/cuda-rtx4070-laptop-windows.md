# NVIDIA GeForce RTX 4070 Laptop GPU - CUDA / Windows 11

## Summary

Bonsai 2 27B on an HP Victus 16-s1xxx laptop with an NVIDIA GeForce RTX 4070 Laptop GPU (8 GB VRAM), 32 GB system RAM, and Windows 11 Home, using llama.cpp build `d8f26eec7 (10683)`.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | Not tested | Not tested |
| PTQ1_0 | 435.60 ± 3.89 | 32.44 ± 0.17 |
| Q2_0 (development) | Not tested | Not tested |

## Configuration

- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`
- Model packing: `PTQ1_0`
- Exact model filename: `Ternary-Bonsai-2-27B-PTQ1_0.gguf`
- Model revision/hash: Not recorded
- llama.cpp build: `d8f26eec7 (10683)`
- Backend: CUDA
- OS: Microsoft Windows 11 Home, version `10.0.26100`, build `26100`
- NVIDIA driver: `592.82`
- CUDA version reported by `nvidia-smi`: `13.1`
- GPU: NVIDIA GeForce RTX 4070 Laptop GPU
- GPU compute capability: 8.9
- GPU VRAM: 8187 MiB
- CPU: AMD Ryzen 7 8845HS w/ Radeon 780M Graphics
- System RAM: 32 GB
- GPU offload: `-ngl 99`
- Flash attention: enabled (`-fa 1`)
- Benchmark KV cache types: defaults
- Benchmark batch sizes / threads: defaults unless set internally by `llama-bench`
- GPU power limit: 90 W hardware power cap reported by `nvidia-smi`; no manual power-limit or overclock tuning was applied

## llama-bench results

### PQ2_0

Not tested.

### PTQ1_0

Exact PowerShell command:

```powershell
.\bin\cuda\llama-bench.exe `
  -m models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PTQ1_0.gguf `
  -p 512 `
  -n 128 `
  -ngl 99 `
  -fa 1
```

Raw result:

```text
ggml_cuda_init: found 1 CUDA devices (Total VRAM: 8187 MiB):
Device 0: NVIDIA GeForce RTX 4070 Laptop GPU, compute capability 8.9, VMM: yes, VRAM: 8187 MiB

| model                                              |     size |  params | backend | ngl | fa |  test |           t/s |
| -------------------------------------------------- | -------: | ------: | ------- | --: | -: | ----: | ------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA    |  99 |  1 | pp512 | 435.60 ± 3.89 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) | 5.53 GiB | 26.90 B | CUDA    |  99 |  1 | tg128 |  32.44 ± 0.17 |

build: d8f26eec7 (10683)
```

### Q2_0

Not tested.

## Additional observations

### 64K-context interactive use

For normal interactive use, Bonsai 2 27B PTQ1_0 is run with a configured 65,536-token context window and Q4_0 quantization for both the K and V KV caches.

Server command:

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

Observed generation throughput during normal interactive use is approximately:

**22 tokens/second**

Relevant settings:

- Configured context window: 65,536 tokens
- K-cache: `q4_0`
- V-cache: `q4_0`
- GPU offload: `-ngl 99`
- Flash attention: enabled
- Batch size: 512
- Micro-batch size: 256
- Parallel sequences: 1
- Reasoning budget: 500
- No MTP or speculative decoding

This is an informal real-world observation rather than a standardized `llama-bench` result. The configured 64K context window does not necessarily mean 64K tokens were resident during every observed generation, so this result should not be directly compared with PP512 or TG128.
