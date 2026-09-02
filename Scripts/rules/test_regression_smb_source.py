#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/verification"))

import regression_smb_source as smb


class FakeMount:
    def __init__(self, source: Path, *, failure: Exception | None = None) -> None:
        self.source = source
        self.failure = failure
        self.mounts: list[tuple[str, str, str, str, Path]] = []
        self.unmounts: list[Path] = []
        self.listed: list[tuple[str, str, str]] = []

    def shares(self, address: str, user: str, password: str) -> list[str]:
        self.listed.append((address, user, password))
        return ["Cortisol", "TestMedia"]

    def mount(
        self,
        address: str,
        share_name: str,
        user: str,
        password: str,
        mount_point: Path,
    ) -> None:
        self.mounts.append((address, share_name, user, password, mount_point))
        if self.failure is not None:
            raise self.failure
        shutil.copytree(self.source, mount_point, dirs_exist_ok=True)

    def unmount(self, mount_point: Path) -> None:
        self.unmounts.append(mount_point)


class SMBSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="regression-smb-test-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name).resolve()
        self.runtime_root = root / "runtime"
        self.share_root = root / "share"
        self.environment_file = root / ".env"
        self.registry_path = root / "fixture-registry.json"
        self.user = "fixture-user"
        self.password = "fixture-password-that-must-not-leak"
        self.environment_file.write_text(
            f"SMB_USER={self.user}\nSMB_PASSWORD={self.password}\n",
            encoding="utf-8",
        )
        fixtures = []
        paths = (
            "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv",
            "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.zh-CN.srt",
            "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.styled.ass",
        )
        for index, relative in enumerate(paths, start=1):
            payload = (f"registered aggregate object {index}\n" * index).encode()
            destination = self.share_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(payload)
            fixtures.append(
                {
                    "id": f"aggregate-{index}",
                    "deviceImportPath": relative,
                    "sha256": hashlib.sha256(payload).hexdigest(),
                    "regressionSets": ["remote-aggregate"],
                }
            )
        self.registry_path.write_text(
            json.dumps({"schemaVersion": 2, "fixtures": fixtures}),
            encoding="utf-8",
        )
        self.configuration = smb.SMBSourceConfiguration(
            runtime_root=self.runtime_root,
            registry_path=self.registry_path,
            environment_file=self.environment_file,
            address="192.168.64.1",
        )

    def test_ensure_mounts_registered_aggregate_and_writes_stable_0600_identity(self) -> None:
        mount = FakeMount(self.share_root)
        first = smb.ensure(self.configuration, mount=mount)
        encoded = self.configuration.runtime_file.read_bytes()
        first_information = self.configuration.runtime_file.lstat()
        second = smb.ensure(self.configuration, mount=mount)

        self.assertEqual(first, second)
        self.assertEqual(encoded, self.configuration.runtime_file.read_bytes())
        information = self.configuration.runtime_file.lstat()
        self.assertEqual(information.st_ino, first_information.st_ino)
        self.assertEqual(information.st_mtime_ns, first_information.st_mtime_ns)
        self.assertTrue(stat.S_ISREG(information.st_mode))
        self.assertEqual(information.st_uid, os.getuid())
        self.assertEqual(stat.S_IMODE(information.st_mode), 0o600)
        runtime = json.loads(encoded)
        self.assertEqual(set(runtime), smb.RUNTIME_DOCUMENT_KEYS)
        self.assertEqual(runtime["address"], "192.168.64.1")
        self.assertEqual(runtime["user"], self.user)
        self.assertEqual(runtime["password"], self.password)
        self.assertEqual(runtime["shareName"], "TestMedia")
        self.assertRegex(runtime["sourceIdentity"], r"^smb-source:[0-9a-f]{24}$")
        self.assertRegex(runtime["aggregateDigest"], r"^sha256:[0-9a-f]{64}$")
        self.assertEqual(len(runtime["aggregateManifestHashes"]), 3)
        self.assertEqual(len(runtime["aggregatePaths"]), 3)
        self.assertEqual(len(mount.mounts), 2)
        self.assertEqual(len(mount.unmounts), 2)

        rendered = smb.render_report(first)
        self.assertNotIn(self.user, rendered)
        self.assertNotIn(self.password, rendered)
        self.assertNotIn("authorization", rendered.casefold())
        identity = first["runtimeIdentity"]
        self.assertEqual(identity["mode"], "0600")
        self.assertEqual(
            identity["addressReference"],
            {"textFile": str(self.configuration.runtime_file), "textJSONKey": "address"},
        )
        self.assertEqual(identity["userReference"]["textJSONKey"], "user")
        self.assertEqual(identity["passwordReference"]["textJSONKey"], "password")
        smb.validate_preflight_report(first, self.configuration.runtime_file)

    def test_credentials_are_read_only_from_env_and_failures_are_redacted(self) -> None:
        rejected = FakeMount(
            self.share_root,
            failure=smb.SMBCredentialsRejected("SMB credentials were rejected"),
        )
        report = smb.run_preflight(self.configuration, mount=rejected)
        encoded = smb.render_report(report)
        self.assertFalse(report["ready"])
        self.assertIn("credentials were rejected", report["reason"])
        self.assertNotIn(self.user, encoded)
        self.assertNotIn(self.password, encoded)
        self.assertFalse(self.configuration.runtime_file.exists())

        self.environment_file.write_text("SMB_USER=fixture-user\n", encoding="utf-8")
        missing = smb.run_preflight(self.configuration, mount=FakeMount(self.share_root))
        self.assertFalse(missing["ready"])
        self.assertEqual(missing["reason"], "SMB_USER or SMB_PASSWORD is missing from .env")

    def test_mount_failure_and_tampered_aggregate_fail_closed_without_runtime_identity(self) -> None:
        smb.ensure(self.configuration, mount=FakeMount(self.share_root))
        self.assertTrue(self.configuration.runtime_file.exists())
        failed = smb.run_preflight(
            self.configuration,
            mount=FakeMount(
                self.share_root,
                failure=smb.SMBMountRejected("SMB share mount failed"),
            ),
        )
        self.assertFalse(failed["ready"])
        self.assertEqual(failed["reason"], "SMB share mount failed")
        self.assertFalse(self.configuration.runtime_file.exists())

        first = next(self.share_root.rglob("*.mkv"))
        first.write_bytes(b"tampered")
        tampered = smb.run_preflight(
            self.configuration, mount=FakeMount(self.share_root)
        )
        self.assertFalse(tampered["ready"])
        self.assertIn("registered aggregate digest mismatch", tampered["reason"])
        self.assertFalse(self.configuration.runtime_file.exists())

    def test_runtime_validation_rejects_permissions_and_secret_bearing_reports(self) -> None:
        report = smb.ensure(self.configuration, mount=FakeMount(self.share_root))
        os.chmod(self.configuration.runtime_file, 0o644)
        with self.assertRaisesRegex(smb.SMBSourceConfigurationError, "0600"):
            smb.validate_preflight_report(report, self.configuration.runtime_file)

        os.chmod(self.configuration.runtime_file, 0o600)
        leaked = dict(report)
        leaked["password"] = self.password
        with self.assertRaisesRegex(smb.SMBSourceConfigurationError, "secret"):
            smb.validate_preflight_report(leaked, self.configuration.runtime_file)

    def test_cli_stdout_is_sanitized(self) -> None:
        ready = smb.ensure(self.configuration, mount=FakeMount(self.share_root))
        output = io.StringIO()
        with (
            mock.patch.object(smb, "run_preflight", return_value=ready),
            contextlib.redirect_stdout(output),
        ):
            status = smb.main(
                [
                    "ensure",
                    "--address",
                    "192.168.64.1",
                    "--runtime-root",
                    str(self.runtime_root),
                    "--registry",
                    str(self.registry_path),
                    "--environment-file",
                    str(self.environment_file),
                ]
            )
        self.assertEqual(status, 0)
        rendered = output.getvalue()
        self.assertNotIn(self.user, rendered)
        self.assertNotIn(self.password, rendered)
        self.assertEqual(json.loads(rendered)["check"], "smb-aggregate")

    def test_mount_uses_in_process_framework_not_credential_bearing_commands(self) -> None:
        source = Path(smb.__file__).read_text(encoding="utf-8")
        self.assertNotIn("mount_smbfs", source)
        self.assertNotIn("SMB_PASSWORD", source.partition("def main")[2])

        class FakeLibrary:
            def __init__(self, open_status: int = 0, mount_status: int = 0) -> None:
                self.open_status = open_status
                self.mount_status = mount_status
                self.targets: list[bytes] = []
                self.mount_points: list[bytes] = []
                self.releases = 0

            def SMBOpenServerEx(self, target, handle, options):
                self.targets.append(target)
                return self.open_status

            def SMBMountShare(self, handle, share, mount_point):
                self.mount_points.append(mount_point)
                return self.mount_status

            def SMBReleaseServer(self, handle):
                self.releases += 1
                return 0

        boundary = smb.DarwinSMBMount()
        library = FakeLibrary()
        mount_point = self.runtime_root / "framework-mount"
        mount_point.mkdir(parents=True)
        with (
            mock.patch.object(boundary, "_library", return_value=library),
            mock.patch.object(
                smb.subprocess,
                "run",
                return_value=mock.Mock(returncode=0),
            ) as run,
        ):
            boundary.mount(
                "192.168.64.1",
                "TestMedia",
                self.user,
                self.password,
                mount_point,
            )
            boundary.unmount(mount_point)
        self.assertIn(self.user.encode(), library.targets[0])
        self.assertIn(self.password.encode(), library.targets[0])
        command = run.call_args.args[0]
        self.assertEqual(command, ["/sbin/umount", str(mount_point)])
        self.assertNotIn(self.user, json.dumps(command))
        self.assertNotIn(self.password, json.dumps(command))

        rejected = smb.DarwinSMBMount()
        with mock.patch.object(
            rejected,
            "_library",
            return_value=FakeLibrary(open_status=0xC000006D),
        ):
            with self.assertRaisesRegex(
                smb.SMBCredentialsRejected, "credentials were rejected"
            ) as caught:
                rejected.mount(
                    "192.168.64.1",
                    "TestMedia",
                    self.user,
                    self.password,
                    mount_point,
                )
        self.assertNotIn(self.user, str(caught.exception))
        self.assertNotIn(self.password, str(caught.exception))

    def test_journey_preflight_delegates_without_legacy_credential_argv(self) -> None:
        import journey_preflight

        source = Path(journey_preflight.__file__).read_text(encoding="utf-8")
        self.assertNotIn("mount_smbfs", source)
        expected = {"schema": smb.REPORT_SCHEMA, "check": "smb-aggregate", "ready": True}
        host_value = journey_preflight.HostAddress(host="192.168.64.1", hostKind="lan-ip")
        with (
            mock.patch.object(
                journey_preflight, "host_address", return_value=host_value
            ),
            mock.patch.object(
                journey_preflight.smb_source,
                "run_preflight",
                return_value=expected,
            ) as run,
        ):
            self.assertEqual(journey_preflight.check_smb(), expected)
        configuration = run.call_args.args[0]
        self.assertEqual(configuration.environment_file, smb.DEFAULT_ENVIRONMENT_FILE)
        self.assertEqual(configuration.share_name, "TestMedia")
        self.assertEqual(configuration.address, "192.168.64.1")



class HostShareListingTests(unittest.TestCase):
    LISTING = """Share                                           Type    Comments
-------------------------------
MacBackup                                       Disk    
Cortisol                                        Disk    
IPC$                                            Pipe    
Macintosh HD                                    Disk    
TestMedia                                       Disk    

5 shares listed
"""

    def test_disk_shares_are_returned_sorted(self) -> None:
        self.assertEqual(
            smb._parse_shares(self.LISTING),
            ["Cortisol", "MacBackup", "Macintosh HD", "TestMedia"],
        )

    def test_an_administrative_share_is_excluded(self) -> None:
        self.assertNotIn("IPC$", smb._parse_shares(self.LISTING))

    def test_a_dollar_suffixed_disk_share_is_excluded(self) -> None:
        listing = self.LISTING.replace("MacBackup      ", "ADMIN$         ")

        self.assertNotIn("ADMIN$", smb._parse_shares(listing))

    def test_a_listing_with_no_disk_share_is_empty(self) -> None:
        self.assertEqual(smb._parse_shares("Share  Type\n----\nIPC$  Pipe\n"), [])

if __name__ == "__main__":
    unittest.main()
