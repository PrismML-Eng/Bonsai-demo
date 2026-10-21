# Bonsai 1: binary and ternary models

This guide covers the earlier **Bonsai (1-bit)** and **Ternary-Bonsai** families,
available in **27B, 8B, 4B, and 1.7B** sizes. The 27B models support text and images;
the smaller models are text-only. **Bonsai 2 27B is the repository default** and has
its own [main README](README.md).

- [Models](#models)
- [Setup and running](#setup-and-running)
- [Binary upstream support](#upstream-status-for-binary)
- [Ternary formats and upstream support](#upstream-status-for-ternary-bonsai-1)
- [MLX runtime](#mlx-runtime)
- [Speculative decoding](#speculative-decoding)
- [Context and memory](#context-and-memory)

## Models

Collections: [Bonsai 27B](https://huggingface.co/collections/prism-ml/bonsai-27b) ·
[Ternary-Bonsai](https://huggingface.co/collections/prism-ml/ternary-bonsai) ·
[Bonsai (1-bit)](https://huggingface.co/collections/prism-ml/bonsai).

Whitepapers: [Bonsai 27B](bonsai-27b-whitepaper.pdf) ·
[1-bit Bonsai 8B](1-bit-bonsai-8b-whitepaper.pdf) ·
[Ternary-Bonsai 8B](ternary-bonsai-8b-whitepaper.pdf).

### Bonsai (1-bit)

Available in GGUF (llama.cpp) and MLX 1-bit formats.

| Model               | Format   | HuggingFace Repo                                                                          |
|---------------------|----------|-------------------------------------------------------------------------------------------|
| Bonsai-27B          | GGUF     | [prism-ml/Bonsai-27B-gguf](https://huggingface.co/prism-ml/Bonsai-27B-gguf)             |
| Bonsai-27B          | MLX      | [prism-ml/Bonsai-27B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit)     |
| Bonsai-8B           | GGUF     | [prism-ml/Bonsai-8B-gguf](https://huggingface.co/prism-ml/Bonsai-8B-gguf)               |
| Bonsai-8B           | MLX      | [prism-ml/Bonsai-8B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-8B-mlx-1bit)       |
| Bonsai-4B           | GGUF     | [prism-ml/Bonsai-4B-gguf](https://huggingface.co/prism-ml/Bonsai-4B-gguf)               |
| Bonsai-4B           | MLX      | [prism-ml/Bonsai-4B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-4B-mlx-1bit)       |
| Bonsai-1.7B         | GGUF     | [prism-ml/Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Bonsai-1.7B-gguf)           |
| Bonsai-1.7B         | MLX      | [prism-ml/Bonsai-1.7B-mlx-1bit](https://huggingface.co/prism-ml/Bonsai-1.7B-mlx-1bit)   |

Set `BONSAI_MODEL` to choose which size to download and run (default: `27B`).

### Ternary-Bonsai

Available in GGUF (llama.cpp) and MLX 2-bit formats.

| Model                  | Format        | HuggingFace Repo                                                                                        |
|------------------------|---------------|---------------------------------------------------------------------------------------------------------|
| Ternary-Bonsai-27B     | GGUF          | [prism-ml/Ternary-Bonsai-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf)             |
| Ternary-Bonsai-27B     | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-27B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-27B-mlx-2bit)     |
| Ternary-Bonsai-8B      | GGUF          | [prism-ml/Ternary-Bonsai-8B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-gguf)               |
| Ternary-Bonsai-8B      | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-8B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit)       |
| Ternary-Bonsai-4B      | GGUF          | [prism-ml/Ternary-Bonsai-4B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf)               |
| Ternary-Bonsai-4B      | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-4B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-mlx-2bit)       |
| Ternary-Bonsai-1.7B    | GGUF          | [prism-ml/Ternary-Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf)           |
| Ternary-Bonsai-1.7B    | MLX (2-bit)   | [prism-ml/Ternary-Bonsai-1.7B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-mlx-2bit)   |

Set `BONSAI_FAMILY=ternary` to use this family.

## Setup and running

Clone the repository as described in the [quick start](README.md#quick-start).
Set the family and size for **both setup and subsequent launch commands**. If you
leave the family unset in a new terminal, the scripts select Bonsai 2 instead.

### macOS / Linux

```bash
export BONSAI_FAMILY=bonsai  # 1-bit; use ternary for Ternary-Bonsai
export BONSAI_MODEL=27B      # or 8B, 4B, 1.7B
./setup.sh
./scripts/start_llama_server.sh
# Or one question:
./scripts/run_llama.sh -p "What is the capital of France?"
```

On Apple Silicon, use `./scripts/run_mlx.sh` or `./scripts/start_mlx_server.sh`
for MLX. For Open WebUI, use `./scripts/start_openwebui.sh`; the same exported
family and size apply.

### Windows (PowerShell)

```powershell
$env:BONSAI_FAMILY = "bonsai" # or "ternary"
$env:BONSAI_MODEL = "27B"    # or "8B", "4B", "1.7B"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
.\scripts\start_llama_server.ps1
```

### Other download combinations

These examples select what setup downloads; set the same family and an individual
size when launching a model.

```bash
BONSAI_FAMILY=ternary BONSAI_MODEL=1.7B ./setup.sh
BONSAI_FAMILY=bonsai BONSAI_MODEL=4B ./setup.sh
BONSAI_FAMILY=ternary BONSAI_MODEL=all ./setup.sh    # All four ternary sizes
BONSAI_FAMILY=all BONSAI_MODEL=all ./setup.sh        # All available families/sizes
BONSAI_FAMILY=bonsai BONSAI_SKIP_GGUF=1 ./setup.sh   # MLX only (macOS)
```

For shared setup options, see [environment_variables.md](environment_variables.md).
See the [build instructions](README.md#building-from-source) and
[FAQ and troubleshooting](FAQ.md).

## Upstream Status for Binary

Q1_0 is supported out of the box in upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) across many backends: CPU (generic, NEON, and optimized x86), Metal, CUDA, and Vulkan.

| Runtime | Status |
|---------|--------|
| llama.cpp (CPU, Metal, CUDA, Vulkan) | ✅ Merged upstream, works out of the box |
| MLX (1-bit) | ⏳ Pending upstream: [mlx#3161](https://github.com/ml-explore/mlx/pull/3161); until it merges, use [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) (branch `prism`, built automatically by `setup.sh`) |

## Upstream Status for Ternary (Bonsai 1)

Ternary support has landed in mainline [llama.cpp](https://github.com/ggml-org/llama.cpp) for CPU,
Metal, Vulkan and CUDA, so the group-64 `Q2_0` files run on a stock build with no fork needed. The
x86 AVX-512-VNNI optimization is still pending, but x86 already works through the generic CPU path.
MLX 2-bit runs on stock [MLX](https://github.com/ml-explore/mlx).

Published files were deliberately not renamed, since too many things link to them. The result is
three ternary formats on the current repos, and each needs the right binaries:

| File | Format | Runs on |
|------|--------|---------|
| `*-PQ2_0.gguf` | Group size 128 (2.13 bpw), our packing under its own ggml type. **What this demo prefers**: smallest file and usually fastest where the backend is optimized (CUDA, Metal, CPU, ROCm) | This demo / fork binaries `prism-b10658+` |
| `*-Q2_0_g64.gguf` (27B file: `*-Q2_g64.gguf`) | Group size 64 (2.25 bpw). The official llama.cpp `Q2_0` format, widest backend coverage (adds Vulkan and SYCL) | Mainline llama.cpp and fork binaries `prism-b10658+` |
| `*-Q2_0.gguf` (legacy, no `g64`) | ⚠️ **Deprecated.** Pre-migration group-128 files stored under the ggml type id that now belongs to the official group-64 format | Only the old `prism-v5` releases; newer binaries refuse them with an error |

Future releases drop the transitional suffix. The demo's setup scripts download `PQ2_0` where the
backend is optimized for it and the group-64 file otherwise (details:
[community-benchmarks/ternary-bonsai/README.md](community-benchmarks/ternary-bonsai/README.md#available-formats)).

**Speculative decoding: use this demo's binaries.** Bonsai 2 27B has no official DSpark drafter released yet; the following applies to the previous-generation `ternary` and `bonsai` 27B models. Since the rebase, dspark rides on mainline llama.cpp's own DSpark implementation ([ggml-org/llama.cpp#25173](https://github.com/ggml-org/llama.cpp/pull/25173)) with fork-side patches on top, and the drafter is the converted `*dspark-dflash*` sidecar (~0.6 GB; the old `*dspark-Q4_1*.gguf` files are the pre-migration packing). Use `BONSAI_SPECULATIVE=1` with this demo's binaries — see [SPECULATIVE.md](SPECULATIVE.md).

To run the smaller ternary models directly on stock `ggml-org/llama.cpp`, use the group-64 files:

| Model | Repo | File (mainline-compatible) |
|-------|------|----------------------------|
| 1.7B | [prism-ml/Ternary-Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf) | `Ternary-Bonsai-1.7B-Q2_0_g64.gguf` |
| 4B | [prism-ml/Ternary-Bonsai-4B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf) | `Ternary-Bonsai-4B-Q2_0_g64.gguf` |
| 8B | [prism-ml/Ternary-Bonsai-8B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-gguf) | `Ternary-Bonsai-8B-Q2_0_g64.gguf` |

```bash
hf download prism-ml/Ternary-Bonsai-1.7B-gguf Ternary-Bonsai-1.7B-Q2_0_g64.gguf --local-dir models
hf download prism-ml/Ternary-Bonsai-4B-gguf  Ternary-Bonsai-4B-Q2_0_g64.gguf  --local-dir models
hf download prism-ml/Ternary-Bonsai-8B-gguf  Ternary-Bonsai-8B-Q2_0_g64.gguf  --local-dir models
```

## MLX runtime

The following runtime notes apply to these earlier families. For Bonsai 2's native
mlx-vlm runtime, see [the main README](README.md#bonsai-2-ternary-default).

For earlier families, `run_mlx.sh` uses `mlx_generate.py` in `.venv` for text-only
one-shot generation. Binary 1-bit and the smaller ternary models also use
`mlx_lm.server` in `.venv` for serving.

**Ternary-Bonsai 27B serving:** `start_mlx_server.sh` and the MLX backend of
`start_openwebui.sh` prefer native `mlx-vlm` in `.venv-vlm`, with image input and
thinking enabled. If that environment is unavailable, or `BONSAI_MLX_VLM=0`,
they fall back to text-only `mlx_lm` in `.venv`. This fallback applies to the
earlier ternary family; Bonsai 2 requires its native mlx-vlm loader.

**Earlier `.venv` validation (reproducibility).** The released MLX weights are plain safetensors and need no runtime patches. The 1-bit packs need an MLX build with 1-bit quantization support: the [PrismML-Eng/mlx](https://github.com/PrismML-Eng/mlx) fork, branch `prism`, until [mlx#3161](https://github.com/ml-explore/mlx/pull/3161) merges upstream. The 2-bit ternary packs run on stock MLX. The released 27B packs were validated with:

- Python 3.11
- mlx fork branch `prism` at commit [`88c9c20`](https://github.com/PrismML-Eng/mlx/commit/88c9c205a50f)
- `mlx-lm==0.31.2` (the version `setup.sh` pins)

`setup.sh` builds the fork from the branch tip. To pin the exact validated runtime instead, clone and check out the commit before running setup; setup reuses an existing `./mlx` checkout:

```bash
git clone -b prism https://github.com/PrismML-Eng/mlx.git mlx
git -C mlx checkout 88c9c20
BONSAI_FAMILY=bonsai ./setup.sh
```

## Speculative decoding

`BONSAI_SPECULATIVE=1` pairs the previous-generation `ternary` or `bonsai` 27B with its DSpark drafter. **Bonsai 2 27B has no official drafter yet**; the launcher warns and runs without speculation for that family. Measured on an L40S (CUDA): 1.8-2.4x faster decode for the ternary 27B and 1.4-1.75x for the 1-bit 27B, workload-dependent (code/math best). On Apple Silicon (Metal) it only pays off for ternary code/math (~1.2x) and is a net slowdown otherwise, so leave it off on Macs. Needs this demo's binaries. Trade-offs and verification: [SPECULATIVE.md](SPECULATIVE.md).

## Context and memory

The earlier 27B models support up to 262,144 tokens of context. The launchers choose
a RAM-tiered default; use `BONSAI_CTX` to override it. FP16 KV cache costs 64 KiB
per token, about 6.3 GiB at 100K tokens. The optional
[mean-centered 4-bit KV cache](KV-CACHE.md) reduces this to roughly 18 KiB per token,
about 1.8 GiB at 100K, saving approximately 4.5 GiB.

These are the earlier models' memory estimates, not Bonsai 2 measurements.

*Peak memory for the 27B (weights + activations + FP16 KV cache + ~1.2 GiB overhead; text-only, add ~0.9 GiB for the vision projector):*

| Model | Format | Weights | 4K context | 10K context | 100K context |
|---|---|---|---|---|---|
| Bonsai-27B (1-bit) | llama.cpp `Q1_0` | 3.53 GiB | 4.8 GiB | 5.2 GiB | 10.8 GiB |
| Bonsai-27B (1-bit) | MLX 1-bit | 3.92 GiB | 5.5 GiB | 5.9 GiB | 11.4 GiB |
| Ternary-Bonsai-27B | llama.cpp `Q2_0` | 6.66 GiB | 7.8 GiB | 8.1 GiB | 13.7 GiB |
| Ternary-Bonsai-27B | MLX 2-bit | 7.05 GiB | 8.6 GiB | 8.9 GiB | 14.4 GiB |
| *reference: 27B 16-bit* | GGUF BF16 | 47.73 GiB | 49 GiB | 49.6 GiB | 55.2 GiB |
| *reference: 27B "4-bit"* | llama.cpp `UD Q4_K_M` | 15.73 GiB | 17.2 GiB | 17.6 GiB | 23.2 GiB |
| *reference: 27B "4-bit"* | MLX 4-bit | 13.3 GiB | 17.0 GiB | 17.3 GiB | 22 GiB |

(The MLX packs are ~400 MiB larger than GGUF because MLX stores both scales and biases, GGUF only scales.)

Extra arguments pass straight through to llama.cpp, so `./scripts/run_llama.sh -c 8192 -p "Your prompt"` also works for a one-off context override.

The older text-only sizes are smaller across the board; the 8B supports up to 65,536 tokens of context:

*Estimates for Bonsai-8B (weights + KV cache + activations):*

| Context Size        | Est. Memory Usage |
|---------------------|-------------------|
| 8,192 tokens        | ~2.5 GB           |
| 32,768 tokens       | ~5.9 GB           |
| 65,536 tokens       | ~10.5 GB          |

## Benchmarks and shared guides

- [Bonsai 1-bit community benchmarks](community-benchmarks/bonsai/README.md)
- [Ternary-Bonsai community benchmarks](community-benchmarks/ternary-bonsai/README.md)
- [Backend support](BACKEND-SUPPORT.md), [vision](VISION.md), [tools](TOOLS.md),
  [Open WebUI](OPENWEBUI.md), and [prompt caching](PROMPT-CACHE.md)
