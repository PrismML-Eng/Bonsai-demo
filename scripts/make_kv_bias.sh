#!/bin/sh
# Build a model-specific K-cache mean-centering bias GGUF for the optional
# 4-bit KV cache (BONSAI_KV4=1 in start_llama_server.sh). The bias reduces
# Q4_0 quantization error at zero decode-time cost; without it the 4-bit KV
# cache still runs, just with slightly lower quality.
#
# Usage:
#   ./scripts/make_kv_bias.sh                  (built-in tiny synthetic corpus)
#   ./scripts/make_kv_bias.sh my_corpus.txt    (your own calibration text)
#
# Calibration does not need much data. The built-in corpus is a small synthetic
# example; for best results pass a text file representative of your workload.
# The bias is model-specific: re-run after switching BONSAI_FAMILY/BONSAI_MODEL.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"
assert_gguf_downloaded

# ── Find the target model: select exactly the demo quant for the family ──
MODEL=""
for _m in $GGUF_MODEL_DIR/$GGUF_QUANT_PATTERN; do
    [ -f "$_m" ] || continue
    case "$_m" in *mmproj*|*dspark*|*kv-bias*) continue ;; esac
    MODEL="$DEMO_DIR/$_m" && break
done
if [ -z "$MODEL" ]; then
    err "No ${GGUF_QUANT_PATTERN} model found in ${GGUF_MODEL_DIR}/."
    exit 1
fi

# ── Find the calibration tool ──
BIN=""
for _d in bin/mac bin/cuda bin/rocm bin/hip bin/vulkan bin/cpu llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
    [ -f "$DEMO_DIR/$_d/llama-kv-mean-center" ] && BIN="$DEMO_DIR/$_d/llama-kv-mean-center" && break
done
if [ -z "$BIN" ]; then
    err "llama-kv-mean-center not found. Run ./scripts/download_binaries.sh (or a build_*.sh) first."
    exit 1
fi
BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ── Calibration corpus: user-provided file, or a tiny built-in example ──
CORPUS="${1:-}"
_tmp_corpus=""
if [ -n "$CORPUS" ]; then
    if [ ! -f "$CORPUS" ]; then
        err "Calibration file not found: $CORPUS"
        exit 1
    fi
    info "Calibrating on: $CORPUS"
else
    _tmp_corpus="$(mktemp)"
    CORPUS="$_tmp_corpus"
    cat > "$CORPUS" <<'EOF'
The quick brown fox jumps over the lazy dog while the seasons change from a
mild spring into a hot, humid summer. Rivers carve valleys over thousands of
years, and glaciers grind mountains into gravel that settles on the sea floor.

def fibonacci(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

for i in range(10):
    print(i, fibonacci(i))

Quarterly revenue grew 12.4 percent to 48.3 million, while operating margin
compressed from 21.7 percent to 19.2 percent on higher logistics costs. The
board approved a 250 million buyback and guided full-year EPS to 3.10-3.25.

To integrate x squared times sin(x), apply integration by parts twice:
let u = x^2 and dv = sin(x) dx, giving -x^2 cos(x) + 2x sin(x) + 2 cos(x) + C.

SELECT region, SUM(quantity * unit_price) AS revenue
FROM orders JOIN order_items ON orders.id = order_items.order_id
GROUP BY region ORDER BY revenue DESC;

Die Katze schlief den ganzen Nachmittag auf dem warmen Fensterbrett, wahrend
draussen ein leichter Regen fiel. El tren llego a la estacion con veinte
minutos de retraso y los pasajeros esperaban bajo los paraguas.

The recipe calls for two cups of flour, one teaspoon of baking soda, half a
teaspoon of salt, and three quarters of a cup of unsalted butter, creamed with
brown sugar until fluffy, then folded with chocolate chips and baked at 350 F
for eleven minutes until the edges turn golden but the centers stay soft.

{"order_id": 48213, "customer": "Meridian Grid AG", "items": [{"sku": "TE-ACC",
"quantity": 4, "unit_price": 4200.0}, {"sku": "PS-12", "quantity": 1,
"unit_price": 1200.0}], "status": "completed", "shipped": "2025-06-14"}

$ git status --short
 M scripts/start_server.sh
?? notes/meeting-2025-06-02.md
$ grep -rn "timeout" src/network/ | head -3
src/network/client.py:44: DEFAULT_TIMEOUT = 30
src/network/client.py:81: raise TimeoutError(f"no response after {timeout}s")

Photosynthesis converts carbon dioxide and water into glucose and oxygen using
light energy absorbed by chlorophyll. The light-dependent reactions occur in
the thylakoid membranes and produce ATP and NADPH, which the Calvin cycle then
consumes in the stroma to fix carbon into three-carbon sugars. Limiting
factors include light intensity, carbon dioxide concentration, and temperature.

"Could you check whether the backup job finished?" she asked. "It finished at
half past two," he replied, "but the log shows four retries on the second
volume, so we should verify the checksums before rotating the tapes tonight."

Steps to reproduce the issue: first, open the settings panel and disable the
hardware acceleration toggle. Second, restart the application while holding
the shift key. Third, load any project larger than two gigabytes and switch
the preview quality to full. The frame rate counter should now drop sharply,
and the memory graph will climb until the process is terminated by the system.

The committee reviewed seventeen proposals over three sessions and shortlisted
five for funding: coastal erosion monitoring with low-cost buoys, a longitudinal
study of adolescent sleep patterns, open-source firmware for insulin pumps,
drought-resistant wheat trials across four climate zones, and a survey of
medieval trade routes reconstructed from shipwreck cargo manifests. Reviewers
praised methodological rigor but asked two teams to clarify their power
calculations and preregistration plans before the final decision in October.
EOF
    info "Calibrating on the built-in synthetic example corpus."
    echo "  For best results pass your own text: ./scripts/make_kv_bias.sh my_corpus.txt"
fi

OUT="$DEMO_DIR/$GGUF_MODEL_DIR/${BONSAI_DISPLAY}-kv-bias.gguf"
NGL=$(bonsai_llama_ngl)

step "Computing K-cache mean-centering bias for ${BONSAI_DISPLAY} ..."
"$BIN" -m "$MODEL" -f "$CORPUS" -o "$OUT" -ngl "$NGL" -c 512

[ -n "$_tmp_corpus" ] && rm -f "$_tmp_corpus"

info "Bias written to $OUT"
echo ""
echo "  Use it with the 4-bit KV cache (picked up automatically):"
echo "    BONSAI_KV4=1 ./scripts/start_llama_server.sh"
