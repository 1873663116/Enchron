from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import stage_registered_bluray as staging


class FakeTransport:
    lane = "simulator"
    target = "simulator-test"

    def __init__(self, corrupt: bool = False) -> None:
        self.files: dict[str, bytes] = {}
        self.corrupt = corrupt

    def copy_to_container(self, source: Path, destination: str) -> None:
        self.files[destination] = source.read_bytes()

    def copy_from_container(self, source: str, destination: Path) -> None:
        destination.write_bytes(self.files[source] + (b"bad" if self.corrupt else b""))


class BluRayStageTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "Media/Disc"
        (self.source / "BDMV/PLAYLIST").mkdir(parents=True)
        (self.source / "BDMV/STREAM").mkdir()
        (self.source / "BDMV/index.bdmv").write_bytes(b"index")
        (self.source / "BDMV/PLAYLIST/00000.mpls").write_bytes(b"playlist")
        (self.source / "BDMV/STREAM/00000.m2ts").write_bytes(b"stream")
        self.registry = self.root / "registry.json"
        self.registry.write_text(json.dumps({
            "schemaVersion": 1,
            "discs": [{
                "id": "bluray-test-directory",
                "relativePath": "Media/Disc",
                "kind": "directory",
                "indexSHA256": hashlib.sha256(b"index").hexdigest(),
                "playlistCount": 1,
                "streamCount": 1,
            }],
        }))

    def test_stage_directory_preserves_files_and_returns_manifest(self) -> None:
        transport = FakeTransport()
        with mock.patch.object(staging, "REGISTRY", self.registry):
            receipt = staging.stage_registered_bluray(
                identifier="bluray-test-directory", source_root=self.root, transport=transport
            )
        self.assertEqual(receipt["fileCount"], 3)
        self.assertEqual(receipt["destination"], "Documents/TestMediaInbox/Disc")
        self.assertEqual(receipt["productSetup"], {
            "verb": "importStagedFolder", "arguments": {"directory": "Disc", "entry": "root"}
        })
        self.assertEqual(transport.files["Documents/TestMediaInbox/Disc/BDMV/STREAM/00000.m2ts"], b"stream")
        self.assertRegex(receipt["copyBackManifestDigest"], r"^sha256:[0-9a-f]{64}$")

    def test_corrupt_copyback_fails(self) -> None:
        with mock.patch.object(staging, "REGISTRY", self.registry):
            with self.assertRaisesRegex(staging.FixtureStageError, "copy-back differs"):
                staging.stage_registered_bluray(
                    identifier="bluray-test-directory", source_root=self.root,
                    transport=FakeTransport(corrupt=True),
                )

    def test_symlink_rejected(self) -> None:
        (self.source / "BDMV/STREAM/link.m2ts").symlink_to(self.source / "BDMV/STREAM/00000.m2ts")
        with mock.patch.object(staging, "REGISTRY", self.registry):
            with self.assertRaisesRegex(staging.FixtureStageError, "symlink"):
                staging.stage_registered_bluray(
                    identifier="bluray-test-directory", source_root=self.root,
                    transport=FakeTransport(),
                )


if __name__ == "__main__":
    unittest.main()
