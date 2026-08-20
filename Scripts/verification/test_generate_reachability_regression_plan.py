#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path

import generate_reachability_regression_plan as generator


class QualifiedEvidenceTests(unittest.TestCase):
    def test_requires_one_complete_continuous_session(self) -> None:
        document = {
            "status": "complete",
            "sessionID": "session-1",
            "channelHealth": {
                "before": {"passed": True, "sessionID": "session-1"},
                "after": {"passed": True, "sessionID": "session-1"},
            },
            "channelContinuity": {"passed": True},
            "probeJournal": {"passed": True},
        }

        self.assertTrue(generator.segment_result_is_qualified(document))
        document["channelHealth"]["after"]["sessionID"] = "session-2"
        self.assertFalse(generator.segment_result_is_qualified(document))


class RegressionPlanTests(unittest.TestCase):
    def test_reachable_cells_use_driven_routes_and_requested_defects_use_plans(
        self,
    ) -> None:
        reachable = generator.CellKey("window", "accessibility:reachable")
        defect = generator.CellKey("docked", "accessibility:defect")
        window_route = generator.Route(
            context="window",
            scenarios=("window-playback",),
            expected_maximum_steps=50,
            source_segment="window",
            source_result=Path("/evidence/window/results.json"),
        )
        docked_route = generator.Route(
            context="docked",
            scenarios=("docked-menus",),
            expected_maximum_steps=60,
            source_segment="docked",
            source_result=Path("/evidence/docked/results.json"),
        )

        plan = generator.build_plan(
            baseline={"cells": [
                {
                    "context": reachable.context,
                    "operation": reachable.operation,
                    "verdict": "reachable",
                },
                {
                    "context": defect.context,
                    "operation": defect.operation,
                    "verdict": "known-defect",
                },
            ]},
            driven_routes={reachable: {window_route}},
            planned_routes={defect: {docked_route}},
            additional_cells={defect},
        )

        self.assertEqual(plan["requiredReachableBaselineCells"], 1)
        self.assertEqual(
            sum(len(segment["decisions"]) for segment in plan["segments"]),
            2,
        )
        self.assertEqual(len(plan["segments"]), 2)

    def test_missing_reachable_route_fails_loudly(self) -> None:
        with self.assertRaisesRegex(ValueError, "accessibility:missing"):
            generator.build_plan(
                baseline={"cells": [{
                    "context": "main-window-browser",
                    "operation": "accessibility:missing",
                    "verdict": "reachable",
                }]},
                driven_routes={},
                planned_routes={},
                additional_cells=set(),
            )

    def test_current_portal_scenario_covers_transport_without_old_segment_data(
        self,
    ) -> None:
        key = generator.CellKey(
            "portal", "accessibility:PlayerPanel-button-forward"
        )

        route = generator.current_route_for_unmapped_cell(key)

        self.assertIsNotNone(route)
        self.assertEqual(route.scenarios, ("portal",))

    def test_docked_exit_addition_uses_the_corrected_command_route(self) -> None:
        key = generator.CellKey(
            "docked", "accessibility:PlayerPanel-button-exit-spatial"
        )

        route = generator.current_route_for_additional_cell(key)

        self.assertIsNotNone(route)
        self.assertEqual(route.scenarios, ("docked-exit-command-round11",))


if __name__ == "__main__":
    unittest.main()
