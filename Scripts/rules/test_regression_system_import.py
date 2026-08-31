#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/verification"))

import regression_system_import as system_import


class FakeSimulator:
    def __init__(self, data_root: Path) -> None:
        self.data_root = data_root
        self.added: list[tuple[str, Path]] = []
        self.asset_counter = 0

    def resolve_booted_visionos_data_root(self, device_identifier: str) -> Path:
        return self.data_root

    def add_media(self, device_identifier: str, source: Path) -> None:
        self.added.append((device_identifier, source))
        self.asset_counter += 1
        media = self.data_root / "Media/DCIM/100APPLE"
        media.mkdir(parents=True, exist_ok=True)
        filename = f"IMG_{self.asset_counter:04d}.MP4"
        stored = media / filename
        stored.write_bytes(source.read_bytes())
        database = self.data_root / "Media/PhotoData/Photos.sqlite"
        database.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(database) as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ZASSET (
                    Z_PK INTEGER PRIMARY KEY,
                    ZUUID TEXT,
                    ZDIRECTORY TEXT,
                    ZFILENAME TEXT,
                    ZDURATION REAL,
                    ZTRASHEDSTATE INTEGER
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ZADDITIONALASSETATTRIBUTES (
                    ZASSET INTEGER,
                    ZORIGINALFILENAME TEXT,
                    ZORIGINALFILESIZE INTEGER
                )
                """
            )
            asset_uuid = f"00000000-0000-4000-8000-{self.asset_counter:012d}"
            cursor = connection.execute(
                """
                INSERT INTO ZASSET (
                    ZUUID, ZDIRECTORY, ZFILENAME, ZDURATION, ZTRASHEDSTATE
                ) VALUES (?, ?, ?, ?, 0)
                """,
                (asset_uuid, "DCIM/100APPLE", filename, 30.0),
            )
            connection.execute(
                """
                INSERT INTO ZADDITIONALASSETATTRIBUTES (
                    ZASSET, ZORIGINALFILENAME, ZORIGINALFILESIZE
                ) VALUES (?, ?, ?)
                """,
                (
                    cursor.lastrowid,
                    system_import.VISIBLE_FILENAME,
                    source.stat().st_size,
                ),
            )


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
            photo_poll_timeout_seconds=0.5,
        )
        self.simulator = FakeSimulator(self.data_root)

    def test_ensure_seeds_both_pickers_and_is_byte_stable(self) -> None:
        first = system_import.ensure(self.configuration, boundary=self.simulator)
        encoded = self.configuration.runtime_file.read_bytes()
        information = self.configuration.runtime_file.lstat()
        second = system_import.ensure(self.configuration, boundary=self.simulator)

        self.assertEqual(first, second)
        self.assertEqual(len(self.simulator.added), 1)
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
        self.assertEqual(
            first["photosPicker"]["authorizationMode"],
            "system-picker-no-library-authorization",
        )
        self.assertEqual(
            first["filesPicker"]["digest"], first["photosPicker"]["digest"]
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
        tampered["photosPicker"]["digest"] = "sha256:" + "0" * 64
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
        self.assertEqual(len(self.simulator.added), 1)

    def test_duplicate_or_tampered_photo_asset_fails_closed(self) -> None:
        system_import.ensure(self.configuration, boundary=self.simulator)
        self.simulator.add_media(self.device, self.fixture)
        report = system_import.run_preflight(
            self.configuration, boundary=self.simulator
        )
        self.assertFalse(report["ready"])
        self.assertIn("duplicate", report["reason"])
        self.assertFalse(self.configuration.runtime_file.exists())

        database = self.data_root / "Media/PhotoData/Photos.sqlite"
        with sqlite3.connect(database) as connection:
            connection.execute(
                "DELETE FROM ZADDITIONALASSETATTRIBUTES WHERE ZASSET = 2"
            )
            connection.execute("DELETE FROM ZASSET WHERE Z_PK = 2")
        stored = self.data_root / "Media/DCIM/100APPLE/IMG_0001.MP4"
        stored.write_bytes(b"tampered")
        report = system_import.run_preflight(
            self.configuration, boundary=self.simulator
        )
        self.assertFalse(report["ready"])
        self.assertIn("digest mismatch", report["reason"])

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

    def test_configuration_rejects_non_uuid_and_nonpositive_timeout(self) -> None:
        with self.assertRaisesRegex(
            system_import.SystemImportConfigurationError, "Simulator UUID"
        ):
            system_import.SystemImportConfiguration("booted")
        with self.assertRaisesRegex(
            system_import.SystemImportConfigurationError, "positive"
        ):
            system_import.SystemImportConfiguration(
                self.device, photo_poll_timeout_seconds=0
            )

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
