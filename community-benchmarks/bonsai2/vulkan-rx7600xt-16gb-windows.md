# AMD Radeon RX 7600 XT (16 GB) - llama.cpp Vulkan on Windows (Bonsai 2 27B)

Submitted 2026-11-02. Model paths in the commands are anonymized; the exact
filename and hash are listed in the Configuration section.

## Summary

Bonsai 2 27B on AMD Radeon RX 7600 XT 16 GB (Navi 33, RDNA3), Windows 11 Pro
(build 26300), using a custom Vulkan build based on the community fork
Torchit1/llama.cpp v0.10.1 (see Configuration). Experimental build, not a release.

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | not tested | not tested |
| PTQ1_0 (community mtp-lean graft, plain inference, q4_0 KV) | 329.89 ± 0.35 | 33.61 ± 0.60 |
| Q2_0 (development) | not tested | not tested |

> llama-bench measures plain decode. The MTP head in the mtp-lean file is not
> used for speculation in these numbers.

## Configuration

- Model: `Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf` from
  `sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF` (community graft of the
  PTQ1_0 weights with the MTP head; same file as in the
  [Arc B580 SYCL report](sycl-arc-b580-12gb-windows.md)):
  6,297,658,848 bytes, sha256
  `1e33c571a5ce7a9a3e42474d66192923d5a6d77da7fb3a22986dc809522b5685`.
- llama.cpp: custom Vulkan build based on
  [Torchit1/llama.cpp](https://github.com/Torchit1/llama.cpp) v0.10.1
  (commit `7adb2dd207bd`, itself based on the PrismML fork), plus unpublished
  RDNA3 Vulkan flash-attention and prefill patches, including ports of
  ggml-org/llama.cpp#27952 (int8 coopmat1 matmul shaders), ggml-org/llama.cpp#30283
  and ggml-org/llama.cpp#27812.
  The source of this build is not public. llama-bench prints `build: unknown (0)`
  because it was built from a tree snapshot.
- OS: Windows 11 Pro (build 26300).
- GPU driver: AMD 32.0.32015.7029 (Vulkan, AMD proprietary driver,
  `KHR_coopmat`, warp size 64).
- Hardware: AMD Radeon RX 7600 XT 16 GB, Intel Core i5-12600KF, 32 GB RAM,
  stock power and clocks.
- Flags: `-ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 -ub 512 -b 2048`, default threads.
  The q4_0 KV cache and batch sizes match the settings this card uses for
  serving; they differ from the defaults used by most rows in the table.
- Build-specific environment switches for the custom Vulkan flash-attention
  kernels (no effect on public builds): `GGML_VK_FA_DEC_V2=1`,
  `GGML_VK_FA_Q4_0_DEQUANT_KV=1`, `GGML_VK_FA_DEQUANT_CHUNK=32768`,
  `GGML_VK_FA_CM1_SG=32`, `GGML_VK_FA_CM1_NSG=4`, `GGML_VK_FA_P_ROW=1`,
  `GGML_VK_FA_DQ_VEC=1`.
- 3 repetitions for the depth-0 run, 1 repetition for the depth-32768 run
  (time budget). `±` is llama-bench's mean ± sample standard deviation.
- One llama-bench process at a time; no other GPU workload and no signed-in
  desktop session during the measurement.

## llama-bench results

### PTQ1_0 (community mtp-lean graft)

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf -ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 -ub 512 -b 2048 -p 512,2048,8192 -n 128 -r 3 -o md
```

| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.85 GiB |    27.32 B | Vulkan     |  99 |   q4_0 |   q4_0 |   1 |           pp512 |        329.89 ± 0.35 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.85 GiB |    27.32 B | Vulkan     |  99 |   q4_0 |   q4_0 |   1 |          pp2048 |        330.54 ± 0.35 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.85 GiB |    27.32 B | Vulkan     |  99 |   q4_0 |   q4_0 |   1 |          pp8192 |        321.98 ± 0.45 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.85 GiB |    27.32 B | Vulkan     |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         33.61 ± 0.60 |

build: unknown (0)

### PTQ1_0 at depth 32768

```text
llama-bench.exe -m C:\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf -ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 -ub 512 -b 2048 -p 512 -n 128 -d 32768 -r 1 -o md
```

| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.85 GiB |    27.32 B | Vulkan     |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d32768 |        240.19 ± 0.00 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.85 GiB |    27.32 B | Vulkan     |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d32768 |         30.43 ± 0.00 |

build: unknown (0)

### PQ2_0 and Q2_0 (development)

Not tested.

## Additional observations

- Device line reported by the Vulkan backend:
  `AMD Radeon RX 7600 XT (AMD proprietary driver) | uma: 0 | fp16: 1 | bf16: 1 | fp4: 0 | warp size: 64 | shared memory: 32768 | int dot: 1 | matrix cores: KHR_coopmat`.
- Prompt processing is flat from 512 to 8192 tokens (322-331 t/s) and drops to
  240 t/s for a 512-token prompt at depth 32768. Decode drops from 33.6 to
  30.4 t/s at depth 32768.
- These numbers come from a custom build and a non-default KV cache type, so
  they are not a like-for-like comparison with rows that use the release
  binaries and default f16 KV.
