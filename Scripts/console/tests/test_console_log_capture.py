from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import engine


class Answer:
    def __init__(self, text: str) -> None:
        self.stdout = text


class Expired(Exception):
    pass


class CaptureDeviceLogsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())

    def test_writes_the_command_output(self) -> None:
        calls: list[list[str]] = []

        def runner(command, capture_output, text, timeout):
            calls.append(command)
            return Answer("session.heartbeat samples=1\n")

        with mock.patch.object(engine, "_device_target", return_value="UDID"):
            engine._capture_device_logs(
                self.directory, 0.0, 1.0, runner=runner, timeout_error=Expired
            )
        self.assertEqual(
            (self.directory / "logs.txt").read_text(encoding="utf-8"),
            "session.heartbeat samples=1\n",
        )
        command = calls[0]
        self.assertIn("simctl", command)
        self.assertIn("log", command)
        self.assertIn('subsystem == "com.xiongzhipeng.PlaybackCore"', command)

    def test_writes_nothing_without_a_device(self) -> None:
        def runner(command, capture_output, text, timeout):
            raise AssertionError("the runner must not be called")

        with mock.patch.object(engine, "_device_target", return_value=None):
            engine._capture_device_logs(
                self.directory, 0.0, 1.0, runner=runner, timeout_error=Expired
            )
        self.assertFalse((self.directory / "logs.txt").exists())

    def test_records_a_timeout(self) -> None:
        def runner(command, capture_output, text, timeout):
            raise Expired()

        with mock.patch.object(engine, "_device_target", return_value="UDID"):
            engine._capture_device_logs(
                self.directory, 0.0, 1.0, runner=runner, timeout_error=Expired
            )
        self.assertIn(
            "timed out", (self.directory / "logs.txt").read_text(encoding="utf-8")
        )


if __name__ == "__main__":
    unittest.main()
