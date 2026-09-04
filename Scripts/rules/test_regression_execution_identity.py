#!/usr/bin/env python3

from __future__ import annotations

from contextlib import contextmanager
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.contracts import BoundLane
from regression.core.digest import canonical_bytes, digest_bytes
from regression.core.plan import ToolchainIdentity
import regression.execution_identity as identity
from regression.execution_identity import (
    ExecutionIdentityError,
    PhysicalVisionOSDevice,
    PhysicalVisionOSDeviceRegistry,
    freeze_execution_input,
    load_execution_input,
    load_frozen_test_launch,
    prepare_build_provenance,
    registered_physical_visionos_devices,
    registered_simulator_udids,
    repository_source_digest,
    write_execution_input,
)
from regression.runctl import _prepared_build_payload


TOOLCHAIN = ToolchainIdentity(
    "27.0",
    "27A5252f",
    "27.0",
    "24M5357a",
    "27.0",
    "24M5357a",
)
UI_TEST = "InteractiveDeviceUITests/testInteractiveDeviceSession()"


def _fixed_name(value: str) -> bytes:
    source = value.encode("ascii")
    return source + b"\0" * (16 - len(source))


def _macho(
    stamp: bytes,
    lane: BoundLane,
    *,
    platform: int | None = None,
    build_version_count: int = 1,
) -> bytes:
    packed_sdk = 27 << 16
    build_command = struct.pack(
        "<6I",
        0x32,
        24,
        platform
        if platform is not None
        else (12 if lane is BoundLane.SIMULATOR else 11),
        2 << 16,
        packed_sdk,
        0,
    )
    build_commands = build_command * build_version_count
    segment_size = 72 + 80
    command_bytes = len(build_commands) + segment_size
    data_offset = (32 + command_bytes + 15) & ~15
    file_size = data_offset + len(stamp)
    segment = struct.pack(
        "<II16sQQQQiiII",
        0x19,
        segment_size,
        _fixed_name("__TEXT"),
        0,
        file_size,
        0,
        file_size,
        7,
        5,
        1,
        0,
    )
    section = struct.pack(
        "<16s16sQQIIIIIIII",
        _fixed_name("__enchsrc"),
        _fixed_name("__TEXT"),
        0,
        len(stamp),
        data_offset,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    )
    header = struct.pack(
        "<8I",
        0xFEEDFACF,
        0x0100000C,
        0,
        6,
        build_version_count + 1,
        command_bytes,
        0,
        0,
    )
    commands = build_commands + segment + section
    return header + commands + b"\0" * (data_offset - len(header) - len(commands)) + stamp


class ExecutionIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        self.artifact = self.repository / ".runtime"
        self.environment = {
            "PATH": os.environ["PATH"],
            "HOME": self.temporary.name,
            "GIT_AUTHOR_NAME": "test",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "test",
            "GIT_COMMITTER_EMAIL": "test@example.com",
        }
        self.git("init", "-q")
        self.write_text(".gitignore", ".runtime/\n")
        self.write_text("Sources/App.swift", "let value = 1\n")
        self.write_text("Scripts/regression/runtime.py", "VALUE = 1\n")
        self.write_text("Scripts/verification/regression_adapter.py", "VALUE = 2\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "fixture")
        with self.boundaries():
            self.prepared = prepare_build_provenance(self.repository, self.artifact)
        self.source_digest = repository_source_digest(self.repository)
        self.write_configuration_receipt()
        self.products: dict[BoundLane, dict[str, Path]] = {}
        for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE):
            self.products[lane] = self.write_lane(lane)

    @staticmethod
    def physical_registry() -> PhysicalVisionOSDeviceRegistry:
        return PhysicalVisionOSDeviceRegistry(
            (
                PhysicalVisionOSDevice("DEVICE-UDID", "DEVICE-CORE-ID"),
                PhysicalVisionOSDevice("OTHER-DEVICE-UDID", "OTHER-DEVICE-CORE-ID"),
            )
        )

    @contextmanager
    def boundaries(self, *, toolchain: ToolchainIdentity = TOOLCHAIN):
        with (
            patch.object(identity, "query_toolchain_identity", return_value=toolchain),
            patch.object(
                identity,
                "registered_simulator_udids",
                return_value=frozenset({"SIM-UDID"}),
            ),
            patch.object(
                identity,
                "registered_physical_visionos_devices",
                return_value=self.physical_registry(),
            ),
        ):
            yield

    def write_text(self, relative: str, source: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")
        return path

    def write_bytes(self, relative: str, source: bytes) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(source)
        return path

    def git(self, *arguments: str) -> str:
        completed = subprocess.run(
            ["git", "-C", str(self.repository), *arguments],
            capture_output=True,
            text=True,
            check=True,
            env=self.environment,
        )
        return completed.stdout.strip()

    def write_configuration_receipt(self) -> Path:
        fake = "sha256:" + "a" * 64
        payload = {
            "schema": "enchron.regression.configuration-receipt",
            "schemaVersion": 1,
            "sourceDigest": str(self.source_digest),
            "blueprintDigest": fake,
            "catalogDigest": fake,
            "reviewCompletionDigest": fake,
            "semanticAuthorityDigest": fake,
            "preFreezeVerification": {},
            "mergeRunReceipt": {},
            "buildLogs": {},
        }
        path = self.artifact / "configuration-receipt.json"
        path.write_bytes(canonical_bytes(payload) + b"\n")
        return path

    def xctestrun_payload(self, lane: BoundLane) -> dict[str, object]:
        configuration = "Debug"
        return {
            "TestPlan": {"Name": f"Interactive-{lane.value}", "IsDefault": True},
            "TestConfigurations": [
                {
                    "Name": "Interactive",
                    "IsEnabled": True,
                    "TestTargets": [
                        {
                            "BlueprintName": "EnchronAppUITests",
                            "TestBundlePath": (
                                "__TESTHOST__/PlugIns/EnchronAppUITests.xctest"
                            ),
                            "TestHostPath": (
                                f"__TESTROOT__/{configuration}/"
                                "EnchronAppUITests-Runner.app"
                            ),
                            "UITargetAppPath": (
                                f"__TESTROOT__/{configuration}/Enchron.app"
                            ),
                            "DependentProductPaths": [
                                f"__TESTROOT__/{configuration}/Enchron.app",
                                (
                                    f"__TESTROOT__/{configuration}/"
                                    "EnchronAppUITests-Runner.app"
                                ),
                                f"__TESTROOT__/{configuration}/Shared.framework",
                            ],
                            "OnlyTestIdentifiers": [UI_TEST],
                            "TestingEnvironmentVariables": {},
                        }
                    ],
                },
                {
                    "Name": "Disabled",
                    "IsEnabled": False,
                    "TestTargets": [],
                },
            ],
            "CodeCoverageBuildableInfos": [],
            "__xctestrun_metadata__": {"FormatVersion": 2},
        }

    def write_lane(self, lane: BoundLane) -> dict[str, Path]:
        prefix = (
            self.artifact
            / "lanes"
            / lane.value
            / "DerivedData"
            / "Build"
            / "Products"
        )
        configuration = prefix / "Debug"
        app = configuration / "Enchron.app"
        runner = configuration / "EnchronAppUITests-Runner.app"
        test_bundle = runner / "PlugIns" / "EnchronAppUITests.xctest"
        shared = configuration / "Shared.framework"
        for directory in (app, test_bundle, shared):
            directory.mkdir(parents=True, exist_ok=True)
        (app / "Info.plist").write_bytes(
            plistlib.dumps(
                {
                    "CFBundleIdentifier": "com.example.Enchron",
                    "CFBundleExecutable": "Enchron",
                },
                sort_keys=True,
            )
        )
        (app / "Enchron").write_bytes(f"{lane.value}-launch-stub".encode())
        stamp = self.artifact / "build-provenance" / f"{lane.value}.json"
        code = app / "Enchron.debug.dylib"
        code.write_bytes(_macho(stamp.read_bytes(), lane))
        (runner / "Runner").write_bytes(f"{lane.value}-runner".encode())
        (test_bundle / "EnchronAppUITests").write_bytes(
            f"{lane.value}-tests".encode()
        )
        dependency = shared / "Shared"
        dependency.write_bytes(f"{lane.value}-dependent-product".encode())
        xctestrun = prefix / f"Enchron-{lane.value}.xctestrun"
        xctestrun.write_bytes(
            plistlib.dumps(self.xctestrun_payload(lane), sort_keys=True)
        )
        return {
            "root": prefix,
            "app": app,
            "runner": runner,
            "test_bundle": test_bundle,
            "dependency": dependency,
            "code": code,
            "xctestrun": xctestrun,
        }

    def freeze(self, *, device_target: str = "DEVICE-UDID"):
        with self.boundaries():
            return freeze_execution_input(
                self.repository,
                self.artifact,
                {
                    BoundLane.SIMULATOR: "SIM-UDID",
                    BoundLane.DEVICE: device_target,
                },
                "gpt-5.6-sol",
            )

    def write_input(self):
        frozen = self.freeze()
        path = self.artifact / "execution-input.json"
        write_execution_input(path, frozen)
        return frozen, path

    def load(self, path: Path):
        with self.boundaries():
            return load_execution_input(path)

    def mutate_xctestrun(self, lane: BoundLane, mutate) -> None:
        path = self.products[lane]["xctestrun"]
        payload = plistlib.loads(path.read_bytes())
        mutate(payload)
        path.write_bytes(plistlib.dumps(payload, sort_keys=True))

    def test_prepare_writes_exact_canonical_lane_stamps(self) -> None:
        self.assertEqual(
            (BoundLane.SIMULATOR, BoundLane.DEVICE),
            tuple(item.lane for item in self.prepared),
        )
        for prepared in self.prepared:
            self.assertEqual(
                self.artifact / "build-provenance" / f"{prepared.lane.value}.json",
                prepared.path,
            )
            source = prepared.path.read_bytes()
            payload = json.loads(source)
            self.assertEqual("enchron.regression.link-provenance", payload["schema"])
            self.assertEqual(1, payload["schemaVersion"])
            self.assertEqual(prepared.lane.value, payload["lane"])
            self.assertEqual(str(self.source_digest), payload["sourceTreeDigest"])
            self.assertEqual(digest_bytes(source), prepared.digest)
            self.assertEqual(self.source_digest, prepared.identity.source_tree_digest)
            self.assertEqual(TOOLCHAIN, prepared.identity.toolchain)
            self.assertEqual(
                "ENCHRON_REGRESSION_LINK_PROVENANCE_FLAG="
                f"-Wl,-sectcreate,__TEXT,__enchsrc,{prepared.path}",
                prepared.xcode_build_setting,
            )
            self.assertEqual(canonical_bytes(payload) + b"\n", source)

        production_payload = _prepared_build_payload(self.artifact, self.prepared)
        self.assertEqual(str(self.source_digest), production_payload["sourceTreeDigest"])
        self.assertEqual(
            [BoundLane.SIMULATOR.value, BoundLane.DEVICE.value],
            [item["lane"] for item in production_payload["lanes"]],
        )
        self.assertEqual(
            [item.xcode_build_setting for item in self.prepared],
            [item["xcodeBuildSetting"] for item in production_payload["lanes"]],
        )

    def test_round_trip_binds_schema_v2_and_exact_frozen_launches(self) -> None:
        frozen, path = self.write_input()
        loaded = self.load(path)

        self.assertEqual(frozen, loaded)
        self.assertEqual(2, json.loads(path.read_bytes())["schemaVersion"])
        self.assertNotIn("worktreeClean", path.read_text(encoding="utf-8"))
        self.assertEqual("com.example.Enchron", loaded.build_identity.bundle_identifier)
        self.assertEqual(TOOLCHAIN, loaded.build_identity.toolchain)
        simulator = load_frozen_test_launch
        with self.boundaries():
            launch = simulator(path, BoundLane.SIMULATOR, "SIM-UDID")
        self.assertEqual(self.products[BoundLane.SIMULATOR]["xctestrun"], launch.xctestrun_path)
        self.assertEqual(
            "platform=visionOS Simulator,id=SIM-UDID",
            launch.destination_specifier,
        )

    def test_application_digest_uses_debug_dylib_not_launch_stub(self) -> None:
        frozen = self.freeze()
        artifacts = {item.lane: item for item in frozen.build_identity.lane_artifacts}
        for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE):
            self.assertEqual(
                digest_bytes(self.products[lane]["code"].read_bytes()),
                artifacts[lane].application_code_digest,
            )
            self.assertNotEqual(
                digest_bytes((self.products[lane]["app"] / "Enchron").read_bytes()),
                artifacts[lane].application_code_digest,
            )

    def test_exact_xctestrun_discovery_rejects_zero_or_multiple_files(self) -> None:
        simulator = self.products[BoundLane.SIMULATOR]
        original = simulator["xctestrun"].read_bytes()
        simulator["xctestrun"].unlink()
        with self.assertRaisesRegex(ExecutionIdentityError, "exactly one"):
            self.freeze()
        simulator["xctestrun"].write_bytes(original)
        (simulator["root"] / "duplicate.xctestrun").write_bytes(original)
        with self.assertRaisesRegex(ExecutionIdentityError, "exactly one"):
            self.freeze()

    def test_plist_rejects_extra_enabled_target_and_wrong_test_selection(self) -> None:
        def extra(payload):
            targets = payload["TestConfigurations"][0]["TestTargets"]
            targets.append(dict(targets[0]))

        self.mutate_xctestrun(BoundLane.SIMULATOR, extra)
        with self.assertRaisesRegex(ExecutionIdentityError, "exactly one test target"):
            self.freeze()

        self.products[BoundLane.SIMULATOR]["xctestrun"].write_bytes(
            plistlib.dumps(self.xctestrun_payload(BoundLane.SIMULATOR), sort_keys=True)
        )

        def wrong_test(payload):
            target = payload["TestConfigurations"][0]["TestTargets"][0]
            target["OnlyTestIdentifiers"] = ["OtherTests/testOther()"]

        self.mutate_xctestrun(BoundLane.SIMULATOR, wrong_test)
        with self.assertRaisesRegex(ExecutionIdentityError, "interactive device session"):
            self.freeze()

    def test_plist_rejects_unregistered_macro_and_product_path_escape(self) -> None:
        def macro(payload):
            target = payload["TestConfigurations"][0]["TestTargets"][0]
            target["UITargetAppPath"] = "__UNKNOWN__/Enchron.app"

        self.mutate_xctestrun(BoundLane.SIMULATOR, macro)
        with self.assertRaisesRegex(ExecutionIdentityError, "unsupported Xcode macro"):
            self.freeze()

        self.products[BoundLane.SIMULATOR]["xctestrun"].write_bytes(
            plistlib.dumps(self.xctestrun_payload(BoundLane.SIMULATOR), sort_keys=True)
        )

        def escape(payload):
            target = payload["TestConfigurations"][0]["TestTargets"][0]
            target["UITargetAppPath"] = "__TESTROOT__/../Enchron.app"

        self.mutate_xctestrun(BoundLane.SIMULATOR, escape)
        with self.assertRaisesRegex(ExecutionIdentityError, "canonical absolute product path"):
            self.freeze()

    def test_variable_product_closure_change_or_mode_change_invalidates_load(self) -> None:
        _, path = self.write_input()
        dependency = self.products[BoundLane.DEVICE]["dependency"]
        dependency.write_bytes(b"changed-dependent-product")
        with self.assertRaisesRegex(ExecutionIdentityError, "BuildIdentity"):
            self.load(path)

        dependency.write_bytes(b"device-dependent-product")
        dependency.chmod(0o755)
        with self.assertRaisesRegex(ExecutionIdentityError, "BuildIdentity"):
            self.load(path)

    def test_product_closure_rejects_symlinks(self) -> None:
        dependency = self.products[BoundLane.SIMULATOR]["dependency"]
        dependency.unlink()
        dependency.symlink_to(self.products[BoundLane.DEVICE]["dependency"])
        with self.assertRaisesRegex(ExecutionIdentityError, "symlink"):
            self.freeze()

    def test_manifest_and_lane_roots_reject_symlinks(self) -> None:
        _, path = self.write_input()
        alias = self.artifact / "execution-input-link.json"
        alias.symlink_to(path)
        with self.assertRaisesRegex(ExecutionIdentityError, "symlink"):
            self.load(alias)

        lane_root = self.artifact / "lanes" / "device"
        moved = self.artifact / "lanes" / "device-real"
        lane_root.rename(moved)
        lane_root.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(ExecutionIdentityError, "symlink"):
            self.freeze()

    def test_macho_rejects_wrong_platform_duplicate_build_version_and_fat_file(self) -> None:
        device = self.products[BoundLane.DEVICE]
        stamp = (self.artifact / "build-provenance/device.json").read_bytes()
        device["code"].write_bytes(_macho(stamp, BoundLane.DEVICE, platform=12))
        with self.assertRaisesRegex(ExecutionIdentityError, "wrong Mach-O platform"):
            self.freeze()

        device["code"].write_bytes(
            _macho(stamp, BoundLane.DEVICE, build_version_count=2)
        )
        with self.assertRaisesRegex(ExecutionIdentityError, "exactly one LC_BUILD_VERSION"):
            self.freeze()

        device["code"].write_bytes(b"\xca\xfe\xba\xbe" + b"\0" * 64)
        with self.assertRaisesRegex(ExecutionIdentityError, "thin little-endian"):
            self.freeze()

    def test_macho_rejects_out_of_bounds_provenance_section(self) -> None:
        device = self.products[BoundLane.DEVICE]
        stamp = (self.artifact / "build-provenance/device.json").read_bytes()
        source = bytearray(_macho(stamp, BoundLane.DEVICE))
        section_offset_field = 32 + 24 + 72 + 48
        struct.pack_into("<I", source, section_offset_field, len(source) + 1)
        device["code"].write_bytes(source)
        with self.assertRaisesRegex(ExecutionIdentityError, "__enchsrc.*out of bounds"):
            self.freeze()

    def test_embedded_provenance_must_match_lane_source_and_toolchain(self) -> None:
        device = self.products[BoundLane.DEVICE]
        simulator_stamp = (
            self.artifact / "build-provenance/simulator.json"
        ).read_bytes()
        device["code"].write_bytes(_macho(simulator_stamp, BoundLane.DEVICE))
        with self.assertRaisesRegex(ExecutionIdentityError, "stale or cross-bound"):
            self.freeze()

    def test_cross_lane_xctestrun_digest_collision_is_rejected(self) -> None:
        simulator = self.products[BoundLane.SIMULATOR]["xctestrun"]
        device = self.products[BoundLane.DEVICE]["xctestrun"]
        device.write_bytes(simulator.read_bytes())
        with self.assertRaisesRegex(ExecutionIdentityError, "xctestrun.*must not collide"):
            self.freeze()

    def test_raw_xctestrun_or_configuration_change_invalidates_load(self) -> None:
        _, path = self.write_input()
        xctestrun = self.products[BoundLane.SIMULATOR]["xctestrun"]
        payload = plistlib.loads(xctestrun.read_bytes())
        xctestrun.write_bytes(plistlib.dumps(payload, fmt=plistlib.FMT_BINARY))
        with self.assertRaisesRegex(ExecutionIdentityError, "BuildIdentity"):
            self.load(path)

        xctestrun.write_bytes(
            plistlib.dumps(self.xctestrun_payload(BoundLane.SIMULATOR), sort_keys=True)
        )
        receipt = self.artifact / "configuration-receipt.json"
        value = json.loads(receipt.read_bytes())
        value["catalogDigest"] = "sha256:" + "b" * 64
        receipt.write_bytes(canonical_bytes(value) + b"\n")
        with self.assertRaisesRegex(ExecutionIdentityError, "configuration receipt"):
            self.load(path)

    def test_schema_v1_and_noncanonical_manifest_are_rejected(self) -> None:
        _, path = self.write_input()
        payload = json.loads(path.read_bytes())
        payload["schemaVersion"] = 1
        path.write_bytes(canonical_bytes(payload) + b"\n")
        with self.assertRaisesRegex(ExecutionIdentityError, "schema identity"):
            self.load(path)

        payload["schemaVersion"] = 2
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(ExecutionIdentityError, "canonical JSON"):
            self.load(path)

    def test_source_and_current_toolchain_changes_invalidate_load(self) -> None:
        _, path = self.write_input()
        self.write_text("Sources/App.swift", "let value = 2\n")
        with self.assertRaisesRegex(ExecutionIdentityError, "source tree"):
            self.load(path)

        self.write_text("Sources/App.swift", "let value = 1\n")
        changed = ToolchainIdentity(
            "27.0", "different", "27.0", "24M5357a", "27.0", "24M5357a"
        )
        with self.boundaries(toolchain=changed):
            with self.assertRaisesRegex(ExecutionIdentityError, "toolchain"):
                load_execution_input(path)

    def test_frozen_launch_rejects_a_different_requested_target(self) -> None:
        _, path = self.write_input()
        with self.boundaries():
            with self.assertRaisesRegex(ExecutionIdentityError, "differs from the frozen"):
                load_frozen_test_launch(path, BoundLane.DEVICE, "OTHER-DEVICE-UDID")

    def test_freeze_accepts_coredevice_alias_for_paired_device(self) -> None:
        frozen = self.freeze(device_target="DEVICE-CORE-ID")
        self.assertEqual("DEVICE-UDID", frozen.lane_targets[BoundLane.DEVICE])
        device = next(
            launch for launch in frozen.launches if launch.lane is BoundLane.DEVICE
        )
        self.assertEqual("platform=visionOS,id=DEVICE-UDID", device.destination_specifier)

    def test_freeze_normalizes_each_coredevice_alias_to_its_own_hardware_udid(self) -> None:
        frozen = self.freeze(device_target="OTHER-DEVICE-CORE-ID")
        self.assertEqual(
            "OTHER-DEVICE-UDID", frozen.lane_targets[BoundLane.DEVICE]
        )

    def test_prepare_rejects_whitespace_in_linker_stamp_path(self) -> None:
        with self.boundaries():
            with self.assertRaisesRegex(ExecutionIdentityError, "comma or whitespace"):
                prepare_build_provenance(
                    self.repository, self.artifact / "path with whitespace"
                )

    def test_prepare_and_freeze_require_clean_ignored_runtime_boundary(self) -> None:
        self.write_text("Sources/App.swift", "let value = 9\n")
        with self.boundaries():
            with self.assertRaisesRegex(ExecutionIdentityError, "clean integrated worktree"):
                prepare_build_provenance(self.repository, self.artifact)

        outside = self.repository / "visible-artifacts"
        with self.boundaries():
            with self.assertRaisesRegex(ExecutionIdentityError, "excluded"):
                prepare_build_provenance(self.repository, outside)

    def test_simulator_registry_accepts_only_visionos_simulators(self) -> None:
        document = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.visionOS-2-0": [
                    {"udid": "VISION-SIMULATOR-LEGACY-RUNTIME-ID"}
                ],
                "com.apple.CoreSimulator.SimRuntime.xrOS-27-0": [
                    {"udid": "VISION-SIMULATOR"}
                ],
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                    {"udid": "IOS-SIMULATOR"}
                ],
            }
        }
        with patch.object(
            subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                ["xcrun", "simctl"], 0, stdout=json.dumps(document), stderr=""
            ),
        ):
            self.assertEqual(
                frozenset(
                    {"VISION-SIMULATOR", "VISION-SIMULATOR-LEGACY-RUNTIME-ID"}
                ),
                registered_simulator_udids(),
            )

    def test_physical_registry_maps_hardware_and_coredevice_aliases(self) -> None:
        document = {
            "result": {
                "devices": [
                    {
                        "identifier": "CORE-PHYSICAL",
                        "properties": {
                            "hardware": {
                                "platform": "visionOS",
                                "reality": "physical",
                                "udid": "UDID-PHYSICAL",
                            },
                            "connection": {"pairingState": "paired"},
                        },
                    }
                ]
            }
        }

        def run(command, **_options):
            Path(command[-1]).write_text(json.dumps(document), encoding="utf-8")
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        with patch.object(subprocess, "run", side_effect=run):
            registry = registered_physical_visionos_devices()

        self.assertIs(registry["UDID-PHYSICAL"], registry["CORE-PHYSICAL"])


if __name__ == "__main__":
    unittest.main()
