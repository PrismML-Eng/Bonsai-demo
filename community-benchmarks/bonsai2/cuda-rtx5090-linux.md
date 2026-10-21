# NVIDIA RTX 5090 32 GB - CUDA / Linux

## Summary

Bonsai 2 27B on one RTX 5090, using PrismML release `prism-b10743-adfffbe`
(commit `adfffbe41`), CUDA 12.8 binaries. Measured September 30, 2026.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 4074.89 | 142.97 |
| PTQ1_0 | 4116.64 | 133.01 |

These are five-repetition means. Prompt processing was similar for the two
packings on this build; decode was about 7.5% faster with PQ2_0. This is one
machine and build, not a claim about other hardware or versions.

## Configuration

- GPU: NVIDIA RTX 5090, 32607 MiB reported VRAM; no power-limit or clock changes made for these runs.
- CPU: Intel Core Ultra 7 265K; system RAM: approximately 62 GiB.
- OS: Ubuntu 22.04 series, Linux 6.8.0-111-generic x86_64.
- NVIDIA driver: 595.91.07. Binary asset: `llama-prism-b10743-adfffbe-bin-linux-cuda-12.8-x64.tar.gz`.
- CUDA runtime: 12.8.90; cuBLAS: 12.8.5.5, reused from an existing installation via `LD_LIBRARY_PATH`.
- Demo checkout used for deployment: `69c3a8beeab80283bfd45cb7b7a6b927075c29fd`.
- Model repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`, revision `b072e1d3b35a0a630cece372c2127528e0994386`.
- `Ternary-Bonsai-2-27B-PQ2_0.gguf`: 7,206,168,928 bytes; SHA256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`.
- `Ternary-Bonsai-2-27B-PTQ1_0.gguf`: 5,946,648,928 bytes; SHA256 `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`.
- All layers offloaded; flash attention on; F16 K/V; 4 CPU threads; batch 2048; microbatch 512; depth 0.
- PQ2_0 then PTQ1_0, sequentially. An existing 32K PQ2_0 chat server remained resident (about 9548 MiB process GPU memory); no requests to it were scheduled by the benchmark. This was not an otherwise empty GPU.
- No vision projector, speculative decoding, or experimental KV quantization.

## llama-bench results

Commands below are the recorded commands, with the experiment root factored into
`ROOT`. CUDA runtime libraries must already be discoverable. Raw JSON is retained
below, including individual samples and standard deviations.

### PQ2_0

```bash
ROOT=/var/tmp/bonsai-5090-20260930
"$ROOT/Bonsai-demo/bin/cuda/llama-bench" \
  -m "$ROOT/models/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
  -ngl 99 -fa on -p 512,4096 -n 128 -r 5 -o json
```

