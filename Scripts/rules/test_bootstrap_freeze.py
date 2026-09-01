#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest import mock
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
    prepare_build_provenance,
    repository_source_digest,
    write_execution_input,
)
from regression.runctl import _parser
import verify_bootstrap_freeze


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


def _macho(stamp: bytes, lane: BoundLane) -> bytes:
    packed_sdk = 27 << 16
    build_command = struct.pack(
        "<6I",
        0x32,
        24,
        12 if lane is BoundLane.SIMULATOR else 11,
        2 << 16,
        packed_sdk,
        0,
    )
    build_commands = build_command
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
        2,
        command_bytes,
        0,
        0,
    )
    commands = build_commands + segment + section
    return header + commands + b"\0" * (data_offset - len(header) - len(commands)) + stamp


class BootstrapFreezeTests(unittest.TestCase):
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
            )
        )

    def boundaries(self, *, toolchain: ToolchainIdentity = TOOLCHAIN):
        return patch.multiple(
            identity,
            query_toolchain_identity=lambda: toolchain,
            registered_simulator_udids=lambda: frozenset({"SIM-UDID"}),
            registered_physical_visionos_devices=lambda: self.physical_registry(),
        )

    def write_text(self, relative: str, source: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")
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
        return {
            "TestPlan": {"Name": f"Interactive-{lane.value}"},
            "TestConfigurations": [
                {
                    "Name": "Interactive",
                    "IsEnabled": True,
                    "TestTargets": [
                        {
                            "BlueprintName": "EnchronAppUITests",
                            "TestBundlePath": "__TESTHOST__/PlugIns/EnchronAppUITests.xctest",
                            "TestHostPath": "__TESTROOT__/Debug/EnchronAppUITests-Runner.app",
                            "UITargetAppPath": "__TESTROOT__/Debug/Enchron.app",
                            "DependentProductPaths": [
                                "__TESTROOT__/Debug/Enchron.app",
                                "__TESTROOT__/Debug/EnchronAppUITests-Runner.app",
                                "__TESTROOT__/Debug/Shared.framework",
                            ],
                            "OnlyTestIdentifiers": [UI_TEST],
                        }
                    ],
                }
            ],
            "__xctestrun_metadata__": {"FormatVersion": 2},
        }

    def write_lane(self, lane: BoundLane) -> dict[str, Path]:
        prefix = self.artifact / "lanes" / lane.value / "DerivedData" / "Build" / "Products"
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
        (test_bundle / "EnchronAppUITests").write_bytes(f"{lane.value}-tests".encode())
        dependency = shared / "Shared"
        dependency.write_bytes(f"{lane.value}-dependent-product".encode())
        xctestrun = prefix / f"Enchron-{lane.value}.xctestrun"
        xctestrun.write_bytes(plistlib.dumps(self.xctestrun_payload(lane), sort_keys=True))
        return {"root": prefix, "code": code, "xctestrun": xctestrun}

    def test_bootstrap_freeze_bypasses_missing_configuration_receipt(self) -> None:
        (self.artifact / "configuration-receipt.json").unlink()
        with self.boundaries():
            with self.assertRaisesRegex(ExecutionIdentityError, "configuration receipt"):
                freeze_execution_input(
                    self.repository,
                    self.artifact,
                    {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                    "gpt-5",
                    bootstrap=False,
                )
        with self.boundaries():
            value = freeze_execution_input(
                self.repository,
                self.artifact,
                {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                "gpt-5",
                bootstrap=True,
            )
        self.assertTrue(value.bootstrap)
        path = self.artifact / "execution-input-bootstrap.json"
        write_execution_input(path, value)
        with self.boundaries():
            loaded = load_execution_input(path)
        self.assertTrue(loaded.bootstrap)
        self.assertEqual(value.build_identity.configuration_digest, loaded.build_identity.configuration_digest)

    def test_bootstrap_payload_is_explicitly_marked_inside_file(self) -> None:
        (self.artifact / "configuration-receipt.json").unlink()
        with self.boundaries():
            value = freeze_execution_input(
                self.repository,
                self.artifact,
                {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                "gpt-5",
                bootstrap=True,
            )
        path = self.artifact / "execution-input-bootstrap.json"
        write_execution_input(path, value)
        payload = json.loads(path.read_bytes())
        self.assertEqual(payload.get("bootstrap"), True)
        self.assertIn("configurationReceipt", payload)
        self.assertNotIn("worktreeClean", path.read_text(encoding="utf-8"))
        with self.boundaries():
            bound = freeze_execution_input(
                self.repository,
                self.artifact,
                {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                "gpt-5",
                bootstrap=False,
            ) if (self.artifact / "configuration-receipt.json").exists() else None
        if bound is not None:
            bound_path = self.artifact / "execution-input-bound.json"
            write_execution_input(bound_path, bound)
            bound_payload = json.loads(bound_path.read_bytes())
            self.assertNotIn("bootstrap", bound_payload)
        raw = path.read_bytes()
        self.assertIn(b'"bootstrap":true', raw)
        self.assertNotIn(path.name.encode(), raw)

    def test_bootstrap_loader_distinguishes_from_bound(self) -> None:
        with self.boundaries():
            bound = freeze_execution_input(
                self.repository,
                self.artifact,
                {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                "gpt-5",
                bootstrap=False,
            )
        bound_path = self.artifact / "execution-input-bound.json"
        write_execution_input(bound_path, bound)
        with self.boundaries():
            loaded_bound = load_execution_input(bound_path)
        self.assertFalse(loaded_bound.bootstrap)
        (self.artifact / "configuration-receipt.json").unlink()
        with self.boundaries():
            bootstrap = freeze_execution_input(
                self.repository,
                self.artifact,
                {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                "gpt-5",
                bootstrap=True,
            )
        bootstrap_path = self.artifact / "execution-input-bootstrap2.json"
        write_execution_input(bootstrap_path, bootstrap)
        with self.boundaries():
            loaded_bootstrap = load_execution_input(bootstrap_path)
        self.assertTrue(loaded_bootstrap.bootstrap)
        self.assertNotEqual(
            str(loaded_bound.build_identity.configuration_digest),
            str(loaded_bootstrap.build_identity.configuration_digest),
        )
        self.assertEqual(
            str(loaded_bootstrap.configuration_receipt_digest),
            str(loaded_bootstrap.build_identity.configuration_digest),
        )

    def test_runctl_freeze_exposes_bootstrap_flag(self) -> None:
        parser = _parser()
        arguments = parser.parse_args(
            [
                "freeze",
                "--artifact-root",
                str(self.artifact),
                "--simulator-target",
                "SIM-UDID",
                "--device-target",
                "DEVICE-UDID",
                "--agent-model",
                "gpt-5",
                "--output",
                "execution-input.json",
            ]
        )
        self.assertFalse(bool(getattr(arguments, "bootstrap", False)))
        parser_bootstrap = _parser()
        arguments_bootstrap = parser_bootstrap.parse_args(
            [
                "freeze",
                "--artifact-root",
                str(self.artifact),
                "--simulator-target",
                "SIM-UDID",
                "--device-target",
                "DEVICE-UDID",
                "--agent-model",
                "gpt-5",
                "--output",
                "execution-input.json",
                "--bootstrap",
            ]
        )
        self.assertTrue(bool(getattr(arguments_bootstrap, "bootstrap", False)))

    def test_bootstrap_digest_is_derived_from_source_tree(self) -> None:
        with self.boundaries():
            first = freeze_execution_input(
                self.repository,
                self.artifact,
                {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                "gpt-5",
                bootstrap=True,
            )
        self.write_text("Sources/App.swift", "let value = 2\n")
        self.git("add", "Sources/App.swift")
        self.git("commit", "-q", "-m", "change source")
        with self.boundaries():
            prepare_build_provenance(self.repository, self.artifact)
        for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE):
            self.products[lane] = self.write_lane(lane)
        with self.boundaries():
            second = freeze_execution_input(
                self.repository,
                self.artifact,
                {BoundLane.SIMULATOR: "SIM-UDID", BoundLane.DEVICE: "DEVICE-UDID"},
                "gpt-5",
                bootstrap=True,
            )
        self.assertNotEqual(
            str(first.build_identity.configuration_digest),
            str(second.build_identity.configuration_digest),
        )
        self.assertNotEqual(
            str(first.configuration_receipt_digest),
            str(second.configuration_receipt_digest),
        )

    def test_verify_bootstrap_freeze_probe_is_green(self) -> None:
        self.assertEqual(verify_bootstrap_freeze.main(), 0)


if __name__ == "__main__":
    unittest.main()


class BootstrapRejectionTests(unittest.TestCase):
    """A bootstrap freeze carries no configuration receipt, so the two stages
    that bind evidence to a reviewed configuration refuse it by name.

    The marker alone proves nothing: an execution input that announces itself as
    unbound and is then accepted everywhere is indistinguishable from one that
    never announced anything.
    """

    def bootstrap_input(self):
        class Execution:
            bootstrap = True
            build_identity = object()
            evidence_environment_identity = object()
        return Execution()

    def test_compile_refuses_a_bootstrap_execution_input(self) -> None:
        import regression.runctl as runctl
        with mock.patch.object(runctl, "load_execution_input",
                               return_value=self.bootstrap_input()):
            with self.assertRaises(runctl.RunControlError) as raised:
                runctl.compile_execution_plan(
                    repository_root=Path("."),
                    execution_input_path=Path("execution-input.json"),
                    catalog_root=Path("Regression"),
                    policy_path=Path("Regression/review-policy.json"),
                    reviews_root=Path("Regression/reviews"),
                    blueprint_path=Path("Config/regression/catalog-v2.json"),
                )
        self.assertIn("bootstrap", str(raised.exception))

    def test_completion_refuses_a_bootstrap_execution_input(self) -> None:
        root = Path(__file__).resolve().parents[2]
        source = (root / "Scripts/regression/completion.py").read_text(encoding="utf-8")
        marker = "if execution.bootstrap:"
        self.assertIn(marker, source)
        after = source[source.index(marker):source.index(marker) + 400]
        self.assertIn("CompletionError", after)
        self.assertIn("bootstrap", after)


class FrozenRunLeavesSourceTreeAloneTests(unittest.TestCase):
    """A frozen run binds the source tree by digest, and controller_timings.json
    is tracked, so a sample appended by the first command invalidates the freeze
    that command is running under. The matrix reported drive-error on
    ensure-session for exactly this reason.
    """

    def record(self, **environment):
        root = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(root / "Scripts/verification"))
        import interactive_visionpro_ui as controller
        before = controller.TIMINGS_DEVICE_PATH.read_bytes()
        with mock.patch.dict(os.environ, environment, clear=False):
            controller.record_timing("probe-action", 1.25, device="00008142-0001")
        after = controller.TIMINGS_DEVICE_PATH.read_bytes()
        return before, after

    def test_a_frozen_run_writes_no_sample(self) -> None:
        root = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(root / "Scripts/verification"))
        import interactive_visionpro_ui as controller
        before = controller.TIMINGS_DEVICE_PATH.read_bytes()
        controller.record_timing(
            "probe-action", 1.25, device="00008142-0001", frozen=True
        )
        self.assertEqual(before, controller.TIMINGS_DEVICE_PATH.read_bytes())

    def test_the_environment_alone_does_not_make_a_run_frozen(self) -> None:
        """The matrix passes --execution-input on the command line, so a guard
        that reads the environment let a hundred and thirty commands through."""
        root = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(root / "Scripts/verification"))
        import interactive_visionpro_ui as controller
        original = controller.TIMINGS_DEVICE_PATH.read_bytes()
        try:
            with mock.patch.dict(
                os.environ,
                {"ENCHRON_EXECUTION_INPUT": "/tmp/execution-input.json"},
                clear=False,
            ):
                controller.record_timing("probe-action", 1.25, device="00008142-0001")
            self.assertIn(b"probe-action", controller.TIMINGS_DEVICE_PATH.read_bytes())
        finally:
            controller.TIMINGS_DEVICE_PATH.write_bytes(original)

    def test_an_unfrozen_run_still_records(self) -> None:
        root = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(root / "Scripts/verification"))
        import interactive_visionpro_ui as controller
        original = controller.TIMINGS_DEVICE_PATH.read_bytes()
        try:
            environment = {k: v for k, v in os.environ.items()
                           if k != "ENCHRON_EXECUTION_INPUT"}
            with mock.patch.dict(os.environ, environment, clear=True):
                controller.record_timing("probe-action", 1.25, device="00008142-0001")
            self.assertIn(b"probe-action", controller.TIMINGS_DEVICE_PATH.read_bytes())
        finally:
            controller.TIMINGS_DEVICE_PATH.write_bytes(original)
