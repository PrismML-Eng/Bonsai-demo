# Apple M3 Pro — Metal

## Summary

Apple M3 Pro (11-core CPU / 14-core GPU, 18 GB unified memory), macOS 26.5.2, llama.cpp Metal (pre-built binaries from `./setup.sh`, build 62061f910 (9591)). All four Ternary-Bonsai sizes fit comfortably in 18 GB. Headline numbers: 27B ~12.6 t/s tg128 (78.6 t/s pp512); 8B ~51.3 t/s tg128.

## llama-bench Results

### Ternary-Bonsai-27B

```bash
BENCH=bin/mac/llama-bench
$BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | MTL,BLAS   |       5 |   1 |           pp512 |         78.61 ± 0.09 |
| qwen35 27B Q2_0                |   6.66 GiB |    26.90 B | MTL,BLAS   |       5 |   1 |           tg128 |         12.61 ± 0.58 |

build: 62061f910 (9591)

### Ternary-Bonsai-8B

```bash
$BENCH -m models/ternary-gguf/8B/Ternary-Bonsai-8B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen3 8B Q2_0                  |   2.03 GiB |     8.19 B | MTL,BLAS   |       5 |   1 |           pp512 |        287.82 ± 0.32 |
| qwen3 8B Q2_0                  |   2.03 GiB |     8.19 B | MTL,BLAS   |       5 |   1 |           tg128 |         51.31 ± 0.41 |

build: 62061f910 (9591)

### Ternary-Bonsai-4B

```bash
$BENCH -m models/ternary-gguf/4B/Ternary-Bonsai-4B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen3 4B Q2_0                  | 1019.50 MiB |     4.02 B | MTL,BLAS   |       5 |   1 |           pp512 |        532.38 ± 0.27 |
| qwen3 4B Q2_0                  | 1019.50 MiB |     4.02 B | MTL,BLAS   |       5 |   1 |           tg128 |         83.41 ± 1.80 |

build: 62061f910 (9591)

### Ternary-Bonsai-1.7B

```bash
$BENCH -m models/ternary-gguf/1.7B/Ternary-Bonsai-1.7B-Q2_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen3 1.7B Q2_0                | 436.16 MiB |     1.72 B | MTL,BLAS   |       5 |   1 |           pp512 |       1348.77 ± 0.82 |
| qwen3 1.7B Q2_0                | 436.16 MiB |     1.72 B | MTL,BLAS   |       5 |   1 |           tg128 |        164.56 ± 1.39 |

build: 62061f910 (9591)

## Configuration

- Pre-built llama.cpp binaries downloaded by `./setup.sh` (`bin/mac`), default settings, `-ngl 99 -fa 1`.
- MLX was not tested on this machine (Command Line Tools only, no full Xcode / Metal Toolchain).
- 18 GB unified memory is the binned M3 Pro configuration (11-core CPU / 14-core GPU).

## Notes

- macOS 26.5.2 (Tahoe), Metal 4.
- Machine was otherwise idle during the runs; variance across the 5 llama-bench repetitions was low (see ± columns).

## Hardware

```
machdep.cpu.brand_string: Apple M3 Pro
hw.memsize: 19327352832
hw.ncpu: 11
      Chipset Model: Apple M3 Pro
      Total Number of Cores: 14
      Metal Support: Metal 4
```
