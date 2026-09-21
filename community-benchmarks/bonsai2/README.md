# Bonsai 2 Community Benchmarks

Benchmark results submitted by the community running
[Bonsai 2 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) on their own hardware.

Bonsai 2 is the `bonsai2` family in `setup.sh` (the default, 27B only). It ships in two GGUF
packings, and **both need this demo's binaries** - see [AGENTS.md](../../AGENTS.md) for why stock llama.cpp is not an
option:

| Band | Bits/weight | Size | Notes |
|------|------------:|-----:|-------|
| `PTQ1_0` | 1.75 | 5.9 GB | Densely packed trits. Smallest. |
| `PQ2_0` | 2.13 | 7.2 GB | Two-bit slots. Faster prompt processing. The setup default. |

`setup.sh` fetches `PQ2_0` only. To benchmark `PTQ1_0` too, download it from the model repo and pass
it to `llama-bench -m` directly (`BONSAI_MODEL` selects a model size, not a file path).

## Results

### Bonsai-2-27B

| Band | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | Details |
|------|----------|---------|------------:|------------:|---------|
| `PTQ1_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 1,597 | 86.0 | [link](cuda-rtx4090-windows.md) |
| `PQ2_0` | NVIDIA RTX 4090 24 GB | llama.cpp CUDA (Windows) | 3,285 | 84.9 | [link](cuda-rtx4090-windows.md) |

## How to Submit

1. Run `./setup.sh` on macOS/Linux or `.\setup.ps1` in Windows PowerShell.
   The default family is Bonsai 2; setup downloads the `PQ2_0` packing.
2. Copy [TEMPLATE-llama-cpp.md](TEMPLATE-llama-cpp.md) to
   `<backend>-<hardware>-<os>.md` here (lowercase, dashes). Keep both packings in
   the same machine report, with separate commands and raw results for each.
3. Include the exact model filename, binary release or commit, hardware, OS,
   driver/backend version, and benchmark command. Both packings are welcome;
   one is enough if that is what you tested. Note any skipped or unsupported runs.
4. Add a row per tested packing to the table above and the
   [Bonsai 2 table in the main index](../README.md#bonsai-2-27b), then open a PR.

Use pp512/tg128 for the summary tables. Preserve raw output (including variation)
in the report. Keep different builds or settings labeled separately. The first
RTX 4090 submission shows comparable decode speed for the two packings and roughly
twice the prefill speed for `PQ2_0`; other hardware and builds may differ.

MLX submissions are also welcome in this folder. Identify the model, runtime versions,
harness, and prompt/generation lengths. Only put matching pp512/tg128 measurements
in those columns. Keep server, long-context, speculative decoding, and vision or
quality checks in separate labeled sections, with their commands and workloads.
