#!/usr/bin/env python3
from __future__ import annotations

import sys
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "verification"))

from harness.failures import InstrumentFault
import reachability_matrix as matrix

HUNG = "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"
CONTEXT = "main-window-browser"


def fake_run(lane: str) -> types.SimpleNamespace:
    def exploded(*_args, **_kwargs):
        raise AssertionError("controller reached")

    return types.SimpleNamespace(
        lane=lane,
        cells={},
        operations={},
        tapped_cells=set(),
        controller=exploded,
    )


class SimulatorRefusesTheOpen(unittest.TestCase):
    def test_open_tap_faults_before_touching_the_controller(self) -> None:
        run = fake_run("simulator")
        with self.assertRaises(InstrumentFault) as caught:
            matrix.ReachabilityRun.tap(run, CONTEXT, HUNG)
        self.assertEqual(caught.exception.kind, "playback-open-on-simulator-lane")
        self.assertEqual(caught.exception.evidence["identifier"], HUNG)
        self.assertEqual(caught.exception.evidence["operation"], f"accessibility:{HUNG}")
        self.assertEqual(run.tapped_cells, set())

    def test_device_lane_reaches_the_controller(self) -> None:
        with self.assertRaisesRegex(AssertionError, "controller reached"):
            matrix.ReachabilityRun.tap(fake_run("device"), CONTEXT, HUNG)

    def test_browse_tap_on_the_simulator_reaches_the_controller(self) -> None:
        with self.assertRaisesRegex(AssertionError, "controller reached"):
            matrix.ReachabilityRun.tap(
                fake_run("simulator"), CONTEXT, "MediaLibrary-Manage-newFolder"
            )


if __name__ == "__main__":
    unittest.main()
