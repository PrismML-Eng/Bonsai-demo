#!/usr/bin/env python3
"""Generate the pinned, integrity-backed Bonsai Mobile model catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional, Protocol, Sequence

from huggingface_hub import HfApi, hf_hub_download


GIBIBYTE = 1_073_741_824
IMMUTABLE_REVISION = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
WEIGHT_SUFFIX = ".safetensors"
INDEX_SUFFIX = ".safetensors.index.json"

RUNTIME_METADATA_FILES = {
    "added_tokens.json",
    "chat_template.jinja",
    "chat_template.json",
    "config.json",
    "generation_config.json",
    "image_processor_config.json",
    "merges.txt",
    "preprocessor_config.json",
    "processor_config.json",
    "sentencepiece.bpe.model",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer.model",
    "tokenizer_config.json",
    "video_preprocessor_config.json",
    "vocab.json",
    "vocab.txt",
}
TOKENIZER_FILES = {
    "merges.txt",
    "sentencepiece.bpe.model",
    "tokenizer.json",
    "tokenizer.model",
    "vocab.json",
    "vocab.txt",
}
CHAT_TEMPLATE_FILES = {
    "chat_template.jinja",
    "chat_template.json",
}
PROCESSOR_FILES = {
    "image_processor_config.json",
    "preprocessor_config.json",
    "processor_config.json",
    "video_preprocessor_config.json",
}
DRAFTER_MARKERS = ("draft", "drafter", "dspark")

REPOSITORIES = (
    ("oneBit27B", "prism-ml/Bonsai-27B-mlx-1bit"),
    ("ternary27B", "prism-ml/Ternary-Bonsai-27B-mlx-2bit"),
)


class ManifestError(RuntimeError):
    """Raised when Hub metadata cannot produce a safe runtime manifest."""


@dataclass(frozen=True)
class RemoteFile:
    path: str
    size: Optional[int]
    lfs_sha256: Optional[str]


@dataclass(frozen=True)
class RepositorySnapshot:
    repo_id: str
    revision: str
    files: tuple[RemoteFile, ...]


class RepositorySource(Protocol):
    def snapshot(self, repo_id: str) -> RepositorySnapshot: ...

    def read_file(self, repo_id: str, revision: str, path: str) -> bytes: ...


class HuggingFaceRepositorySource:
    """The only network boundary used by deterministic manifest construction."""

    def __init__(self, api: Optional[HfApi] = None) -> None:
        self._api = api or HfApi()

    def snapshot(self, repo_id: str) -> RepositorySnapshot:
        info = self._api.model_info(repo_id, revision="main", files_metadata=True)
        files = []
        for sibling in info.siblings or ():
            lfs = sibling.lfs
            lfs_sha256 = None
            lfs_size = None
            if lfs is not None:
                if isinstance(lfs, dict):
                    lfs_sha256 = lfs.get("sha256")
                    lfs_size = lfs.get("size")
                else:
                    lfs_sha256 = getattr(lfs, "sha256", None)
                    lfs_size = getattr(lfs, "size", None)
            files.append(
                RemoteFile(
                    path=sibling.rfilename,
                    size=sibling.size if sibling.size is not None else lfs_size,
                    lfs_sha256=lfs_sha256,
                )
            )
        return RepositorySnapshot(repo_id=repo_id, revision=info.sha, files=tuple(files))

    def read_file(self, repo_id: str, revision: str, path: str) -> bytes:
        local_path = hf_hub_download(
            repo_id=repo_id,
            filename=path,
            revision=revision,
        )
        return Path(local_path).read_bytes()


def select_runtime_files(files: Iterable[RemoteFile]) -> list[RemoteFile]:
    """Select root-level runtime candidates without interpreting an index."""
    selected = []
    for remote_file in files:
        path = remote_file.path
        basename = Path(path).name
        lowered = basename.lower()
        if "/" in path or path.startswith("."):
            continue
        if any(marker in lowered for marker in DRAFTER_MARKERS):
            continue
        if (
            basename in RUNTIME_METADATA_FILES
            or lowered.endswith(WEIGHT_SUFFIX)
            or lowered.endswith(INDEX_SUFFIX)
        ):
            selected.append(remote_file)
    return sorted(selected, key=lambda remote_file: remote_file.path)


def build_model_manifest(
    model_id: str,
    repo_id: str,
    source: RepositorySource,
) -> dict:
    snapshot = source.snapshot(repo_id)
    if snapshot.repo_id != repo_id:
        raise ManifestError(f"repository mismatch: requested {repo_id}, got {snapshot.repo_id}")
    if not IMMUTABLE_REVISION.fullmatch(snapshot.revision):
        raise ManifestError(f"{repo_id} did not return an immutable commit revision")

    candidates = select_runtime_files(snapshot.files)
    _reject_duplicate_paths(repo_id, candidates)
    by_path = {remote_file.path: remote_file for remote_file in candidates}
    _require_runtime_roles(repo_id, by_path)

    contents: dict[str, bytes] = {}
    for remote_file in candidates:
        if not remote_file.path.endswith(WEIGHT_SUFFIX):
            contents[remote_file.path] = source.read_file(
                repo_id, snapshot.revision, remote_file.path
            )

    required_weights = _required_weight_paths(repo_id, by_path, contents)
    candidates = [
        remote_file
        for remote_file in candidates
        if not remote_file.path.endswith(WEIGHT_SUFFIX)
        or remote_file.path in required_weights
    ]

    manifest_files = []
    for remote_file in candidates:
        if remote_file.size is None or remote_file.size < 0:
            raise ManifestError(f"{remote_file.path}: missing size")
        if remote_file.path.endswith(WEIGHT_SUFFIX):
            if remote_file.lfs_sha256 is None:
                raise ManifestError(f"{remote_file.path}: missing LFS SHA-256")
            if not SHA256.fullmatch(remote_file.lfs_sha256):
                raise ManifestError(f"{remote_file.path}: invalid LFS SHA-256")
            digest = remote_file.lfs_sha256
        else:
            content = contents[remote_file.path]
            if len(content) != remote_file.size:
                raise ManifestError(
                    f"{remote_file.path}: content size {len(content)} does not match "
                    f"Hub metadata {remote_file.size}"
                )
            digest = hashlib.sha256(content).hexdigest()
        manifest_files.append(
            {
                "isOptional": False,
                "path": remote_file.path,
                "role": _role(remote_file.path),
                "sha256": digest,
                "sizeBytes": remote_file.size,
            }
        )

    return {
        "files": manifest_files,
        "id": model_id,
        "repository": repo_id,
        "revision": snapshot.revision,
    }


def build_catalog(
    specs: Sequence[tuple[str, str]], source: RepositorySource
) -> dict:
    descriptors = []
    for model_id, repo_id in sorted(specs):
        manifest = build_model_manifest(model_id, repo_id, source)
        one_bit = model_id == "oneBit27B"
        descriptors.append(
            {
                "capabilities": ["textGeneration", "thinking", "toolCalling", "vision"],
                "displayName": (
                    "Bonsai 27B 1-bit" if one_bit else "Ternary Bonsai 27B 2-bit"
                ),
                "family": "bonsai" if one_bit else "ternaryBonsai",
                "id": model_id,
                "manifest": manifest,
                "minimumPhysicalMemoryBytes": (8 if one_bit else 16) * GIBIBYTE,
                # One GiB leaves room for per-file staging and filesystem metadata.
                "storageSafetyMarginBytes": GIBIBYTE,
            }
        )
    return {"models": descriptors, "schemaVersion": 1}


def render_catalog(catalog: dict) -> str:
    return json.dumps(catalog, indent=2, sort_keys=True) + "\n"


def write_text_atomically(output: Path, content: str) -> None:
    """Replace output with a fully flushed sibling temporary file."""
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Optional[Path] = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=output.parent,
            prefix=f".{output.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, output)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def _require_runtime_roles(repo_id: str, by_path: dict[str, RemoteFile]) -> None:
    if "config.json" not in by_path:
        raise ManifestError(f"{repo_id} is missing config.json")
    if not TOKENIZER_FILES.intersection(by_path):
        raise ManifestError(f"{repo_id} is missing tokenizer files")
    if not CHAT_TEMPLATE_FILES.intersection(by_path):
        raise ManifestError(f"{repo_id} is missing a chat template")
    if not PROCESSOR_FILES.intersection(by_path):
        raise ManifestError(f"{repo_id} is missing processor configuration")


def _reject_duplicate_paths(repo_id: str, files: Iterable[RemoteFile]) -> None:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for remote_file in files:
        if remote_file.path in seen:
            duplicates.add(remote_file.path)
        seen.add(remote_file.path)
    if duplicates:
        raise ManifestError(
            f"{repo_id} has duplicate runtime path: {sorted(duplicates)[0]}"
        )


def _required_weight_paths(
    repo_id: str,
    by_path: dict[str, RemoteFile],
    contents: dict[str, bytes],
) -> set[str]:
    """Resolve the complete, deterministic runtime-weight closure."""
    eligible_weights = {
        path for path in by_path if path.endswith(WEIGHT_SUFFIX)
    }
    index_paths = sorted(path for path in by_path if path.endswith(INDEX_SUFFIX))
    if len(index_paths) > 1:
        raise ManifestError(f"{repo_id} has multiple safetensor indexes")
    if not index_paths:
        if not eligible_weights:
            raise ManifestError(f"{repo_id} is missing model weights")
        return eligible_weights

    referenced_weights = _referenced_weights(repo_id, contents[index_paths[0]])
    missing_weights = referenced_weights.difference(eligible_weights)
    if missing_weights:
        raise ManifestError(
            f"referenced shard is missing: {sorted(missing_weights)[0]}"
        )
    return referenced_weights


def _referenced_weights(repo_id: str, content: bytes) -> set[str]:
    try:
        payload = json.loads(content)
        weight_map = payload["weight_map"]
        referenced = set(weight_map.values())
    except (KeyError, TypeError, ValueError, UnicodeDecodeError) as error:
        raise ManifestError(f"{repo_id} has an invalid safetensor index") from error
    if not referenced or not all(
        isinstance(path, str) and path.endswith(WEIGHT_SUFFIX) for path in referenced
    ):
        raise ManifestError(f"{repo_id} has an invalid safetensor index weight map")
    return referenced


def _role(path: str) -> str:
    if path.endswith(WEIGHT_SUFFIX):
        return "weight"
    if Path(path).name in PROCESSOR_FILES:
        return "processor"
    if Path(path).name in TOKENIZER_FILES or "token" in path or "vocab" in path:
        return "tokenizer"
    return "configuration"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    catalog = build_catalog(REPOSITORIES, HuggingFaceRepositorySource())
    write_text_atomically(args.output, render_catalog(catalog))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
