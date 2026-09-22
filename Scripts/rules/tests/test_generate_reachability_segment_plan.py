#!/usr/bin/env python3
from __future__ import annotations
import json
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))
from harness import lane_partition
import reachability_matrix as matrix
import generate_reachability_segment_plan as plan

class MergeSharedRunnerSessionTests(unittest.TestCase):
    def test_merge_accepts_results_sharing_runner_sessionID_but_different_evidenceSession(self) -> None:
        baseline = [
            {"context": "window", "operation": "accessibility:a", "verdict": "known-defect"},
            {"context": "window", "operation": "accessibility:b", "verdict": "known-defect"},
        ]
        segment1 = {
            "segment": "window-a",
            "status": "complete",
            "sessionID": "runner-shared",
            "evidenceSession": "evidence-1",
            "channelHealth": {
                "before": {"passed": True, "sessionID": "runner-shared"},
                "after": {"passed": True, "sessionID": "runner-shared"},
            },
            "channelContinuity": {"passed": True},
            "cells": [
                {"context": "window", "operation": "accessibility:a", "verdict": "reachable", "evidence": ["raw/probe.log"], "applicationReceived": True, "existsInHierarchy": True, "reportsHittable": True},
            ],
            "drivenCells": [{"context": "window", "operation": "accessibility:a"}],
            "deliveryAssessmentModel": "explicit-v1",
            "schemaVersion": 3,
        }
        segment2 = {
            "segment": "window-b",
            "status": "complete",
            "sessionID": "runner-shared",
            "evidenceSession": "evidence-2",
            "channelHealth": {
                "before": {"passed": True, "sessionID": "runner-shared"},
                "after": {"passed": True, "sessionID": "runner-shared"},
            },
            "channelContinuity": {"passed": True},
            "cells": [
                {"context": "window", "operation": "accessibility:b", "verdict": "reachable", "evidence": ["raw/probe.log"], "applicationReceived": True, "existsInHierarchy": True, "reportsHittable": True},
            ],
            "drivenCells": [{"context": "window", "operation": "accessibility:b"}],
            "deliveryAssessmentModel": "explicit-v1",
            "schemaVersion": 3,
        }
        delivery = matrix.merge_segment_delivery(baseline, [segment1, segment2])
        self.assertTrue(delivery["accepted"])
        self.assertEqual(set(delivery["acceptedSegments"]), {"window-a", "window-b"})
        self.assertEqual(delivery["rejectedSegments"], [])
        verdicts = {(c["context"], c["operation"]): c["verdict"] for c in delivery["candidateCells"]}
        self.assertEqual(verdicts[("window", "accessibility:a")], "reachable")
        self.assertEqual(verdicts[("window", "accessibility:b")], "reachable")

    def test_probe_plan_covers_inventory_cells(self) -> None:
        probe = plan.probe_plan()
        self.assertTrue(len(probe["segments"]) >= 1)
        self.assertTrue(all("decisions" in s for s in probe["segments"]))

    def test_probe_plan_validates(self) -> None:
        self.assertEqual(plan.validate(plan.probe_plan()), [])

    def test_every_segment_declares_its_lane(self) -> None:
        for seg in plan.probe_plan()["segments"]:
            self.assertIn(seg["lane"], ("simulator", "device"), seg["id"])
            if seg["context"] != "main-window-browser":
                self.assertEqual(seg["lane"], "device", seg["id"])

    def test_browser_scenarios_split_by_lane_without_loss(self) -> None:
        probe = plan.probe_plan()
        browse = next(s for s in probe["segments"] if s["id"] == plan.BROWSER_SEGMENT)
        playback = next(s for s in probe["segments"] if s["id"] == plan.BROWSER_PLAYBACK_SEGMENT)
        self.assertEqual(browse["lane"], "simulator")
        self.assertEqual(playback["lane"], "device")
        self.assertEqual(set(browse["scenarios"]) & set(playback["scenarios"]), set())
        self.assertEqual(
            sorted(browse["scenarios"] + playback["scenarios"]),
            plan.scenarios_by_context()["main-window-browser"],
        )
        for name in browse["scenarios"]:
            self.assertEqual(matrix.SCENARIO_LANES[name], "simulator", name)
        for name in playback["scenarios"]:
            self.assertEqual(matrix.SCENARIO_LANES[name], "device", name)

    def test_simulator_browser_segment_never_decides_an_opener(self) -> None:
        probe = plan.probe_plan()
        by_id = plan.inventory_operations()
        browse = next(s for s in probe["segments"] if s["id"] == plan.BROWSER_SEGMENT)
        playback = next(s for s in probe["segments"] if s["id"] == plan.BROWSER_PLAYBACK_SEGMENT)
        openers = {
            op for op in plan.inventory_cells()["main-window-browser"]
            if lane_partition.opens_playback(by_id[op])
        }
        self.assertTrue(openers)
        self.assertEqual({d["operation"] for d in browse["decisions"]} & openers, set())
        self.assertTrue(openers <= {d["operation"] for d in playback["decisions"]})

    def test_final_plan_takes_context_and_scenarios_from_the_probe_result(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = Path(directory) / "results.json"
            result.write_text(json.dumps({
                "segment": plan.BROWSER_PLAYBACK_SEGMENT,
                "segmentPlan": {
                    "context": "main-window-browser",
                    "scenarios": ["resume-decision"],
                },
                "drivenCells": [
                    {"context": "main-window-browser", "operation": "accessibility:MediaLibrary-grid-video-{reference.name}"},
                ],
            }), encoding="utf-8")
            final, uncovered = plan.final_plan([result], 60)
        self.assertEqual(len(final["segments"]), 1)
        segment = final["segments"][0]
        self.assertEqual(segment["id"], "main-window-browser-playback-driven")
        self.assertEqual(segment["context"], "main-window-browser")
        self.assertEqual(segment["lane"], "device")
        self.assertEqual(segment["scenarios"], ["resume-decision"])
        self.assertEqual(len(segment["decisions"]), 1)
        self.assertTrue(uncovered)


class LaneValidationTests(unittest.TestCase):
    def validate(self, lane, context="main-window-browser", scenarios=("browser-core",)):
        segment = {
            "id": "s",
            "context": context,
            "expectedMaximumSteps": 10,
            "scenarios": list(scenarios),
            "decisions": [{"context": context, "operation": "accessibility:x"}],
        }
        if lane is not None:
            segment["lane"] = lane
        return matrix.validate_segment_plan(
            {"segments": [segment]},
            operation_contexts={"accessibility:x": {context}},
            scenario_names={"browser-core", "resume-decision", "window-playback"},
            scenario_lanes={"browser-core": "simulator", "resume-decision": "device", "window-playback": "device"},
        )

    def test_a_segment_without_a_lane_is_rejected(self) -> None:
        self.assertTrue(any("must declare lane" in e for e in self.validate(None)))

    def test_a_simulator_segment_with_an_opening_scenario_is_rejected(self) -> None:
        errors = self.validate("simulator", scenarios=("browser-core", "resume-decision"))
        self.assertTrue(any("resume-decision opens playback" in e for e in errors), errors)

    def test_a_simulator_segment_on_a_presentation_is_rejected(self) -> None:
        errors = self.validate("simulator", context="window", scenarios=("window-playback",))
        self.assertTrue(any("needs the device lane" in e for e in errors), errors)

    def test_a_device_segment_may_run_anything(self) -> None:
        self.assertEqual(self.validate("device", scenarios=("browser-core", "resume-decision")), [])

    def test_a_simulator_segment_of_browse_scenarios_is_accepted(self) -> None:
        self.assertEqual(self.validate("simulator"), [])

    def test_docked_reset_media_step_belongs_to_exactly_one_segment(self) -> None:
        probe = plan.probe_plan()
        ids = [s["id"] for s in probe["segments"]]
        self.assertIn("probe-docked-reset-media-information", ids)
        self.assertIn("probe-docked", ids)
        self.assertLess(ids.index("probe-docked"), ids.index("probe-docked-reset-media-information"))
        fault_ops = {
            ("docked", "accessibility:PlayerPanel-DockedPlacement-reset"),
            ("docked", "accessibility:PlayerPanel-media-information"),
        }
        owners = {op: [] for op in fault_ops}
        for seg in probe["segments"]:
            for dec in seg["decisions"]:
                key = (dec["context"], dec["operation"])
                if key in owners:
                    owners[key].append(seg["id"])
        for op, segs in owners.items():
            self.assertEqual(segs, ["probe-docked-reset-media-information"], f"{op} must belong to exactly one segment")

    def test_panel_back_buttons_each_land_in_one_existing_segment(self) -> None:
        probe = plan.probe_plan()
        wanted = {
            ("window", "accessibility:PlayerPanel-precision-timeline-back"),
            ("portal", "accessibility:PlayerPanel-precision-timeline-back"),
            ("panorama", "accessibility:PlayerPanel-precision-timeline-back"),
            ("docked", "accessibility:PlayerPanel-precision-timeline-back"),
            ("docked", "accessibility:PlayerPanel-DockedPlacement-back"),
        }
        owners = {key: [] for key in wanted}
        for seg in probe["segments"]:
            for dec in seg["decisions"]:
                key = (dec["context"], dec["operation"])
                if key in owners:
                    owners[key].append(seg["id"])
        self.assertEqual(owners[("window", "accessibility:PlayerPanel-precision-timeline-back")], ["probe-window"])
        self.assertEqual(owners[("portal", "accessibility:PlayerPanel-precision-timeline-back")], ["probe-portal"])
        self.assertEqual(owners[("panorama", "accessibility:PlayerPanel-precision-timeline-back")], ["probe-panorama"])
        self.assertEqual(owners[("docked", "accessibility:PlayerPanel-precision-timeline-back")], ["probe-docked"])
        self.assertEqual(
            owners[("docked", "accessibility:PlayerPanel-DockedPlacement-back")],
            ["probe-docked-reset-media-information"],
        )

    def test_the_docked_settings_close_follows_the_settings_open_into_the_reset_segment(
        self,
    ) -> None:
        """docked_settings_scenario is the only route to both buttons.

        probe-docked returns before it, so a cell declared there is planned and
        never driven.
        """
        self.assertIn(
            "accessibility:PlayerPanel-DockedPlacement-back",
            plan.DOCKED_RESET_OPERATIONS,
        )
        probe = plan.probe_plan()
        docked = next(s for s in probe["segments"] if s["id"] == "probe-docked")
        self.assertNotIn(
            "accessibility:PlayerPanel-DockedPlacement-back",
            {d["operation"] for d in docked["decisions"]},
        )

    def test_probe_docked_does_not_claim_fault_step(self) -> None:
        probe = plan.probe_plan()
        docked = next(s for s in probe["segments"] if s["id"] == "probe-docked")
        fault = next(s for s in probe["segments"] if s["id"] == "probe-docked-reset-media-information")
        docked_keys = {(d["context"], d["operation"]) for d in docked["decisions"]}
        fault_keys = {(d["context"], d["operation"]) for d in fault["decisions"]}
        self.assertTrue(fault_keys)
        self.assertEqual(docked_keys & fault_keys, set())
        self.assertIn("docked-reset-media-information", fault["scenarios"])
        self.assertNotIn("docked-reset-media-information", docked["scenarios"])

if __name__ == "__main__":
    unittest.main()
