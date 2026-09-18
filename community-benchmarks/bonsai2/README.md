# Bonsai 2 Community Benchmarks

Benchmark results submitted by the community running
[Bonsai 2 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) on their own hardware.

Bonsai 2 is the `bonsai2` family in `setup.sh` (the default, 27B only). It ships in two GGUF
packings, and **both need this demo's binaries** - see `AGENTS.md` for why stock llama.cpp is not an
option:

| Band | Bits/weight | Size | Notes |
|------|------------:|-----:|-------|
| `PTQ1_0` | 1.75 | 5.9 GB | Densely packed trits. Smallest. |
| `PQ2_0` | 2.13 | 7.2 GB | Two-bit slots. Faster prompt processing. What `setup.sh` downloads and what `AGENTS.md` recommends. |

`setup.sh` fetches `PQ2_0` only. To benchmark `PTQ1_0` too, download it from the model repo and pass
it to `llama-bench -m` directly (or point `BONSAI_MODEL` at it).

## Results

### Bonsai-2-27B

| Band | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | Details |
|------|----------|---------|------------:|------------:|---------|
| `PTQ1_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 1,597 | 86.0 | [link](cuda-rtx4090-windows.md) |
| `PQ2_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 3,285 | 84.9 | [link](cuda-rtx4090-windows.md) |

## How to Submit

1. Run `./setup.sh` - the default family is Bonsai 2, which downloads the `PQ2_0` band.
2. Copy [../bonsai/TEMPLATE-llama-cpp.md](../bonsai/TEMPLATE-llama-cpp.md) to a new file here, named
   `<backend>-<hardware>-<os>.md` (lowercase, dashes), then run at least:

   ```bash
   BENCH=bin/cuda/llama-bench          # bin/mac, bin/vulkan, bin/rocm, bin/cpu …
   $BENCH -m models/bonsai2-gguf/27B/*-PQ2_0.gguf -ngl 99 -fa 1
   ```

3. Both bands are welcome and preferred where memory allows - the 5.9 GB `PTQ1_0` band fits on cards
   where `PQ2_0` is tight, and it decodes faster on Ada-class parts. Say which one you skipped and
   why, rather than leaving it out silently.
4. Open a PR to this repo.
