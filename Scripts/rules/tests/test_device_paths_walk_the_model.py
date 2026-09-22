#!/usr/bin/env python3

"""Every device path has to be a walk the product can actually make.

The matrix and the stress run each carry their own table of where a step lands.
Both drifted off the model and asked for exit-spatial from portal, a button
portal does not have, so four paths could not complete on any build. Deriving
the landings is what fixed it; this is what keeps them derived.
"""

import unittest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

from playback_mode_matrix import PATHS
from playback_transition_stress import LEGAL_MOVES, build_step
from presentation_model import PRESENTATIONS, edge

UNCOMMITTED = "any-steady"


class MatrixPaths(unittest.TestCase):
    def test_every_step_lands_somewhere_the_model_declares(self) -> None:
        for name, steps in PATHS.items():
            for step in steps:
                landing = step.expect_presentation
                if landing == UNCOMMITTED:
                    continue
                self.assertIn(landing, PRESENTATIONS, f"{name}/{step.name}")

    def test_every_path_is_a_legal_walk(self) -> None:
        for name, steps in PATHS.items():
            landings = [s.expect_presentation for s in steps if s.expect_presentation != UNCOMMITTED]
            for source, target in zip(landings, landings[1:]):
                self.assertNotEqual(
                    edge(source, target), "illegal", f"{name}: {source} to {target}"
                )

    def test_no_path_asks_to_leave_the_immersive_space_from_the_main_window(self) -> None:
        for name, steps in PATHS.items():
            previous = None
            for step in steps:
                leaves = any("exit-spatial" in action for action in step.actions)
                if leaves and previous is not None:
                    self.assertIn(previous, ("panorama", "docked"), f"{name}/{step.name}")
                previous = step.expect_presentation


class StressMoves(unittest.TestCase):
    def test_every_offered_move_is_a_legal_edge(self) -> None:
        for source, moves in LEGAL_MOVES.items():
            for move in moves:
                target = build_step(move, source, "180_3D.mp4").expect_presentation
                self.assertNotEqual(
                    edge(source, target), "illegal", f"{source}: {move} to {target}"
                )

    def test_the_immersive_cells_only_offer_the_way_out(self) -> None:
        for source in ("panorama", "docked"):
            self.assertEqual(LEGAL_MOVES[source], ("exit-spatial",))

    def test_every_presentation_has_a_move_table(self) -> None:
        self.assertEqual(set(LEGAL_MOVES), set(PRESENTATIONS))


if __name__ == "__main__":
    unittest.main()
