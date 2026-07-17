#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd -P)"
PROJECT="$REPO_ROOT/mobile/BonsaiMobile.xcodeproj"
VALIDATOR="$SCRIPT_DIR/validate_device_evidence.py"
INSPECTION_VALIDATOR="$SCRIPT_DIR/validate_external_inspection.py"
MODEL="" SCENARIOS="" DESTINATION="" DEVICE_ID="" MODEL_DIR="" MODEL_REVISION=""
NETWORK_CAPTURE="" SOURCE_AUDIT="" DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: run_device_evidence.sh OPTIONS
  --model oneBit27B|ternary27B
  --scenarios text,thinking,cancel,calculator,date,device,notes,vision-fast,vision-full,offline,load-unload
  --model-revision 40-lowercase-hex
  --network-capture PATH      Immutable external network-inspection artifact
  --source-audit PATH         Immutable revision-linked network-boundary audit
  --device-id UDID            Unique physical iOS destination; never published
  --destination platform=macOS
  --model-dir PATH            macOS only; iOS consumes Models/installed/<modelID>
  --dry-run
  --help

The test harness generates the JSON as an xcresult attachment. Caller-authored evidence is never
accepted. Actual runs require a clean tree and preserve the unique xcresult under docs/mobile/evidence/results.
EOF
}

while (($#)); do
  case "$1" in
    --model|--scenarios|--destination|--device-id|--model-dir|--model-revision|--network-capture|--source-audit)
      (($# >= 2)) || { echo "missing value for $1" >&2; exit 64; }
      case "$1" in
        --model) MODEL="$2" ;; --scenarios) SCENARIOS="$2" ;;
        --destination) DESTINATION="$2" ;; --device-id) DEVICE_ID="$2" ;;
        --model-dir) MODEL_DIR="$2" ;; --model-revision) MODEL_REVISION="$2" ;;
        --network-capture) NETWORK_CAPTURE="$2" ;; --source-audit) SOURCE_AUDIT="$2" ;;
      esac
      shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;; --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ "$MODEL" == "oneBit27B" || "$MODEL" == "ternary27B" ]] || { echo "invalid --model" >&2; exit 64; }
[[ "$MODEL_REVISION" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid --model-revision" >&2; exit 64; }
[[ -n "$SCENARIOS" ]] || { echo "--scenarios is required" >&2; exit 64; }
seen=","
IFS=',' read -r -a scenario_list <<< "$SCENARIOS"
for scenario in "${scenario_list[@]}"; do
  case "$scenario" in
    text|thinking|cancel|calculator|date|device|notes|vision-fast|vision-full|offline|load-unload) ;;
    *) echo "unknown scenario: $scenario" >&2; exit 64 ;;
  esac
  [[ "$seen" != *",$scenario,"* ]] || { echo "duplicate scenario: $scenario" >&2; exit 64; }
  seen="$seen$scenario,"
done
for required in text thinking cancel calculator date device notes offline load-unload; do
  [[ "$seen" == *",$required,"* ]] || { echo "missing required scenario: $required" >&2; exit 64; }
done
if [[ -n "$DEVICE_ID" ]]; then
  [[ -z "$DESTINATION" ]] || { echo "choose --device-id or --destination" >&2; exit 64; }
  [[ "$DEVICE_ID" =~ ^[A-Fa-f0-9-]{8,64}$ ]] || { echo "invalid --device-id" >&2; exit 64; }
  DESTINATION="platform=iOS,id=$DEVICE_ID"
  [[ -z "$MODEL_DIR" ]] || { echo "physical iOS cannot consume --model-dir" >&2; exit 64; }
  for required in vision-fast vision-full; do
    [[ "$seen" == *",$required,"* ]] || { echo "missing iPhone scenario: $required" >&2; exit 64; }
  done
elif [[ "$DESTINATION" == "platform=macOS" ]]; then
  [[ -n "$MODEL_DIR" ]] || { echo "--model-dir is required for macOS" >&2; exit 64; }
else
  echo "use --device-id or --destination platform=macOS" >&2; exit 64
fi

