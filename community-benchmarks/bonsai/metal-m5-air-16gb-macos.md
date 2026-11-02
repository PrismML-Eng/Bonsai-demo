# Apple M5 (MacBook Air, 16 GB) — Metal — Bonsai-27B (1-bit)

## Summary

Base M5 Air, 16 GB unified. Upstream llama.cpp **b11630** (no fork needed — `Q1_0` is fully merged
upstream), `-ngl 99 -fa 1 -p 512 -n 128 -r 3`:

| file | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| `Q1_0` (3.53 GiB) | 84.18 ± 0.36 | 11.54 ± 0.08 |

Decode 1.7x the same laptop's ternary rows; the 27B sits in 3.53 GiB — twice over, with KV headroom.

## Configuration

- Command: `LD_LIBRARY_PATH=./bin/b11630 ./bin/b11630/llama-bench -m Bonsai-27B-Q1_0.gguf -ngl 99 -fa 1 -p 512 -n 128 -r 3` (build 6868a52cb).
- File: `prism-ml/Bonsai-27B-gguf` — `Bonsai-27B-Q1_0.gguf` sha256 `17ef842e47450caeb8eaa3ebfbbab5d2f2278b62b79be107985fb69a2f819aa0`.
- 27B only on this box (8B/4B/1.7B skipped: passive cooling makes long sweeps thermally noisy).

## Notes

- The whole point of 1-bit: a 27B-class model that fits *twice* in 16 GB with room for context, on upstream llama.cpp, in a $999 laptop.

## Hardware

```
Apple M5 (base), 16 GB unified, Metal4/tensor-API
```
