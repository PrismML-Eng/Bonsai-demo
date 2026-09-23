# AMD BC-250 16 GB — Vulkan (CachyOS Linux)

## Summary

AMD BC-250 (gfx1013, RDNA1 without integer dot) with 16 GB unified memory on CachyOS Linux, Mesa RADV 26.2.2. Source build of this demo's prism fork (`ab9dffd6a`, build 10718: PQ2_0 Vulkan + draft-mtp path, BC-250 PQ2 rows4/sg32 gate, qwen35 MTP Hadamard inverse). Bonsai 2 27B `PQ2_0`, `-ngl 99`:

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 (`-fa 1`) | 142.58 ± 0.03 | 24.11 ± 0.02 |
| PQ2_0 (default `-fa`) | 142.57 ± 0.03 | 24.12 ± 0.02 |
| PTQ1_0 | not tested | not tested |
| Q2_0 (development) | not tested | not tested |

Explicit flash attention on and the default (`auto`) produced identical results here.

PTQ1_0 was not tested because gfx1013 has no integer dot product, so PTQ1_0 falls back to generic LUT decode on this GPU (llama.cpp #231); PQ2_0 is the usable path.

## Configuration

- Model: `Ternary-Bonsai-2-27B-PQ2_0.gguf` (6.70 GiB), sha256 `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1`.
- llama.cpp: source build of the prism fork, `ab9dffd6a (10718)`, `GGML_NATIVE=ON`, `GGML_VULKAN=ON`, GNU 16.2.1.
- OS/driver: CachyOS (kernel 7.2.2), Mesa RADV 26.2.2, `AMD BC-250 (RADV GFX1013)`.
- Hardware: AMD BC-250 16 GB unified memory, 6C/12T CPU. Custom fan curve (passive OEM chassis, sustained load peaks ~86C).
- Offload/FA/KV/other: full offload (`-ngl 99`); flash attention on vs default compared above; bench run with llama-bench defaults (no ctx/batch/thread overrides).

## llama-bench results

Run from the repository root (source build used here instead of a prebuilt archive).

### PQ2_0 (`-fa 1`)

```
./build/bin/llama-bench -m ~/bonsai2/models/Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

| model | size | params | backend | ngl | fa | test | t/s |
|---|---|---|---|---|---|---|---|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | 1 | pp512 | 142.58 ± 0.03 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | 1 | tg128 | 24.11 ± 0.02 |

build: ab9dffd6a (10718)

### PQ2_0 (default `-fa`)

```
./build/bin/llama-bench -m ~/bonsai2/models/Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99
```

| model | size | params | backend | ngl | fa | test | t/s |
|---|---|---|---|---|---|---|---|
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | default | pp512 | 142.57 ± 0.03 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) | 6.70 GiB | 26.90 B | Vulkan | 99 | default | tg128 | 24.12 ± 0.02 |

build: ab9dffd6a (10718)

## Serving note (non-standard, extra)

Same GPU serves a community MTP checkpoint (`Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf`, HF creator ProCreations, 7.13 GiB) via llama-server: ctx 100K unified pool shared by 2 slots, KV K q8_0 / V q4_1, `--spec-type draft-mtp` (p-min 0.5, n-max 5), draft accept ~61%. Mixed Korean/security/code workload: TG mean ~33.6 t/s; min free RAM 0.5–1.4 GiB depending on context size (16 GB UMA, 1 GiB hard floor guard); stable over multi-hour runs. Details in issue #221.
