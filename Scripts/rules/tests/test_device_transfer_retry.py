#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

import interactive_visionpro_ui as controller

DEVICE = "00008142-000000000000000A"
FILE_NODE_ERROR = (
    "ERROR: Failed to retrieve the file node for Documents/test-command.json "
    "(com.apple.dt.CoreDeviceError error 7000 (0x1B58))\n"
)


class ScriptedDevicectl:
    def __init__(self, outcomes: list[int]) -> None:
        self.outcomes = list(outcomes)
        self.calls: list[list[str]] = []

    def __call__(self, arguments, *, quiet=False):
        self.calls.append(list(arguments))
        code = self.outcomes.pop(0) if self.outcomes else 0
        return subprocess.CompletedProcess(arguments, code, stdout="", stderr=FILE_NODE_ERROR if code else "")


class DeviceTransferRetryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.pauses: list[float] = []
        self.original_run = controller.run_devicectl
        self.original_pause = controller.device_transfer_pause
        self.original_simulator = controller.is_simulator
        controller.device_transfer_pause = self.pauses.append
        controller.is_simulator = lambda device, **kwargs: False
        self.temporary = tempfile.TemporaryDirectory(prefix="transfer-")
        self.addCleanup(self.temporary.cleanup)
        self.local = Path(self.temporary.name) / "test-command.json"
        self.local.write_text("{}", encoding="utf-8")

    def tearDown(self) -> None:
        controller.run_devicectl = self.original_run
        controller.device_transfer_pause = self.original_pause
        controller.is_simulator = self.original_simulator

    def copy(self) -> None:
        controller.copy_to_device(
            device=DEVICE,
            runner_bundle_id="com.example.runner",
            local_path=self.local,
            remote_path="Documents/test-command.json",
        )

    def test_transient_file_node_error_is_retried_then_succeeds(self) -> None:
        scripted = ScriptedDevicectl([1, 0])
        controller.run_devicectl = scripted
        self.copy()
        self.assertEqual(len(scripted.calls), 2)
        self.assertEqual(self.pauses, [controller.DEVICE_TRANSFER_RETRY_SECONDS])

    def test_persistent_failure_raises_after_every_attempt(self) -> None:
        scripted = ScriptedDevicectl([1, 1, 1, 1])
        controller.run_devicectl = scripted
        with self.assertRaises(RuntimeError) as raised:
            self.copy()
        self.assertEqual(len(scripted.calls), controller.DEVICE_TRANSFER_ATTEMPTS)
        self.assertEqual(len(self.pauses), controller.DEVICE_TRANSFER_ATTEMPTS - 1)
        self.assertIn("error 7000", str(raised.exception))
        self.assertIn(f"after {controller.DEVICE_TRANSFER_ATTEMPTS} devicectl transfer attempts", str(raised.exception))

    def test_first_attempt_success_never_pauses(self) -> None:
        scripted = ScriptedDevicectl([0])
        controller.run_devicectl = scripted
        self.copy()
        self.assertEqual(len(scripted.calls), 1)
        self.assertEqual(self.pauses, [])


if __name__ == "__main__":
    unittest.main()
