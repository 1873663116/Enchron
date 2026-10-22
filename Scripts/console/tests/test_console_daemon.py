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
import engine as engine_module


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


class AwaitFieldTests(unittest.TestCase):
    def test_one_probe_can_check_several_fields(self) -> None:
        observed = {"presentation": "window", "mediaName": "clip.mkv"}
        self.assertTrue(
            engine_module._await_matches(
                observed, "", {"presentation": "window", "mediaName": "clip.mkv"}, "equals"
            )
        )

    def test_one_mismatched_field_refuses_the_wait(self) -> None:
        observed = {"presentation": "window", "mediaName": "other.mkv"}
        self.assertFalse(
            engine_module._await_matches(
                observed, "", {"presentation": "window", "mediaName": "clip.mkv"}, "equals"
            )
        )


class SettlingTests(unittest.TestCase):
    def test_a_transient_miss_is_retried(self) -> None:
        answer = {"kind": "result", "value": {"ok": False, "detail": "The requested element exists but is not currently hittable."}}
        self.assertFalse(engine_module._settled(answer))

    def test_a_real_failure_is_not_retried(self) -> None:
        answer = {"kind": "result", "value": {"ok": False, "detail": "The identifier is not in the allowlist."}}
        self.assertTrue(engine_module._settled(answer))

    def test_a_healthy_journal_is_not_recovered(self) -> None:
        answer = {"kind": "result", "value": {"ok": True, "detail": "App command probeStatus completed."}}
        self.assertFalse(engine_module._journal_unhealthy(answer))

    def test_an_unhealthy_journal_is_recovered(self) -> None:
        answer = {"kind": "result", "value": {"ok": False, "detail": "The DEBUG probe journal is unhealthy."}}
        self.assertTrue(engine_module._journal_unhealthy(answer))


class RecoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        (self.root / ".console").mkdir(parents=True, exist_ok=True)
        self.channel = daemon_module.Channel(self.root, "SIM-TEST-UDID")
        self.channel.session_ready = True
        self.channel.ready = {"sessionID": "session-1"}
        self.calls: list[str] = []
        self.original_send = daemon_module.transport.send_command
        self.original_alive = self.channel.alive
        self.original_recover = self.channel._recover

    def tearDown(self) -> None:
        daemon_module.transport.send_command = self.original_send
        self.channel.alive = self.original_alive
        self.channel._recover = self.original_recover
        self.directory.cleanup()

    def test_a_dead_runner_is_recovered_once_and_the_call_retried(self) -> None:
        answers = [
            {"success": False, "stage": "runnerGone", "message": "runner gone"},
            {"success": True, "message": "Element tapped."},
        ]

        def send(_arguments):
            self.calls.append("send")
            return answers.pop(0)

        self.channel.alive = lambda: True
        self.channel._recover = lambda: {"restarted": True}
        daemon_module.transport.send_command = send
        answer, ok, detail = self.channel.invoke("tap", "X", None)
        self.assertTrue(ok)
        self.assertEqual(detail, "Element tapped.")
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(answer["recovery"], {"restarted": True})

    def test_a_second_failure_is_reported_without_another_retry(self) -> None:
        def send(_arguments):
            self.calls.append("send")
            return {"success": False, "stage": "runnerGone", "message": "runner gone"}

        self.channel.alive = lambda: True
        self.channel._recover = lambda: {"restarted": True}
        daemon_module.transport.send_command = send
        _, ok, detail = self.channel.invoke("tap", "X", None)
        self.assertFalse(ok)
        self.assertEqual(detail, "runner gone")
        self.assertEqual(len(self.calls), 2)

    def test_a_non_recoverable_failure_is_not_retried(self) -> None:
        self.channel.alive = lambda: True
        self.channel._recover = lambda: self.fail("recovery must not run")

        def send(_arguments):
            self.calls.append("send")
            return {"success": False, "stage": "refused", "message": "no such identifier"}

        daemon_module.transport.send_command = send
        _, ok, detail = self.channel.invoke("tap", "X", None)
        self.assertFalse(ok)
        self.assertEqual(detail, "no such identifier")
        self.assertEqual(len(self.calls), 1)


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


class AwaitComparisonTests(unittest.TestCase):
    def test_equality_matches_only_the_same_value(self) -> None:
        self.assertTrue(
            engine_module._await_matches({"mode": "playing"}, "mode", "playing", "equals")
        )
        self.assertFalse(
            engine_module._await_matches({"mode": "playing"}, "mode", "paused", "equals")
        )

    def test_a_threshold_compares_numbers(self) -> None:
        self.assertTrue(
            engine_module._await_matches({"position": "12.5"}, "position", 10, "atLeast")
        )
        self.assertFalse(
            engine_module._await_matches({"position": "9.5"}, "position", 10, "atLeast")
        )

    def test_a_threshold_rejects_an_unparsable_value(self) -> None:
        self.assertFalse(
            engine_module._await_matches({"position": "unknown"}, "position", 10, "atLeast")
        )

    def test_an_empty_field_compares_the_whole_value(self) -> None:
        self.assertTrue(engine_module._await_matches({"": "grid"}, "", "grid", "equals"))
        self.assertFalse(
            engine_module._await_matches({"": "grid"}, "", "list", "equals")
        )

    def test_a_dotted_path_walks_into_nested_payloads(self) -> None:
        payload = {"matchedElement": {"value": "alpha=1;beta=2"}}
        self.assertEqual(
            engine_module._resolve_field(payload, "matchedElement.value"),
            "alpha=1;beta=2",
        )
        self.assertIsNone(engine_module._resolve_field(payload, "matchedElement.absent"))
