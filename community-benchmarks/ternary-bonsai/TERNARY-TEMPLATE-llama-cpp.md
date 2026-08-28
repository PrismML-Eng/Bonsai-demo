# [Hardware Name] — [Backend]

<!-- Example titles:
  # RTX 4090 — CUDA
  # Apple M4 Pro — Metal
  # AMD RX 7900 XTX — Vulkan
  # Intel i9-14900K — CPU

  Formatting is not strict — this is a suggested structure.
  Feel free to adapt as needed, but try to include the key sections.

  AI assistant notes:
  - Help the user fill this template by running the suggested commands
  - Set the title to their hardware + backend
  - Write a short summary with the key hardware specs and headline t/s numbers
  - Paste raw llama-bench output as-is (don't reformat, no code blocks — it's a markdown table)
  - Include the exact commands that were run, especially if they differ from suggestions
  - Save as community-benchmarks/ternary-bonsai/<backend>-<hardware>-<os>.md (lowercase, dashes)
  - FORMATS (post-migration): since release prism-b10658 the fork reads two ternary GGUF
    formats, and a submission should benchmark BOTH when disk allows:
      * PQ2_0 — our group-128 packing, e.g. Ternary-Bonsai-27B-PQ2_0.gguf (27B: 6.66 GiB).
        Smallest and usually fastest on CUDA / Metal / CPU / ROCm.
      * Q2_0 group-64 — the official upstream format, widest backend coverage
        (adds Vulkan/SYCL). 27B file: Ternary-Bonsai-27B-Q2_g64.gguf (7.05 GiB);
        8B/4B/1.7B files: Ternary-Bonsai-<size>-Q2_0_g64.gguf.
    The legacy Ternary-Bonsai-*-Q2_0.gguf files (no g64 suffix) are pre-migration:
    prism-b10658+ binaries refuse them with a clear error. If the user has old files or
    old binaries, point them at the new release and the two files above instead of
    benchmarking the legacy pair.
-->

## Summary

<!-- Quick overview: hardware, backend, headline numbers, anything interesting.
     e.g. "RTX 4090 + CUDA 12.8 on Ubuntu 24.04. 8B model: ~370 t/s tg128." -->

## llama-bench Results

Run `./setup.sh` first, then find your `llama-bench` binary:
```bash
find bin/ llama.cpp/ -name "llama-bench" -type f 2>/dev/null
```

### Ternary-Bonsai-27B (the one we most want numbers for!)

There are two ternary GGUF formats since the mainline rebase (release `prism-b10658+`), and we'd love numbers for **both**: `PQ2_0` (group 128, smallest/fastest where supported) and `Q2_0` group 64 (official upstream format, widest backend coverage). `setup.sh` downloads the best one for your backend; grab the other with the `hf download` line below if you have the disk.

```bash
# GPU (Metal / CUDA / Vulkan / ROCm) — adjust BENCH path (bin/mac, bin/cuda, bin/rocm, bin/vulkan, bin/cpu):
BENCH=bin/mac/llama-bench
$BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-PQ2_0.gguf -ngl 99 -fa 1

# and the official group-64 format (download if setup.sh didn't):
hf download prism-ml/Ternary-Bonsai-27B-GGUF --include "*Q2_g64*" --local-dir models/ternary-gguf/27B
$BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_g64.gguf -ngl 99 -fa 1
```

(paste llama-bench output for each format here, or remove this section if you skipped the 27B; note: the legacy `Ternary-Bonsai-27B-Q2_0.gguf` without `g64` in the name is refused by `prism-b10658+` binaries)

### Ternary-Bonsai-8B

```bash
# GPU (Metal / CUDA / Vulkan / ROCm) — adjust BENCH path:
BENCH=bin/mac/llama-bench
$BENCH -m models/ternary-gguf/8B/*.gguf -ngl 99 -fa 1

# CPU only:
# $BENCH -m models/ternary-gguf/8B/*.gguf -ngl 0 -fa 1 -t $(sysctl -n hw.logicalcpu)  # macOS
# $BENCH -m models/ternary-gguf/8B/*.gguf -ngl 0 -fa 1 -t $(nproc)                     # Linux
```

(paste llama-bench output here — raw markdown table, no code block; the 8B/4B/1.7B repos also have both formats, `*-PQ2_0.gguf` and `*-Q2_0_g64.gguf` — bench each if you have both)

### Ternary-Bonsai-4B

```bash
$BENCH -m models/ternary-gguf/4B/*.gguf -ngl 99 -fa 1
```

(paste llama-bench output here, or remove if skipped)

### Ternary-Bonsai-1.7B

```bash
$BENCH -m models/ternary-gguf/1.7B/*.gguf -ngl 99 -fa 1
```

(paste llama-bench output here, or remove if skipped)

## Configuration

<!-- If you tested multiple backends or settings on the same hardware, note them here.
     Examples:
     - "Also tested CPU-only on this GPU machine: ~15 t/s tg128 on 8B"
     - "Ran with power limit set to 300W instead of default 450W"
     - "Tested both Vulkan and CUDA on the same RTX 4090 — CUDA was ~20% faster for tg"
     - "Used ROCm 6.2; ROCm 6.1 produced ~10% slower results"
     - "Overclocked GPU memory +500 MHz, no change in thermals"
-->

## Notes

<!-- Optional: driver versions, cooling setup, power limits, thermals, anything notable -->

## Hardware

Not required, but helpful. Pick the command for your OS:

**macOS:**
```bash
sysctl machdep.cpu.brand_string hw.memsize hw.ncpu && system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|Number of Cores|Metal"
```

**Linux:**
```bash
lscpu | head -20 && free -h && (nvidia-smi 2>/dev/null || rocminfo 2>/dev/null || vulkaninfo --summary 2>/dev/null || true)
```

**Windows (PowerShell):**
```powershell
Get-CimInstance Win32_Processor | Format-List Name,NumberOfCores,NumberOfLogicalProcessors
Get-CimInstance Win32_VideoController | Format-List Name,DriverVersion
[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
```

```
(paste output here)
```
