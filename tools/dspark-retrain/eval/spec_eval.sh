#!/usr/bin/env bash
# Honest speculative-decoding eval harness.
# Measures drafted throughput + acceptance and a no-drafter baseline on the SAME prompts,
# across workloads (code/math/reasoning/chat), for a sweep of n-max and p-min.
# Usage: spec_eval.sh <base_gguf> <drafter_gguf> <out_json> [n_predict] [nmax_list] [pmin_list]
set -u
ROOT="${BONSAI_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
export LD_LIBRARY_PATH=$ROOT/bin/cuda
BASE="${1:?base gguf}"; DRAFTER="${2:?drafter gguf}"; OUT="${3:-/tmp/spec_eval.json}"
NPRED="${4:-256}"; NMAX_LIST="${5:-3 4 5 7}"; PMIN_LIST="${6:-0.0 0.4 0.6}"
CLI=$ROOT/bin/cuda/llama-cli; SPEC=$ROOT/bin/cuda/llama-speculative-simple
declare -A P
P[code]='<|im_start|>user\nWrite a Python function merge_intervals(intervals) that merges overlapping intervals and returns the sorted list. Include a docstring and three assert-based tests.<|im_end|>\n<|im_start|>assistant\n'
P[math]='<|im_start|>user\nA tank holds 240 liters. Pipe A fills it in 12 minutes, pipe B drains it in 20 minutes. Both open at t=0. How long until the tank is full? Show each step.<|im_end|>\n<|im_start|>assistant\n'
P[reason]='<|im_start|>user\nFive people finish a race. Ana is not last. Ben beat Cara. Dan is right after Ana. Cara is third. Give the finishing order and your reasoning.<|im_end|>\n<|im_start|>assistant\n'
P[chat]='<|im_start|>user\nExplain in one short paragraph why memory bandwidth, not compute, limits token generation speed for large language models on consumer GPUs.<|im_end|>\n<|im_start|>assistant\n'
ts(){ date +%s.%N; }
echo "[" > "$OUT"; first=1
emit(){ [ $first -eq 1 ] && first=0 || echo "," >> "$OUT"; echo "  $1" >> "$OUT"; }
for w in code math reason chat; do
  # baseline: no drafter
  b=$($CLI -m "$BASE" -fa on -ngl 99 -c 4096 -n $NPRED --temp 0 -e -p "${P[$w]}" 2>&1 | grep -E 'eval time' | grep -oE '[0-9.]+ tokens per second' | tail -1 | grep -oE '^[0-9.]+')
  emit "{\"workload\":\"$w\",\"mode\":\"baseline\",\"tok_s\":${b:-null}}"
  echo "baseline $w: ${b:-?} t/s"
  for K in $NMAX_LIST; do for PM in $PMIN_LIST; do
    o=$($SPEC -m "$BASE" -md "$DRAFTER" --spec-type draft-dspark --spec-draft-n-max $K --spec-draft-p-min $PM -fa on -ngl 99 -ngld 999 -c 4096 -n $NPRED --temp 0 -e -p "${P[$w]}" 2>&1)
    spd=$(echo "$o" | grep -oE 'decoded[[:space:]]+[0-9]+ tokens in[[:space:]]+[0-9.]+ seconds, speed:[[:space:]]+[0-9.]+' | grep -oE '[0-9.]+$' | tail -1)
    acc=$(echo "$o" | grep -oE 'accept[[:space:]]+=[[:space:]]+[0-9.]+' | grep -oE '[0-9.]+' | tail -1)
    na=$(echo "$o" | grep -oE 'n_accept[[:space:]]+=[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | tail -1)
    nd=$(echo "$o" | grep -oE 'n_drafted[[:space:]]+=[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | tail -1)
    emit "{\"workload\":\"$w\",\"mode\":\"spec\",\"n_max\":$K,\"p_min\":$PM,\"tok_s\":${spd:-null},\"accept_pct\":${acc:-null},\"n_accept\":${na:-null},\"n_drafted\":${nd:-null}}"
    echo "spec $w K=$K p=$PM: ${spd:-?} t/s, acc ${acc:-?}%"
  done; done
done
echo "]" >> "$OUT"
echo "WROTE $OUT"
