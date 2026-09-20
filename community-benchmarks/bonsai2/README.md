# Bonsai 2 Community Benchmarks

Community results for **Bonsai 2 27B**, the current generation and the default
installed by this demo. These results are separate from the previous
[Ternary-Bonsai](../ternary-bonsai/) generation.

The available formats are GGUF (`PQ2_0` and `PTQ1_0`) and MLX (2-bit). For
llama.cpp runs, use the Prism fork binaries described in the
[repository guide](../../AGENTS.md); stock llama.cpp does not support these
Bonsai 2 GGUF bands.

## Results

### HTTP serving comparisons

These reports measure complete API requests, including time to first token and
response latency. Their output-throughput and derived decode rates are not
`llama-bench` PP512/TG128 measurements.

- [Bonsai 2 27B PQ2_0 — Apple M1 Max 32 GB, Metal: Ferrum and Prism llama-server](metal-m1-max-32gb-macos-http.md)

## How to Submit

1. From the repository root, run `BONSAI_FAMILY=bonsai2 ./setup.sh` to download
   models and binaries.
2. Copy the submission template below into a new file in this folder. Use
   **`<backend>-<hardware>-<os>.md`** for `llama-bench` or MLX benchmarks, or
   **`<backend>-<hardware>-<os>-http.md`** for HTTP serving measurements.
   Use lowercase and dashes, for example `metal-m1-max-32gb-macos-http.md`.
3. Fill in the exact model band, runtime version, commands, configuration,
   workload, and results. For comparisons, report each runtime's configuration
   and errors, and state intentional differences. Keep HTTP measurements
   separate from `llama-bench` results; do not substitute HTTP output throughput
   for TG128.
4. Link the report here and in the appropriate section of the
   [community index](../README.md), then open a PR.

### Submission template

```markdown
# <Hardware> — Bonsai 2 27B <format> — <backend / measurement type>

## Hardware and software

- CPU, GPU, memory, OS, power mode, and background load:
- Runtime and benchmark client versions / commits:
- Model repository, revision, filename, and precision:

## Commands and workload

- Exact server / benchmark commands and relevant configuration:
- Dataset or prompt construction, input / output lengths, and concurrency:
- Sampling, thinking, context, cache, and speculative-decoding settings:
- Warmups, measured repetitions, and measurement order:

## Results

- Individual observations and summary statistics with units:
- For llama-bench: retain its model / backend / test / throughput output.
- For HTTP: report TTFT, end-to-end latency, actual usage-token counts,
  completed / failed requests, and formulas for any derived rates.

## Validation and limitations

- Output / protocol checks, errors, and retained evidence:
- Configuration differences, uncertainty, and limits on conclusions:
```