```json
[
  {
    "build_commit": "adfffbe41",
    "build_number": 10743,
    "cpu_info": "Intel(R) Core(TM) Ultra 7 265K",
    "gpu_info": "NVIDIA GeForce RTX 5090",
    "backends": "CUDA",
    "model_filename": "/var/tmp/bonsai-5090-20260930/models/Ternary-Bonsai-2-27B-PQ2_0.gguf",
    "model_type": "qwen35 27B PQ2_0 - 2.13 bpw (group 128)",
    "model_size": 7195047936,
    "model_n_params": 26895998464,
    "n_batch": 2048,
    "n_ubatch": 512,
    "n_threads": 4,
    "cpu_mask": "0x0",
    "cpu_strict": false,
    "poll": 50,
    "type_k": "f16",
    "type_v": "f16",
    "n_gpu_layers": 99,
    "n_cpu_moe": 0,
    "split_mode": "layer",
    "main_gpu": 0,
    "no_kv_offload": false,
    "flash_attn": 1,
    "devices": "auto",
    "tensor_split": "0.00",
    "tensor_buft_overrides": "none",
    "load_mode": "auto",
    "embeddings": false,
    "no_op_offload": 0,
    "no_host": false,
    "fit_target": 0,
    "fit_min_ctx": 0,
    "n_prompt": 512,
    "n_gen": 0,
    "n_depth": 0,
    "test_time": "2026-09-30T02:25:06Z",
    "avg_ns": 126110993,
    "stddev_ns": 8870864,
    "avg_ts": 4074.886213,
    "stddev_ts": 266.188932,
    "samples_ns": [ 141374205, 126395376, 121715262, 120864427, 120205699 ],
    "samples_ts": [ 3621.59, 4050.78, 4206.54, 4236.15, 4259.37 ]
  },
  {
    "build_commit": "adfffbe41",
    "build_number": 10743,
    "cpu_info": "Intel(R) Core(TM) Ultra 7 265K",
    "gpu_info": "NVIDIA GeForce RTX 5090",
    "backends": "CUDA",
    "model_filename": "/var/tmp/bonsai-5090-20260930/models/Ternary-Bonsai-2-27B-PQ2_0.gguf",
    "model_type": "qwen35 27B PQ2_0 - 2.13 bpw (group 128)",
    "model_size": 7195047936,
    "model_n_params": 26895998464,
    "n_batch": 2048,
    "n_ubatch": 512,
    "n_threads": 4,
    "cpu_mask": "0x0",
    "cpu_strict": false,
    "poll": 50,
    "type_k": "f16",
    "type_v": "f16",
    "n_gpu_layers": 99,
    "n_cpu_moe": 0,
    "split_mode": "layer",
    "main_gpu": 0,
    "no_kv_offload": false,
    "flash_attn": 1,
    "devices": "auto",
    "tensor_split": "0.00",
    "tensor_buft_overrides": "none",
    "load_mode": "auto",
    "embeddings": false,
    "no_op_offload": 0,
    "no_host": false,
    "fit_target": 0,
    "fit_min_ctx": 0,
    "n_prompt": 4096,
    "n_gen": 0,
    "n_depth": 0,
    "test_time": "2026-09-30T02:25:07Z",
    "avg_ns": 972271348,
    "stddev_ns": 1445860,
    "avg_ts": 4212.823146,
    "stddev_ts": 6.264530,
    "samples_ns": [ 971330947, 970313819, 972544319, 973340651, 973827008 ],
    "samples_ts": [ 4216.89, 4221.31, 4211.63, 4208.19, 4206.09 ]
  },
  {
    "build_commit": "adfffbe41",
    "build_number": 10743,
    "cpu_info": "Intel(R) Core(TM) Ultra 7 265K",
    "gpu_info": "NVIDIA GeForce RTX 5090",
    "backends": "CUDA",
    "model_filename": "/var/tmp/bonsai-5090-20260930/models/Ternary-Bonsai-2-27B-PQ2_0.gguf",
    "model_type": "qwen35 27B PQ2_0 - 2.13 bpw (group 128)",
    "model_size": 7195047936,
    "model_n_params": 26895998464,
    "n_batch": 2048,
    "n_ubatch": 512,
    "n_threads": 4,
    "cpu_mask": "0x0",
    "cpu_strict": false,
    "poll": 50,
    "type_k": "f16",
    "type_v": "f16",
    "n_gpu_layers": 99,
    "n_cpu_moe": 0,
    "split_mode": "layer",
    "main_gpu": 0,
    "no_kv_offload": false,
    "flash_attn": 1,
    "devices": "auto",
    "tensor_split": "0.00",
    "tensor_buft_overrides": "none",
    "load_mode": "auto",
    "embeddings": false,
    "no_op_offload": 0,
    "no_host": false,
    "fit_target": 0,
    "fit_min_ctx": 0,
    "n_prompt": 0,
    "n_gen": 128,
    "n_depth": 0,
    "test_time": "2026-09-30T02:25:13Z",
    "avg_ns": 895363807,
    "stddev_ns": 6985933,
    "avg_ts": 142.965539,
    "stddev_ts": 1.103893,
    "samples_ns": [ 907859728, 892305847, 892296020, 892233015, 892124429 ],
    "samples_ts": [ 140.991, 143.449, 143.45, 143.46, 143.478 ]
  }
]
```

### PTQ1_0

```bash
ROOT=/var/tmp/bonsai-5090-20260930
"$ROOT/Bonsai-demo/bin/cuda/llama-bench" \
  -m "$ROOT/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf" \
  -ngl 99 -fa on -p 512,4096 -n 128 -r 5 -o json
```

