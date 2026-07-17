#!/usr/bin/env python3
"""Validate closed, content-free external inspection attestations."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


def load(path: pathlib.Path) -> object:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_network(value: object) -> dict[str, object]:
    fields = {
        "schemaVersion", "airplaneModeEnabled", "observedOutboundRequestCount",
        "inspectionMethod", "captureArtifactSHA256",
    }
    if not isinstance(value, dict) or set(value) != fields:
        raise ValueError("invalid network inspection fields")
    if value["schemaVersion"] != 1:
        raise ValueError("invalid network inspection schema")
    if value["airplaneModeEnabled"] is not True:
        raise ValueError("airplane mode was not externally observed")
    if type(value["observedOutboundRequestCount"]) is not int:
        raise ValueError("invalid outbound request count")
    if value["observedOutboundRequestCount"] != 0:
        raise ValueError("outbound requests were observed")
    if value["inspectionMethod"] not in {"external_packet_capture"}:
        raise ValueError("invalid inspection method")
    if not re.fullmatch(r"[0-9a-f]{64}", str(value["captureArtifactSHA256"])):
        raise ValueError("invalid capture artifact digest")
    return value


def validate_source_audit(value: object, commit: str) -> dict[str, object]:
    fields = {
        "schemaVersion", "sourceCommit", "networkBoundaryAuditPassed", "auditArtifactSHA256",
    }
    if not isinstance(value, dict) or set(value) != fields:
        raise ValueError("invalid source audit fields")
    if value["schemaVersion"] != 1 or value["sourceCommit"] != commit:
        raise ValueError("source audit is not bound to the release commit")
    if value["networkBoundaryAuditPassed"] is not True:
        raise ValueError("source network-boundary audit did not pass")
    if not re.fullmatch(r"[0-9a-f]{64}", str(value["auditArtifactSHA256"])):
        raise ValueError("invalid source audit digest")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", required=True, type=pathlib.Path)
    parser.add_argument("--source-audit", required=True, type=pathlib.Path)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument(
        "--print", choices=("airplane", "outbound", "method"), required=True,
        dest="output")
    args = parser.parse_args()
    try:
        if not re.fullmatch(r"[0-9a-f]{40}", args.source_commit):
            raise ValueError("invalid release source commit")
        network = validate_network(load(args.network))
        validate_source_audit(load(args.source_audit), args.source_commit)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"invalid external inspection: {error}", file=sys.stderr)
        return 2
    outputs = {
        "airplane": "true" if network["airplaneModeEnabled"] else "false",
        "outbound": str(network["observedOutboundRequestCount"]),
        "method": str(network["inspectionMethod"]),
    }
    print(outputs[args.output])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
