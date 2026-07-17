import importlib.util
from pathlib import Path

import pytest

MODULE_PATH = Path(__file__).parents[1] / "mobile/scripts/validate_device_evidence.py"
SPEC = importlib.util.spec_from_file_location("device_evidence_validator", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)

SYNC_PATH = Path(__file__).parents[1] / "mobile/scripts/sync_evidence_resources.py"
SYNC_SPEC = importlib.util.spec_from_file_location("sync_evidence_resources", SYNC_PATH)
SYNC_MODULE = importlib.util.module_from_spec(SYNC_SPEC)
assert SYNC_SPEC.loader is not None
SYNC_SPEC.loader.exec_module(SYNC_MODULE)

INSPECTION_PATH = Path(__file__).parents[1] / "mobile/scripts/validate_external_inspection.py"
INSPECTION_SPEC = importlib.util.spec_from_file_location("external_inspection", INSPECTION_PATH)
INSPECTION_MODULE = importlib.util.module_from_spec(INSPECTION_SPEC)
assert INSPECTION_SPEC.loader is not None
INSPECTION_SPEC.loader.exec_module(INSPECTION_MODULE)


def valid_document():
    return {
        "schemaVersion": 1, "evidenceID": "2026-07-17-device-onebit-text",
        "runID": "11111111-1111-4111-8111-111111111111", "destinationHash": "d" * 64,
        "recordKind": "supported",
        "recordedAt": "2026-07-17T00:00:00Z", "deviceClass": "Mac16,1",
        "hardwareIdentifier": "Mac16,1", "osBuild": "25F90", "appBuild": "1.0-1",
        "appCommit": "a" * 40, "modelID": "oneBit27B", "modelRevision": "b" * 40,
        "dirtyBuild": False, "simulator": False, "runtimeFingerprint": "c" * 64,
        "capabilities": ["textGeneration"], "physicalMemoryBytes": 16_000_000_000,
        "contextTokens": 4096, "imageDetail": "notApplicable", "coldLoadMilliseconds": 2000,
        "warmLoadMilliseconds": 500, "timeToFirstTokenMilliseconds": 900,
        "promptTokensPerSecond": 100.0, "generatedTokensPerSecond": 12.0,
        "peakMemoryBytes": 7_000_000_000, "thermalTransitions": ["nominal"],
        "batteryDeltaPercent": 0.0, "cancellationResult": "completedWithinDeadline",
        "batteryMeasurement": {"available": True, "startPercent": 90.0, "endPercent": 90.0,
                               "deltaPercent": 0.0, "unavailableReason": None},
        "outcome": "completed", "pressureTermination": False,
        "offlineProof": {"airplaneModeEnabled": True, "observedOutboundRequestCount": 0,
                         "inspectionMethod": "external packet capture plus source audit",
                         "networkCaptureSHA256": "e" * 64, "sourceAuditSHA256": "f" * 64},
        "scenarioResults": [
            {"scenario": scenario, "capability": capability, "outcome": "passed",
             "completion": completion, "elapsedMilliseconds": 10}
            for scenario, capability, completion in [
                ("text", "textGeneration", "stop"), ("thinking", "thinking", "stop"),
                ("cancel", None, "cancelled"),
                ("calculator", "toolCalling", "tool_round_trip"),
                ("date", "toolCalling", "tool_round_trip"),
                ("device", "toolCalling", "tool_round_trip"),
                ("notes", "toolCalling", "approved_tool_round_trip"),
                ("offline", None, "external_proof_bound"),
                ("load-unload", None, "three_cycles"),
            ]
        ],
        "unsupportedReason": None,
    }


def test_validates_complete_content_free_evidence():
    assert MODULE.validate(valid_document())["modelID"] == "oneBit27B"


@pytest.mark.parametrize("field", sorted(MODULE.REQUIRED))
def test_rejects_every_missing_release_field(field):
    document = valid_document()
    del document[field]
    with pytest.raises(ValueError, match="missing fields"):
        MODULE.validate(document)


def test_rejects_pressure_and_outbound_attempts():
    pressure = valid_document()
    pressure["pressureTermination"] = True
    with pytest.raises(ValueError, match="pressure"):
        MODULE.validate(pressure)
    outbound = valid_document()
    outbound["offlineProof"]["observedOutboundRequestCount"] = 1
    with pytest.raises(ValueError, match="offline"):
        MODULE.validate(outbound)


def test_expected_lane_binding_rejects_another_run():
    with pytest.raises(ValueError, match="runID"):
        MODULE.validate(valid_document(), expected={"runID": "another-run"})


def test_supported_capability_requires_its_scenario():
    document = valid_document()
    document["capabilities"].append("vision")
    with pytest.raises(ValueError, match="vision"):
        MODULE.validate(document)


