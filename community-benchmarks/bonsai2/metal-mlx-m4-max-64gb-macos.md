# M4 Max 64GB - Metal / MLX, macOS: end-to-end serving comparison

Measured on an Apple M4 Max (40 GPU cores), 64 GiB unified memory, macOS 26.6.2,
Metal 4, on 2026-10-02 KST. This compares three server configurations on a small
Korean order-extraction workload: Bonsai 2 PQ2_0 with llama.cpp Metal, Bonsai 2
MLX 2-bit with mlx-vlm, and an existing Ollama NVFP4/MLX model.

**PP512 and TG128 were not measured.** These serving results are separate from
the throughput leaderboards and are not a controlled comparison of quantization
formats. PTQ1_0 and development Q2_0 were not tested.

## What was tested

- **Order:** extract four flower names, quantities and units from Korean text,
  excluding a cancelled item, and return JSON.
- **Tool:** extract the same order via one native `extract_order` call. The call
  was checked against expected arguments but never executed; no tool round-trip
  or business action was tested.
- **Image:** extract the four rows from one synthetic 1200×760 statement image
  containing large, clear Korean text. This was not a real-document OCR evaluation.

Each workload was repeated three times per configuration, for 27 requests total.
The final tables below retain the contributor's measurements; no rerun was made
when simplifying this report.

## Configuration

- Demo revision: `bfaea577522626b883f755236878e4583f3d6e68`.
- PrismML llama.cpp release `prism-b10743-adfffbe`, build 10743,
  commit `adfffbe41`, AppleClang 21.0.0.21000101 for Darwin arm64.
  Metal offload confirmed for 65/65 layers. Binary SHA-256:
  `ccb543f84f6873459c99ab67983dbeacdb4ece836cc8257758bb14afea04f528`.
- GGUF repository: `prism-ml/Ternary-Bonsai-2-27B-gguf`, revision
  `b072e1d3b35a0a630cece372c2127528e0994386`.
  `Ternary-Bonsai-2-27B-PQ2_0.gguf`: 7,206,168,928 bytes;
  `Ternary-Bonsai-2-27B-mmproj-BF16.gguf`: 931,145,856 bytes.
- MLX repository: `prism-ml/Ternary-Bonsai-2-27B-mlx-2bit`, revision
  `fcba37d2117a7077eac6b613b2668d14d9779edd`.
  `model.safetensors`: 8,595,477,990 bytes, affine 2-bit/group 128,
  `prism_hadamard_qwen35`. mlx 0.32.2, mlx-vlm 0.7.2, transformers 5.14.1.
- Existing baseline tag: `qwen3.8:27b-mlx`. Despite the tag, actual metadata was
  safetensors **NVFP4**, qwen3_5, 27.8B, Ollama 0.33.2,
  MLX GPU runtime `0.32.1-37-gc793734` / `mlx_metal_v4`.
  Manifest SHA-256: `5642e97495e1a088883805981563dcdc4a040c2f53388b7a41d1f24d3622cf7e`.
  Model tensor files total 18,174,721,596 bytes. This locally installed tag is not
  assumed to be a reproducible public download by name alone.
- Benchmark client: Python 3.11.15.
- No power tuning was applied. Other existing apps/services remained running;
  this was not an idle dedicated machine. Background load and thermal state were
  not controlled throughout. Initial system swap was already about 24 GiB;
  calibration increased retained swap before the final runs.

## Running a similar comparison

Use the pinned model/runtime versions above. Set `$LAB` to your experiment
folder containing `Bonsai-demo/`, `models/` and a Python environment at `venv/`.
For the optional Ollama baseline, set `$OLLAMA_MODELS` to your existing model
store; its local tag alone is not enough to obtain the same checkpoint.
Run one server at a time using the recorded launch commands:

