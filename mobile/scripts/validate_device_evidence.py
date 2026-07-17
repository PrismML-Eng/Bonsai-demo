#!/usr/bin/env python3
"""Validate Bonsai release evidence without emitting prompt or response content."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys

REQUIRED = {
    "schemaVersion", "runID", "destinationHash", "recordKind",
    "evidenceID", "recordedAt", "deviceClass", "hardwareIdentifier",
    "osBuild", "appBuild", "appCommit", "dirtyBuild", "simulator", "runtimeFingerprint",
    "modelID", "modelRevision", "capabilities",
    "physicalMemoryBytes", "contextTokens", "imageDetail", "coldLoadMilliseconds",
    "warmLoadMilliseconds", "timeToFirstTokenMilliseconds", "promptTokensPerSecond",
    "generatedTokensPerSecond", "peakMemoryBytes", "thermalTransitions",
    "batteryDeltaPercent", "batteryMeasurement", "cancellationResult", "outcome", "pressureTermination",
    "offlineProof", "scenarioResults", "unsupportedReason",
}
MODELS = {"oneBit27B", "ternary27B"}
CAPABILITIES = {"textGeneration", "thinking", "toolCalling", "vision"}
UNSUPPORTED_REASONS = {"model_load_failure"}


def fail(message: str) -> None:
    raise ValueError(message)


def validate(document: object, expected: dict[str, str] | None = None) -> dict[str, object]:
    if not isinstance(document, dict):
        fail("artifact must be a JSON object")
    unknown = set(document) - REQUIRED
    missing = REQUIRED - set(document)
    if unknown:
        fail(f"unknown fields: {','.join(sorted(unknown))}")
    if missing:
        fail(f"missing fields: {','.join(sorted(missing))}")
    if document["schemaVersion"] != 1:
        fail("unsupported schemaVersion")
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", str(document["runID"])):
        fail("invalid runID")
    if not re.fullmatch(r"[0-9a-f]{64}", str(document["destinationHash"])):
        fail("invalid destinationHash")
    if document["recordKind"] not in {"supported", "unsupported"}:
        fail("invalid recordKind")
    for field, value in (expected or {}).items():
        if document.get(field) != value:
            fail(f"{field} does not match the executed lane")
    for field in ("evidenceID", "recordedAt", "deviceClass", "hardwareIdentifier", "osBuild", "appBuild"):
        if not isinstance(document[field], str) or not document[field].strip():
            fail(f"invalid {field}")
    if document["deviceClass"] != document["hardwareIdentifier"]:
        fail("deviceClass must equal the raw hardwareIdentifier")
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{7,127}", str(document["evidenceID"])):
        fail("invalid evidenceID")
    for field in ("appCommit", "modelRevision"):
        if not re.fullmatch(r"[0-9a-f]{40}", str(document[field])):
            fail(f"invalid {field}")
    if document["dirtyBuild"] is not False:
        fail("dirty build")
    if document["simulator"] is not False:
        fail("simulator evidence")
    if not re.fullmatch(r"[0-9a-f]{64}", str(document["runtimeFingerprint"])):
        fail("invalid runtimeFingerprint")
    if document["modelID"] not in MODELS:
        fail("invalid modelID")
    capabilities = document["capabilities"]
    if not isinstance(capabilities, list) or set(capabilities) - CAPABILITIES:
        fail("invalid capabilities")
    if len(capabilities) != len(set(capabilities)):
        fail("duplicate capabilities")
    for field in ("physicalMemoryBytes", "contextTokens", "peakMemoryBytes"):
        if type(document[field]) is not int or document[field] <= 0:
            fail(f"invalid {field}")
    for field in ("coldLoadMilliseconds", "warmLoadMilliseconds", "timeToFirstTokenMilliseconds"):
        if type(document[field]) is not int or document[field] < 0:
            fail(f"invalid {field}")
    for field in ("promptTokensPerSecond", "generatedTokensPerSecond", "batteryDeltaPercent"):
        value = document[field]
        if type(value) not in (int, float) or not math.isfinite(value):
            fail(f"invalid {field}")
    if document["recordKind"] == "supported" and (
        document["promptTokensPerSecond"] <= 0 or document["generatedTokensPerSecond"] <= 0
    ):
        fail("supported token rates must be positive")
    if not -100 <= document["batteryDeltaPercent"] <= 100:
        fail("invalid batteryDeltaPercent")
    battery = document["batteryMeasurement"]
    if not isinstance(battery, dict) or set(battery) != {
        "available", "startPercent", "endPercent", "deltaPercent", "unavailableReason"
    }:
        fail("invalid batteryMeasurement")
    if battery["available"] is True:
        values = (battery["startPercent"], battery["endPercent"], battery["deltaPercent"])
        if any(type(value) not in (int, float) or not math.isfinite(value) for value in values):
            fail("invalid batteryMeasurement")
        if abs((values[1] - values[0]) - values[2]) > 0.001:
            fail("invalid batteryMeasurement")
    elif battery["available"] is False:
        if any(battery[field] is not None for field in ("startPercent", "endPercent", "deltaPercent")):
            fail("invalid unavailable batteryMeasurement")
        if not isinstance(battery["unavailableReason"], str) or not battery["unavailableReason"]:
            fail("missing battery unavailable reason")
    else:
        fail("invalid batteryMeasurement")
    if document["imageDetail"] not in {"notApplicable", "fast1024", "fullDetail"}:
        fail("invalid imageDetail")
    transitions = document["thermalTransitions"]
    if not isinstance(transitions, list) or not transitions or set(transitions) - {
        "nominal", "fair", "serious", "critical"
    }:
        fail("invalid thermalTransitions")
    results = document["scenarioResults"]
    if not isinstance(results, list) or not results:
        fail("invalid scenarioResults")
    scenarios = {}
    for result in results:
        if not isinstance(result, dict) or set(result) != {
            "scenario", "capability", "outcome", "completion", "elapsedMilliseconds"
        }:
            fail("invalid scenario result")
        scenario = result["scenario"]
        if scenario in scenarios:
            fail("duplicate scenario result")
        if result["outcome"] not in {"passed", "unsupported", "infrastructureFailure"}:
            fail("invalid scenario outcome")
        if type(result["elapsedMilliseconds"]) is not int or result["elapsedMilliseconds"] < 0:
            fail("invalid scenario duration")
        if not isinstance(result["completion"], str) or not result["completion"]:
            fail("invalid scenario completion")
        scenarios[scenario] = result
    if document["recordKind"] == "unsupported":
        if capabilities or document["unsupportedReason"] not in UNSUPPORTED_REASONS:
            fail("unsupported evidence requires a reason and no capabilities")
        if not any(item["outcome"] == "unsupported" for item in results):
            fail("unsupported evidence requires an unsupported scenario")
        return document
    if document["unsupportedReason"] is not None:
        fail("supported evidence cannot contain unsupportedReason")
    required = {"text", "cancel", "calculator", "date", "device", "notes", "offline", "load-unload"}
    for scenario in required:
        if scenarios.get(scenario, {}).get("outcome") != "passed":
            fail(f"incomplete {scenario} scenario")
    capability_scenarios = {
        "textGeneration": {"text"}, "thinking": {"thinking"},
        "toolCalling": {"calculator", "date", "device", "notes"},
        "vision": {"vision-fast", "vision-full"},
    }
    for capability in capabilities:
        for scenario in capability_scenarios[capability]:
            if scenarios.get(scenario, {}).get("outcome") != "passed":
                fail(f"incomplete {scenario} scenario")
    if not capabilities:
        fail("supported evidence requires capabilities")
    if document["cancellationResult"] != "completedWithinDeadline":
        fail("cancellation scenario incomplete")
    if document["outcome"] not in {"completed", "cancelledAsExpected"}:
        fail("outcome did not pass")
    if document["pressureTermination"] is not False:
        fail("pressure termination")
    proof = document["offlineProof"]
    if not isinstance(proof, dict) or set(proof) != {
        "airplaneModeEnabled", "observedOutboundRequestCount", "inspectionMethod",
        "networkCaptureSHA256", "sourceAuditSHA256"
    }:
        fail("invalid offlineProof")
    if proof["airplaneModeEnabled"] is not True or proof["observedOutboundRequestCount"] != 0:
        fail("offline proof incomplete")
    if not isinstance(proof["inspectionMethod"], str) or not proof["inspectionMethod"].strip():
        fail("offline inspection method missing")
    for field in ("networkCaptureSHA256", "sourceAuditSHA256"):
        if not re.fullmatch(r"[0-9a-f]{64}", str(proof[field])):
            fail(f"invalid {field}")
    return document


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=pathlib.Path)
    parser.add_argument("--print-evidence-id", action="store_true")
    parser.add_argument("--expected-run-id")
    parser.add_argument("--expected-destination-hash")
    parser.add_argument("--expected-model")
    parser.add_argument("--expected-scenarios")
    parser.add_argument("--expected-network-capture-sha256")
    parser.add_argument("--expected-source-audit-sha256")
    args = parser.parse_args()
    try:
        with args.artifact.open("r", encoding="utf-8") as handle:
            expected = {
                key: value for key, value in {
                    "runID": args.expected_run_id,
                    "destinationHash": args.expected_destination_hash,
                    "modelID": args.expected_model,
                }.items() if value is not None
            }
            document = validate(
                json.load(handle, parse_constant=lambda value: fail(f"invalid {value}")), expected)
            if args.expected_scenarios:
                actual = {item["scenario"] for item in document["scenarioResults"]}
                requested = set(args.expected_scenarios.split(","))
                if actual != requested:
                    fail("scenarioResults do not match the executed lane")
            proof = document.get("offlineProof")
            if args.expected_network_capture_sha256 and (
                not isinstance(proof, dict)
                or proof.get("networkCaptureSHA256") != args.expected_network_capture_sha256
            ):
                fail("network capture digest does not match external inspection")
            if args.expected_source_audit_sha256 and (
                not isinstance(proof, dict)
                or proof.get("sourceAuditSHA256") != args.expected_source_audit_sha256
            ):
                fail("source audit digest does not match external inspection")
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"invalid evidence: {error}", file=sys.stderr)
        return 2
    if args.print_evidence_id:
        print(document["evidenceID"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
