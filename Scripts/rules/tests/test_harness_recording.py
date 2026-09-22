#!/usr/bin/env python3

from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

VERIFICATION = Path(__file__).resolve().parents[2] / "verification"
if str(VERIFICATION) not in sys.path:
    sys.path.insert(0, str(VERIFICATION))

from harness import recording
from harness.budgets import Budget
from harness.failures import InstrumentFault
from harness.recording import (
    RecordingError,
    recorder_command,
    segment_filename,
    segment_root,
    start_segment,
    stop_segment,
    temporary_root,
)

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]

RUNNING_RECORDER = """
import os
import signal
import sys
import time

path = sys.argv[1]
if os.path.exists(path):
    sys.stderr.write("cannot save recorded video output into a file that already exists\\n")
    sys.exit(17)
if os.path.commonpath([os.path.realpath(path), REPOSITORY]) == REPOSITORY:
    sys.stderr.write("The file couldn't be saved because you don't have permission.\\n")
    sys.exit(1)
open(path, "wb").close()
sys.stderr.write("Recording started\\n")
sys.stderr.flush()


def stop(signum, frame):
    with open(path, "wb") as sink:
        sink.write(b"a segment of encoded video")
    sys.exit(0)


signal.signal(signal.SIGINT, stop)
while True:
    time.sleep(0.05)
"""

REFUSING_RECORDER = """
import sys

sys.stderr.write("no such device is booted\\n")
sys.exit(164)
"""

DYING_RECORDER = """
import sys
import time

open(sys.argv[1], "wb").close()
time.sleep(3.0)
sys.stderr.write("the simulator shut down\\n")
sys.exit(3)
"""

EMPTY_RECORDER = """
import signal
import sys
import time

open(sys.argv[1], "wb").close()


def stop(signum, frame):
    sys.exit(0)


signal.signal(signal.SIGINT, stop)
while True:
    time.sleep(0.05)
"""

VANISHING_RECORDER = """
import os
import signal
import sys
import time

path = sys.argv[1]
open(path, "wb").close()


def stop(signum, frame):
    os.unlink(path)
    sys.exit(0)


signal.signal(signal.SIGINT, stop)
while True:
    time.sleep(0.05)
"""

STUBBORN_RECORDER = """
import signal
import sys
import time

open(sys.argv[1], "wb").close()
signal.signal(signal.SIGINT, signal.SIG_IGN)
while True:
    time.sleep(0.05)
"""

SILENT_RECORDER = """
import signal
import sys
import time

signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(0))
while True:
    time.sleep(0.05)
"""

CRASHING_RECORDER = """
import signal
import sys
import time

path = sys.argv[1]
open(path, "wb").close()


def stop(signum, frame):
    with open(path, "wb") as sink:
        sink.write(b"a truncated segment")
    sys.stderr.write("the recorder lost the display midway\\n")
    sys.exit(1)


signal.signal(signal.SIGINT, stop)
while True:
    time.sleep(0.05)
"""


def stand_in(source: str):
    preamble = f"REPOSITORY = {str(REPOSITORY_ROOT)!r}\n"

    def command(udid: str, path: Path) -> list[str]:
        return [sys.executable, "-c", preamble + source, str(path)]

    return command


class SegmentNameTests(unittest.TestCase):
    """ffmpeg reads everything before the first colon of a relative path as a
    protocol scheme, so a segment named for a raw NodeID is unreadable from the
    directory that holds it. The colon becomes a doubled hyphen, which no slug
    can contain, so two NodeIDs never collapse onto one name."""

    def test_the_name_binds_the_node_and_the_attempt(self) -> None:
        self.assertEqual(
            "node--playback--seek-2.mp4", segment_filename("node:playback:seek", 2)
        )
        self.assertNotEqual(
            segment_filename("node:playback:seek", 1),
            segment_filename("node:playback:seek", 2),
        )
        self.assertNotEqual(
            segment_filename("node:playback", 1), segment_filename("node:menu", 1)
        )

    def test_no_colon_survives_into_the_name(self) -> None:
        self.assertNotIn(":", segment_filename("node:playback:seek", 1))

    def test_hyphenated_slugs_stay_distinguishable(self) -> None:
        self.assertNotEqual(
            segment_filename("node:a-b:c", 1), segment_filename("node:a:b-c", 1)
        )

    def test_the_recorder_command_is_the_simctl_one(self) -> None:
        self.assertEqual(
            [
                "xcrun",
                "simctl",
                "io",
                "UDID",
                "recordVideo",
                "--codec",
                "h264",
                "/tmp/segment.mp4",
            ],
            recorder_command("UDID", Path("/tmp/segment.mp4")),
        )


