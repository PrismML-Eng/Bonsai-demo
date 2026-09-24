# AMD Radeon RX 9070 XT 16 GB — ROCm/HIP on Proxmox

## Summary

AMD Radeon RX 9070 XT 16 GB (`gfx1201`) + source-built PrismML llama.cpp (`bdc23b56`, build `10728`) on a Linux KVM guest hosted by Proxmox VE. Bonsai 2 27B was fully GPU-offloaded for the `llama-bench` runs.

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|------------:|------------:|
| Bonsai 2 27B `PQ2_0` | 1,259.47 ± 146.72 | 48.53 ± 0.27 |
| Bonsai 2 27B `PQ2_0-MTP-Q8_0` bundle, plain inference | 1,257.75 ± 145.67 | 48.64 ± 0.32 |

The MTP-enabled bundle was also tested with speculative decoding using `--spec-type draft-mtp --spec-draft-n-max 2`. In a matched single-request `llama-cli` comparison, generation measured 75.1 t/s with MTP and 47.0 t/s without speculation (~1.60x). These one-shot CLI timings use a different harness from `llama-bench` and are reported separately below.

## llama-bench Results

### Bonsai 2 27B `PQ2_0`

```bash
BENCH=bin/rocm/llama-bench
LD_LIBRARY_PATH="$PWD/bin/rocm:/opt/rocm/core-10.0/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$BENCH" -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  -p 512 -n 128 -ngl 99 -fa 1 -t 10 -r 3
```

| model | size | params | backend | ngl | fa | test | t/s |
|---|---:|---:|---|---:|---:|---:|---:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | ROCm | 99 | 1 | pp512 | 1259.47 ± 146.72 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | ROCm | 99 | 1 | tg128 | 48.53 ± 0.27 |

build: bdc23b56 (10728)

### Bonsai 2 27B MTP bundle, plain inference

This `llama-bench` run measures ordinary inference with the MTP-enabled GGUF. It does not enable MTP speculative decoding.

```bash
LD_LIBRARY_PATH="$PWD/bin/rocm:/opt/rocm/core-10.0/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  bin/rocm/llama-bench \
  -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf \
  -p 512 -n 128 -ngl 99 -fa 1 -t 10 -r 3
```

| model | size | params | backend | ngl | fa | test | t/s |
|---|---:|---:|---|---:|---:|---:|---:|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 7.12 GiB | 27.32 B | ROCm | 99 | 1 | pp512 | 1257.75 ± 145.67 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 7.12 GiB | 27.32 B | ROCm | 99 | 1 | tg128 | 48.64 ± 0.32 |

build: bdc23b56 (10728)

## MTP Speculative Decoding

The MTP GGUF was run with `draft-mtp` and a maximum draft length of two. The base GGUF was run with the same prompt and options, without speculative decoding. One timed request was run for each configuration; these are not repeated averages.

Prompt:

```text
In one paragraph, explain how a solar panel converts sunlight into electricity.
```

MTP command:

```bash
LD_LIBRARY_PATH="$PWD/bin/rocm:/opt/rocm/core-10.0/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  bin/rocm/llama-cli \
  -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf \
  -p "In one paragraph, explain how a solar panel converts sunlight into electricity." \
  -n 128 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 -b 512 -ub 512 -t 10 \
  --temp 0 --reasoning off \
  --spec-type draft-mtp --spec-draft-n-max 2 \
  --no-display-prompt --show-timings -st
```

Matched base-model command: same prompt and options using `Ternary-Bonsai-2-27B-PQ2_0.gguf`, with the two `--spec-*` options omitted.

```text
MTP enabled:          [ Prompt: 58.8 t/s | Generation: 75.1 t/s ]
Base, no speculation: [ Prompt: 66.6 t/s | Generation: 47.0 t/s ]
```

## Configuration

- Model repository: [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf). The MTP bundle is from [ProCreations/Ternary-Bonsai-2-27B-MTP](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP).
- llama.cpp: source build from [PrismML-Eng/llama.cpp commit `bdc23b56b4458b9f1655aec5287f3ab56ee8daaa`](https://github.com/PrismML-Eng/llama.cpp/commit/bdc23b56b4458b9f1655aec5287f3ab56ee8daaa), build `10728`. Build metadata: HIP `gfx1201`, `GGML_NATIVE=ON` on Intel Core Ultra 7 265KF. No prebuilt binary or different llama.cpp version was used.
- GPU: AMD Radeon RX 9070 XT, `gfx1201`; 16,304 MiB VRAM reported by ROCm.
- `llama-bench`: all layers GPU-offloaded (`-ngl 99`), flash attention enabled (`-fa 1`), 10 threads, three repetitions, 512 prompt tokens and 128 generated tokens.
- ROCm: 10.0.0 userspace; ROCk driver `7.1.3.31500000`.
- Test date: 2026-09-24.

## Notes

- The Proxmox host reports 20 CPUs on one Intel Core Ultra 7 265KF socket. The benchmark ran inside a KVM guest exposing 10 vCPUs, not directly on all 20 host CPUs.
- The host reports Proxmox VE `pve-manager/9.2.20/49318c671b82f31e`, kernel `7.0.14-17-pve` (`2026-09-10T10:16Z`), EFI boot. A non-production-ready Proxmox repository was enabled.
- The guest was Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`, with 30 GiB RAM visible.
- The MTP speculative-decoding result is from `llama-cli`, not `llama-bench`; do not compare its one-shot generation timing directly to the PP512/TG128 table.

## Hardware

AMD Radeon RX 9070 XT 16 GB (`gfx1201`), Proxmox host with Intel Core Ultra 7 265KF (20 CPUs, one socket); benchmark executed in a KVM guest with 10 vCPUs and 30 GiB RAM.

```text
Guest OS: Ubuntu 26.04.1 LTS
Guest kernel: Linux 7.0.0-31-generic
Virtualization: KVM
CPU model: Intel(R) Core(TM) Ultra 7 265KF
Guest CPU(s): 10
Guest RAM: 30 GiB

GPU: AMD Radeon RX 9070 XT
GFX version: gfx1201
ROCm VRAM total: 17,095,983,104 bytes
ROCm driver: 7.1.3.31500000
ROCm userspace: 10.0.0
```
