#!/usr/bin/env python3
"""Stage a registered disc in the app container through a leased setup Operation."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import tempfile
from typing import Protocol

from stage_registered_fixture import FixtureStageError


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REGISTRY = REPOSITORY_ROOT / "Tests/Fixtures/bluray-disc-registry.json"
INBOX = "Documents/TestMediaInbox"


class Transport(Protocol):
    lane: str
    target: str

    def copy_to_container(self, source: Path, destination: str) -> None: ...
    def copy_from_container(self, source: str, destination: Path) -> None: ...


def _sha256(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            size += len(block)
            digest.update(block)
    return digest.hexdigest(), size


def _registered_disc(identifier: str) -> tuple[dict, str]:
    encoded = REGISTRY.read_bytes()
    registry = json.loads(encoded)
    if registry.get("schemaVersion") != 1 or not isinstance(registry.get("discs"), list):
        raise FixtureStageError("Blu-ray registry schema is invalid")
    matches = [item for item in registry["discs"] if item.get("id") == identifier]
    if len(matches) != 1:
        raise FixtureStageError(f"Blu-ray fixture is not uniquely registered: {identifier}")
    entry = matches[0]
    relative = entry.get("relativePath")
    if not isinstance(relative, str) or "\\" in relative:
        raise FixtureStageError("Blu-ray fixture path must be relative POSIX")
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or len(path.parts) < 2:
        raise FixtureStageError("Blu-ray fixture path escapes sourceRoot")
    if entry.get("kind") not in ("iso", "directory"):
        raise FixtureStageError("Blu-ray fixture kind is invalid")
    return entry, hashlib.sha256(encoded).hexdigest()


def _files(source: Path) -> list[Path]:
    files: list[Path] = []
    for item in source.rglob("*"):
        if item.is_symlink():
            raise FixtureStageError(f"Blu-ray directory contains a symlink: {item}")
        if item.is_file():
            files.append(item)
    return sorted(files)


def stage_registered_bluray(
    *, identifier: str, source_root: Path, transport: Transport
) -> dict[str, object]:
    if transport.lane != "simulator":
        raise FixtureStageError("Blu-ray corpus staging is simulator-only")
    if not source_root.is_absolute() or not source_root.is_dir():
        raise FixtureStageError("sourceRoot must be an absolute existing directory")
    entry, registry_digest = _registered_disc(identifier)
    root = source_root.resolve()
    relative = PurePosixPath(entry["relativePath"])
    source = root.joinpath(*relative.parts).resolve()
    if not source.is_relative_to(root):
        raise FixtureStageError("Blu-ray fixture resolves outside sourceRoot")
    kind = entry["kind"]
    if kind == "iso":
        if not source.is_file():
            raise FixtureStageError(f"Blu-ray ISO is missing: {source}")
        files = [source]
        expected, _ = _sha256(source)
        if expected != entry["sha256"]:
            raise FixtureStageError("Blu-ray ISO source digest differs from registry")
    else:
        if not source.is_dir() or source.is_symlink():
            raise FixtureStageError(f"Blu-ray directory is missing: {source}")
        bdmv = source / "BDMV"
        if not bdmv.is_dir():
            raise FixtureStageError("Blu-ray directory has no BDMV child")
        index_digest, _ = _sha256(bdmv / "index.bdmv")
        if index_digest != entry["indexSHA256"]:
            raise FixtureStageError("Blu-ray index differs from registry")
        files = _files(source)
        if len(list((bdmv / "PLAYLIST").glob("*.mpls"))) != entry["playlistCount"]:
            raise FixtureStageError("Blu-ray playlist count differs from registry")
        if len(list((bdmv / "STREAM").glob("*.m2ts"))) != entry["streamCount"]:
            raise FixtureStageError("Blu-ray stream count differs from registry")
    if not files:
        raise FixtureStageError("Blu-ray fixture contains no regular files")

    destination_root = f"{INBOX}/{source.name}"
    manifest = hashlib.sha256()
    byte_count = 0
    with tempfile.TemporaryDirectory(prefix="enchron-bluray-copyback-") as temporary:
        copyback = Path(temporary) / "copyback"
        for item in files:
            member = PurePosixPath(item.name) if kind == "iso" else PurePosixPath(item.relative_to(source).as_posix())
            destination = f"{INBOX}/{member}" if kind == "iso" else f"{destination_root}/{member}"
            before_digest, before_size = _sha256(item)
            transport.copy_to_container(item, destination)
            transport.copy_from_container(destination, copyback)
            if not copyback.is_file():
                raise FixtureStageError(f"Blu-ray copy-back missing: {member}")
            after_digest, after_size = _sha256(copyback)
            if (after_digest, after_size) != (before_digest, before_size):
                raise FixtureStageError(f"Blu-ray copy-back differs: {member}")
            manifest.update(member.as_posix().encode("utf-8") + b"\0")
            manifest.update(bytes.fromhex(before_digest))
            manifest.update(before_size.to_bytes(8, "big"))
            byte_count += before_size
    receipt: dict[str, object] = {
        "schema": "bluray-stage-receipt@1",
        "fixtureID": identifier,
        "registryDigest": "sha256:" + registry_digest,
        "sourceRoot": str(root),
        "sourceRelativePath": relative.as_posix(),
        "lane": transport.lane,
        "target": transport.target,
        "destination": destination_root,
        "fileCount": len(files),
        "byteLength": byte_count,
        "productSetup": {
            "verb": "importMedia" if kind == "iso" else "importStagedFolder",
            "arguments": {"file": source.name} if kind == "iso"
                else {"directory": source.name, "entry": "root"},
        },
        "copyBackManifestDigest": "sha256:" + manifest.hexdigest(),
        "injectionBlindSpot": "Container staging bypasses Files import and source connection; subsequent title-card activation is real UI input.",
    }
    receipt["receiptDigest"] = "sha256:" + hashlib.sha256(
        json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return receipt
