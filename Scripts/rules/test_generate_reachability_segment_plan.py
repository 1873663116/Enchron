#!/usr/bin/env python3
from __future__ import annotations
import json
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))
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
