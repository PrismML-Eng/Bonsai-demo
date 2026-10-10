# Backend and model format support

This page tracks GGUF format support and Bonsai 2 Hadamard support in the PrismML
llama.cpp fork.
Update it as releases and validation results change. For previous-generation formats,
see [MODEL-FORMATS.md](MODEL-FORMATS.md); for measured performance, see
[community benchmarks](community-benchmarks/bonsai2/README.md).

## Release baseline

The demo pins **`prism-b10770-6684606`**, also the SYCL source audit baseline.
Vulkan was audited at **`prism-b10743-adfffbe`**; other backend rows retain the
original **`prism-b10709-9a9394a`** audit.
Pending PRs and newer branch code do not count as released support.

✅ Implemented · ❌ No native kernels · ⚠️ Partial / needs validation.
Source-level status, not a guarantee for every device or configuration.

## Quantized formats

| Backend | Q1_0 | PQ2_0 | PTQ1_0 | Q2_0 |
|---|:---:|:---:|:---:|:---:|
| CPU | ✅ | ✅ | ✅ | ✅ |
| Metal | ✅ | ✅ | ✅ | ✅ |
| CUDA | ✅ | ✅ | ✅ | ✅ |
| ROCm / HIP | ✅ | ✅ | ✅ | ✅ |
| Vulkan | ✅ | ✅* | ✅* | ✅ |
| SYCL | ✅ | ✅* | ✅* | ✅ |

**Q1_0** is the earlier 1-bit Bonsai format, not a Bonsai 2 packing. It is broadly
supported in mainline llama.cpp as well as our fork; optimizations and device-specific
behavior can differ. Q2_0 is also an upstream format, but the Bonsai 2 Q2_0 model
still requires the transforms below.

- **Vulkan PQ2_0 / PTQ1_0:** scalar/coopmat1 paths and integer-dot mat-vec
  kernels exist; kernel selection depends on the device and driver. Neither format
  has a direct coopmat2 decoder. PQ2_0 support landed through
  [llama.cpp #238](https://github.com/PrismML-Eng/llama.cpp/pull/238) and shipped in
  `prism-b10735-842b188`; older binaries may need updating.
- **SYCL:** native PQ2_0, PTQ1_0, and Q2_0 conversion and matrix-vector kernels
  exist. PQ2_0/PTQ1_0 also have device-dependent XMX acceleration; PTQ1_0 expands
  to a PQ2_0-sized layout on that path, so its smaller file does not guarantee
  smaller GPU weight memory. No new end-to-end Intel GPU validation was run here.
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
| SYCL | ✅* |

- **SYCL:** dedicated kernels for widths 64, 128, 256, 512, 1024, 2048, 4096,
  and 8192, plus Kronecker transforms for 384, 640, 768, and 1280, on contiguous
  F32 tensors. Unsupported shapes/layouts use the ordinary matrix-multiply path.
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
PQ2_0 is supported on Vulkan in the audited release; downloading the model alone
does not update an older runtime or guarantee GPU offload.

## SYCL release packages

The pinned release includes Linux x64 FP16/FP32 SYCL packages and a Windows x64
SYCL backend with runtime DLLs. Linux needs matching oneAPI libraries installed;
the Windows package overlays the CPU package from the same release. Both need
Intel GPU drivers. See the [SYCL package instructions](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10770-6684606/docs/backend/SYCL-RELEASE.md).
The demo setup scripts do not automatically select or install SYCL yet.

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
- [Vulkan format pipelines and FWHT](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10743-adfffbe/ggml/src/ggml-vulkan/ggml-vulkan.cpp)
  and [shader generation and coopmat2 exclusions](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10743-adfffbe/ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp)
- [SYCL Q2_0 matrix-vector dispatch](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10770-6684606/ggml/src/ggml-sycl/mmvq.cpp) and [dot-product kernels](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10770-6684606/ggml/src/ggml-sycl/vecdotq.hpp)
- [SYCL FWHT width and tensor restrictions](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10770-6684606/ggml/src/ggml-sycl/fwht.cpp)
- [SYCL conversion dispatch](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10770-6684606/ggml/src/ggml-sycl/convert.cpp) and [FWHT dispatch](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10770-6684606/ggml/src/ggml-sycl/ggml-sycl.cpp)

When updating a row, record the release/commit and link the implementation or
validation report. Hardware validation should identify the model filename, GPU/CPU,
OS, driver, backend build, exact command, and a correctness check as well as timings.
Keep partial support and known limitations explicit. Update the baseline and source
links when the demo's release pin changes; review launcher policy separately.
