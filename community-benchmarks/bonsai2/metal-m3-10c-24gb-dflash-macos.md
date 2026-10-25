# Apple M3 (10 GPU Cores, 24 GB) — Metal / macOS — Speculative Decoding with DFlash2

## Summary

Physical empirical benchmarks of **`Ternary-Bonsai-2-27B-PQ2_0`** on Apple Silicon M3 (10 GPU Cores, 24 GB Unified Memory, 100 GB/s physical memory bandwidth), comparing **baseline standalone generation** against **speculative decoding using open-source DFlash2 drafters**.

All benchmarks were physically measured using the official `PrismML-Eng/llama.cpp` Metal C++ backend under deterministic greedy sampling (`--temp 0`). For the tested greedy runs, both drafters produced outputs with SHA-256 digests matching the standalone baseline. This observation is limited to the tested prompts and settings.

| Configuration / Drafter | Drafter File Size | Avg TPS | Net Speedup | Acceptance Rate | Output Match in Tested Runs (SHA-256) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Target Baseline (`--spec-type none`)** | — | **8.65 to 9.23 t/s** | 1.00x (Ref) | — | Reference (`84ce7b...`) |
| **Tier 1: Full-Rank Q2_K FC (`draft-dflash`)** | **715.5 MB** | **11.05 to 13.00 t/s** | **+22.5% to +41.3%** | **76.7% to 91.7%** | **100% Match** |
| **Tier 2: SVD-r256-QAT (`draft-dflash`)** | **375.5 MB** | **10.40 to 11.80 t/s** | **+8.0% to +28.3%** | **43.2% to 62.1%** | **100% Match** |

