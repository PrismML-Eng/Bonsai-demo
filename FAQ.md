# FAQ and troubleshooting

[Back to the main README](README.md) · [Bonsai 1 guide](Bonsai1_README.md)

- [October 2026 certifi certificate update](#october-2026-certifi-certificate-update)
- [The model allocates huge memory or the machine freezes at startup](#the-model-allocates-huge-memory-or-the-machine-freezes-at-startup)
- [M5 Mac on macOS 26.2/26.3: Metal compile errors, then out-of-memory](#m5-mac-on-macos-262263-metal-compile-errors-then-out-of-memory)
- [Windows setup selects Vulkan or CPU instead of CUDA](#windows-setup-selects-vulkan-or-cpu-instead-of-cuda)
- [CUDA source build runs out of memory or freezes](#cuda-source-build-runs-out-of-memory-or-freezes)
- [Metal fails to initialize on Apple M5 (macOS 26.2–26.4)](#metal-fails-to-initialize-on-apple-m5-macos-262264)

## The model allocates huge memory or the machine freezes at startup

Older revisions defaulted to llama.cpp's `-c 0`, which uses the model's full training context (262K on the 27B) regardless of available memory and could exhaust it on constrained machines. The scripts now always use a RAM-tiered context instead; `BONSAI_CTX=0` maps to that same safe default rather than `-c 0`. If you still hit memory pressure, pin a smaller context:

```bash
BONSAI_CTX=8192 ./scripts/start_llama_server.sh
```

## M5 Mac on macOS 26.2/26.3: Metal compile errors, then out-of-memory

On M5 devices with certain macOS 26 point releases, the Metal tensor-API probe fails to compile at runtime (`ggml_metal_library_init_from_source: error compiling source`) and can leave the GPU in a bad state. This is an ecosystem-wide issue in the OS Metal headers, hitting every ggml-based project. Workaround, keeps full Metal speed and just skips the tensor-API path:

```bash
GGML_METAL_TENSOR_DISABLE=1 ./scripts/run_llama.sh -p "Hello"
```

## Windows setup selects Vulkan or CPU instead of CUDA

**Symptom:** `setup.ps1` reports `[INFO] No GPU toolchain detected. Will use CPU build.` or selects Vulkan, even though `nvidia-smi` runs successfully and detects your NVIDIA GPU.

**Cause:** Older versions of the setup script expected the header `CUDA Version:`. Some newer NVIDIA drivers instead report `CUDA UMD Version:`. The extra `UMD` prevented CUDA detection, causing setup to select another backend.

This can leave you with binaries under `bin\vulkan` or `bin\cpu` rather than `bin\cuda`. On affected Bonsai 2 setups, users reported prompts stalling without processing any tokens instead of producing a clear error.

## CUDA source build runs out of memory or freezes

**Symptom:** `cmake --build` hangs, the system becomes unresponsive, or the build process is killed with an OOM error when building llama.cpp from source with CUDA enabled.

**Cause:** Compiling CUDA kernels is memory-intensive — each parallel compile job can consume several GB of GPU VRAM and/or system RAM. Running `make -j$(nproc)` on a machine with a low-VRAM GPU (< 16 GB) or limited system RAM can exhaust available memory.

**How the build scripts handle this:** `build_cuda_linux.sh` and `build_cuda_windows.ps1` automatically detect the GPU's VRAM before building. If the maximum detected VRAM is less than 16 GB, the scripts cap parallelism at `-j 2` instead of using all logical CPU cores. You will see a message like:

```
Detected GPU VRAM: 8.0 GB (< 16 GB) -- limiting CUDA build to -j 2
```

**Manual override:** If you still encounter OOM errors, reduce parallelism further by editing the build invocation in the relevant script, or close other GPU-heavy applications before building.

## Metal fails to initialize on Apple M5 (macOS 26.2–26.4)

**Symptom:** On M5 Macs, `run_llama.sh` / `start_llama_server.sh` fail with Metal errors and produce no output, e.g.:

```
ggml_metal_library_init_from_source: error compiling source
ggml_metal_device_init: - the tensor API is not supported in this environment - disabling
ggml_metal_synchronize: error: command buffer 0 failed with status 5
```

Pre-M5 Apple Silicon (M1–M4) is not affected — those devices load the embedded, precompiled Metal library and never compile shaders at runtime.

**Cause:** On M5 (and A19) devices, ggml compiles its Metal library from source at runtime to enable the tensor API (Neural Accelerators). Some macOS 26 point releases ship stricter MetalPerformancePrimitives headers whose `static_assert` (bfloat/half type mismatch) breaks that runtime compile. This is an ecosystem-wide issue also seen in [ollama](https://github.com/ollama/ollama/issues/15594) and [whisper.cpp](https://github.com/ggml-org/whisper.cpp/issues/3722); see [#93](https://github.com/PrismML-Eng/Bonsai-demo/issues/93).

**Workaround:** Disable the tensor API so the M5 uses the embedded library like pre-M5 devices — full Metal speed is kept, only the Neural Accelerator prefill boost is lost:

```bash
GGML_METAL_TENSOR_DISABLE=1 ./scripts/run_llama.sh -p "Hello"
GGML_METAL_TENSOR_DISABLE=1 ./scripts/start_llama_server.sh
```

This is much faster than falling back to CPU (`BONSAI_NGL=0`). If out-of-memory errors persist afterwards on lower-memory machines, additionally pin a smaller context, e.g. `-c 16384` (extra args pass through to llama.cpp and override the default).

## October 2026 certifi certificate update

Existing Python environments should update to `certifi>=2026.10.23` following [GHSA-6q48-6c7w-9gw2](https://github.com/advisories/GHSA-6q48-6c7w-9gw2). This affects outbound HTTPS clients using certifi's certificate bundle, including model downloads; it does not require a publicly hosted server. Updating the repository alone does not update installed packages.

After pulling the updated repository, stop running demo servers and update each existing environment from the repository root:

**macOS / Linux:**

```sh
for env_dir in .venv .venv-vlm .venv-jupyter; do
    if [ -x "$env_dir/bin/python" ]; then
        uv pip install --python "$env_dir/bin/python" "certifi>=2026.10.23" || break
    fi
done
```

**Windows PowerShell:**

```powershell
uv pip install --python .venv\Scripts\python.exe "certifi>=2026.10.23"
```

Restart the servers afterward. These commands only update certifi as needed and do not download models. Updated setup scripts also enforce this minimum when rerun. Rebuild any containers or other environments you maintain separately with a patched certifi bundle.
