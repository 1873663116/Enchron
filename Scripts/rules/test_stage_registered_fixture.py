#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import stage_registered_fixture as staging


class FakeTransport:
    def __init__(self, lane: str = "simulator", mutate_copyback: bool = False) -> None:
        self.lane = lane
        self.target = "target-1"
        self.mutate_copyback = mutate_copyback
        self.container: dict[str, bytes] = {}
        self.destinations: list[str] = []

    def copy_to_container(self, source: Path, destination: str) -> None:
        self.destinations.append(destination)
        self.container[destination] = source.read_bytes()

    def copy_from_container(self, source: str, destination: Path) -> None:
        data = self.container[source]
        destination.write_bytes(data + b"bad" if self.mutate_copyback else data)


class StageRegisteredFixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="fixture-stage-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source_root = self.root / "source"
        self.source_root.mkdir()
        self.bytes = b"registered bytes"
        self.relative = "TestVectors/fixture.mp4"
        source = self.source_root / self.relative
        source.parent.mkdir()
        source.write_bytes(self.bytes)
        self.digest = hashlib.sha256(self.bytes).hexdigest()

    def registry_path(self, fixtures: list[dict[str, object]]) -> Path:
        path = self.root / "registry.json"
        path.write_text(
            json.dumps({"schemaVersion": 2, "fixtures": fixtures}),
            encoding="utf-8",
        )
        return path

    def entry(self, **changes: object) -> dict[str, object]:
        entry: dict[str, object] = {
            "id": "fixture-1",
            "deviceImportPath": self.relative,
            "sha256": self.digest,
        }
        entry.update(changes)
        return entry

    def stage(
        self,
        registry: staging.FixtureRegistry,
        transport: FakeTransport | None = None,
    ) -> dict[str, object]:
        return staging.stage_registered_fixture(
            registry=registry,
            fixture_id="fixture-1",
            source_root=self.source_root.resolve(),
            transport=transport or FakeTransport(),
        )

    def test_stages_one_file_and_binds_round_trip_receipt(self) -> None:
        transport = FakeTransport("device")
        receipt = self.stage(
            staging.FixtureRegistry.load(self.registry_path([self.entry()])),
            transport,
        )
        self.assertEqual(transport.destinations, ["Documents/TestMediaInbox/fixture.mp4"])
        self.assertEqual(receipt["schema"], "fixture-stage-receipt@1")
        self.assertEqual(receipt["lane"], "device")
        self.assertEqual(receipt["source"]["digest"], "sha256:" + self.digest)
        self.assertEqual(receipt["copyBack"]["digest"], "sha256:" + self.digest)
        self.assertRegex(receipt["receiptDigest"], r"^sha256:[0-9a-f]{64}$")

    def test_fixture_without_device_import_path_cannot_be_staged(self) -> None:
        registry = staging.FixtureRegistry.load(
            self.registry_path([{"id": "fixture-1", "sha256": self.digest}])
        )
        with self.assertRaisesRegex(staging.FixtureStageError, "no deviceImportPath"):
            self.stage(registry)

    def test_registry_rejects_bad_digest_and_path_escape(self) -> None:
        for entry in (
            self.entry(sha256="bad"),
            self.entry(deviceImportPath="../escape.mp4"),
            self.entry(deviceImportPath="/absolute.mp4"),
        ):
            with self.subTest(entry=entry), self.assertRaises(staging.FixtureStageError):
                staging.FixtureRegistry.load(self.registry_path([entry]))

    def test_source_digest_mismatch_is_rejected_before_transport(self) -> None:
        registry = staging.FixtureRegistry.load(
            self.registry_path([self.entry(sha256="0" * 64)])
        )
        transport = FakeTransport()
        with self.assertRaisesRegex(staging.FixtureStageError, "source digest mismatch"):
            self.stage(registry, transport)
        self.assertEqual(transport.destinations, [])

    def test_copy_back_mismatch_is_rejected(self) -> None:
        registry = staging.FixtureRegistry.load(self.registry_path([self.entry()]))
        with self.assertRaisesRegex(staging.FixtureStageError, "round-trip"):
            self.stage(registry, FakeTransport(mutate_copyback=True))

    def test_relative_source_root_is_rejected(self) -> None:
        registry = staging.FixtureRegistry.load(self.registry_path([self.entry()]))
        with self.assertRaisesRegex(staging.FixtureStageError, "absolute"):
            staging.stage_registered_fixture(
                registry=registry,
                fixture_id="fixture-1",
                source_root=Path("relative"),
                transport=FakeTransport(),
            )

    def test_transport_lane_is_derived_from_its_target_not_process_environment(self) -> None:
        with (
            mock.patch.object(staging.enchron_target, "is_simulator", return_value=True),
            mock.patch.object(
                staging.enchron_target, "target_device", return_value="OTHER-TARGET"
            ) as process_target,
        ):
            transport = staging.EnchronStageTransport(
                "simulator",
                "LEASE-TARGET",
                "com.example.App",
                "/Applications/Xcode.app/Contents/Developer",
            )

        self.assertEqual(transport.target, "LEASE-TARGET")
        process_target.assert_not_called()

    def test_current_registry_population_is_38_with_37_stageable(self) -> None:
        registry = staging.FixtureRegistry.load(staging.DEFAULT_REGISTRY)
        self.assertEqual(registry.total_count, 38)
        self.assertEqual(len(registry.fixtures), 37)

    def test_current_registry_source_root_is_workspace_test_media(self) -> None:
        payload = json.loads(staging.DEFAULT_REGISTRY.read_text(encoding="utf-8"))
        source_root = (staging.REPOSITORY_ROOT.parent / "TestMedia").resolve()
        self.assertEqual(payload["deviceMediaRoot"], "$WORKSPACE/TestMedia")
        self.assertTrue(source_root.is_absolute())
        if not source_root.is_dir():
            self.skipTest("workspace TestMedia is not available")
        for fixture in staging.FixtureRegistry.load(staging.DEFAULT_REGISTRY).fixtures:
            with self.subTest(fixture=fixture.identifier):
                source = (source_root / Path(*fixture.import_path.parts)).resolve()
                self.assertTrue(source.is_relative_to(source_root))
                self.assertTrue(source.is_file())


if __name__ == "__main__":
    unittest.main()