def test_deterministic_unsupported_record_is_valid_but_has_no_capabilities():
    document = valid_document()
    document["recordKind"] = "unsupported"
    document["capabilities"] = []
    document["outcome"] = "failed"
    document["unsupportedReason"] = "model_load_failure"
    document["scenarioResults"] = [{"scenario": "load-unload", "capability": None,
                                     "outcome": "unsupported", "completion": "load_failed",
                                     "elapsedMilliseconds": 1}]
    assert MODULE.validate(document)["recordKind"] == "unsupported"


def test_supported_rates_are_observed_positive_values():
    for field in ("promptTokensPerSecond", "generatedTokensPerSecond"):
        document = valid_document()
        document[field] = 0
        with pytest.raises(ValueError, match="positive"):
            MODULE.validate(document)


def test_unsupported_reason_is_closed_and_content_free():
    document = valid_document()
    document["recordKind"] = "unsupported"
    document["capabilities"] = []
    document["unsupportedReason"] = "/private/tmp/model failed with prompt data"
    document["scenarioResults"] = [{"scenario": "load-unload", "capability": None,
                                     "outcome": "unsupported", "completion": "load_failed",
                                     "elapsedMilliseconds": 1}]
    with pytest.raises(ValueError, match="reason"):
        MODULE.validate(document)


def test_external_inspection_rejects_assertion_placeholders():
    with pytest.raises(ValueError, match="airplane"):
        INSPECTION_MODULE.validate_network({
            "schemaVersion": 1, "airplaneModeEnabled": False,
            "observedOutboundRequestCount": 0, "inspectionMethod": "external_packet_capture",
            "captureArtifactSHA256": "a" * 64,
        })


def test_sync_rejects_manifest_artifact_missing_from_docs(tmp_path):
    manifest = tmp_path / "mobile/Resources/Evidence/support-manifest.json"
    manifest.parent.mkdir(parents=True)
    manifest.write_text('{"schemaVersion":1,"evidence":[{"artifactPath":"Evidence/run.json",'
                        '"artifactSHA256":"' + "a" * 64 + '"}]}')
    with pytest.raises(ValueError, match="reviewed artifact"):
        SYNC_MODULE.sync(tmp_path, write=True)


def test_integration_scheme_has_each_evidence_environment_key_once():
    project = (Path(__file__).parents[1] / "mobile/project.yml").read_text()
    integration = project.split("  BonsaiMobileIntegrationTests:", 1)[1]
    for key in (
        "BONSAI_MODEL_RELATIVE_PATH", "BONSAI_MODEL_REVISION", "BONSAI_EVIDENCE_MODEL",
        "BONSAI_EVIDENCE_SCENARIOS", "BONSAI_EVIDENCE_RUN_ID",
        "BONSAI_EVIDENCE_DESTINATION_HASH", "BONSAI_NETWORK_CAPTURE_SHA256",
        "BONSAI_SOURCE_AUDIT_SHA256", "BONSAI_AIRPLANE_MODE_ENABLED",
        "BONSAI_OBSERVED_OUTBOUND_REQUEST_COUNT", "BONSAI_NETWORK_INSPECTION_METHOD",
        "BONSAI_SOURCE_COMMIT",
    ):
        assert integration.count(f"        {key}:") == 1


def test_runner_only_promotes_the_just_run_xcresult_attachment():
    runner = (Path(__file__).parents[1] / "mobile/scripts/run_device_evidence.sh").read_text()
    assert "--evidence-input" not in runner
    assert "xcresulttool export attachments" in runner
    assert "--expected-run-id" in runner
    assert "--expected-destination-hash" in runner
    assert "--expected-scenarios" in runner
    assert "expected exactly one evidence attachment" in runner


def test_runner_binds_validated_external_inspection_values_and_digests():
    runner = (Path(__file__).parents[1] / "mobile/scripts/run_device_evidence.sh").read_text()
    assert "validate_external_inspection.py" in runner
    assert "--expected-network-capture-sha256" in runner
    assert "--expected-source-audit-sha256" in runner
    assert '"BONSAI_AIRPLANE_MODE_ENABLED=$airplane_mode_enabled"' in runner
    assert '"BONSAI_OBSERVED_OUTBOUND_REQUEST_COUNT=$observed_outbound_request_count"' in runner


def test_integration_harness_has_local_tool_results_and_no_offline_placeholders():
    harness = (Path(__file__).parents[1] / "mobile/IntegrationTests/RealModelScenarioTests.swift").read_text()
    tool_method = harness.split("private static func verifyAgentTools", 1)[1].split(
        "private static func verifyVision", 1)[0]
    assert "var results: [DeviceEvidence.ScenarioResult] = []" in tool_method
    assert "airplaneModeEnabled: true" not in harness
    assert "observedOutboundRequestCount: 0" not in harness
    assert "String(describing: error)" not in harness


def test_release_build_uses_canonical_source_provenance_lane():
    root = Path(__file__).parents[1]
    project = (root / "mobile/project.yml").read_text()
    build = (root / "mobile/scripts/build_mobile.sh").read_text()
    assert "validate_source_provenance.sh" in project
    assert '"BONSAI_SOURCE_COMMIT=$source_commit"' in build
    assert "xcodebuild" in build
