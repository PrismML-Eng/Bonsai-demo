# Ternary model formats and the prism-v7 migration

Bonsai 2 has its own, stricter story: see the first section. The rest of this page covers the
previous ternary generation, whose GGUFs exist in three formats. It says which file to
use, what changed in the prism-v7 migration, and why the current HuggingFace repos are
named the way they are.

## TL;DR

For Bonsai 2, start with the [backend and format support table](BACKEND-SUPPORT.md).
The bullets below apply to the previous ternary generation.

- On prism-v7 (and newer) builds, the demo picks the right file automatically:
  **PQ2_0** where the backend has optimized kernels, otherwise the official
  **group-64 Q2_0**.
- The old `*-Q2_0.gguf` files on the current repos are **deprecated**. They do not load
  on prism-v7 builds (you get an error pointing you here). Use the `_g64` file or the
  `PQ2_0` file instead.
- For most people the official group-64 file is all you need. PQ2_0 buys about 6% less
  memory (and, depending on backend, a matching speed edge) at the cost of running only
  on backends with fork kernels.

## The three formats

| format | ggml type id | group size | who reads it |
|---|---|---|---|
| legacy `Q2_0` (deprecated) | 42 | 128 | pre-v7 fork releases only (`prism` = prism-v5 branch) |
| official `Q2_0` | 42 | 64 | mainline llama.cpp AND prism-v7+ |
| `PQ2_0` | 142 | 128 | prism-v7+ fork builds, on supported backends |

The legacy format stored a group-128 layout under the same type id that mainline later
standardized as group-64. prism-v7 follows mainline: type id 42 is read as group-64,
and the fork's group-128 layout lives under its own name and id, PQ2_0 (142).

## Bonsai 2 formats

| Packing | Runtime | Trade-off |
|---|---|---|
| `Q2_0` | Current official llama.cpp with Bonsai 2 support, or our fork | Upstream format |
| `PQ2_0` | PrismML fork | Faster prompt processing than PTQ1_0 on many devices |
| `PTQ1_0` | PrismML fork | Smallest packed files |

All three contain the same model weights. Bonsai 2 needs the Hadamard/sign-flip
integration as well as format decoding: update old runtimes before using Q2_0.
Older builds could load Q2_0 while missing those transforms and produce gibberish.

See the [model links](README.md#bonsai-2-ternary-default) for each size and
[backend support](BACKEND-SUPPORT.md) for the fork's platform matrix. The older
27B development-repository filename may still include a historical fork warning;
compatibility depends on the runtime version, not that filename.

## Exact file names on the current repos

We decided NOT to rename already-published files (too many things link to them).
Current repos therefore carry all three, and the official group-64 file has a
transitional `_g64` suffix. Watch the 27B name, it differs:

| size | deprecated (do not use on v7) | official group-64 | fork PQ2_0 |
|---|---|---|---|
| 1.7B | `Ternary-Bonsai-1.7B-Q2_0.gguf` | `Ternary-Bonsai-1.7B-Q2_0_g64.gguf` | `Ternary-Bonsai-1.7B-PQ2_0.gguf` |
| 4B | `Ternary-Bonsai-4B-Q2_0.gguf` | `Ternary-Bonsai-4B-Q2_0_g64.gguf` | `Ternary-Bonsai-4B-PQ2_0.gguf` |
| 8B | `Ternary-Bonsai-8B-Q2_0.gguf` | `Ternary-Bonsai-8B-Q2_0_g64.gguf` | `Ternary-Bonsai-8B-PQ2_0.gguf` |
| 27B | `Ternary-Bonsai-27B-Q2_0.gguf` | `Ternary-Bonsai-27B-Q2_g64.gguf` | `Ternary-Bonsai-27B-PQ2_0.gguf` |

Future model releases drop the transitional suffix: the official group-64 file will be
named plain `*-Q2_0.gguf` and the fork file `*-PQ2_0.gguf`, with no legacy file at all.
The demo scripts already handle both naming eras.

## Which file should I use?

- **Official group-64 Q2_0**: works everywhere (every fork backend and mainline
  llama.cpp). If unsure, use this.
- **PQ2_0**: about 6% smaller on disk and in memory. Runs on the backends listed
  below; on others it has no kernels yet and would fall back to slow generic code.

Backend support for PQ2_0 (the demo's selection registry, `pq2_0_ready_backend` in
`scripts/common.sh`, mirrors this table):

| backend | PQ2_0 kernels |
|---|---|
| Metal (macOS) | yes |
| CUDA | yes |
| ROCm / HIP | yes |
| CPU (x86 VNNI, ARM NEON) | yes |
| Vulkan | not yet (port planned) |
| SYCL | not yet |

## If you see the legacy-format error

prism-v7 builds refuse the deprecated files with:

```
this file matches the legacy Prism Q2_0 layout (group size 128 stored as ggml type id 42),
but this build reads Q2_0 as the official group-64 format
```

Download the `PQ2_0` or `_g64` file for your model from the same repo (table above),
or if you must run the legacy file, use a release from the frozen `prism` (= prism-v5)
branch.
