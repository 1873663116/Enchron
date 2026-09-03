#!/usr/bin/env python3
from __future__ import annotations

import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import run_campaign

EXECUTION_INPUT = {
    "buildIdentity": {"laneArtifacts": [{"lane": "simulator"}, {"lane": "device"}]}
}
REACHABLE = {"simulator": True, "device": True}
TWO_LANE = [
    {"segment": "probe-window", "target": "device"},
    {"segment": "probe-portal", "target": "device"},
    {"segment": "probe-main-window-browser", "target": "simulator"},
]


class CampaignLauncherTests(unittest.TestCase):
    def test_lanes_run_concurrently(self) -> None:
        barrier = threading.Barrier(2, timeout=5)
        seen_first: set[str] = set()
        lock = threading.Lock()
        tokens: list[str] = []

        def spawn(target: str, segment: str, token: str) -> int:
            tokens.append(token)
            with lock:
                first = target not in seen_first
                seen_first.add(target)
            if first:
                barrier.wait()
            return 0

        results = run_campaign.launch(TWO_LANE, EXECUTION_INPUT, REACHABLE, spawn)
        self.assertEqual(sorted(results), ["device", "simulator"])
        self.assertEqual(results["device"], [0, 0])
        self.assertEqual(results["simulator"], [0])

    def test_token_is_shared_and_non_empty(self) -> None:
        tokens: list[str] = []

        def spawn(target: str, segment: str, token: str) -> int:
            tokens.append(token)
            return 0

        run_campaign.launch(TWO_LANE, EXECUTION_INPUT, REACHABLE, spawn, token="abc123")
        self.assertEqual(set(tokens), {"abc123"})

    def test_segments_within_a_target_run_in_order(self) -> None:
        order: list[str] = []

        def spawn(target: str, segment: str, token: str) -> int:
            order.append(segment)
            return 0

        run_campaign.launch(
            [
                {"segment": "a", "target": "device"},
                {"segment": "b", "target": "device"},
                {"segment": "c", "target": "simulator"},
            ],
            EXECUTION_INPUT,
            REACHABLE,
            spawn,
        )
        self.assertLess(order.index("a"), order.index("b"))

    def test_refuses_when_not_parallelizable(self) -> None:
        single = [{"segment": "probe-window", "target": "device"}]
        with self.assertRaises(run_campaign.CampaignNotParallelizable):
            run_campaign.launch(single, EXECUTION_INPUT, REACHABLE, lambda *a: 0)

    def test_refuses_when_the_freeze_has_one_lane(self) -> None:
        one_lane = {"buildIdentity": {"laneArtifacts": [{"lane": "simulator"}]}}
        with self.assertRaises(run_campaign.CampaignNotParallelizable):
            run_campaign.launch(TWO_LANE, one_lane, REACHABLE, lambda *a: 0)


if __name__ == "__main__":
    unittest.main()
