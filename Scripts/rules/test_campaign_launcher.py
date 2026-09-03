#!/usr/bin/env python3
from __future__ import annotations

import sys
import threading
import types
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

    def test_refuses_lanes_sharing_a_worktree(self) -> None:
        shared = {"device": "/wt/one", "simulator": "/wt/one"}
        with self.assertRaisesRegex(
            run_campaign.CampaignNotParallelizable, "distinct worktrees"
        ):
            run_campaign.launch(
                TWO_LANE, EXECUTION_INPUT, REACHABLE, lambda *a: 0, worktrees=shared
            )

    def test_distinct_worktrees_run_both_lanes(self) -> None:
        distinct = {"device": "/wt/device", "simulator": "/wt/simulator"}
        results = run_campaign.launch(
            TWO_LANE, EXECUTION_INPUT, REACHABLE, lambda *a: 0, worktrees=distinct
        )
        self.assertEqual(sorted(results), ["device", "simulator"])


class SpawnWorktreeTests(unittest.TestCase):
    def test_each_lane_runs_its_own_worktree_copy_of_the_matrix(self) -> None:
        from harness import campaign
        from unittest.mock import patch

        calls = []

        def fake_run(command, env, cwd):
            calls.append((list(command), cwd, env["ENCHRON_TARGET_DEVICE"]))
            return types.SimpleNamespace(returncode=0)

        spawn = campaign.default_spawn(
            {"device": "dev-udid", "simulator": "sim-udid"},
            {"device": Path("/wt/device"), "simulator": Path("/wt/simulator")},
            Path("/p/plan.json"),
            Path("/a/execution-input.json"),
            Path("/o"),
        )
        with patch.object(campaign.subprocess, "run", fake_run):
            spawn("simulator", "probe-main-window-browser", "tok")
            spawn("device", "probe-window", "tok")
        (sim_command, sim_cwd, sim_target), (dev_command, dev_cwd, dev_target) = calls
        self.assertEqual(sim_cwd, Path("/wt/simulator"))
        self.assertEqual(sim_command[1], "/wt/simulator/Scripts/verification/reachability_matrix.py")
        self.assertEqual(sim_target, "sim-udid")
        self.assertEqual(dev_cwd, Path("/wt/device"))
        self.assertEqual(dev_command[1], "/wt/device/Scripts/verification/reachability_matrix.py")
        self.assertEqual(dev_target, "dev-udid")


class ExtraArgsTests(unittest.TestCase):
    def test_extra_args_follow_the_segment_context(self) -> None:
        plan = {
            "segments": [
                {"id": "probe-main-window-browser", "context": "main-window-browser"},
                {"id": "probe-main-window-browser-playback", "context": "main-window-browser"},
                {"id": "probe-window", "context": "window"},
            ]
        }
        by_segment = run_campaign.extra_args_by_segment(
            plan, {"main-window-browser": ["--emby-credentials", "/creds.json"]}
        )
        self.assertEqual(
            by_segment,
            {
                "probe-main-window-browser": ["--emby-credentials", "/creds.json"],
                "probe-main-window-browser-playback": ["--emby-credentials", "/creds.json"],
                "probe-window": [],
            },
        )


class SegmentCommandTests(unittest.TestCase):
    def test_command_carries_execution_input_and_segment(self) -> None:
        from harness.campaign import segment_command

        command = segment_command(
            Path("/m/reachability_matrix.py"),
            Path("/p/plan.json"),
            Path("/a/execution-input.json"),
            Path("/o/device-probe-window"),
            "probe-window",
        )
        self.assertEqual(
            command[command.index("--execution-input") + 1], "/a/execution-input.json"
        )
        self.assertEqual(command[command.index("--segment") + 1], "probe-window")
        self.assertIn("/o/device-probe-window", command)

    def test_command_appends_extra_args(self) -> None:
        from harness.campaign import segment_command

        command = segment_command(
            Path("/m/reachability_matrix.py"),
            Path("/p/plan.json"),
            Path("/a/execution-input.json"),
            Path("/o/simulator-probe-main-window-browser"),
            "probe-main-window-browser",
            ["--emby-credentials", "/creds.json"],
        )
        self.assertEqual(command[command.index("--emby-credentials") + 1], "/creds.json")


if __name__ == "__main__":
    unittest.main()
