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

if __name__ == "__main__":
    unittest.main()
