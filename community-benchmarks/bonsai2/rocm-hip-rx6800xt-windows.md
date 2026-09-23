# AMD Radeon RX 6800 XT 16 GB — ROCm/HIP (Windows)

## Summary

AMD Radeon RX 6800 XT 16 GB (RDNA2, gfx1030) with an AMD Ryzen 9 5900X on Windows 11, AMD Adrenalin 26.7.1, 16 GB system RAM.
Prebuilt Windows HIP archive from this demo's fork (`prism-b10709-9a9394a`), run against the
**ROCm 7.14.0 runtime from AMD TheRock** (`rocm-sdk-core` wheel). Bonsai 2 27B `PQ2_0`, `-ngl 99`:

| Format | PP512 (t/s) | TG128 (t/s) |
|--------|------------:|------------:|
| PQ2_0 (`-fa 1`) | 266.42 | 44.94 |
| PQ2_0 (`-fa` default) | 266.71 | 44.84 |
| PTQ1_0 | not tested | not tested |
| Q2_0 (development) | not tested | not tested |

Flash attention makes no measurable difference on this card.

**Runtime note:** the AMD HIP SDK 7.2 for Windows does not support gfx1030. With it, llama-server
logs `ggml_cuda_init: failed to initialize ROCm: no ROCm-capable device is detected` and falls back
to CPU (~1.7 t/s prompt processing). AMD lists the RX 6800 XT as unsupported in the HIP SDK 7.2
Windows system requirements, and the same failure is reported for HIP SDK 7.1.1 in
[ROCm/hip#3899](https://github.com/ROCm/hip/issues/3899). The TheRock runtime detects the card and
runs the fork's HIP build at the speeds above.

## Configuration

- Model: `prism-ml/Ternary-Bonsai-2-27B-gguf`, `Ternary-Bonsai-2-27B-PQ2_0.gguf` (6.70 GiB), as downloaded by `setup.ps1`.
- llama.cpp: `llama-prism-b10709-9a9394a-bin-win-hip-radeon-x64.zip`, build `9a9394a89 (10709)`.
- HIP runtime: `rocm==7.14.0` / `rocm-sdk-core==7.14.0` from `https://repo.amd.com/rocm/whl-multi-arch/`,
  installed into a Python 3.12 venv; its `_rocm_sdk_core\bin` directory placed first on `PATH`.
  AMD HIP SDK not installed.
- OS: Windows 11. GPU driver: AMD Adrenalin 26.7.1.
- GPU: AMD Radeon RX 6800 XT 16 GB (gfx1030, wave32). CPU: AMD Ryzen 9 5900X (12C/24T). System RAM: 16 GB.
- Full offload (`-ngl 99`), otherwise `llama-bench` defaults. No power limit or clock changes.

## llama-bench results

### PQ2_0 — flash attention on

```powershell
$rocmBin = (Get-ChildItem <venv> -Recurse -Filter amdhip64_7.dll | Select-Object -First 1).DirectoryName
$env:Path = "$rocmBin;$env:Path"
.\bin\hip\llama-bench.exe -m models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -p 512 -n 128 -fa 1
```

```
ggml_cuda_init: found 1 ROCm devices (Total VRAM: 16368 MiB):
  Device 0: AMD Radeon RX 6800 XT, gfx1030 (0x1030), VMM: no, Wave Size: 32, VRAM: 16368 MiB
load_backend: loaded ROCm backend from ...\bin\hip\ggml-hip.dll
load_backend: loaded RPC backend from ...\bin\hip\ggml-rpc.dll
load_backend: loaded CPU backend from ...\bin\hip\ggml-cpu.dll
| model                          |       size |     params | backend    | ngl |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |   1 |           pp512 |        266.42 ± 0.84 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |   1 |           tg128 |         44.94 ± 0.09 |

build: 9a9394a89 (10709)
```

### PQ2_0 — flash attention default

```powershell
.\bin\hip\llama-bench.exe -m models\bonsai2-gguf\27B\Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -p 512 -n 128
```

```
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |           pp512 |        266.71 ± 0.98 |
| qwen35 27B PQ2_0 - 2.13 bpw (group 128) |   6.70 GiB |    26.90 B | ROCm       |  99 |           tg128 |         44.84 ± 0.21 |

build: 9a9394a89 (10709)
```

PTQ1_0 and development Q2_0 were not tested.

## Additional observations

- **Vulkan:** the prebuilt Vulkan archive of the same release loads `PQ2_0` but prompt processing
  runs at ~0.9 t/s (llama-server log), consistent with `PQ2_0` having no Vulkan kernels yet and with
  the RX 7800 XT report.
- **Server:** `llama-server` via `start_llama_server.ps1`, 32K context, 4 slots: 62-token prompt at
  97 t/s, 213 generated tokens at 43.5 t/s.
- **Setup detection:** `setup.ps1` chooses the HIP archive only when `HIP_PATH` (or `hipcc`) is
  present. Without the HIP SDK, setting `HIP_PATH` to the TheRock `_rocm_sdk_core` directory for the
  setup run is enough for it to download the HIP archive.

## Hardware

```
GPU    : AMD Radeon RX 6800 XT 16 GB (Navi 21, gfx1030)
Driver : AMD Adrenalin 26.7.1
CPU    : AMD Ryzen 9 5900X, 12C/24T (Zen 3)
RAM    : 16 GB
OS     : Windows 11
Runtime: AMD TheRock rocm-sdk-core 7.14.0
Binary : PrismML fork prebuilt Windows HIP, release prism-b10709-9a9394a
Model  : Ternary-Bonsai-2-27B-PQ2_0.gguf (6.70 GiB) + mmproj-Q8_0
```
