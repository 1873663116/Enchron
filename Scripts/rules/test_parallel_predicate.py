#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

from harness import parallel

BOTH_LANES = {"simulator", "device"}
BOTH_REACHABLE = {"simulator": True, "device": True}


class LaneTargetsTests(unittest.TestCase):
    def test_reads_lanes_from_freeze(self) -> None:
        execution_input = {
            "buildIdentity": {
                "laneArtifacts": [{"lane": "simulator"}, {"lane": "device"}]
            }
        }
        self.assertEqual(parallel.lane_targets(execution_input), BOTH_LANES)

    def test_missing_artifacts_yield_no_targets(self) -> None:
        self.assertEqual(parallel.lane_targets({}), set())


class PartitionTests(unittest.TestCase):
    def test_groups_segments_by_target(self) -> None:
        assignments = [
            {"segment": "probe-window", "target": "device"},
            {"segment": "probe-portal", "target": "device"},
            {"segment": "probe-main-window-browser", "target": "simulator"},
        ]
        self.assertEqual(
            parallel.partition_by_target(assignments),
            {"device": ["probe-window", "probe-portal"], "simulator": ["probe-main-window-browser"]},
        )


class ParallelizableTests(unittest.TestCase):
    def setUp(self) -> None:
        self.pending = {"device": ["probe-window"], "simulator": ["probe-main-window-browser"]}

    def test_true_when_two_targets_have_pending_reachable_frozen_work(self) -> None:
        self.assertTrue(parallel.parallelizable(BOTH_LANES, self.pending, BOTH_REACHABLE))
        self.assertEqual(
            parallel.parallelizable_targets(BOTH_LANES, self.pending, BOTH_REACHABLE),
            ["device", "simulator"],
        )

    def test_false_when_only_one_target_has_pending_work(self) -> None:
        pending = {"device": ["probe-window"], "simulator": []}
        self.assertFalse(parallel.parallelizable(BOTH_LANES, pending, BOTH_REACHABLE))

    def test_false_when_a_target_hardware_is_unreachable(self) -> None:
        reachable = {"simulator": True, "device": False}
        self.assertFalse(parallel.parallelizable(BOTH_LANES, self.pending, reachable))

    def test_false_when_the_freeze_lacks_a_lane_artifact(self) -> None:
        self.assertFalse(parallel.parallelizable({"simulator"}, self.pending, BOTH_REACHABLE))

    def test_false_when_both_lanes_share_one_worktree(self) -> None:
        shared = {"device": "/wt", "simulator": "/wt"}
        self.assertFalse(
            parallel.parallelizable(BOTH_LANES, self.pending, BOTH_REACHABLE, shared)
        )

    def test_true_when_each_lane_has_its_own_worktree(self) -> None:
        distinct = {"device": "/wt-a", "simulator": "/wt-b"}
        self.assertTrue(
            parallel.parallelizable(BOTH_LANES, self.pending, BOTH_REACHABLE, distinct)
        )

    def test_refusal_reason_names_the_targets(self) -> None:
        reason = parallel.serial_refusal_reason(["device", "simulator"])
        self.assertIn("device", reason)
        self.assertIn("simulator", reason)


class SerialRunRefusalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.execution_input = {
            "buildIdentity": {"laneArtifacts": [{"lane": "simulator"}, {"lane": "device"}]}
        }
        self.campaign = {
            "assignments": [
                {"segment": "probe-window", "target": "device"},
                {"segment": "probe-main-window-browser", "target": "simulator"},
            ],
            "reachable": {"simulator": True, "device": True},
        }

    def test_hand_run_of_a_parallelizable_segment_is_refused(self) -> None:
        reason = parallel.serial_run_refused(
            self.execution_input, self.campaign, token=None, this_segment="probe-window"
        )
        self.assertIsNotNone(reason)

    def test_launcher_token_is_allowed(self) -> None:
        self.assertIsNone(
            parallel.serial_run_refused(
                self.execution_input, self.campaign, token="abc", this_segment="probe-window"
            )
        )

    def test_no_campaign_declared_is_allowed(self) -> None:
        self.assertIsNone(
            parallel.serial_run_refused(
                self.execution_input, None, token=None, this_segment="probe-window"
            )
        )

    def test_segment_outside_the_campaign_is_allowed(self) -> None:
        self.assertIsNone(
            parallel.serial_run_refused(
                self.execution_input, self.campaign, token=None, this_segment="probe-docked"
            )
        )

    def test_unreachable_second_lane_is_allowed(self) -> None:
        campaign = dict(self.campaign)
        campaign["reachable"] = {"simulator": True, "device": False}
        self.assertIsNone(
            parallel.serial_run_refused(
                self.execution_input, campaign, token=None, this_segment="probe-window"
            )
        )


if __name__ == "__main__":
    unittest.main()
