#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

from harness.budgets import BudgetProvider
from harness.controller import CompletedInvocation, ControllerClient
from harness.failures import InstrumentFault
from harness.replay import (
    RecordingTap,
    ReplayDrift,
    ReplayRun,
    normalize_command,
    select_run,
)


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
        self.budgets = BudgetProvider(timings_directory=Path(self.temporary.name))

    def record(self) -> None:
        inner = ScriptedInner()
        client = ControllerClient(
            "simulator", command_prefix=["py", "runner"], run=RecordingTap(inner, self.transcript),
            budgets=self.budgets,
        )
        response = client.invoke("snapshot", ["--no-screenshot"])
        self.assertEqual(response.document, snapshot_document())
        with self.assertRaises(InstrumentFault) as caught:
            client.invoke("tap", ["--identifier", "X"])
        self.assertEqual(caught.exception.kind, "transport-timeout")

    def test_replay_drives_production_reconcile_and_fault_path(self) -> None:
        self.record()
        client = ControllerClient(
            "simulator", command_prefix=["py", "runner"], run=ReplayRun(self.transcript),
            budgets=self.budgets,
        )
        response = client.invoke("snapshot", ["--no-screenshot"])
        self.assertEqual(response.document, snapshot_document())
        with self.assertRaises(InstrumentFault) as caught:
            client.invoke("tap", ["--identifier", "X"])
        self.assertEqual(caught.exception.kind, "transport-timeout")



class SelectRunTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        self.default = ScriptedInner()

    def test_no_env_uses_the_live_run_unwrapped(self) -> None:
        run, mode = select_run(
            self.default, record="", replay="",
            default_transcript=self.directory / "t.jsonl",
        )
        self.assertIs(run, self.default)
        self.assertEqual(mode, "live")

    def test_record_flag_wraps_with_a_recording_tap_at_the_default_path(self) -> None:
        transcript = self.directory / "t.jsonl"
        run, mode = select_run(
            self.default, record="1", replay="", default_transcript=transcript,
        )
        self.assertIsInstance(run, RecordingTap)
        self.assertEqual(run.transcript_path, transcript)
        self.assertEqual(mode, "record")

    def test_record_path_records_to_that_path(self) -> None:
        chosen = self.directory / "explicit.jsonl"
        run, mode = select_run(
            self.default, record=str(chosen), replay="",
            default_transcript=self.directory / "t.jsonl",
        )
        self.assertEqual(run.transcript_path, chosen)

    def test_replay_takes_priority_and_reads_the_transcript(self) -> None:
        transcript = self.directory / "t.jsonl"
        transcript.write_text("", encoding="utf-8")
        run, mode = select_run(
            self.default, record="1", replay=str(transcript),
            default_transcript=self.directory / "other.jsonl",
        )
        self.assertIsInstance(run, ReplayRun)
        self.assertEqual(mode, "replay")

    def test_a_recorded_run_replays_identically(self) -> None:
        transcript = self.directory / "t.jsonl"
        prefix = ["python", "runner.py"]
        recorder = ControllerClient(
            "device", command_prefix=prefix,
            run=RecordingTap(self.default, transcript),
        )
        recorded = recorder.run(["python", "runner.py", "snapshot"], 30.0)
        replayer = ControllerClient("device", command_prefix=prefix, run=ReplayRun(transcript))
        replayed = replayer.run(["python", "runner.py", "snapshot"], 30.0)
        self.assertEqual(recorded.stdout, replayed.stdout)
        self.assertEqual(recorded.returncode, replayed.returncode)



class NormalizeCommandTests(unittest.TestCase):
    def test_output_directory_is_volatile(self) -> None:
        a = normalize_command(["runner", "--output-directory", "/a/x", "snapshot"])
        b = normalize_command(["runner", "--output-directory", "/b/y", "snapshot"])
        self.assertEqual(a, b)
        self.assertNotIn("/a/x", a)

    def test_uuids_are_replaced_with_a_placeholder(self) -> None:
        one = normalize_command(["--arg", "evidenceSession=7d72ce74-c9f5-47e9-bf39-b02fcaecf66e"])
        two = normalize_command(["--arg", "evidenceSession=083d6d24-012d-4f5b-847a-ff9b3f252070"])
        self.assertEqual(one, two)
        self.assertEqual(one, ["--arg", "evidenceSession=<uuid>"])

    def test_a_transcript_recorded_before_a_normalization_change_still_replays(self) -> None:
        directory = Path(tempfile.mkdtemp())
        transcript = directory / "t.jsonl"
        transcript.write_text(json.dumps({
            "command": ["runner", "--output-directory", "/old/path", "snapshot"],
            "returncode": 0, "stdout": "{}", "stderr": "",
        }) + "\n", encoding="utf-8")
        replay = ReplayRun(transcript)
        result = replay(["runner", "--output-directory", "/new/path", "snapshot"], 30.0)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
