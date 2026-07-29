# RTX 3080 Ti — CUDA

## Summary

Benchmarked the Ternary-Bonsai model family on an NVIDIA RTX 3080 Ti (12 GB) with an AMD Ryzen 9 5900X (32 GB RAM) running Ubuntu under WSL2. All four model sizes (27B, 8B, 4B, and 1.7B) fit fully on the GPU without CPU layer offloading.

`llama-bench` tg128 throughput:

| Model | Throughput   |
| ----- | ------------ |
| 27B   | 62.98 tok/s  |
| 8B    | 197.16 tok/s |
| 4B    | 255.74 tok/s |
| 1.7B  | 403.17 tok/s |

The paired `draft-dspark` model was also evaluated using `llama-server` speculative decoding. For a short code-generation prompt, speculative decoding increased generation throughput from **65.1 tok/s** to **95.9 tok/s** (1.47× speedup) with a **68.5% draft acceptance rate**.

---

## llama-bench Results

Run `./setup.sh` first, then locate the CUDA `llama-bench` binary:

```bash
find bin/ llama.cpp/ -name "llama-bench" -type f 2>/dev/null
```

### Ternary-Bonsai-27B

```bash
BENCH=bin/cuda/llama-bench
$BENCH -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf -ngl 99 -fa 1
```

| model           | size     | params  | backend | ngl | fa | test  | t/s             |
| --------------- | -------- | ------- | ------- | --- | -- | ----- | --------------- |
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA    | 99  | 1  | pp512 | 1383.62 ± 24.68 |
| qwen35 27B Q2_0 | 6.66 GiB | 26.90 B | CUDA    | 99  | 1  | tg128 | 62.98 ± 0.70    |

### Ternary-Bonsai-8B

```bash
$BENCH -m models/ternary-gguf/8B/*.gguf -ngl 99 -fa 1
```

| model         | size     | params | backend | ngl | fa | test  | t/s              |
| ------------- | -------- | ------ | ------- | --- | -- | ----- | ---------------- |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | CUDA    | 99  | 1  | pp512 | 5184.86 ± 147.84 |
| qwen3 8B Q2_0 | 2.03 GiB | 8.19 B | CUDA    | 99  | 1  | tg128 | 197.16 ± 0.98    |

### Ternary-Bonsai-4B

```bash
$BENCH -m models/ternary-gguf/4B/*.gguf -ngl 99 -fa 1
```

| model         | size        | params | backend | ngl | fa | test  | t/s              |
| ------------- | ----------- | ------ | ------- | --- | -- | ----- | ---------------- |
| qwen3 4B Q2_0 | 1019.50 MiB | 4.02 B | CUDA    | 99  | 1  | pp512 | 8602.05 ± 551.37 |
| qwen3 4B Q2_0 | 1019.50 MiB | 4.02 B | CUDA    | 99  | 1  | tg128 | 255.74 ± 2.64    |

### Ternary-Bonsai-1.7B

```bash
$BENCH -m models/ternary-gguf/1.7B/*.gguf -ngl 99 -fa 1
```

| model           | size       | params | backend | ngl | fa | test  | t/s                |
| --------------- | ---------- | ------ | ------- | --- | -- | ----- | ------------------ |
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | CUDA    | 99  | 1  | pp512 | 16775.00 ± 2057.45 |
| qwen3 1.7B Q2_0 | 436.16 MiB | 1.72 B | CUDA    | 99  | 1  | tg128 | 403.17 ± 4.03      |

---

## Speculative Decoding (`draft-dspark`)

The paired `Ternary-Bonsai-27B-dspark-Q4_1.gguf` draft model was evaluated using `llama-server` with speculative decoding enabled.

Server with speculative decoding:

```bash
bin/cuda/llama-server \
  -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf \
  -md models/ternary-gguf/27B/Ternary-Bonsai-27B-dspark-Q4_1.gguf \
  --spec-type draft-dspark \
  --spec-draft-n-max 4 \
  -ngl 999 -ngld 999 \
  -fa on \
  -c 2048
```

Server without speculative decoding:

```bash
bin/cuda/llama-server \
  -m models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf \
  -ngl 999 \
  -fa on \
  -c 2048
```

Benchmark Request:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions   -H 'Content-Type: application/json'   -d '{"messages":[{"role":"user","content":"Implement quicksort in Python."}],"max_tokens":400}'   | jq '.timings | {predicted_per_second, draft_n, draft_n_accepted}'
```

| Configuration        | Decode throughput |
| -------------------- | ----------------- |
| 27B target only      | 65.1 tok/s        |
| 27B + `draft-dspark` | 95.9 tok/s        |

Results:

* Draft acceptance: **292 / 426 tokens (68.5%)**
* End-to-end generation speedup: **1.47×**

**Observation**

During testing, throughput was substantially higher with -c 2048 than with -c 16384 for this workload, suggesting that context size can significantly affect speculative decoding performance on a 12 GB GPU.

---

## Configuration

The complete `llama-bench` suite was executed twice to verify reproducibility. All measurements were consistent across runs and remained within expected benchmark variance.

Examples:

* 27B tg128: 63.30 vs. 62.81 tok/s
* 8B tg128: 197.16 vs. 196.47 tok/s
* 4B tg128: 255.74 vs. 254.99 tok/s
* 1.7B tg128: 403.17 vs. 400.99 tok/s

---

## Notes

* Prebuilt CUDA binaries from release `prism-b9596-9fcaed7` (downloaded via `./scripts/download_binaries.sh`).
* Benchmarks were performed under Ubuntu on WSL2 rather than native Linux.
* GPU passthrough used NVIDIA's WSL driver.
* Baseline GPU memory usage was approximately 1.8–2.0 GB from WSLg/desktop compositing before benchmarking. Other GPU applications were closed prior to testing.

---

## Hardware

**Linux:**
```bash
lscpu | head -20 && free -h && (nvidia-smi 2>/dev/null || rocminfo 2>/dev/null || vulkaninfo --summary 2>/dev/null || true)
```

```
Architecture:                x86_64
  CPU op-mode(s):            32-bit, 64-bit
  Address sizes:             48 bits physical, 48 bits virtual
  Byte Order:                Little Endian
CPU(s):                      24
  On-line CPU(s) list:       0-23
Vendor ID:                   AuthenticAMD
  Model name:                AMD Ryzen 9 5900X 12-Core Processor
    CPU family:              25
    Model:                   33
    Thread(s) per core:      2
    Core(s) per socket:      12
    Socket(s):               1
    Stepping:                0
    BogoMIPS:                7386.21
Caches (sum of all):
  L1d:                       384 KiB (12 instances)
  L1i:                       384 KiB (12 instances)
  L2:                        6 MiB (12 instances)
  L3:                        32 MiB (1 instance)
               total        used        free      shared  buff/cache   available
Mem:            31Gi        835Mi       28Gi       3.5Mi       2.4Gi        30Gi
Swap:          8.0Gi          0B       8.0Gi

Mon Jul 27 19:33:25 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 610.43.02              KMD Version: 610.47        CUDA UMD Version: 13.3     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 3080 Ti     On  |   00000000:0A:00.0  On |                  N/A |
|  0%   37C    P8             33W /  400W |    1879MiB /  12288MiB |      4%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------------------------------------------------------+
```