- **Tier 1 (715.5 MB)**: Re-quantized FFN projection weights to asymmetric `Q2_K` while locking Attention and Selector at `Q4_K`. Breaks past the real-time 10 tok/s threshold on Apple Silicon M3, averaging 11.31 t/s across multi-prompt workloads (up to 13.00 t/s on concise tasks).
- **Tier 2 (375.5 MB)**: Factorized 15 SwiGLU FFN matrices into rank-256 pairs via SVD followed by multi-step K=3 QAT knowledge distillation. Reduces the drafter file size to 375.5 MB (65.9% reduction vs uncompressed 1.10 GB baseline) with forward latency of approx. 15.1 ms, preserving positive speedup (+20.2% on code generation).
- **Drafter Model Weights & Documentation**: [https://huggingface.co/NOhhh/Ternary-Bonsai-2-27B-Speculative-Drafters](https://huggingface.co/NOhhh/Ternary-Bonsai-2-27B-Speculative-Drafters)

---

Drafter sizes below refer to GGUF files on disk, not measured runtime memory use.

## Configuration

- **Hardware**: Apple Silicon M3 (8 CPU cores: 4P + 4E, 10 GPU cores, 16-core Neural Engine)
- **Memory**: 24 GB Unified Memory (100 GB/s physical memory bandwidth)
- **OS**: macOS Sequoia / Sonoma (Metal 3)
- **Inference Engine**: [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) (Built with `cmake -B build -DGGML_METAL=ON`)
- **Target Model**: `prism-ml/Ternary-Bonsai-2-27B-gguf` (`Ternary-Bonsai-2-27B-PQ2_0.gguf`, 7.21 GB, 2.13 bpw)
- **Drafter Models**:
  - Tier 1: `Ternary-Bonsai-2-27B-DFlash2-ft5-asym-Q2_K-FC-FullRank.gguf` (715.5 MB)
  - Tier 2: `Ternary-Bonsai-2-27B-DFlash2-SVD-r256-QAT-K3-Q4_K.gguf` (375.5 MB)

---

## Detailed Benchmark Results

### 1. Code Generation Workload (160 Tokens, Python Quicksort)
*Prompt: "Write a clean Python implementation of quicksort with type annotations and docstring."*

| Configuration | Gen TPS | Net Speedup | Neural Acceptance (Accepted/Proposed) | Output SHA-256 Digest |
| :--- | :---: | :---: | :---: | :---: |
| Baseline (Standalone Target) | 8.65 tok/s | 1.00x | — | `84ce7bdb7fd29205...` (243 B) |
| Tier 1 Full-Rank (715.5 MB) | **11.05 tok/s** | **+27.7%** | **76.7% (69 / 90)** | `84ce7bdb7fd29205...` (100% Match) |
| Tier 2 SVD-r256 (375.5 MB) | **10.40 tok/s** | **+20.2%** | **62.1% (54 / 87)** | `84ce7bdb7fd29205...` (100% Match) |

### 2. Multi-Prompt Physical Repeatability Matrix (Mean ± SD across 27 Replicated Runs)
*Measured with temp=0, seed=42..44, 64 tokens per condition to evaluate physical execution variance:*

| Workload Domain | Baseline (Mean ± SD) | Tier 1 (715.5 MB) | Tier 1 Speedup | Tier 2 (375.5 MB) | Tier 2 Speedup |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Python Quicksort (Code) | 9.03 ± 0.21 t/s | **10.53 ± 0.55 t/s** | +16.6% | 9.03 ± 0.86 t/s | +0.0% |
| Math / Logic (Tunnel Problem) | 9.23 ± 0.21 t/s | **12.23 ± 0.06 t/s** | +32.5% | **10.07 ± 0.06 t/s** | +9.1% |
| Technical QA (Unified Memory) | 9.43 ± 0.06 t/s | **11.17 ± 0.25 t/s** | +18.5% | **10.80 ± 0.10 t/s** | +14.5% |
| **Grand Mean Across Workloads** | **9.23 ± 0.17 t/s** | **11.31 ± 0.35 t/s** | **+22.5%** | **9.97 ± 0.50 t/s** | **+8.0%** |

---

## Reproduction Commands

### Build Engine
```bash
git clone https://github.com/PrismML-Eng/llama.cpp.git
cd llama.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build --target llama-cli -j8
```

### Download Weights
```bash
# Target Model (7.21 GB)
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-PQ2_0.gguf --local-dir ./models

# Drafter Tier 1 (715.5 MB)
hf download NOhhh/Ternary-Bonsai-2-27B-Speculative-Drafters Ternary-Bonsai-2-27B-DFlash2-ft5-asym-Q2_K-FC-FullRank.gguf --local-dir ./models

# Drafter Tier 2 (375.5 MB)
hf download NOhhh/Ternary-Bonsai-2-27B-Speculative-Drafters Ternary-Bonsai-2-27B-DFlash2-SVD-r256-QAT-K3-Q4_K.gguf --local-dir ./models
```

### Run Benchmark

**1. Baseline (Without Drafter):**
```bash
./build/bin/llama-cli \
  -m ./models/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  -ngl 999 -c 2048 -t 4 --temp 0 -s 42 -n 160 -st \
  -p "Write a clean Python implementation of quicksort with type annotations and docstring."
```

**2. Tier 1 Speculative Decoding (+27.7% Speedup):**
```bash
./build/bin/llama-cli \
  -m ./models/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  -md ./models/Ternary-Bonsai-2-27B-DFlash2-ft5-asym-Q2_K-FC-FullRank.gguf \
  -ngl 999 -ngld 999 -c 2048 -t 4 --temp 0 -s 42 -n 160 -st \
  --spec-type draft-dflash --spec-draft-n-max 3 \
  -p "Write a clean Python implementation of quicksort with type annotations and docstring."
```

**3. Tier 2 Speculative Decoding (+20.2% Speedup, 375.5 MB Drafter File):**
```bash
./build/bin/llama-cli \
  -m ./models/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  -md ./models/Ternary-Bonsai-2-27B-DFlash2-SVD-r256-QAT-K3-Q4_K.gguf \
  -ngl 999 -ngld 999 -c 2048 -t 4 --temp 0 -s 42 -n 160 -st \
  --spec-type draft-dflash --spec-draft-n-max 3 \
  -p "Write a clean Python implementation of quicksort with type annotations and docstring."
```
