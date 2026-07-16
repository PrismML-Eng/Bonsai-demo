import json
import importlib.util
import sys
from dataclasses import replace
from pathlib import Path

import pytest

MODULE_PATH = Path(__file__).parents[1] / "scripts/generate_mobile_model_manifest.py"
SPEC = importlib.util.spec_from_file_location("generate_mobile_model_manifest", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
manifest_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = manifest_module
SPEC.loader.exec_module(manifest_module)

ManifestError = manifest_module.ManifestError
RemoteFile = manifest_module.RemoteFile
RepositorySnapshot = manifest_module.RepositorySnapshot
build_catalog = manifest_module.build_catalog
build_model_manifest = manifest_module.build_model_manifest
render_catalog = manifest_module.render_catalog
select_runtime_files = manifest_module.select_runtime_files


SHA_A = "a" * 64
SHA_B = "b" * 64
REVISION_A = "1" * 40


class FakeSource:
    def __init__(self, snapshots, contents):
        self.snapshots = snapshots
        self.contents = contents

    def snapshot(self, repo_id):
        return self.snapshots[repo_id]

    def read_file(self, repo_id, revision, path):
        return self.contents[(repo_id, revision, path)]


def test_selects_runtime_files_and_excludes_drafter_and_docs():
    files = [
        RemoteFile("README.md", 10, None),
        RemoteFile("config.json", 11, None),
        RemoteFile("tokenizer.json", 12, None),
        RemoteFile("model-00001-of-00002.safetensors", 20, SHA_A),
        RemoteFile("model-00002-of-00002.safetensors", 30, SHA_B),
        RemoteFile("dspark.safetensors", 40, "c" * 64),
        RemoteFile("demo/screenshot.png", 50, None),
        RemoteFile(".gitattributes", 60, None),
    ]

    selected = select_runtime_files(files)

    assert [file.path for file in selected] == [
        "config.json",
        "model-00001-of-00002.safetensors",
        "model-00002-of-00002.safetensors",
        "tokenizer.json",
    ]


def test_safetensor_index_requires_every_referenced_shard():
    repo_id = "example/model"
    index = json.dumps(
        {
            "weight_map": {
                "layer.0": "model-00001-of-00002.safetensors",
                "layer.1": "model-00002-of-00002.safetensors",
            }
        }
    ).encode()
    snapshot = RepositorySnapshot(
        repo_id=repo_id,
        revision=REVISION_A,
        files=(
            RemoteFile("config.json", 2, None),
            RemoteFile("tokenizer.json", 2, None),
            RemoteFile("preprocessor_config.json", 2, None),
            RemoteFile("model.safetensors.index.json", len(index), None),
            RemoteFile("model-00001-of-00002.safetensors", 20, SHA_A),
        ),
    )
    source = FakeSource(
        {repo_id: snapshot},
        {
            (repo_id, REVISION_A, "config.json"): b"{}",
            (repo_id, REVISION_A, "tokenizer.json"): b"{}",
            (repo_id, REVISION_A, "preprocessor_config.json"): b"{}",
            (repo_id, REVISION_A, "model.safetensors.index.json"): index,
        },
    )

    with pytest.raises(ManifestError, match="referenced shard.*model-00002"):
        build_model_manifest("oneBit27B", repo_id, source)


@pytest.mark.parametrize(
    ("weight", "message"),
    [
        (RemoteFile("model.safetensors", None, SHA_A), "missing size"),
        (RemoteFile("model.safetensors", 20, None), "missing LFS SHA-256"),
        (RemoteFile("model.safetensors", 20, "short"), "invalid LFS SHA-256"),
    ],
)
def test_rejects_weight_without_size_and_valid_lfs_hash(weight, message):
    source = minimal_source(weight=weight)

    with pytest.raises(ManifestError, match=message):
        build_model_manifest("oneBit27B", "example/model", source)


def test_captures_immutable_commit_revision_and_hashes_small_files():
    source = minimal_source()

    manifest = build_model_manifest("oneBit27B", "example/model", source)

    assert manifest["revision"] == REVISION_A
    assert manifest["revision"] != "main"
    config = next(file for file in manifest["files"] if file["path"] == "config.json")
    assert config["sha256"] == (
        "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    )


def test_rejects_mutable_or_invalid_revision():
    source = minimal_source()
    snapshot = source.snapshots["example/model"]
    source.snapshots["example/model"] = replace(snapshot, revision="main")

    with pytest.raises(ManifestError, match="immutable commit revision"):
        build_model_manifest("oneBit27B", "example/model", source)


def test_requires_config_tokenizer_processor_and_weight_files():
    source = minimal_source()
    snapshot = source.snapshots["example/model"]
    source.snapshots["example/model"] = replace(
        snapshot,
        files=tuple(file for file in snapshot.files if file.path != "preprocessor_config.json"),
    )

    with pytest.raises(ManifestError, match="processor configuration"):
        build_model_manifest("oneBit27B", "example/model", source)


def test_catalog_order_and_rendering_are_deterministic():
    one_bit = minimal_source(repo_id="z/one-bit", revision="2" * 40)
    ternary = minimal_source(repo_id="a/ternary", revision="3" * 40)
    source = FakeSource(
        {**one_bit.snapshots, **ternary.snapshots},
        {**one_bit.contents, **ternary.contents},
    )
    specs = [
        ("ternary27B", "a/ternary"),
        ("oneBit27B", "z/one-bit"),
    ]

    first = render_catalog(build_catalog(specs, source))
    second = render_catalog(build_catalog(list(reversed(specs)), source))

    assert first == second
    parsed = json.loads(first)
    assert [model["id"] for model in parsed["models"]] == [
        "oneBit27B",
        "ternary27B",
    ]
    assert first.endswith("\n")


def minimal_source(
    weight=RemoteFile("model.safetensors", 20, SHA_A),
    repo_id="example/model",
    revision=REVISION_A,
):
    contents = {
        "config.json": b"{}",
        "tokenizer.json": b"{}",
        "tokenizer_config.json": b"{}",
        "preprocessor_config.json": b"{}",
    }
    files = tuple(
        RemoteFile(path, len(content), None) for path, content in contents.items()
    ) + (weight,)
    snapshot = RepositorySnapshot(repo_id=repo_id, revision=revision, files=files)
    keyed_contents = {
        (repo_id, revision, path): content for path, content in contents.items()
    }
    return FakeSource({repo_id: snapshot}, keyed_contents)
