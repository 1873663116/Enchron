#!/usr/bin/env python3

from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.contracts import BoundLane
from regression.core.errors import RegressionError
from regression.core.ids import NodeID
from regression.core.scheduler import PlannedNode, ReadyCandidate, choose_ready, compute_critical_costs


def node(
    identifier: str,
    cost: int,
    predecessors: tuple[str, ...] = (),
    lanes: tuple[BoundLane, ...] = (BoundLane.SIMULATOR,),
) -> PlannedNode:
    return PlannedNode(
        NodeID(identifier),
        cost,
        tuple(NodeID(item) for item in predecessors),
        lanes,
    )


class CriticalCostTests(unittest.TestCase):
    def test_bottom_level_uses_weighted_longest_remaining_path(self) -> None:
        costs = {
            str(item.node_id): item.remaining_millis
            for item in compute_critical_costs(
                (
                    node("node:a", 10),
                    node("node:b", 70, ("node:a",)),
                    node("node:c", 20, ("node:a",)),
                    node("node:d", 5, ("node:b", "node:c")),
                )
            )
        }
        self.assertEqual(
            {"node:a": 85, "node:b": 75, "node:c": 25, "node:d": 5},
            costs,
        )

    def test_cycle_reports_the_concrete_path(self) -> None:
        with self.assertRaises(RegressionError) as found:
            compute_critical_costs(
                (
                    node("node:a", 1, ("node:b",)),
                    node("node:b", 1, ("node:a",)),
                )
            )
        self.assertEqual("scheduler.cycle", found.exception.code)
        self.assertIn("node:a", found.exception.detail)
        self.assertIn("node:b", found.exception.detail)

    def test_unknown_predecessor_and_invalid_cost_are_rejected(self) -> None:
        with self.assertRaises(RegressionError) as missing:
            compute_critical_costs((node("node:a", 1, ("node:missing",)),))
        self.assertEqual("scheduler.unknown_predecessor", missing.exception.code)
        with self.assertRaises(RegressionError) as cost:
            node("node:a", True)
        self.assertEqual("scheduler.invalid_cost", cost.exception.code)

    def test_non_runnable_join_participates_in_the_critical_path(self) -> None:
        nodes = (
            node("node:sim", 10),
            node("node:device", 20),
            PlannedNode(
                NodeID("node:both:join"),
                0,
                (NodeID("node:sim"), NodeID("node:device")),
                (),
                runnable=False,
            ),
            node("node:after", 5, ("node:both:join",)),
        )
        costs = {
            str(item.node_id): item.remaining_millis
            for item in compute_critical_costs(nodes)
        }
        self.assertEqual(15, costs["node:sim"])
        self.assertEqual(25, costs["node:device"])
        self.assertEqual(5, costs["node:both:join"])

        with self.assertRaises(RegressionError) as found:
            PlannedNode(
                NodeID("node:bad:join"),
                0,
                (),
                (BoundLane.SIMULATOR,),
                runnable=False,
            )
        self.assertEqual("scheduler.join_has_lane", found.exception.code)


class ReadySelectionTests(unittest.TestCase):
    def candidate(
        self,
        identifier: str,
        lanes: tuple[BoundLane, ...],
        critical: int,
        state: int,
        cost: int,
    ) -> ReadyCandidate:
        return ReadyCandidate(NodeID(identifier), lanes, critical, state, cost)

    def test_lane_exclusive_work_is_protected_from_either_work(self) -> None:
        selected = choose_ready(
            (
                self.candidate(
                    "node:either",
                    (BoundLane.SIMULATOR, BoundLane.DEVICE),
                    1000,
                    5,
                    100,
                ),
                self.candidate(
                    "node:sim-only", (BoundLane.SIMULATOR,), 10, 0, 10
                ),
            ),
            BoundLane.SIMULATOR,
        )
        self.assertEqual(NodeID("node:sim-only"), selected.node_id)

    def test_critical_path_precedes_state_reuse_then_cost_then_id(self) -> None:
        critical = self.candidate(
            "node:critical", (BoundLane.SIMULATOR,), 100, 0, 1
        )
        stateful = self.candidate(
            "node:stateful", (BoundLane.SIMULATOR,), 90, 99, 1000
        )
        self.assertEqual(
            critical,
            choose_ready((stateful, critical), BoundLane.SIMULATOR),
        )
        stateful_high = self.candidate(
            "node:z", (BoundLane.SIMULATOR,), 100, 2, 1
        )
        self.assertEqual(
            stateful_high,
            choose_ready((critical, stateful_high), BoundLane.SIMULATOR),
        )
        costly = self.candidate("node:z", (BoundLane.SIMULATOR,), 100, 2, 8)
        cheap = self.candidate("node:a", (BoundLane.SIMULATOR,), 100, 2, 7)
        self.assertEqual(costly, choose_ready((cheap, costly), BoundLane.SIMULATOR))
        lexical = self.candidate("node:a", (BoundLane.SIMULATOR,), 100, 2, 8)
        self.assertEqual(lexical, choose_ready((costly, lexical), BoundLane.SIMULATOR))

    def test_no_ready_work_is_a_typed_error(self) -> None:
        with self.assertRaises(RegressionError) as found:
            choose_ready((), BoundLane.DEVICE)
        self.assertEqual("scheduler.no_ready_work", found.exception.code)

    def test_scheduler_module_parses_as_python_39(self) -> None:
        path = SCRIPTS / "regression/core/scheduler.py"
        ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