```bash
OLLAMA_HOST=127.0.0.1:19434 OLLAMA_MODELS="$OLLAMA_MODELS" \
OLLAMA_KEEP_ALIVE=-1 OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 \
OLLAMA_LOAD_TIMEOUT=10m HF_HOME="$LAB/hf-cache" TOKENIZERS_PARALLELISM=false \
/Applications/Ollama.app/Contents/Resources/ollama serve

HF_HOME="$LAB/hf-cache" TOKENIZERS_PARALLELISM=false \
"$LAB/Bonsai-demo/bin/mac/llama-server" \
  -m "$LAB/models/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
  --mmproj "$LAB/models/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-mmproj-BF16.gguf" \
  --host 127.0.0.1 --port 19435 -ngl 99 -fa on -c 4096 -np 1 --jinja \
  --reasoning off --chat-template-kwargs '{"enable_thinking":false}' \
  --cache-type-k f16 --cache-type-v f16 --cache-prompt --cache-ram 0 \
  --image-max-tokens 1024 --seed 42

HF_HOME="$LAB/hf-cache" TOKENIZERS_PARALLELISM=false \
"$LAB/venv/bin/python" -m mlx_vlm.server \
  --model "$LAB/models/Ternary-Bonsai-2-27B-mlx-2bit" \
  --host 127.0.0.1 --port 19436 --max-tokens 512 --max-kv-size 4096 \
  --vision-cache-size 20 --max-num-seqs 1
```


Send requests to `/v1/chat/completions` on the selected server, using the loaded
model ID returned by `/v1/models`. For each workload, repeat identical input
three times with thinking disabled, temperature 0, top_p 0.95, top_k 20,
min_p 0, max output 512 and seed 42 where supported. These are the experiment's
settings, not recommended defaults for every use case.

Example order text:

```text
주문 확정: 장미 레드나오미 3단, 리시안셔스 보라 12대, 카네이션 핑크 2단, 유칼립투스 5대. 취소한 해바라기 9대는 제외해 주세요.
```

Ask for `{"items":[{"name":"...","quantity":3,"unit":"단"}]}` with the
original names and units, without unit conversion or extra explanation. Expected
rows are 장미 레드나오미 / 3 / 단, 리시안셔스 보라 / 12 / 대,
카네이션 핑크 / 2 / 단, and 유칼립투스 / 5 / 대. The original prompt also
repeated the preservation/no-conversion rule 12 times as reference context.
For the tool variant, supply `extract_order` with a required `items` array of
objects requiring `name` (string), `quantity` (number), and `unit` (`단` or `대`),
and ask for one call. For vision, use an image containing the same four rows.

Measure HTTP-start to first observable output and total completion time; record
server-reported token counts, cache use and generation rate separately. Report
the first request and the median of repeats 2–3 separately. Use a fresh server
process per configuration, and record background load and memory conditions.
The original image and custom harness are not included in this report, so this
procedure describes a similar experiment, not an exact replay of the published
measurements. New inputs/images should be reported as a separate run.

## End-to-end serving

27 main requests: 3 configurations × 3 fixed workloads × 3 repetitions. Identical
raw system/user text and image bytes, thinking OFF, temperature 0, seed 42
requested where supported, top_p 0.95, top_k 20, min_p 0, max output 512 tokens.
Context/request cap 4096; inputs were much shorter, not a saturated-context test.

Order prompt count was 524 for all configurations. Tool counts were Ollama 855
versus Bonsai 860; image counts were 1401 versus 1402. Tool-schema rendering and
image tokenization differ despite identical raw input.

Cold means a new server process, **without OS filesystem-cache purge**. First
order is process-cold; first tool is a new prompt with resident weights; first
image includes its first vision processing. Warm is the median of repetitions
2–3, not a three-sample cold distribution. Readiness excludes baseline weights
but includes candidate preloading, so startup + first-order is reported separately.

TTFT is HTTP-start to first nonempty content/reasoning/tool delta. Buffered tool
responses on Ollama/MLX make this first observable tool output, not raw GPU TTFT.

| Configuration | Workload | First TTFT / total (s) | Warm TTFT / total (s) | Warm uncached input (t/s) | Warm generation (t/s) | Warm cached tokens |
|---|---|---:|---:|---:|---:|---:|
| Ollama NVFP4/MLX | Order | 11.16 / 13.87 | 0.17 / 3.03 | 83.4 | 52.1 | 519 |
| Ollama NVFP4/MLX | Tool | 7.12 / 7.12 | 2.58 / 2.58 | 74.1 | 47.9 | 850 |
| Ollama NVFP4/MLX | Image | 9.60 / 12.60 | 0.20 / 3.56 | 80.8 | 45.7 | 1396 |
| PQ2_0 Metal | Order | 3.18 / 5.48 | 0.16 / 2.62 | 28.3 | 29.3 | 520 |
| PQ2_0 Metal | Tool | 5.81 / 9.81 | 0.55 / 4.74 | 22.1 | 26.3 | 856 |
| PQ2_0 Metal | Image | 10.13 / 12.68 | 0.21 / 3.21 | 23.5 | 24.0 | 1398 |
| MLX 2-bit | Order | 6.40 / 10.77 | 6.57 / 10.79 | 81.0 | 17.1 | 0 |
| MLX 2-bit | Tool | 17.71 / 17.71 | 18.54 / 18.54 | 81.7 | 15.1 | 0 |
| MLX 2-bit | Image | 20.44 / 26.79 | 33.15 / 48.89 | 44.4 | 4.7 | 0 |

