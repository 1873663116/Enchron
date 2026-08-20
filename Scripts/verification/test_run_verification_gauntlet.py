#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import fcntl
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

import run_verification_gauntlet as gauntlet


@contextlib.contextmanager
def captured():
    """Keep the guards' expected complaints out of the enclosing gate log.

    These tests run as one of the gate's own structure checks, so anything
    they print lands in a passing run's log and reads like a real failure.
    """
    stream = io.StringIO()
    with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
        yield stream


class StepSilenceGuardTests(unittest.TestCase):
    """The gate holds one lock for every worktree while a step runs.

    A step that stops emitting without exiting used to block the read loop
    forever, so the holder never released and every later run and every push
    queued behind it in silence.
    """

    def test_a_step_that_stops_emitting_is_terminated_with_its_subtree(self) -> None:
        original = gauntlet.STEP_SILENCE_SECONDS
        gauntlet.STEP_SILENCE_SECONDS = 2
        marker = f"gauntlet-silence-probe-{os.getpid()}"
        try:
            with tempfile.TemporaryDirectory() as scratch, captured():
                started = time.monotonic()
                code, output = gauntlet.run_logged(
                    "silence probe",
                    ["/bin/sh", "-c", f"echo alive; exec sleep 600 # {marker}"],
                    Path(scratch) / "step.log",
                    os.environ.copy(),
                )
        finally:
            gauntlet.STEP_SILENCE_SECONDS = original

        self.assertEqual(code, 124)
        self.assertLess(time.monotonic() - started, 30)
        self.assertIn("alive", output)
        self.assertIn("no output for", output)
        survivors = subprocess.run(
            ["/usr/bin/pgrep", "-f", marker],
            capture_output=True,
            text=True,
        )
        self.assertEqual(survivors.stdout.strip(), "")

    def test_a_step_that_finishes_normally_is_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as scratch, captured():
            code, output = gauntlet.run_logged(
                "fast probe",
                ["/bin/echo", "done"],
                Path(scratch) / "step.log",
                os.environ.copy(),
            )
        self.assertEqual(code, 0)
        self.assertEqual(output, "done\n")


class LockWaitGuardTests(unittest.TestCase):
    def test_a_held_lock_names_its_holder_and_gives_up(self) -> None:
        original = gauntlet.LOCK_WAIT_SECONDS
        gauntlet.LOCK_WAIT_SECONDS = 2
        try:
            with tempfile.TemporaryDirectory() as scratch:
                lock_path = Path(scratch) / ".gauntlet.lock"
                holder = subprocess.Popen(
                    [
                        sys.executable,
                        "-c",
                        "import fcntl, sys, time;"
                        f" f = open({str(lock_path)!r}, 'a+');"
                        " fcntl.flock(f, fcntl.LOCK_EX);"
                        " sys.stderr.write('ready\\n'); sys.stderr.flush();"
                        " time.sleep(60)",
                    ],
                    stderr=subprocess.PIPE,
                    text=True,
                )
                try:
                    self.assertEqual(holder.stderr.readline().strip(), "ready")
                    with captured() as complaint:
                        with lock_path.open("a+", encoding="utf-8") as lock:
                            self.assertFalse(gauntlet.acquire_lock(lock, lock_path))
                    self.assertIn(str(holder.pid), complaint.getvalue())
                finally:
                    holder.kill()
                    holder.wait()
                    holder.stderr.close()
        finally:
            gauntlet.LOCK_WAIT_SECONDS = original

    def test_a_free_lock_is_taken_without_waiting(self) -> None:
        with tempfile.TemporaryDirectory() as scratch, captured():
            lock_path = Path(scratch) / ".gauntlet.lock"
            with lock_path.open("a+", encoding="utf-8") as lock:
                started = time.monotonic()
                self.assertTrue(gauntlet.acquire_lock(lock, lock_path))
                self.assertLess(time.monotonic() - started, 1)
                fcntl.flock(lock, fcntl.LOCK_UN)


if __name__ == "__main__":
    unittest.main()
