from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import engine


class CaptureDeviceLogsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())

    def test_writes_the_command_output(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[], returncode=0, stdout="session.heartbeat samples=1\n", stderr=""
        )
        with mock.patch.object(engine, "_device_target", return_value="UDID"), mock.patch(
            "subprocess.run", return_value=completed
        ) as run:
            engine._capture_device_logs(self.directory, 0.0, 1.0)
        self.assertEqual(
            (self.directory / "logs.txt").read_text(encoding="utf-8"),
            "session.heartbeat samples=1\n",
        )
        command = run.call_args[0][0]
        self.assertIn("simctl", command)
        self.assertIn("log", command)
        self.assertIn('subsystem == "com.xiongzhipeng.PlaybackCore"', command)

    def test_writes_nothing_without_a_device(self) -> None:
        with mock.patch.object(engine, "_device_target", return_value=None), mock.patch(
            "subprocess.run"
        ) as run:
            engine._capture_device_logs(self.directory, 0.0, 1.0)
        self.assertFalse((self.directory / "logs.txt").exists())
        run.assert_not_called()

    def test_records_a_timeout(self) -> None:
        with mock.patch.object(engine, "_device_target", return_value="UDID"), mock.patch(
            "subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="log", timeout=1)
        ):
            engine._capture_device_logs(self.directory, 0.0, 1.0)
        self.assertIn(
            "timed out", (self.directory / "logs.txt").read_text(encoding="utf-8")
        )


if __name__ == "__main__":
    unittest.main()
