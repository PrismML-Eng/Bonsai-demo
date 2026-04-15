# Apple M4 Pro — Metal

## Summary

Apple M4 Pro (14-core CPU, 20-core GPU) with 48 GB unified LPDDR5 memory, running macOS 26.4.1. Backend: Metal (GPU Family Apple9, Metal 4). All layers offloaded to GPU (`-ngl 99`), flash attention enabled (`-fa 1`).

| Model | pp512 (t/s) | tg128 (t/s) |
|-------|-------------|-------------|
| Bonsai-8B | 487 | 117 |
| Bonsai-4B | 888 | 178 |
| Bonsai-1.7B | 2,236 | 308 |

## llama-bench Results

### Bonsai-8B

```bash
BENCH=bin/mac/llama-bench
$BENCH -m models/gguf/8B/Bonsai-8B.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | -: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | MTL,BLAS   |      10 |  1 |           pp512 |        487.43 ± 1.02 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | MTL,BLAS   |      10 |  1 |           tg128 |        116.76 ± 0.67 |

build: e2d67422c (8796)

### Bonsai-4B

```bash
$BENCH -m models/gguf/4B/Bonsai-4B.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | -: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | MTL,BLAS   |      10 |  1 |           pp512 |        888.05 ± 2.82 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | MTL,BLAS   |      10 |  1 |           tg128 |        177.51 ± 1.36 |

build: e2d67422c (8796)

### Bonsai-1.7B

```bash
$BENCH -m models/gguf/1.7B/Bonsai-1.7B.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | -: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | MTL,BLAS   |      10 |  1 |           pp512 |       2235.94 ± 9.37 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | MTL,BLAS   |      10 |  1 |           tg128 |        308.30 ± 8.75 |

build: e2d67422c (8796)

## Configuration

Metal backend with all layers offloaded to GPU. Pre-built macOS arm64 binary from GitHub Releases (not compiled from source).

## Notes

- llama.cpp build: `e2d67422c (8796)` (PrismML fork, release `prism-b8796-e2d6742`)
- All three model sizes fit comfortably in 48 GB unified memory
- Metal GPU family: Apple9 / Metal 4

## Hardware

```bash
sysctl machdep.cpu.brand_string hw.memsize hw.ncpu && system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|Number of Cores|Metal"
```

```
machdep.cpu.brand_string: Apple M4 Pro
hw.memsize: 51539607552
hw.ncpu: 14
      Chipset Model: Apple M4 Pro
      Total Number of Cores: 20
      Metal Support: Metal 4
```