run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
destination_hash="$(printf '%s' "$DESTINATION" | shasum -a 256 | awk '{print $1}')"
source_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
network_digest="" source_audit_digest=""
airplane_mode_enabled="" observed_outbound_request_count="" network_inspection_method=""
if ((DRY_RUN == 0)); then
  [[ -f "$NETWORK_CAPTURE" && -f "$SOURCE_AUDIT" ]] || {
    echo "--network-capture and --source-audit are required" >&2; exit 66; }
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || {
    echo "release evidence requires a clean tree" >&2; exit 65; }
  network_digest="$(shasum -a 256 "$NETWORK_CAPTURE" | awk '{print $1}')"
  source_audit_digest="$(shasum -a 256 "$SOURCE_AUDIT" | awk '{print $1}')"
  inspection_args=(--network "$NETWORK_CAPTURE" --source-audit "$SOURCE_AUDIT"
    --source-commit "$source_commit")
  airplane_mode_enabled="$($INSPECTION_VALIDATOR "${inspection_args[@]}" --print airplane)"
  observed_outbound_request_count="$($INSPECTION_VALIDATOR "${inspection_args[@]}" --print outbound)"
  network_inspection_method="$($INSPECTION_VALIDATOR "${inspection_args[@]}" --print method)"
fi

command=(xcodebuild -project "$PROJECT" -scheme BonsaiMobileIntegrationTests
  -configuration Release -destination "$DESTINATION" clean test
  -only-testing:BonsaiMobileIntegrationTests/RealModelScenarioTests/testRequestedRealModelScenariosAndRepeatedLifecycle
  -test-timeouts-enabled YES -default-test-execution-time-allowance 3600
  "BONSAI_SOURCE_COMMIT=$source_commit" "BONSAI_EVIDENCE_MODEL=$MODEL"
  "BONSAI_EVIDENCE_SCENARIOS=$SCENARIOS" "BONSAI_MODEL_REVISION=$MODEL_REVISION"
  "BONSAI_MODEL_DIR=$MODEL_DIR" "BONSAI_MODEL_RELATIVE_PATH=installed/$MODEL"
  "BONSAI_EVIDENCE_RUN_ID=$run_id" "BONSAI_EVIDENCE_DESTINATION_HASH=$destination_hash"
  "BONSAI_NETWORK_CAPTURE_SHA256=$network_digest"
  "BONSAI_SOURCE_AUDIT_SHA256=$source_audit_digest"
  "BONSAI_AIRPLANE_MODE_ENABLED=$airplane_mode_enabled"
  "BONSAI_OBSERVED_OUTBOUND_REQUEST_COUNT=$observed_outbound_request_count"
  "BONSAI_NETWORK_INSPECTION_METHOD=$network_inspection_method")
if ((DRY_RUN)); then
  printf 'RUN_ID=%q DESTINATION_HASH=%q ' "$run_id" "$destination_hash"
  printf '%q ' "${command[@]}"; printf '\n'; exit 0
fi

results_dir="$REPO_ROOT/docs/mobile/evidence/results"
mkdir -p "$results_dir"
result_bundle="$results_dir/$run_id.xcresult"
[[ ! -e "$result_bundle" ]] || { echo "result bundle collision" >&2; exit 73; }
command+=( -resultBundlePath "$result_bundle" )
"${command[@]}"

work="$(mktemp -d "${TMPDIR:-/tmp}/bonsai-evidence.XXXXXX")"
cleanup() { find "$work" -depth -delete; }
trap cleanup EXIT
xcrun xcresulttool export attachments --path "$result_bundle" --output-path "$work/attachments"
attachment_count="$(find "$work/attachments" -type f -name 'bonsai-device-evidence.json' -print | wc -l | tr -d ' ')"
[[ "$attachment_count" -eq 1 ]] || { echo "expected exactly one evidence attachment" >&2; exit 74; }
artifact="$(find "$work/attachments" -type f -name 'bonsai-device-evidence.json' -print -quit)"
"$VALIDATOR" "$artifact" --expected-run-id "$run_id" \
  --expected-destination-hash "$destination_hash" --expected-model "$MODEL" \
  --expected-scenarios "$SCENARIOS" \
  --expected-network-capture-sha256 "$network_digest" \
  --expected-source-audit-sha256 "$source_audit_digest"
evidence_id="$($VALIDATOR --print-evidence-id "$artifact")"
destination_dir="$REPO_ROOT/docs/mobile/evidence"
destination_file="$destination_dir/$evidence_id.json"
[[ ! -e "$destination_file" ]] || { echo "evidence already exists" >&2; exit 73; }
temporary="$destination_dir/.$evidence_id.$$.tmp"
cp "$artifact" "$temporary"
ln "$temporary" "$destination_file"
rm "$temporary"
echo "harness-generated evidence promoted to docs/mobile/evidence/$evidence_id.json"