class TemporaryRootTests(unittest.TestCase):
    """`Scripts/verification/enchron_artifact_paths.sh` points TMPDIR at
    `.scratch/Temporary` inside the checkout, and simctl refuses to write there.
    The refusal is stated here rather than left to the child process."""

    def setUp(self) -> None:
        self.previous = os.environ.get("TMPDIR")

    def tearDown(self) -> None:
        if self.previous is None:
            os.environ.pop("TMPDIR", None)
        else:
            os.environ["TMPDIR"] = self.previous

    def test_a_tmpdir_inside_the_checkout_is_refused(self) -> None:
        os.environ["TMPDIR"] = str(REPOSITORY_ROOT / ".scratch" / "Temporary")

        with self.assertRaisesRegex(RecordingError, "inside the checkout"):
            temporary_root()

    def test_the_checkout_root_itself_is_refused(self) -> None:
        os.environ["TMPDIR"] = str(REPOSITORY_ROOT)

        with self.assertRaisesRegex(RecordingError, "inside the checkout"):
            temporary_root()

    def test_a_tmpdir_outside_the_checkout_is_taken_as_given(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            os.environ["TMPDIR"] = scratch
            self.assertEqual(Path(scratch).resolve(), temporary_root())

    def test_an_unset_tmpdir_falls_back_to_the_system_temporary_directory(self) -> None:
        os.environ.pop("TMPDIR", None)
        self.assertEqual(Path(tempfile.gettempdir()).resolve(), temporary_root())


class SegmentLifecycleTests(unittest.TestCase):
    """simctl refuses any output path inside the repository, so the segment is
    recorded into TMPDIR and moved to the evidence directory once it is closed."""

    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory()
        self.previous_tmpdir = os.environ.get("TMPDIR")
        os.environ["TMPDIR"] = self.scratch.name
        self.original_command = recording.recorder_command
        recording.recorder_command = stand_in(RUNNING_RECORDER)

    def tearDown(self) -> None:
        recording.recorder_command = self.original_command
        for segment in list(recording.ACTIVE_SEGMENTS.values()):
            segment.process.kill()
            segment.process.communicate()
        recording.ACTIVE_SEGMENTS.clear()
        if self.previous_tmpdir is None:
            os.environ.pop("TMPDIR", None)
        else:
            os.environ["TMPDIR"] = self.previous_tmpdir
        self.scratch.cleanup()

    def evidence(self) -> Path:
        return Path(self.scratch.name) / "evidence" / "segments"

    def test_the_segment_records_under_the_device_inside_tmpdir(self) -> None:
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        self.assertEqual(segment_root("UDID"), segment.path.parent)
        self.assertEqual(Path(self.scratch.name).resolve(), temporary_root())
        self.assertNotIn(REPOSITORY_ROOT, segment.path.parents)
        self.assertEqual("node--playback--seek-1.mp4", segment.path.name)

    def test_two_devices_recording_the_same_node_write_to_different_paths(self) -> None:
        one = start_segment("ONE", "node:playback:seek", 1, "scenario:playback")
        two = start_segment("TWO", "node:playback:seek", 1, "scenario:playback")

        self.assertNotEqual(one.path, two.path)
        self.assertEqual(one.path.name, two.path.name)
        self.assertIsNone(one.process.poll())
        self.assertIsNone(two.process.poll())

    def test_a_stopped_segment_lands_non_empty_in_the_evidence_directory(self) -> None:
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        landed = stop_segment(segment, self.evidence())

        self.assertEqual(self.evidence() / "node--playback--seek-1.mp4", landed)
        self.assertEqual(b"a segment of encoded video", landed.read_bytes())
        self.assertFalse(segment.path.exists())

    def test_the_device_takes_a_second_segment_only_after_the_first_is_stopped(
        self,
    ) -> None:
        first = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        with self.assertRaisesRegex(
            RecordingError, "is still recording node:playback:seek attempt 1 for "
            "scenario:playback"
        ):
            start_segment("UDID", "node:playback:seek", 2, "scenario:playback")

        stop_segment(first, self.evidence())
        second = start_segment("UDID", "node:playback:seek", 2, "scenario:playback")
        self.assertEqual(2, second.attempt)

    def test_the_device_refuses_a_segment_for_a_different_node_as_well(self) -> None:
        start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        with self.assertRaisesRegex(RecordingError, "is still recording"):
            start_segment("UDID", "node:menu:open", 1, "scenario:menu")

    def test_a_device_whose_recorder_died_is_refused_with_what_happened(self) -> None:
        recording.recorder_command = stand_in(DYING_RECORDER)
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")
        segment.process.wait()

        with self.assertRaisesRegex(RecordingError, "exited 3 without being stopped"):
            start_segment("UDID", "node:playback:seek", 2, "scenario:playback")

    def test_stopping_a_segment_twice_is_refused(self) -> None:
        first = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")
        stop_segment(first, self.evidence())
        second = start_segment("UDID", "node:playback:seek", 2, "scenario:playback")

        with self.assertRaisesRegex(RecordingError, "already stopped"):
            stop_segment(first, self.evidence())

        self.assertIs(second, recording.ACTIVE_SEGMENTS["UDID"])
        self.assertIsNone(second.process.poll())

    def test_filing_over_an_existing_segment_is_refused(self) -> None:
        first = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")
        landed = stop_segment(first, self.evidence())
        again = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        with self.assertRaisesRegex(RecordingError, "already holds a segment"):
            stop_segment(again, self.evidence())

        self.assertEqual(b"a segment of encoded video", landed.read_bytes())

    def test_an_attempt_below_one_is_refused_before_any_recorder_starts(self) -> None:
        with self.assertRaisesRegex(RecordingError, "numbered from one"):
            start_segment("UDID", "node:playback:seek", 0, "scenario:playback")

        self.assertEqual({}, recording.ACTIVE_SEGMENTS)
        self.assertFalse(segment_root("UDID").exists())

    def test_a_recorder_that_never_starts_reports_its_own_complaint(self) -> None:
        recording.recorder_command = stand_in(REFUSING_RECORDER)
        started = time.monotonic()

        with self.assertRaisesRegex(RecordingError, "simctl refused to record"):
            start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        self.assertLess(time.monotonic() - started, recording.START_BUDGET.seconds / 2)
        self.assertEqual({}, recording.ACTIVE_SEGMENTS)

    def test_a_recorder_that_starts_nothing_is_killed_within_the_budget(self) -> None:
        recording.recorder_command = stand_in(SILENT_RECORDER)
        original_budget = recording.START_BUDGET
        recording.START_BUDGET = Budget(1.0, "shortened for this test")
        try:
            with self.assertRaises(RecordingError) as raised:
                start_segment("UDID", "node:playback:seek", 1, "scenario:playback")
        finally:
            recording.START_BUDGET = original_budget

        self.assertIn("produced no file", str(raised.exception))
        self.assertIsInstance(raised.exception.__cause__, InstrumentFault)
        self.assertEqual({}, recording.ACTIVE_SEGMENTS)

    def test_a_recorder_that_ignores_the_stop_signal_is_killed_and_reported(
        self,
    ) -> None:
        recording.recorder_command = stand_in(STUBBORN_RECORDER)
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")
        original_timeout = recording.STOP_TIMEOUT_SECONDS
        recording.STOP_TIMEOUT_SECONDS = 1.0
        try:
            with self.assertRaisesRegex(RecordingError, "ignored SIGINT"):
                stop_segment(segment, self.evidence())
        finally:
            recording.STOP_TIMEOUT_SECONDS = original_timeout

        self.assertIsNotNone(segment.process.poll())
        self.assertEqual({}, recording.ACTIVE_SEGMENTS)

    def test_a_recorder_that_removes_its_output_is_refused_rather_than_filed(
        self,
    ) -> None:
        recording.recorder_command = stand_in(VANISHING_RECORDER)
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        with self.assertRaisesRegex(RecordingError, "left no bytes"):
            stop_segment(segment, self.evidence())

        self.assertFalse(self.evidence().exists())

    def test_a_recorder_that_writes_nothing_is_refused_rather_than_filed(self) -> None:
        recording.recorder_command = stand_in(EMPTY_RECORDER)
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        with self.assertRaisesRegex(RecordingError, "left no bytes"):
            stop_segment(segment, self.evidence())

        self.assertFalse(self.evidence().exists())

    def test_a_recorder_that_exits_badly_is_refused_and_names_its_file(self) -> None:
        recording.recorder_command = stand_in(CRASHING_RECORDER)
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        with self.assertRaises(RecordingError) as raised:
            stop_segment(segment, self.evidence())

        self.assertIn("exited 1", str(raised.exception))
        self.assertIn(str(segment.path), str(raised.exception))
        self.assertTrue(segment.path.is_file())
        self.assertEqual({}, recording.ACTIVE_SEGMENTS)

    def test_a_stale_segment_file_is_cleared_before_the_recorder_starts(self) -> None:
        stale = segment_root("UDID") / segment_filename("node:playback:seek", 1)
        stale.parent.mkdir(parents=True, exist_ok=True)
        stale.write_bytes(b"a segment left by a run that crashed")

        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")
        landed = stop_segment(segment, self.evidence())

        self.assertEqual(b"a segment of encoded video", landed.read_bytes())

    def test_a_broken_symlink_at_the_segment_path_is_cleared(self) -> None:
        stale = segment_root("UDID") / segment_filename("node:playback:seek", 1)
        stale.parent.mkdir(parents=True, exist_ok=True)
        stale.symlink_to(Path(self.scratch.name) / "a-target-that-was-deleted.mp4")

        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

        self.assertFalse(segment.path.is_symlink())

    def test_a_directory_at_the_segment_path_is_refused_by_name(self) -> None:
        occupied = segment_root("UDID") / segment_filename("node:playback:seek", 1)
        occupied.mkdir(parents=True)

        with self.assertRaisesRegex(RecordingError, "is a directory"):
            start_segment("UDID", "node:playback:seek", 1, "scenario:playback")

    def test_a_destination_that_is_a_file_is_refused_and_keeps_the_segment(
        self,
    ) -> None:
        segment = start_segment("UDID", "node:playback:seek", 1, "scenario:playback")
        occupied = Path(self.scratch.name) / "evidence-file"
        occupied.write_text("not a directory", encoding="utf-8")

        with self.assertRaisesRegex(RecordingError, "takes no segment"):
            stop_segment(segment, occupied)

        self.assertTrue(segment.path.is_file())


if __name__ == "__main__":
    unittest.main()
