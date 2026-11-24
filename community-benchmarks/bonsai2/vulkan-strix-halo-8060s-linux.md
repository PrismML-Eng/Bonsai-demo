# AMD Strix Halo (Ryzen AI Max+ 395, Radeon 8060S) 128 GB — Vulkan (Linux)

## Summary

Bonsai 2 27B on a Bosgame M5 (AMD Ryzen AI Max+ 395, Radeon 8060S iGPU `gfx1151`, 128 GB unified memory) under Ubuntu 26.04 in a Proxmox LXC container (host kernel 7.0.14-26-pve), Mesa RADV 26.0.8, using the unmodified prebuilt release `prism-b12128-d7b2896` (`ubuntu-vulkan-x64` asset), `-ngl 99 -fa 1`:

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | 336.22 ± 0.33 | 24.28 ± 0.04 |
| PTQ1_0 | not tested under comparable conditions | not tested under comparable conditions |
| Q2_0 (development) | not tested | not tested |

`PQ2_0` loaded and ran fully offloaded on the Vulkan backend with this prebuilt release. Neither the AVX-512 load crash nor the silent Vulkan CPU fallback listed for `PQ2_0` in the model's `KNOWN_ISSUES.md` occurred on b12128 on this machine.

## Configuration

- Model: `prism-ml/Ternary-Bonsai-2-27B-gguf`, `Ternary-Bonsai-2-27B-PQ2_0.gguf` (7,206,168,928 bytes; 6.70 GiB reported), sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`.
- llama.cpp: PrismML fork release `prism-b12128-d7b2896`, asset `llama-prism-b12128-d7b2896-bin-ubuntu-vulkan-x64.tar.gz` (sha256 `a73a76f26b161e2fff3815cc3ae6f1daeee5991e1269982561aa620e8e07cca4`), build `d7b289683 (12128)`. No source build, no code changes.
- OS/driver: Ubuntu 26.04 LTS userspace in an LXC container on Proxmox VE, host kernel 7.0.14-26-pve; Mesa 26.0.8-1ubuntu0.3, `Radeon 8060S Graphics (RADV STRIX_HALO)`, Vulkan API 1.4.335.
- Hardware: Bosgame M5, AMD Ryzen AI Max+ 395 (16C/32T), Radeon 8060S integrated GPU, 128 GB unified LPDDR5 (about 124 GiB visible to the OS; BIOS UMA frame buffer at 1 GB, so model memory comes from GTT/shared memory).
- Offload/FA/KV/other: full offload (`-ngl 99`), flash attention on (`-fa 1`), llama-bench defaults otherwise (f16 KV, batch 2048 / ubatch 512, 16 threads as chosen by llama-bench), 2 repetitions.
- Power: firmware `performance` platform profile; no other tuning.

Backend detection line from the run:

```
ggml_vulkan: 0 = Radeon 8060S Graphics (RADV STRIX_HALO) (radv) | uma: 1 | fp16: 1 | bf16: 0 | fp4: 0 | warp size: 64 | shared memory: 65536 | int dot: 1 | matrix cores: KHR_coopmat
```

The CPU backend selected by the loader was `libggml-cpu-zen4.so`.

## llama-bench results

The prebuilt release was unpacked directly rather than installed through `./setup.sh`, so the paths differ from the demo layout.

### PQ2_0

```bash
R=/srv/ai/models/bonsai2/runtime/b12128/llama-prism-b12128-d7b2896
LD_LIBRARY_PATH=$R $R/llama-bench -m /srv/ai/models/bonsai2/weights/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1 -p 512 -n 128 -r 2 -o json
```

The run used `-o json`, so there is no markdown table to paste. The same values in the usual layout:

| model | size | params | backend | ngl | fa | test | t/s |
|---|---|---|---|---|---|---|---|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | 1 | pp512 | 336.22 ± 0.33 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | 1 | tg128 | 24.28 ± 0.04 |

build: d7b289683 (12128)

Raw JSON fields (test time 2026-11-09T09:40Z):

- pp512: `avg_ts` 336.221142, `stddev_ts` 0.328656, `samples_ts` [336.454, 335.989]
- tg128: `avg_ts` 24.283116, `stddev_ts` 0.040848, `samples_ts` [24.2542, 24.312]

Conditions: only 2 repetitions. A second model server (a different model, about 23 GB of weights) was loaded on the same iGPU but idle with no requests in flight during the run; nothing else was using the GPU. The low variation suggests it did not interfere, but this was not a freshly booted, otherwise empty machine.

### PTQ1_0

Not tested under comparable conditions. An earlier run of `PTQ1_0` on the same machine and the same release (2026-10-31) gave pp512 228.5 ± 0.3 and tg128 19.0 ± 7.8, but another model was actively generating on the same iGPU at the time (hence the tg128 variation), and the exact command line was not preserved. It is listed here for context only and is not in the summary tables.

### Q2_0

Not tested.

## Additional observations

Separate from the llama-bench numbers above. Same release and `PQ2_0` file through `llama-server`:

```bash
llama-server -m Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa on -c 786432 -np 3 -ctk q8_0 -ctv q8_0 --jinja \
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05 --presence-penalty 0.0 --repeat-penalty 1.0
```

One streaming chat request at a time, fresh random prompt (no prompt-cache hit), 400 generated tokens, thinking at the template default, server-reported timings:

| Prompt tokens | Prompt processing (t/s) | Generation (t/s) | Notes |
|---:|---:|---:|---|
| 2,861 | 301.1 | 23.9 | no other request on the server |
| 43,978 | 206.7 | 6.4 | another client's request was running on a second slot of the same server, so generation was contended |

These are single observations, not repeated runs, and say nothing about output quality.