Ollama/PQ reused prefixes; this MLX server reported no cross-request reuse.
Ollama also automatically used speculative decoding/MTP; candidates had no draft
model. No matched-speculation/cache ablation was performed. Warm input rates
use new tokens only (`left / prompt_eval_duration` for Ollama, server timings
for candidates); cache-hit rates for a handful of tokens are not full-prefill rates.
Bonsai order/image outputs were 73 tokens
versus Ollama 152/157, so shorter PQ completion is not higher decode throughput.

## Loading, memory and swap

0.5-second sampling, sum of experiment-server process tree RSS and macOS
`proc_pid_rusage(v2)` physical footprint. Brief peaks may be missed, and shared
memory may be counted twice. **MLX GPU allocation may be omitted from RSS and
GGUF mmap pages from footprint. Do not infer RAM savings from either alone.**
Exact model-attributed total unified-memory peak was not measured.

| Configuration | Readiness (s) | Startup + first order TTFT / total (s) | Peak footprint (GiB) | Peak RSS (GiB) | System swap start / peak (GiB) | Peak swap increase (GiB) |
|---|---:|---:|---:|---:|---:|---:|
| Ollama NVFP4/MLX | 1.02 | 12.19 / 14.90 | 23.46 | 6.05 | 37.01 / 40.24 | 3.22 |
| PQ2_0 Metal | 2.04 | 5.21 / 7.52 | 2.26 | 8.85 | 37.19 / 37.19 | 0.00 |
| MLX 2-bit | 3.06 | 9.46 / 13.83 | 15.39 | 8.60 | 37.93 / 37.93 | 0.00 |

Swap is system-wide, with different starting states and retained calibration
swap. It cannot be attributed entirely to these models. MLX's own allocator peak
was 13.722 GB, a separate counter, not directly comparable with footprint/RSS.
GB file sizes use 10^9 bytes; GiB memory sizes use 2^30 bytes.

## Vision and quality observations

The PQ2_0 server used a 1024-token image cap; image processing was not matched
across backends. MLX's two warm image completions took **39.54 and 58.24 seconds**
(median 48.89 seconds). The cause was not isolated; this does not establish an
intrinsic 2-bit limitation.

| Configuration | Order: exact rows / strict JSON | Image: exact rows / strict JSON | Tool: native / exact arguments | Repetition / incomplete / thinking observed |
|---|---|---|---|---|
| Ollama NVFP4/MLX | 3/3 / 3/3 | 3/3 / 0/3 | 3/3 / 3/3 | 0 / 0 / 0 |
| PQ2_0 Metal | 3/3 / 3/3 | 3/3 / 3/3 | 3/3 / 3/3 | 0 / 0 / 0 |
| MLX 2-bit | 3/3 / 3/3 | 3/3 / 3/3 | 3/3 / 3/3 | 0 / 0 / 0 |

Every expected name/quantity/unit matched, with no extra rows. Ollama image JSON
was fenced; strict parsing failed while extracted values after fence removal
were correct. These are repetitions of one order/one image, not 27 distinct
tasks. General Korean/OCR quality, adversarial robustness and production
integration remain untested.

## Limitations

Only one order and one synthetic image were tested, with two warm repetitions.
Cache reuse, speculative decoding, output lengths, image processing and memory
measurement differ across configurations. Background load and thermal state
were uncontrolled. The results do not establish general speed or quality
superiority, RAM savings, long-context performance, or production readiness.

Thinking-on, standard PP512/TG128, idle-machine runs, matched cache/speculation,
real-document OCR, multistep tools and power consumption were not measured.

AI assistance was used for the experiment and report preparation.
