#!/usr/bin/env python3
from __future__ import annotations

import sys
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "verification"))

import reachability_matrix as matrix

HUNG = "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"


def fake_run(lane: str):
    key = ("main-window-browser", f"accessibility:{HUNG}")
    run = types.SimpleNamespace(
        lane=lane,
        cells={key: {"verdict": "unmeasured", "reason": matrix.UNMEASURED_REASON}},
        deferred_opens=[],
        operations={},
        tapped_cells=set(),
    )

    def exploded(*_args, **_kwargs):
        raise AssertionError("controller must not be called for a deferred open")

    run.controller = exploded
    run.defer_playback_open = types.MethodType(
        matrix.ReachabilityRun.defer_playback_open, run
    )
    return run, key


class SimulatorDefersTheOpen(unittest.TestCase):
    def test_open_tap_is_deferred_without_touching_the_controller(self) -> None:
        run, key = fake_run("simulator")
        document = matrix.ReachabilityRun.tap(run, "main-window-browser", HUNG)
        self.assertEqual(document["deferredToLane"], "device")
        self.assertTrue(document["success"])
        self.assertNotIn("matchedElement", document)
        self.assertEqual(run.cells[key]["deferredToLane"], "device")
        self.assertEqual(run.cells[key]["verdict"], "unmeasured")
        self.assertEqual(len(run.deferred_opens), 1)
        self.assertEqual(run.deferred_opens[0]["identifier"], HUNG)

    def test_device_lane_does_not_defer(self) -> None:
        run, _ = fake_run("device")
        with self.assertRaises(AssertionError):
            matrix.ReachabilityRun.tap(run, "main-window-browser", HUNG)


if __name__ == "__main__":
    unittest.main()
