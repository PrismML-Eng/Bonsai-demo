#!/usr/bin/env bash
# Full DSpark drafter pipeline: train -> two-step GGUF convert -> Q4_K_M -> sanity.
# Encodes the path that works. The one-shot convert_safetensors_to_dflash.py fails on a
# donor-tokenizer KV type-tag bug in every environment; do not use it.
#
# The script stops at the first stage that exits non-zero or that writes a file below
# the expected size. Each stage removes its output file before it starts, so a stale
# file from an earlier run can not pass the size check.
#
# Usage: run_full_pipeline.sh <tag> <feats_dir> [epochs=2] [batch_size=2] [lr=1e-4]
# Example: run_full_pipeline.sh full1 tools/dspark-retrain/feats 2
# Env:  BONSAI_ROOT     the Bonsai-demo checkout (default: two levels above this script)
#       DSPARK_TRAINER  command that runs the trainer (default: python3, a Python
#                       environment where torch.cuda.is_available() is true).
#                       Example for a CUDA container (the checkout and the feats
#                       directory must be mounted at the same paths):
#                       DSPARK_TRAINER="sudo docker run --rm --gpus all -v $BONSAI_ROOT:$BONSAI_ROOT -v <feats_dir>:<feats_dir> <image> python3"
set -euo pipefail
TAG="${1:?tag (e.g. full1)}"; FEATS="${2:?feats dir}"; EPOCHS="${3:-2}"; BS="${4:-2}"; LR="${5:-1e-4}"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="${BONSAI_ROOT:-$(cd "$HERE/../.." && pwd)}"
export BONSAI_ROOT="$ROOT"
FEATS=$(cd "$FEATS" && pwd)
V2=$HERE
MD=$ROOT/models/bonsai2-dspark
DONOR=$ROOT/models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf
CK=$MD/bonsai2_dspark_${TAG}.safetensors
RAW=$MD/bonsai2-dspark-${TAG}-dspark-raw.gguf
CONV=$MD/bonsai2-dspark-${TAG}-conv.gguf
Q=$MD/bonsai2-dspark-${TAG}-Q4_K_M.gguf
LOG=$V2/logs/train_${TAG}.log
TRAINER="${DSPARK_TRAINER:-python3}"
mkdir -p "$V2/logs" "$MD"
sz(){ stat -c%s "$1" 2>/dev/null || echo 0; }
need(){ if [ "$(sz "$1")" -lt "$2" ]; then echo "FAIL: $3 -> $1 is $(sz "$1") bytes"; exit 1; fi; }
# stage <name> <exit status> <log>: print the status; on failure show the log tail and exit 1
stage(){
  echo "$1 exit: $2"
  if [ "$2" -ne 0 ]; then echo "FAIL: $1 exit $2 (log: $3)"; tail -n 20 "$3" 2>/dev/null || true; exit 1; fi
}

echo "== [1/5] TRAIN tag=$TAG feats=$FEATS epochs=$EPOCHS bs=$BS lr=$LR  (log: $LOG)"
rm -f "$CK"
rc=0
$TRAINER -u "$V2/train_dspark_v2.py" \
  --feats-dir "$FEATS" --teacher-dir "$V2/teacher" \
  --warm-start "$ROOT/models/qwen38-dspark/model.safetensors" \
  --out "$CK" --epochs "$EPOCHS" --batch-size "$BS" --lr "$LR" \
  --num-anchors 512 --chunk-blocks 64 --log-every 10 > "$LOG" 2>&1 || rc=$?
stage train "$rc" "$LOG"
# optional: a container trainer writes the checkpoints as root; take ownership
if [ -e "$CK" ] && [ ! -O "$CK" ]; then
  sudo chown "$(id -u):$(id -g)" "$MD"/bonsai2_dspark_${TAG}*.safetensors || true
fi
chmod 0644 "$CK" 2>/dev/null || true
need "$CK" 1000000000 "train checkpoint"
grep -E '^ep .*step' "$LOG" | tail -n 3 || true

echo "== [2/5] CONVERT step 1: safetensors -> dspark raw GGUF"
rm -f "$RAW"
rc=0
python3 "$V2/convert_safetensors_to_dspark.py" "$CK" "$RAW" > "$V2/logs/conv1_${TAG}.log" 2>&1 || rc=$?
stage step1 "$rc" "$V2/logs/conv1_${TAG}.log"; need "$RAW" 1000000000 "dspark raw gguf"

echo "== [3/5] CONVERT step 2: dspark -> dflash (+donor tokenizer, drop shared tensors)"
rm -f "$CONV"
rc=0
python3 "$ROOT/llama.cpp/gguf-py/gguf/scripts/gguf_dspark_to_dflash.py" "$RAW" "$DONOR" "$CONV" --drop-shared-tensors > "$V2/logs/conv2_${TAG}.log" 2>&1 || rc=$?
stage step2 "$rc" "$V2/logs/conv2_${TAG}.log"; need "$CONV" 1000000000 "dflash conv gguf"

echo "== [4/5] QUANTIZE -> Q4_K_M"
rm -f "$Q"
rc=0
LD_LIBRARY_PATH=$ROOT/bin/cuda "$ROOT/bin/cuda/llama-quantize" "$CONV" "$Q" Q4_K_M > "$V2/logs/quant_${TAG}.log" 2>&1 || rc=$?
stage quantize "$rc" "$V2/logs/quant_${TAG}.log"; need "$Q" 500000000 "Q4_K_M gguf"

echo "== [5/5] SANITY"
SAN=$V2/logs/sanity_${TAG}.log
rc=0
LD_LIBRARY_PATH=$ROOT/bin/cuda "$ROOT/bin/cuda/llama-gguf" "$Q" r n > "$SAN" 2>&1 || rc=$?
stage sanity "$rc" "$SAN"
grep -iE 'general.architecture|dflash.block_size|dflash.target_layers|mask_token' "$SAN" | head -n 4 || true
echo "DONE: $Q ($(sz "$Q") bytes)"
echo "Eval (idle GPU): $V2/eval/spec_eval.sh $DONOR $Q /tmp/eval_${TAG}.json 200 '4 5 7' '0.0'"