```json
[
  {
    "build_commit": "adfffbe41",
    "build_number": 10743,
    "cpu_info": "Intel(R) Core(TM) Ultra 7 265K",
    "gpu_info": "NVIDIA GeForce RTX 5090",
    "backends": "CUDA",
    "model_filename": "/var/tmp/bonsai-5090-20260930/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    "model_type": "qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128)",
    "model_size": 5935527936,
    "model_n_params": 26895998464,
    "n_batch": 2048,
    "n_ubatch": 512,
    "n_threads": 4,
    "cpu_mask": "0x0",
    "cpu_strict": false,
    "poll": 50,
    "type_k": "f16",
    "type_v": "f16",
    "n_gpu_layers": 99,
    "n_cpu_moe": 0,
    "split_mode": "layer",
    "main_gpu": 0,
    "no_kv_offload": false,
    "flash_attn": 1,
    "devices": "auto",
    "tensor_split": "0.00",
    "tensor_buft_overrides": "none",
    "load_mode": "auto",
    "embeddings": false,
    "no_op_offload": 0,
    "no_host": false,
    "fit_target": 0,
    "fit_min_ctx": 0,
    "n_prompt": 512,
    "n_gen": 0,
    "n_depth": 0,
    "test_time": "2026-09-30T02:25:18Z",
    "avg_ns": 124845738,
    "stddev_ns": 8940287,
    "avg_ts": 4116.644248,
    "stddev_ts": 272.149072,
    "samples_ns": [ 140429326, 124186349, 121006620, 119658779, 118947619 ],
    "samples_ts": [ 3645.96, 4122.84, 4231.17, 4278.83, 4304.42 ]
  },
  {
    "build_commit": "adfffbe41",
    "build_number": 10743,
    "cpu_info": "Intel(R) Core(TM) Ultra 7 265K",
    "gpu_info": "NVIDIA GeForce RTX 5090",
    "backends": "CUDA",
    "model_filename": "/var/tmp/bonsai-5090-20260930/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    "model_type": "qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128)",
    "model_size": 5935527936,
    "model_n_params": 26895998464,
    "n_batch": 2048,
    "n_ubatch": 512,
    "n_threads": 4,
    "cpu_mask": "0x0",
    "cpu_strict": false,
    "poll": 50,
    "type_k": "f16",
    "type_v": "f16",
    "n_gpu_layers": 99,
    "n_cpu_moe": 0,
    "split_mode": "layer",
    "main_gpu": 0,
    "no_kv_offload": false,
    "flash_attn": 1,
    "devices": "auto",
    "tensor_split": "0.00",
    "tensor_buft_overrides": "none",
    "load_mode": "auto",
    "embeddings": false,
    "no_op_offload": 0,
    "no_host": false,
    "fit_target": 0,
    "fit_min_ctx": 0,
    "n_prompt": 4096,
    "n_gen": 0,
    "n_depth": 0,
    "test_time": "2026-09-30T02:25:19Z",
    "avg_ns": 969590658,
    "stddev_ns": 2351870,
    "avg_ts": 4224.483039,
    "stddev_ts": 10.253918,
    "samples_ns": [ 971646183, 966460655, 970181463, 967878887, 971786104 ],
    "samples_ts": [ 4215.53, 4238.14, 4221.89, 4231.93, 4214.92 ]
  },
  {
    "build_commit": "adfffbe41",
    "build_number": 10743,
    "cpu_info": "Intel(R) Core(TM) Ultra 7 265K",
    "gpu_info": "NVIDIA GeForce RTX 5090",
    "backends": "CUDA",
    "model_filename": "/var/tmp/bonsai-5090-20260930/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    "model_type": "qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128)",
    "model_size": 5935527936,
    "model_n_params": 26895998464,
    "n_batch": 2048,
    "n_ubatch": 512,
    "n_threads": 4,
    "cpu_mask": "0x0",
    "cpu_strict": false,
    "poll": 50,
    "type_k": "f16",
    "type_v": "f16",
    "n_gpu_layers": 99,
    "n_cpu_moe": 0,
    "split_mode": "layer",
    "main_gpu": 0,
    "no_kv_offload": false,
    "flash_attn": 1,
    "devices": "auto",
    "tensor_split": "0.00",
    "tensor_buft_overrides": "none",
    "load_mode": "auto",
    "embeddings": false,
    "no_op_offload": 0,
    "no_host": false,
    "fit_target": 0,
    "fit_min_ctx": 0,
    "n_prompt": 0,
    "n_gen": 128,
    "n_depth": 0,
    "test_time": "2026-09-30T02:25:25Z",
    "avg_ns": 962450059,
    "stddev_ns": 12846932,
    "avg_ts": 133.012539,
    "stddev_ts": 1.744238,
    "samples_ns": [ 985430583, 956591610, 956853249, 956745251, 956629603 ],
    "samples_ts": [ 129.892, 133.808, 133.772, 133.787, 133.803 ]
  }
]
```

## Scope

The development Q2_0 packing, CPU-only inference, vision, speculative decoding,
and FP16 quality comparisons were not tested. These throughput results alone do
not establish reasoning accuracy or long-context correctness.

AI assistance was used to run and organize the experiment and prepare this report.
The timings above come from the recorded llama-bench output, not estimates.
