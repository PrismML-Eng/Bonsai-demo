# Intel i3-7100 — CPU

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
  - Save as community-benchmarks/bonsai/<backend>-<hardware>-<os>.md (lowercase, dashes)
-->

## Summary

<!-- Quick overview: hardware, backend, headline numbers, anything interesting.
     e.g. "RTX 4090 + CUDA 12.8 on Ubuntu 24.04. 8B model: ~370 t/s tg128." -->
Intel Core i3-7100 with 16 GB RAM assigned to a Debian 13 VM on Proxmox 9.2.2 (kernel 6.12.96-1), with the host CPU passed through and all mitigations enabled. CPU-only tg128 throughput: 27B 1.05 t/s, 8B 3.61 t/s, 4B 6.51 t/s, and 1.7B 14.26 t/s.

## llama-bench Results

Run `./setup.sh` first, then find your `llama-bench` binary:
```bash
find bin/ llama.cpp/ -name "llama-bench" -type f 2>/dev/null
```

### Bonsai-27B (the one we most want numbers for!)

```bash
# GPU (Metal / CUDA / Vulkan / ROCm) — adjust BENCH path (bin/mac, bin/cuda, bin/rocm, bin/vulkan, bin/cpu):
BENCH=bin/cpu/llama-bench
$BENCH -m models/gguf/27B/Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CPU        |       4 |   1 |           pp512 |          1.91 ± 0.04 |
| qwen35 27B Q1_0                |   3.53 GiB |    26.90 B | CPU        |       4 |   1 |           tg128 |          1.05 ± 0.04 |

build: 9fcaed763 (9596)

### Bonsai-8B

```bash
# GPU (Metal / CUDA / Vulkan / ROCm) — adjust BENCH path:
BENCH=bin/cpu/llama-bench
$BENCH -m models/gguf/8B/*.gguf -ngl 99 -fa 1

# CPU only:
# $BENCH -m models/gguf/8B/*.gguf -ngl 0 -fa 1 -t $(sysctl -n hw.logicalcpu)  # macOS
# $BENCH -m models/gguf/8B/*.gguf -ngl 0 -fa 1 -t $(nproc)                     # Linux
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CPU        |       4 |   1 |           pp512 |          6.99 ± 0.13 |
| qwen3 8B Q1_0                  |   1.07 GiB |     8.19 B | CPU        |       4 |   1 |           tg128 |          3.61 ± 0.19 |

build: 9fcaed763 (9596)

### Bonsai-4B

```bash
$BENCH -m models/gguf/4B/*.gguf -ngl 99 -fa 1
```
| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CPU        |       4 |   1 |           pp512 |         12.44 ± 0.24 |
| qwen3 4B Q1_0                  | 540.09 MiB |     4.02 B | CPU        |       4 |   1 |           tg128 |          6.51 ± 0.13 |

build: 9fcaed763 (9596)

### Bonsai-1.7B

```bash
$BENCH -m models/gguf/1.7B/*.gguf -ngl 99 -fa 1
```

| model                          |       size |     params | backend    | threads |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | ------: | --: | --------------: | -------------------: |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CPU        |       4 |   1 |           pp512 |         31.99 ± 0.82 |
| qwen3 1.7B Q1_0                | 231.13 MiB |     1.72 B | CPU        |       4 |   1 |           tg128 |         14.26 ± 0.77 |

build: 9fcaed763 (9596)


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
Architecture:                            x86_64
CPU op-mode(s):                          32-bit, 64-bit
Address sizes:                           39 bits physical, 48 bits virtual
Byte Order:                              Little Endian
CPU(s):                                  4
On-line CPU(s) list:                     0-3
Vendor ID:                               GenuineIntel
Model name:                              Intel(R) Core(TM) i3-7100 CPU @ 3.90GHz
CPU family:                              6
Model:                                   158
Thread(s) per core:                      1
Core(s) per socket:                      4
Socket(s):                               1
Stepping:                                9
BogoMIPS:                                7823,99
Flags:                                   fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon rep_good nopl xtopology cpuid tsc_known_freq pni pclmulqdq vmx ssse3 fma cx16 pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand hypervisor lahf_lm abm 3dnowprefetch cpuid_fault pti ssbd ibrs ibpb stibp tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid mpx rdseed adx smap clflushopt xsaveopt xsavec xgetbv1 xsaves arat vnmi umip md_clear flush_l1d arch_capabilities
Virtualization:                          VT-x
Hypervisor vendor:                       KVM
Virtualization type:                     full
L1d cache:                               128 KiB (4 instances)
               total        used        free      shared  buff/cache   available
Mem:            15Gi       1,4Gi       826Mi       8,1Mi        13Gi        14Gi
Swap:           14Gi       256Ki        14Gi
```
