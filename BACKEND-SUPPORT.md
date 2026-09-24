# Backend and model format support

This page tracks GGUF format support and Bonsai 2 Hadamard support in the PrismML
llama.cpp fork.
Update it as releases and validation results change. For previous-generation formats,
see [MODEL-FORMATS.md](MODEL-FORMATS.md); for measured performance, see
[community benchmarks](community-benchmarks/bonsai2/README.md).

## Release baseline

Source audit: **`prism-b10709-9a9394a`**, the release pinned by the demo when this
page was added. Pending PRs and newer branch code do not count as released support.

✅ Implemented · ❌ No native kernels · ⚠️ Partial / needs validation.
Source-level status, not a guarantee for every device or configuration.

## Quantized formats

| Backend | Q1_0 | PQ2_0 | PTQ1_0 | Q2_0 |
|---|:---:|:---:|:---:|:---:|
| CPU | ✅ | ✅ | ✅ | ✅ |
| Metal | ✅ | ✅ | ✅ | ✅ |
| CUDA | ✅ | ✅ | ✅ | ✅ |
| ROCm / HIP | ✅ | ✅ | ✅ | ✅ |
| Vulkan | ✅ | ❌ | ✅* | ✅ |
| SYCL | ✅ | ❌ | ❌ | ⚠️ |

**Q1_0** is the earlier 1-bit Bonsai format, not a Bonsai 2 packing. It is broadly
supported in mainline llama.cpp as well as our fork; optimizations and device-specific
behavior can differ. Q2_0 is also an upstream format, but the Bonsai 2 Q2_0 model
still requires the transforms below.

- **Vulkan PTQ1_0:** scalar/coopmat1 paths exist; no coopmat2 decoder.
- **SYCL Q2_0:** conversion and matrix-vector dot-product kernels exist; the warning
  reflects missing end-to-end validation, not missing format kernels.
- **ROCm / HIP:** shares CUDA sources; validate on the target AMD GPU and build.
- CPU optimizations vary by architecture; some GPU operations may fall back to CPU.
  No new hardware tests were run for this table.

## Hadamard transforms (Bonsai 2)

| Backend in our fork | Hadamard / FWHT path |
|---|:---:|
| CPU | ✅ |
| Metal | ✅ |
| CUDA | ✅ |
| ROCm / HIP | ✅ |
| Vulkan | ✅* |
| SYCL | ⚠️ |

- **SYCL:** dedicated FWHT kernels for widths 64, 128, 256, and 512 on contiguous
  F32 tensors. Wider rotations fall back to dense matrix multiplication, preserving
  the transform but potentially running much slower.
- **Vulkan:** FWHT kernels are disabled on Intel proprietary Windows drivers
  from **32.0.101.8509 up to, but not including, 32.0.101.8860** because of crashes.
  Those drivers use the ordinary matrix-multiply fallback instead.

These checks indicate implemented transform paths, subject to supported tensor
shapes, data types, and device capabilities. They do not imply every quantized
format is supported on that backend; consult both tables.

Bonsai 2 also needs its sign flips and model graph transformations. Format decoding
or a standalone Hadamard kernel alone is insufficient. The upstream integration is
still pending; use our fork for all Bonsai 2 GGUF formats for now.

Do not use this table as a directory-name guard. A local build can enable multiple
backends, and a binary under `bin/vulkan` can be launched with CPU offload settings.
Check the selected model, build, devices, and effective launch arguments. The demo's
current model-selection registry is a selection policy, not a complete capability probe.
In particular, setup downloading PQ2_0 does not imply native Vulkan PQ2_0 support.

## Model files and upstream compatibility

- **PQ2_0 and PTQ1_0:** published in the
  [main Bonsai 2 GGUF repository](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf).
  PQ2_0 is the demo's current download default. Both require our fork.
- **Q2_0:** available separately as
  [Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf-dev/blob/main/Ternary-Bonsai-2-27B-Q2_0-prism-fork-required.gguf)
  in the development repository for testing and benchmarks with our fork.

**Q2_0 is already an official llama.cpp format; upstream Bonsai 2 support is the
missing piece.** Stock llama.cpp can recognize the file and load it while omitting
the required Bonsai 2 Hadamard/sign-flip transforms, producing gibberish instead of
an unknown-format error. PQ2_0 and PTQ1_0 instead encounter unknown-type errors in
upstream builds without those custom types. Do not treat successful loading as
compatibility.

The separate development repository is temporary. Once the required upstream PRs
are merged and Bonsai 2 Q2_0 works correctly in upstream llama.cpp, the plan is to
move this model into the main Bonsai 2 GGUF repository. Applications embedding
llama.cpp will also need to adopt a version containing those changes. Until then,
use our fork and keep the fork requirement visible when linking or copying the file.

## Evidence and maintenance

Release-pinned implementation references:

- [CPU type traits and FWHT](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-cpu/ggml-cpu.c)
- [Metal FWHT and signed fusion](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-metal/ggml-metal-ops.cpp)
- [Metal operation support](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-metal/ggml-metal-device.m)
- [CUDA operation support and FWHT](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-cuda/ggml-cuda.cu)
- [HIP shared-source build](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-hip/CMakeLists.txt)
- [Vulkan format pipelines and FWHT](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-vulkan/ggml-vulkan.cpp)
- [SYCL Q2_0 matrix-vector dispatch](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-sycl/mmvq.cpp) and [dot-product kernels](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-sycl/vecdotq.hpp)
- [SYCL FWHT width and tensor restrictions](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-sycl/fwht.cpp)
- [SYCL conversion dispatch](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-sycl/convert.cpp) and [FWHT dispatch](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10709-9a9394a/ggml/src/ggml-sycl/ggml-sycl.cpp)

When updating a row, record the release/commit and link the implementation or
validation report. Hardware validation should identify the model filename, GPU/CPU,
OS, driver, backend build, exact command, and a correctness check as well as timings.
Keep partial support and known limitations explicit. Update the baseline and source
links when the demo's release pin changes; review launcher policy separately.
