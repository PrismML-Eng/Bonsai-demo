# [Hardware] - [Backend / OS]

<!-- Copy to <backend>-<hardware>-<os>.md. This structure is a guide, not a requirement.
     Keep measured results unchanged. Remove untested sections and note what you skipped. -->

## Summary

Bonsai 2 27B on [hardware, VRAM/system RAM, OS], using [release tag / commit].

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 | | |
| PTQ1_0 | | |
| Q2_0 (development) | | |

## Configuration

- Model repository, exact filename(s), and revision or hash if known:
- llama.cpp release/commit and downloaded asset, or source-build options:
- OS, GPU driver, CUDA/ROCm or other backend version:
- GPU/CPU, VRAM, system RAM:
- Offload, flash attention, KV cache types, threads, batch sizes, and any other overrides:
- Power limit or tuning, if changed:

## llama-bench results

Run setup first: `./setup.sh` on macOS/Linux, or `.\setup.ps1` on Windows.
Use this demo's llama.cpp fork. Run from the repository root.

### PQ2_0

macOS/Linux (select the installed backend directory; use `-ngl 0` for CPU):

```bash
BENCH=bin/cuda/llama-bench  # e.g. bin/mac/llama-bench or bin/cpu/llama-bench
"$BENCH" -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

Windows PowerShell:

```powershell
.\bin\cuda\llama-bench.exe -m models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf -p 512 -n 128 -ngl 99 -fa 1
```

Replace the examples with the exact command you ran. Paste the raw result table,
including variation and build line. Report unsupported settings or failures.

### PTQ1_0 (optional)

Setup downloads PQ2_0. For PTQ1_0, obtain the file from the
[model repository](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf)
and pass its path to `-m`. `BONSAI_MODEL` is a size selector, not a file path.
Use the same settings when comparing packings, and list any differences.

(Paste the exact command and raw results, or state that this packing was not tested.)

### Q2_0 (optional, development)

Use [Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf-dev/blob/main/Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf)
and pass its path to `-m` with the same benchmark settings.
This is the official llama.cpp `Q2_0` format, but Bonsai 2 currently requires our
fork's Hadamard transform support. Upstream support is pending our PRs; stock
llama.cpp may load the file but produce incorrect output without those changes.
Record the exact fork build and model revision or hash.

(Paste the exact command and raw results, or state that this format was not tested.)

## Additional observations (optional)

Keep server, speculative decoding, long-context, vision, and quality checks separate
from llama-bench timings. Include their commands, workloads, and settings. Do not
infer correctness or long-context speed from pp512/tg128 throughput alone.
