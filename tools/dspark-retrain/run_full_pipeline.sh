#!/usr/bin/env bash
# Full DSpark drafter pipeline: train (CUDA docker) -> two-step GGUF convert -> Q4_K_M -> sanity.
# Encodes the path that works. The one-shot convert_safetensors_to_dflash.py fails on a
# donor-tokenizer KV type-tag bug in every environment; do not use it.
#
# Usage: run_full_pipeline.sh <tag> <feats_dir> [epochs=2] [batch_size=2] [lr=1e-4]
# Example: run_full_pipeline.sh full1 tools/dspark-retrain/feats 2
# Env:  BONSAI_ROOT     the Bonsai-demo checkout (default: two levels above this script)
#       DSPARK_TRAINER  command that runs the trainer (default: the CUDA container below;
#                       set DSPARK_TRAINER=python3 to use the current Python environment)
set -u
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
TRAINER="${DSPARK_TRAINER:-sudo docker run --rm --gpus all -v $ROOT:$ROOT -v $FEATS:$FEATS bonsai/dflash-trainer:latest python3}"
mkdir -p "$V2/logs" "$MD"
sz(){ stat -c%s "$1" 2>/dev/null || echo 0; }
need(){ if [ "$(sz "$1")" -lt "$2" ]; then echo "FAIL: $3 -> $1 is $(sz "$1") bytes"; exit 1; fi; }

echo "== [1/5] TRAIN tag=$TAG feats=$FEATS epochs=$EPOCHS bs=$BS lr=$LR  (log: $LOG)"
$TRAINER -u $V2/train_dspark_v2.py \
  --feats-dir "$FEATS" --teacher-dir $V2/teacher \
  --warm-start $ROOT/models/qwen38-dspark/model.safetensors \
  --out "$CK" --epochs "$EPOCHS" --batch-size "$BS" --lr "$LR" \
  --num-anchors 512 --chunk-blocks 64 --log-every 10 > "$LOG" 2>&1
echo "train exit: $?"
sudo chown "$(id -u):$(id -g)" "$CK" "$MD"/bonsai2_dspark_${TAG}*.safetensors 2>/dev/null; chmod 0644 "$CK" 2>/dev/null
need "$CK" 1000000000 "train checkpoint"
grep -E '^ep .*step' "$LOG" | tail -3

echo "== [2/5] CONVERT step 1: safetensors -> dspark raw GGUF"
rm -f "$RAW"
python3 -c "
import sys; sys.path.insert(0,'$V2')
from convert_safetensors_to_dspark import convert_to_dspark
convert_to_dspark('$CK','$RAW')" > "$V2/logs/conv1_${TAG}.log" 2>&1
echo "step1 exit: $?"; need "$RAW" 1000000000 "dspark raw gguf"

echo "== [3/5] CONVERT step 2: dspark -> dflash (+donor tokenizer, drop shared tensors)"
rm -f "$CONV"
python3 $ROOT/llama.cpp/gguf-py/gguf/scripts/gguf_dspark_to_dflash.py "$RAW" "$DONOR" "$CONV" --drop-shared-tensors > "$V2/logs/conv2_${TAG}.log" 2>&1
echo "step2 exit: $?"; need "$CONV" 1000000000 "dflash conv gguf"

echo "== [4/5] QUANTIZE -> Q4_K_M"
rm -f "$Q"
LD_LIBRARY_PATH=$ROOT/bin/cuda $ROOT/bin/cuda/llama-quantize "$CONV" "$Q" Q4_K_M > "$V2/logs/quant_${TAG}.log" 2>&1
echo "quantize exit: $?"; need "$Q" 500000000 "Q4_K_M gguf"

echo "== [5/5] SANITY"
LD_LIBRARY_PATH=$ROOT/bin/cuda $ROOT/bin/cuda/llama-gguf "$Q" r n 2>/dev/null | grep -iE 'general.architecture|dflash.block_size|dflash.target_layers|mask_token' | head -4
echo "DONE: $Q ($(sz "$Q") bytes)"
echo "Eval (idle GPU): $V2/eval/spec_eval.sh $DONOR $Q /tmp/eval_${TAG}.json 200 '4 5 7' '0.0'"
