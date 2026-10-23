#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/verification"))

import regression_system_import as system_import


class FakeSimulator:
    def __init__(self, data_root: Path) -> None:
        self.data_root = data_root

    def resolve_booted_visionos_data_root(self, device_identifier: str) -> Path:
        return self.data_root


class SystemImportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(
            prefix="regression-system-import-test-"
        )
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name).resolve()
        self.data_root = root / "CoreSimulator/Devices/device/data"
        self.fixture_root = root / "TestMedia"
        self.runtime_root = root / "runtime"
        self.registry = root / "fixture-registry.json"
        self.device = "11111111-1111-4111-8111-111111111111"
        self.payload = b"fixed system import video bytes\n" * 128
        relative = Path(
            "TestVectors/Enchron/PlaybackBehavior/"
            "sdr-bframe-multiaudio-avsync-30s.mp4"
        )
        self.fixture = self.fixture_root / relative
        self.fixture.parent.mkdir(parents=True, exist_ok=True)
        self.fixture.write_bytes(self.payload)
        self.registry.write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "fixtures": [
                        {
                            "id": system_import.FIXTURE_ID,
                            "deviceImportPath": relative.as_posix(),
                            "sha256": hashlib.sha256(self.payload).hexdigest(),
                            "durationSeconds": 30.0,
                            "regressionSets": ["system-import"],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        group = self.data_root / "Containers/Shared/AppGroup/local-storage"
        storage = group / "File Provider Storage"
        storage.mkdir(parents=True, exist_ok=True)
        with (
            group / ".com.apple.mobile_container_manager.metadata.plist"
        ).open("wb") as output:
            plistlib.dump(
                {"MCMMetadataIdentifier": system_import.LOCAL_STORAGE_GROUP},
                output,
            )
        self.configuration = system_import.SystemImportConfiguration(
            device_identifier=self.device,
            runtime_root=self.runtime_root,
            registry_path=self.registry,
            fixture_root=self.fixture_root,
        )
        self.simulator = FakeSimulator(self.data_root)

    def test_ensure_seeds_the_files_picker_and_is_byte_stable(self) -> None:
        first = system_import.ensure(self.configuration, boundary=self.simulator)
        encoded = self.configuration.runtime_file.read_bytes()
        information = self.configuration.runtime_file.lstat()
        second = system_import.ensure(self.configuration, boundary=self.simulator)

        self.assertEqual(first, second)
        self.assertEqual(encoded, self.configuration.runtime_file.read_bytes())
        current = self.configuration.runtime_file.lstat()
        self.assertEqual(current.st_ino, information.st_ino)
        self.assertEqual(current.st_mtime_ns, information.st_mtime_ns)
        self.assertEqual(stat.S_IMODE(current.st_mode), 0o600)
        self.assertEqual(current.st_uid, os.getuid())
        self.assertTrue(first["ready"])
        self.assertEqual(first["target"]["kind"], "visionos-simulator")
        self.assertEqual(
            first["filesPicker"]["authorizationMode"],
            "system-picker-security-scoped",
        )
        runtime = system_import.validate_runtime(self.configuration.runtime_file)
        self.assertRegex(
            runtime["environmentIdentity"], r"^system-import:[0-9a-f]{24}$"
        )
        self.assertTrue(
            system_import.validate_preflight_report(
                first,
                device_identifier=self.device,
                runtime_file=self.configuration.runtime_file,
            )
        )

        tampered = json.loads(json.dumps(first))
        tampered["filesPicker"]["digest"] = "sha256:" + "0" * 64
        self.assertFalse(
            system_import.validate_preflight_report(
                tampered,
                device_identifier=self.device,
                runtime_file=self.configuration.runtime_file,
            )
        )
        self.assertFalse(
            system_import.validate_preflight_report(
                first,
                device_identifier="22222222-2222-4222-8222-222222222222",
                runtime_file=self.configuration.runtime_file,
            )
        )

    def test_existing_files_copy_is_repaired_before_runtime_is_published(self) -> None:
        storage = system_import._local_storage_root(self.data_root)
        destination = storage / system_import.VISIBLE_FILENAME
        destination.write_bytes(b"stale")

        system_import.ensure(self.configuration, boundary=self.simulator)

        self.assertEqual(destination.read_bytes(), self.payload)

    def test_registry_digest_and_file_provider_identity_fail_closed(self) -> None:
        self.fixture.write_bytes(b"changed")
        report = system_import.run_preflight(
            self.configuration, boundary=self.simulator
        )
        self.assertFalse(report["ready"])
        self.assertIn("digest mismatch", report["reason"])

        self.fixture.write_bytes(self.payload)
        group = self.data_root / "Containers/Shared/AppGroup/duplicate"
        (group / "File Provider Storage").mkdir(parents=True)
        with (
            group / ".com.apple.mobile_container_manager.metadata.plist"
        ).open("wb") as output:
            plistlib.dump(
                {"MCMMetadataIdentifier": system_import.LOCAL_STORAGE_GROUP},
                output,
            )
        report = system_import.run_preflight(
            self.configuration, boundary=self.simulator
        )
        self.assertFalse(report["ready"])
        self.assertIn("not unique", report["reason"])

    def test_runtime_permissions_and_fact_binding_are_strict(self) -> None:
        system_import.ensure(self.configuration, boundary=self.simulator)
        os.chmod(self.configuration.runtime_file, 0o644)
        with self.assertRaisesRegex(
            system_import.SystemImportConfigurationError, "0600"
        ):
            system_import.validate_runtime(self.configuration.runtime_file)

        os.chmod(self.configuration.runtime_file, 0o600)
        document = json.loads(
            self.configuration.runtime_file.read_text(encoding="utf-8")
        )
        document["filesPicker"]["displayName"] = "wrong.mp4"
        self.configuration.runtime_file.write_text(
            json.dumps(document), encoding="utf-8"
        )
        os.chmod(self.configuration.runtime_file, 0o600)
        with self.assertRaisesRegex(
            system_import.SystemImportConfigurationError,
            "not bound|Files picker identity",
        ):
            system_import.validate_runtime(self.configuration.runtime_file)

    def test_configuration_rejects_a_non_uuid_target(self) -> None:
        with self.assertRaisesRegex(
            system_import.SystemImportConfigurationError, "Simulator UUID"
        ):
            system_import.SystemImportConfiguration("booted")

    def test_simctl_boundary_accepts_xros_runtime_and_rejects_ios_runtime(self) -> None:
        expected = (
            Path(self.temporary.name)
            / "CoreSimulator"
            / "Devices"
            / self.device
            / "data"
        )
        expected.mkdir(parents=True)
        expected = expected.resolve()
        boundary = system_import.SimctlBoundary()
        inventory = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.xrOS-27-0": [
                    {
                        "udid": self.device,
                        "state": "Booted",
                        "isAvailable": True,
                    }
                ]
            }
        }

        def run(arguments: list[str]) -> subprocess.CompletedProcess[str]:
            if arguments[:2] == ["list", "devices"]:
                return subprocess.CompletedProcess(
                    arguments, 0, stdout=json.dumps(inventory), stderr=""
                )
            return subprocess.CompletedProcess(
                arguments, 0, stdout=str(expected) + "\n", stderr=""
            )

        boundary._run = run
        self.assertEqual(
            boundary.resolve_booted_visionos_data_root(self.device), expected
        )

        inventory["devices"] = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {
                    "udid": self.device,
                    "state": "Booted",
                    "isAvailable": True,
                }
            ]
        }
        with self.assertRaisesRegex(
            system_import.SystemImportUnavailable, "booted visionOS"
        ):
            boundary.resolve_booted_visionos_data_root(self.device)


if __name__ == "__main__":
    unittest.main()
