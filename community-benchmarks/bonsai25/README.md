# Bonsai 2.5 Community Benchmarks

Benchmark results submitted by the community running
[Bonsai 2.5 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2.5-27B-GGUF) on their own hardware.

## Results

### Bonsai-2.5-27B

| Band | Hardware | Backend | PP512 (t/s) | TG128 (t/s) | Details |
|------|----------|---------|------------:|------------:|---------|
| `PQ2_0-mtp` | Intel Arc Pro B50 16 GB | llama.cpp SYCL (Windows, PrismML fork prism-b10787) | 727 | 24.22 | [link](sycl-arc-pro-b50-16gb-windows.md) |

## Submitting

Same conventions as [bonsai2/README.md](../bonsai2/README.md): copy
[TEMPLATE-llama-cpp.md](../bonsai2/TEMPLATE-llama-cpp.md) to
`<backend>-<hardware>-<os>.md` in this folder (lowercase, dashes), benchmark the
`*-mtp` builds (the head is inert in plain llama-bench runs), and add a row per
tested packing here and in the [main index](../README.md). Keep llama-bench
throughput separate from server, MTP/speculative, long-context, and vision
observations, with their own commands and workloads.
