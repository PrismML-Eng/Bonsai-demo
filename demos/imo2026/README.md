# IMO 2026: Bonsai 2 27B and two other open models (131k thinking budget)

This folder holds the final answers that three open-weight models wrote for the six problems of the 2026 International Mathematical Olympiad. Each problem got a single attempt per model with a 131,072-token thinking budget. The answers are published exactly as generated, with no edits. Thinking traces are not included.

| Model | Weights | Folder |
|---|---|---|
| Bonsai 2 27B | [`prism-ml/Ternary-Bonsai-2-27B-gguf`](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf), `Ternary-Bonsai-2-27B-PQ2_0.gguf` | [`solutions/bonsai-2-27b-pq2_0`](solutions/bonsai-2-27b-pq2_0) |
| Gemma 4 12B QAT | [`google/gemma-4-12B-it-qat-q4_0-gguf`](https://huggingface.co/google/gemma-4-12B-it-qat-q4_0-gguf), `gemma-4-12b-it-qat-q4_0.gguf` | [`solutions/gemma-4-12b-it-qat-q4_0`](solutions/gemma-4-12b-it-qat-q4_0) |
| Qwen3.8 27B | [`ggml-org/Qwen3.8-27B-GGUF`](https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF), `Qwen3.8-27B-BF16.gguf` | [`solutions/qwen3.8-27b-bf16`](solutions/qwen3.8-27b-bf16) |

Each model folder has `p1.md` to `p6.md`, which are the answers as streamed. It also has `runs.json`, which records each run's finish reason, token counts, generation time and a SHA-256 of the answer. All 18 runs stopped naturally (`finish_reason: stop`), and none hit the output cap.

The problem statements are in [`reproduce/problems.json`](reproduce/problems.json), transcribed from the [official English paper](https://www.imo-official.org/problems/2026/).

## Results

Out of 42 (six problems, 7 points each), one attempt per problem:

| Model | Weights | Score | P1 | P2 | P3 | P4 | P5 | P6 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Qwen3.8 27B | BF16, 53.8 GB | 22 | 7 | 0 | 1 | 7 | 7 | 0 |
| Bonsai 2 27B | PQ2_0, 7.2 GB | 21 | 7 | 0 | 0 | 7 | 7 | 0 |
| Gemma 4 12B QAT | Q4_0, 7.0 GB | 7 | 7 | 0 | 0 | 0 | 0 | 0 |

These are our own grades of the final answers against [Evan Chen's IMO 2026 solution notes](https://web.evanchen.cc/exams/IMO-2026-notes.pdf), not official marks; the official marking schemes are not public. Every model ran on the same Prism llama.cpp runtime with pinned weights, on one NVIDIA H200 GPU per problem.

## Reproducing the runs

### 1. Get the runtime and weights

Use the Prism llama.cpp release [`prism-b10709-9a9394a`](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10709-9a9394a). The runs used `llama-prism-b10709-9a9394a-bin-linux-cuda-12.8-x64.tar.gz`, whose SHA-256 is `8aec67eb023b251712c7e6490f367b5671bf587eced1436a9b85f4a90c3b7d3d`. This fork supports the `reasoning_budget_tokens` request field that enforces the thinking budget.

Download the weights at these exact revisions:

| File | Revision | SHA-256 |
|---|---|---|
| `Ternary-Bonsai-2-27B-PQ2_0.gguf` | `6ed5e12bf84b7a63069882c91dd9e9218647d17b` | `3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1` |
| `gemma-4-12b-it-qat-q4_0.gguf` | `29d097773436b69ff9feafd636ab4cf873786537` | `93567e57a8fe10b23569b9d9ec38cd005deedf71e29477c421a4b83f418a538b` |
| `Qwen3.8-27B-BF16.gguf` | `efbb3b1f70a21d97fd4495240648405f7228554f` | `222e1905eef352bae7c06f3d17dd9385bcb2ee96f435573d18457c7ad1002894` |

```bash
cd demos/imo2026
huggingface-cli download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-PQ2_0.gguf --revision 6ed5e12bf84b7a63069882c91dd9e9218647d17b --local-dir models
huggingface-cli download google/gemma-4-12B-it-qat-q4_0-gguf gemma-4-12b-it-qat-q4_0.gguf --revision 29d097773436b69ff9feafd636ab4cf873786537 --local-dir models
huggingface-cli download ggml-org/Qwen3.8-27B-GGUF Qwen3.8-27B-BF16.gguf --revision efbb3b1f70a21d97fd4495240648405f7228554f --local-dir models
```

### 2. Run a problem

[`reproduce/run_problem.py`](reproduce/run_problem.py) needs only the Python standard library. It starts `llama-server`, confirms the thinking budget is enforced with a short test request, sends the problem, and writes `thinking.txt`, `answer.md`, `request.json` and `result.json` to `results/<model>/p<N>/`.

```bash
python3 reproduce/run_problem.py --model bonsai --problem 1 \
  --server ./llama-prism-b10709-9a9394a/llama-server \
  --model-file models/Ternary-Bonsai-2-27B-PQ2_0.gguf
```

Use `--model gemma` or `--model qwen` with the matching weights file. Run each problem in a fresh server; the script starts and stops its own server every time.

### Settings used

| Setting | Value |
|---|---|
| System prompt | `You are a helpful assistant.` |
| User prompt | `Solve the following IMO 2026 problem. Give a complete, rigorous proof.` + a blank line + `Problem N. <statement>` |
| Thinking | Bonsai and Qwen: native `reasoning_effort: xhigh`. Gemma: native thinking on, since it has no effort levels. |
| Thinking budget | 131,072 tokens (`reasoning_budget_tokens`) |
| Max output tokens | 147,456, i.e. the thinking budget plus 16,384 for the answer |
| Context | 196,608 tokens |
| Sampling | temperature 1.0, top-p 0.95, top-k 20, min-p 0, repeat penalty 1.0, presence penalty 0, seed 42 |
| Server | `-ngl 99 -fa on -np 1 -ctk f16 -ctv f16 --jinja --reasoning-format deepseek --no-context-shift` |
| Hardware | one NVIDIA H200 per problem |
| Attempts | one per problem, with no retries or selection |

Note on exact matching: the seed is fixed, but GPU floating-point results can differ across GPU models, drivers and CUDA versions. Output that is byte-for-byte identical is only expected on matching hardware and software. Use the `answer_sha256` values in `runs.json` to check.

## License

The model answers in [`solutions/`](solutions) are released under [CC BY 4.0](LICENSE-CC-BY-4.0). The reproduction script is covered by this repository's [Apache 2.0 license](../../LICENSE). The models themselves are under their own licenses; see each Hugging Face model page.
