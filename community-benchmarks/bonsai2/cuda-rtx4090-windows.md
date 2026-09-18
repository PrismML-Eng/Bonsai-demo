# NVIDIA RTX 4090 — CUDA

## Summary

NVIDIA GeForce RTX 4090 24 GB (Ada, compute 8.9) on Windows 11, driver 32.0.15.9579 (more specs
below). Bonsai 2 27B, llama.cpp CUDA from this demo's fork (build `7dffb158d`), flash-attn on,
`-ngl 99`:

- **`PQ2_0`: ~3,285 t/s pp512, ~84.9 t/s tg128** — 6.70 GiB of weights, both bands fit comfortably
  in 24 GB.
- **`PTQ1_0`: ~1,597 t/s pp512, ~86.0 t/s tg128** — 5.53 GiB. Decodes at the same speed as `PQ2_0`
  on this card but prefills at about half the rate, which is the trade the two packings describe:
  fewer bytes per weight to move, more arithmetic to unpack them.

## llama-bench Results

### Bonsai-2-27B (PQ2_0)

```bash
BENCH=bin/cuda/llama-bench
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 24563 MiB):

  Device 0: NVIDIA GeForce RTX 4090, compute capability 8.9, VMM: yes, VRAM: 24563 MiB

| model | size | params | backend | ngl | fa | test | t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |     3284.74 ± 129.16 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         84.85 ± 1.80 |

build: 7dffb158d (10685)

### Bonsai-2-27B (PTQ1_0)

```bash
BENCH=bin/cuda/llama-bench
# setup.sh only downloads PQ2_0; get PTQ1_0 from the model repo and point at it:
$BENCH -m /path/to/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1
```

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 24563 MiB):

  Device 0: NVIDIA GeForce RTX 4090, compute capability 8.9, VMM: yes, VRAM: 24563 MiB

| model | size | params | backend | ngl | fa | test | t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           pp512 |      1597.25 ± 54.98 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   1 |           tg128 |         85.98 ± 2.58 |

build: 7dffb158d (10685)

## Configuration

- Fully offloaded (`-ngl 99`) with flash-attn (`-fa 1`), nothing on CPU.
- Benchmarked with `llama-bench` defaults for the repository's usual pp512/tg128 pair.
- The 4090 runs at its default 450 W power limit; no overclock or memory tuning.

## Notes

- The GGUF paths above are this demo's layout. I measured from a copy under LM Studio's models
  directory (`~/.lmstudio/models/prism-ml/Ternary-Bonsai-2-27B-gguf/`), which is where the model
  ends up if you download it by hand for LM Studio; same files, same hashes.
- For reference, the whitepaper lists this card model at 3,124 t/s pp512 and 81.2 t/s tg128 for
  `PQ2_0`, and 1,645 / 91.1 for `PTQ1_0`. Here `PQ2_0` came out slightly higher (3,285 / 84.9) and
  `PTQ1_0` slightly lower on decode (1,597 / 86.0). That is the spread driver and clock differences
  produce; the paper's ordering between the two bands still holds: `PTQ1_0` decodes no slower while
  `PQ2_0` prefills about twice as fast.
- Vision and thinking were checked separately on this machine, not through `llama-bench`: the model
  reads a test image correctly and returns `reasoning_content` as expected under `llama-server`.

## Hardware

```powershell
PS> Get-CimInstance Win32_Processor | Format-List Name,NumberOfCores,NumberOfLogicalProcessors

Name                      : 12th Gen Intel(R) Core(TM) i7-12700K
NumberOfCores             : 12
NumberOfLogicalProcessors : 20

PS> Get-CimInstance Win32_VideoController | Format-List Name,DriverVersion

Name          : NVIDIA GeForce RTX 4090
DriverVersion : 32.0.15.9579

PS> [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
32
```
