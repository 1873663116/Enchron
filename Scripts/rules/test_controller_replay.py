#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

from harness.controller import CompletedInvocation, ControllerClient
from harness.failures import InstrumentFault
from harness.replay import RecordingTap, ReplayDrift, ReplayRun, normalize_command


def snapshot_document() -> dict[str, object]:
    return {"success": True, "verb": "snapshot", "matchedElement": {"isHittable": True}}


class ScriptedInner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def __call__(
        self, command, timeout_seconds: float
    ) -> CompletedInvocation:
        self.calls.append(list(command))
        if "tap" in command:
            raise subprocess.TimeoutExpired(list(command), timeout_seconds)
        return CompletedInvocation(
            returncode=0,
            stdout=json.dumps(snapshot_document()),
            stderr="",
        )


class NormalizeTests(unittest.TestCase):
    def test_strips_only_the_volatile_timeout_pair(self) -> None:
        command = ["py", "runner", "snapshot", "--no-screenshot", "--timeout-seconds", "42.0"]
        self.assertEqual(
            normalize_command(command),
            ["py", "runner", "snapshot", "--no-screenshot"],
        )


class ReplayRunTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="replay-")
        self.addCleanup(self.temporary.cleanup)
        self.transcript = Path(self.temporary.name) / "transcript.jsonl"

    def test_round_trip_reproduces_documents_and_timeouts(self) -> None:
        inner = ScriptedInner()
        tap = RecordingTap(inner, self.transcript)
        first = tap(["py", "runner", "snapshot"], 30.0)
        self.assertEqual(first.returncode, 0)
        with self.assertRaises(subprocess.TimeoutExpired):
            tap(["py", "runner", "tap", "--identifier", "X"], 25.0)

        replay = ReplayRun(self.transcript)
        replayed = replay(["py", "runner", "snapshot"], 99.0)
        self.assertEqual(json.loads(replayed.stdout), snapshot_document())
        with self.assertRaises(subprocess.TimeoutExpired):
            replay(["py", "runner", "tap", "--identifier", "X"], 99.0)
        self.assertTrue(replay.exhausted())

    def test_drift_is_rejected_not_absorbed(self) -> None:
        self.transcript.write_text(
            json.dumps(
                {"command": ["py", "runner", "snapshot"], "returncode": 0, "stdout": "{}", "stderr": ""}
            )
            + "\n",
            encoding="utf-8",
        )
        replay = ReplayRun(self.transcript)
        with self.assertRaises(ReplayDrift):
            replay(["py", "runner", "tap", "--identifier", "X"], 30.0)

    def test_extra_call_past_recording_is_rejected(self) -> None:
        self.transcript.write_text("", encoding="utf-8")
        replay = ReplayRun(self.transcript)
        with self.assertRaises(ReplayDrift):
            replay(["py", "runner", "snapshot"], 30.0)


class FaithfulnessThroughControllerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="replay-client-")
        self.addCleanup(self.temporary.cleanup)
        self.transcript = Path(self.temporary.name) / "transcript.jsonl"

    def record(self) -> None:
        inner = ScriptedInner()
        client = ControllerClient(
            "simulator", command_prefix=["py", "runner"], run=RecordingTap(inner, self.transcript)
        )
        response = client.invoke("snapshot", ["--no-screenshot"])
        self.assertEqual(response.document, snapshot_document())
        with self.assertRaises(InstrumentFault) as caught:
            client.invoke("tap", ["--identifier", "X"])
        self.assertEqual(caught.exception.kind, "transport-timeout")

    def test_replay_drives_production_reconcile_and_fault_path(self) -> None:
        self.record()
        client = ControllerClient(
            "simulator", command_prefix=["py", "runner"], run=ReplayRun(self.transcript)
        )
        response = client.invoke("snapshot", ["--no-screenshot"])
        self.assertEqual(response.document, snapshot_document())
        with self.assertRaises(InstrumentFault) as caught:
            client.invoke("tap", ["--identifier", "X"])
        self.assertEqual(caught.exception.kind, "transport-timeout")


if __name__ == "__main__":
    unittest.main()
