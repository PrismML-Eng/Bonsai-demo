# Apple M4 Pro (20-core GPU, 64 GB) - Metal

## Summary

Apple M4 Pro Mac mini with a 20-core GPU and 64 GB unified memory, running
macOS 26.5.2. Ternary-Bonsai-27B reached 115.99 t/s for pp512 and 19.01 t/s
for tg128 with Metal, full GPU offload, and flash attention.

## llama-bench Results

### Ternary-Bonsai-27B

Command:

```bash
bin/mac/llama-bench -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | MTL,BLAS   |      10 |   1 |           pp512 |        115.99 ± 6.34 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | MTL,BLAS   |      10 |   1 |           tg128 |         19.01 ± 0.22 |

build: 9fcaed763 (9596)

## Configuration

- PrismML llama.cpp prebuilt release `prism-b9596-9fcaed7`
- Full Metal offload (`-ngl 99`)
- Flash attention enabled (`-fa 1`)
- Two external 4K displays connected

## Notes

The paired dspark drafter was also verified through `llama-server` with
`BONSAI_SPECULATIVE=1` and a deterministic 400-token code request. The response
reported `draft_n=416`, `draft_n_accepted=293` (70.4% acceptance), and 6.83 t/s.
As documented in `SPECULATIVE.md`, the Metal path is experimental and is not
currently expected to provide a speedup.

## Hardware

```text
ProductName:            macOS
ProductVersion:         26.5.2
BuildVersion:           25F84
machdep.cpu.brand_string: Apple M4 Pro
hw.memsize: 68719476736
hw.ncpu: 14
hw.logicalcpu: 14
Chipset Model: Apple M4 Pro
Total Number of GPU Cores: 20
Metal Support: Metal 4
```
