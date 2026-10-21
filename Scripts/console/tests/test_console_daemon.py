import json
import socket
import sys
import tempfile
import threading
import unittest
from pathlib import Path

CONSOLE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CONSOLE_ROOT))

import daemon as daemon_module


class DaemonProtocolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.target = "SIM-TEST-UDID"
        (self.root / ".console").mkdir(parents=True, exist_ok=True)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def test_a_missing_socket_reports_an_error_instead_of_raising(self) -> None:
        answer = daemon_module.request(self.root, {"op": "ping"}, self.target, timeout=1)
        self.assertEqual(answer["kind"], "error")

    def test_an_unknown_op_is_refused(self) -> None:
        server = daemon_module.Server(self.root, "target")
        answer = server._handle({"op": "rearrange-everything"})
        self.assertEqual(answer["kind"], "error")
        self.assertIn("rearrange-everything", answer["message"])

    def test_ping_answers_with_the_pid(self) -> None:
        server = daemon_module.Server(self.root, "target")
        answer = server._handle({"op": "ping"})
        self.assertEqual(answer["kind"], "result")
        self.assertIn("pid", answer["value"])

    def test_each_target_gets_its_own_short_socket_path(self) -> None:
        first = daemon_module.socket_path(self.root, "SIM-ONE")
        second = daemon_module.socket_path(self.root, "SIM-TWO")
        self.assertNotEqual(first, second)
        self.assertLess(len(str(first)), 100)
        self.assertEqual(first.suffix, ".sock")

    def test_the_same_target_resolves_to_the_same_socket(self) -> None:
        first = daemon_module.socket_path(self.root, self.target)
        second = daemon_module.socket_path(self.root, self.target)
        self.assertEqual(first, second)


class DaemonSocketTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.target = "SIM-TEST-UDID"
        (self.root / ".console").mkdir(parents=True, exist_ok=True)
        self.server = daemon_module.Server(self.root, self.target)
        self.thread = threading.Thread(target=self.server.serve, daemon=True)

    def tearDown(self) -> None:
        daemon_module.request(self.root, {"op": "stop"}, self.target, timeout=2)
        self.thread.join(timeout=5)
        self.directory.cleanup()

    def test_a_ping_travels_over_the_socket(self) -> None:
        self.thread.start()
        self._await_socket()
        answer = daemon_module.request(self.root, {"op": "ping"}, self.target, timeout=5)
        self.assertEqual(answer["kind"], "result")

    def test_the_socket_is_private_to_the_owner(self) -> None:
        self.thread.start()
        path = self._await_socket()
        mode = path.stat().st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def _await_socket(self) -> Path:
        import time

        path = daemon_module.socket_path(self.root, self.target)
        deadline = time.time() + 10
        while time.time() < deadline:
            if path.exists():
                return path
            time.sleep(0.02)
        self.fail("the daemon socket never appeared")


if __name__ == "__main__":
    unittest.main()
