# [Hardware Name] — [Backend]

<!-- Example titles:
  # RTX 4090 — CUDA
  # Apple M4 Pro — Metal
  # AMD RX 7900 XTX — Vulkan
  # Intel i9-14900K — CPU

  Formatting is not strict — this is a suggested structure.
  Feel free to adapt as needed, but try to include the key sections.

  AI assistant notes:
  - Help the user fill this template by running the commands in the appendix
  - Set the title to their hardware + backend
  - Write a short summary with the key hardware specs and headline t/s numbers
  - Paste raw llama-bench output in the results sections as-is (don't reformat)
  - Paste raw hardware info output in the appendix as-is
  - Include the exact commands that were run, especially if they differ from suggestions
  - Save as community-benchmarks/<backend>-<hardware>-<os>.md (lowercase, dashes)
-->

## Summary

<!-- Quick overview: hardware, backend, headline numbers, anything interesting.
     e.g. "RTX 4090 + CUDA 12.8 on Ubuntu 24.04. 8B model: ~370 t/s tg128."
     Full hardware dump is in the appendix. -->

## llama-bench Results

### Bonsai-8B

```
(paste llama-bench output here)
```

### Bonsai-4B

```
(paste llama-bench output here, or remove if skipped)
```

### Bonsai-1.7B

```
(paste llama-bench output here, or remove if skipped)
```

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

---

## Appendix

### Hardware info

<!-- Paste the command you ran and its output -->

**Command:**
```bash
# macOS
system_profiler SPHardwareDataType SPDisplaysDataType SPMemoryDataType

# Linux
# lscpu && free -h && (nvidia-smi 2>/dev/null || rocminfo 2>/dev/null || vulkaninfo --summary 2>/dev/null || true)

# Windows (PowerShell)
# Get-CimInstance Win32_Processor | Format-List Name,NumberOfCores,NumberOfLogicalProcessors
# Get-CimInstance Win32_VideoController | Format-List Name,AdapterRAM,DriverVersion
# [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
```

**Output:**
```
(paste output here)
```

### llama-bench

Run `./setup.sh` first, then find your `llama-bench` binary:
```bash
find bin/ llama.cpp/ -name "llama-bench" -type f 2>/dev/null
```

Suggested commands (adjust path and flags as needed):

**GPU (Metal / CUDA / Vulkan / ROCm):**
```bash
BENCH=bin/mac/llama-bench  # adjust to your binary path

$BENCH -m models/gguf/8B/*.gguf   -ngl 99 -fa 1
$BENCH -m models/gguf/4B/*.gguf   -ngl 99 -fa 1
$BENCH -m models/gguf/1.7B/*.gguf -ngl 99 -fa 1
```

**CPU only:**
```bash
BENCH=bin/cpu/llama-bench  # adjust to your binary path

# macOS
$BENCH -m models/gguf/8B/*.gguf   -ngl 0 -fa 1 -t $(sysctl -n hw.logicalcpu)
# Linux
$BENCH -m models/gguf/8B/*.gguf   -ngl 0 -fa 1 -t $(nproc)
```

Repeat for 4B and 8B if they fit in memory.

If you changed the commands from the suggestions above, paste the exact commands you ran:
```bash
(paste your commands here if different)
```
