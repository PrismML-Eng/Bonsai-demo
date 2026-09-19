#!/usr/bin/env bash
# Honest speculative-decoding eval harness.
# Measures drafted throughput + acceptance and a no-drafter baseline on the SAME prompts,
# across workloads (code/math/reasoning/chat), for a sweep of n-max and p-min.
#
# The script writes <out_json>.partial while it runs and renames it to <out_json> at the
# end. A llama command that exits non-zero, or a metric that does not parse, stops the
# script with exit status 1. The partial file stays for inspection; <out_json> is not
# written and WROTE is not printed.
#
# Usage: spec_eval.sh <base_gguf> <drafter_gguf> <out_json> [n_predict] [nmax_list] [pmin_list]
set -euo pipefail
ROOT="${BONSAI_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
export LD_LIBRARY_PATH=$ROOT/bin/cuda
BASE="${1:?base gguf}"; DRAFTER="${2:?drafter gguf}"; OUT="${3:-/tmp/spec_eval.json}"
NPRED="${4:-256}"; NMAX_LIST="${5:-3 4 5 7}"; PMIN_LIST="${6:-0.0 0.4 0.6}"
CLI=$ROOT/bin/cuda/llama-cli; SPEC=$ROOT/bin/cuda/llama-speculative-simple
TMP="$OUT.partial"
declare -A P
P[code]='<|im_start|>user\nWrite a Python function merge_intervals(intervals) that merges overlapping intervals and returns the sorted list. Include a docstring and three assert-based tests.<|im_end|>\n<|im_start|>assistant\n'
P[math]='<|im_start|>user\nA tank holds 240 liters. Pipe A fills it in 12 minutes, pipe B drains it in 20 minutes. Both open at t=0. How long until the tank is full? Show each step.<|im_end|>\n<|im_start|>assistant\n'
P[reason]='<|im_start|>user\nFive people finish a race. Ana is not last. Ben beat Cara. Dan is right after Ana. Cara is third. Give the finishing order and your reasoning.<|im_end|>\n<|im_start|>assistant\n'
P[chat]='<|im_start|>user\nExplain in one short paragraph why memory bandwidth, not compute, limits token generation speed for large language models on consumer GPUs.<|im_end|>\n<|im_start|>assistant\n'

# die <message>: report the failure and exit 1. $OUT is not written.
die(){ echo "FAIL: $*" >&2; echo "FAIL: partial results stay in $TMP" >&2; exit 1; }
# require <run> <metric> <value>: fail when the metric did not parse
require(){ [ -n "$3" ] || die "$1: metric '$2' not found in the llama output"; }
# field <text> <line regex> <field regex> [<tail regex>]: the last match, or empty
field(){
  if [ $# -ge 4 ]; then
    printf '%s\n' "$1" | grep -E "$2" | grep -oE "$3" | tail -n 1 | grep -oE "$4" || true
  else
    printf '%s\n' "$1" | grep -oE "$2" | grep -oE "$3" | tail -n 1 || true
  fi
}

echo "[" > "$TMP"; first=1
emit(){ if [ "$first" -eq 1 ]; then first=0; else echo "," >> "$TMP"; fi; echo "  $1" >> "$TMP"; }
for w in code math reason chat; do
  # baseline: no drafter
  rc=0; o=$("$CLI" -m "$BASE" -fa on -ngl 99 -c 4096 -n "$NPRED" --temp 0 -e -p "${P[$w]}" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || die "baseline $w: llama-cli exit $rc: $(printf '%s\n' "$o" | tail -n 3)"
  b=$(field "$o" 'eval time' '[0-9.]+ tokens per second' '^[0-9.]+')
  require "baseline $w" "tokens per second" "$b"
  emit "{\"workload\":\"$w\",\"mode\":\"baseline\",\"tok_s\":$b}"
  echo "baseline $w: $b t/s"
  for K in $NMAX_LIST; do for PM in $PMIN_LIST; do
    rc=0; o=$("$SPEC" -m "$BASE" -md "$DRAFTER" --spec-type draft-dspark --spec-draft-n-max "$K" --spec-draft-p-min "$PM" -fa on -ngl 99 -ngld 999 -c 4096 -n "$NPRED" --temp 0 -e -p "${P[$w]}" 2>&1) || rc=$?
    [ "$rc" -eq 0 ] || die "spec $w K=$K p=$PM: llama-speculative-simple exit $rc: $(printf '%s\n' "$o" | tail -n 3)"
    spd=$(field "$o" 'decoded[[:space:]]+[0-9]+ tokens in[[:space:]]+[0-9.]+ seconds, speed:[[:space:]]+[0-9.]+' '[0-9.]+$')
    acc=$(field "$o" 'accept[[:space:]]+=[[:space:]]+[0-9.]+' '[0-9.]+')
    na=$(field "$o" 'n_accept[[:space:]]+=[[:space:]]+[0-9]+' '[0-9]+')
    nd=$(field "$o" 'n_drafted[[:space:]]+=[[:space:]]+[0-9]+' '[0-9]+')
    run="spec $w K=$K p=$PM"
    require "$run" "speed" "$spd"; require "$run" "accept" "$acc"
    require "$run" "n_accept" "$na"; require "$run" "n_drafted" "$nd"
    emit "{\"workload\":\"$w\",\"mode\":\"spec\",\"n_max\":$K,\"p_min\":$PM,\"tok_s\":$spd,\"accept_pct\":$acc,\"n_accept\":$na,\"n_drafted\":$nd}"
    echo "$run: $spd t/s, acc $acc%"
  done; done
done
echo "]" >> "$TMP"
mv "$TMP" "$OUT"
echo "WROTE $OUT"
