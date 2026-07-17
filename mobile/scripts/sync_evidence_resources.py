#!/usr/bin/env python3
"""Deterministically mirror reviewed manifest evidence from docs into app resources."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import sys


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sync(root: pathlib.Path, write: bool) -> None:
    manifest_path = root / "mobile/Resources/Evidence/support-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for reference in sorted(manifest["evidence"], key=lambda item: item["artifactPath"]):
        relative = pathlib.PurePosixPath(reference["artifactPath"])
        if relative.parts[:1] != ("Evidence",) or ".." in relative.parts:
            raise ValueError(f"invalid artifactPath: {relative}")
        name = pathlib.Path(*relative.parts[1:])
        source = root / "docs/mobile/evidence" / name
        destination = root / "mobile/Resources/Evidence" / name
        if not source.is_file() or digest(source) != reference["artifactSHA256"]:
            raise ValueError(f"missing or stale reviewed artifact: {name}")
        if write:
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(f".{destination.name}.tmp")
            temporary.write_bytes(source.read_bytes())
            temporary.replace(destination)
        if not destination.is_file() or digest(destination) != reference["artifactSHA256"]:
            raise ValueError(f"bundled artifact is not synchronized: {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=pathlib.Path, default=pathlib.Path(__file__).parents[2])
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        sync(args.root.resolve(), args.write)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
