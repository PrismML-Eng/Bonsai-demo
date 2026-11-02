# Bonsai 2 27B Benchmark - AMD Radeon RX 580

## Summary
This report provides performance benchmarks for the Bonsai 2 27B model running on a budget-tier AMD Radeon RX 580 desktop setup. The environment utilizes an AM5 platform under Ubuntu 22.04 LTS to measure token throughput for processing and generation tasks across different quantization formats.

## System Environment
- **Hardware:** AMD Radeon RX 580 (8 GB)
- **CPU:** AMD Ryzen 5 7600 6-Core Processor
- **Motherboard:** ASUSTeK COMPUTER INC. PRIME B650-PLUS
- **RAM:** 32 GB DDR5 4800MHz
- **OS:** Ubuntu 22.04 LTS
- **Backend:** llama.cpp Vulkan (Linux)

## Benchmark Results
Organized by model packing format.

| Format | PP512 (t/s) | TG128 (t/s) |
| --- | --- | --- |
| PQ2_0 | 36.67 | 7.26 |
| PTQ1_0 | 49.03 | 5.50 |

## Raw Output
```text
bin/vulkan/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
load_backend: loaded RPC backend from /games/llm/Bonsai-demo/bin/vulkan/libggml-rpc.so
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = AMD Radeon RX 580 Series (RADV POLARIS10) (radv) | uma: 0 | fp16: 0 | bf16: 0 | fp4: 0 | warp size: 64 | shared memory: 65536 | int dot: 0 | matrix cores: none
load_backend: loaded Vulkan backend from /games/llm/Bonsai-demo/bin/vulkan/libggml-vulkan.so
load_backend: loaded CPU backend from /games/llm/Bonsai-demo/bin/vulkan/libggml-cpu-zen4.so

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | Vulkan     |  99 |   1 |           pp512 |         36.67 ± 0.52 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | Vulkan     |  99 |   1 |           tg128 |          7.26 ± 0.01 |

bin/vulkan/llama-bench -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -p 512 -n 128 -ngl 99 -fa 1
load_backend: loaded RPC backend from /games/llm/Bonsai-demo/bin/vulkan/libggml-rpc.so
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = AMD Radeon RX 580 Series (RADV POLARIS10) (radv) | uma: 0 | fp16: 0 | bf16: 0 | fp4: 0 | warp size: 64 | shared memory: 65536 | int dot: 0 | matrix cores: none
load_backend: loaded Vulkan backend from /games/llm/Bonsai-demo/bin/vulkan/libggml-vulkan.so
load_backend: loaded CPU backend from /games/llm/Bonsai-demo/bin/vulkan/libggml-cpu-zen4.so

| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | Vulkan     |  99 |   1 |           pp512 |         49.03 ± 0.02 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | Vulkan     |  99 |   1 |           tg128 |          5.50 ± 0.00 |

Architecture:                            x86_64
CPU op-mode(s):                          32-bit, 64-bit
Address sizes:                           48 bits physical, 48 bits virtual
Byte Order:                              Little Endian
CPU(s):                                  12
On-line CPU(s) list:                     0-11
Vendor ID:                               AuthenticAMD
Model name:                              AMD Ryzen 5 7600 6-Core Processor
CPU family:                              25
Model:                                   97
Thread(s) per core:                      2
Core(s) per socket:                      6
Socket(s):                               1
Stepping:                                2
CPU(s) scaling MHz:                      78%
CPU max MHz:                             5170.0000
CPU min MHz:                             545.0000
BogoMIPS:                                7585.10
Virtualization:                          AMD-V

               total        used        free      shared  buff/cache   available
Mem:            31Gi       6.6Gi       940Mi       122Mi        24Gi        24Gi
Swap:           15Gi       1.3Gi        14Gi

==========
VULKANINFO
==========
Vulkan Instance Version: 1.3.275

Devices:
========
GPU0:
	apiVersion         = 1.4.318
	driverVersion      = 25.2.8
	vendorID           = 0x1002
	deviceID           = 0x67df
	deviceType         = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
	deviceName         = AMD Radeon RX 580 Series (RADV POLARIS10)
	driverID           = DRIVER_ID_MESA_RADV
	driverName         = radv
	driverInfo         = Mesa 25.2.8-0ubuntu0.24.04.4
```

