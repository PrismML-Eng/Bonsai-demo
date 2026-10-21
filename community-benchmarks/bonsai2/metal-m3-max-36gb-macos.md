# Apple M3 Max (36 GB) — Metal — Bonsai 2 27B PQ2_0 / PTQ1_0

## Summary

Apple M3 Max (14-core CPU — 10 performance + 4 efficiency, 30-core GPU, 36 GB unified
memory), macOS 27.0 (build 26A428), llama.cpp Metal via the Prism fork pre-built
binaries (`./scripts/download_binaries.sh`, build `9a9394a89` / 10709).

Both Bonsai 2 27B bands benchmarked on the same machine. Headline numbers:
**PQ2_0 162.2 t/s pp512 / 24.3 t/s tg128** and **PTQ1_0 136.8 t/s pp512 / 21.9 t/s tg128**.
On this hardware PQ2_0 wins on both axes, so it is the band to use: the 1.17 GiB
smaller PTQ1_0 file costs ~16% of prompt processing and ~10% of decode.

For context within the existing Apple rows: this lands above the M4 Pro 64 GB Metal
result (116 / 19.0) and near the M5 Pro 64 GB Metal result (130 / 26.5). The 30-core
GPU appears to matter more here than the memory tier.

The machine has 36 GB of unified memory. This is the smallest configuration where the
27B runs comfortably with vision loaded; see Notes for the memory behaviour.

## llama-bench Results

```bash
BENCH=bin/mac/llama-bench

$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1
$BENCH -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1
```

### Bonsai-2-27B — PQ2_0 (2.13 bpw, the default band)

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | MTL,BLAS   |      10 |   1 |           pp512 |        162.17 ± 1.04 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | MTL,BLAS   |      10 |   1 |           tg128 |         24.34 ± 0.14 |

build: 9a9394a89 (10709)

### Bonsai-2-27B — PTQ1_0 (1.75 bpw, smaller band)

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | MTL,BLAS   |      10 |   1 |           pp512 |        136.78 ± 0.14 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | MTL,BLAS   |      10 |   1 |           tg128 |         21.89 ± 0.09 |

build: 9a9394a89 (10709)

### Server-mode numbers (llama-server, same machine)

`./scripts/start_llama_server.sh` with PQ2_0 + the Q8_0 vision projector and the tiered
65536 context produced ~22.8 t/s decode through the chat template (single request, no
concurrency). That is the usual gap between `llama-bench` and a served chat loop, so
compare like with like.

## Configuration

Default `llama-bench` run: `-ngl 99 -fa 1`, 10 threads (auto-selected as the performance
cores). No power or clock tuning; plugged in, no thermal throttling observed across the
runs.

## Notes

- **Memory:** with PQ2_0 (6.70 GiB) + mmproj Q8_0 (0.59 GiB) + a 65536-token FP16 KV
  cache, the server holds roughly 13.4 GB resident. That fits 36 GB, but it leaves the
  machine tight: with a browser and an editor open, macOS starts compressing and the
  decode rate drops. Lowering the context with `BONSAI_CTX=32768` or `16384` restores
  headroom (see issue #193 on RAM-tiered defaults).
- **Context tier:** the tiered default resolves to 65536 on a 36 GB machine, which was
  comfortable here but is the setting to lower first on smaller machines.
- **Speculation:** not benchmarked; `AGENTS.md` recommends against DSpark on Metal for
  chat/reasoning, so this submission stays with the default path.

## Hardware

```bash
sysctl machdep.cpu.brand_string hw.memsize hw.ncpu && system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|Number of Cores|Metal"
```

```
machdep.cpu.brand_string: Apple M3 Max
hw.memsize: 38654705664
hw.ncpu: 14
      Chipset Model: Apple M3 Max
      Total Number of Cores: 30
      Metal Support: Metal 4

macOS 27.0 (build 26A428)
```
