#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from types import MappingProxyType
from typing import Any, Mapping
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
if str(SCRIPTS / "rules") not in sys.path:
    sys.path.insert(0, str(SCRIPTS / "rules"))

from regression.core.contracts import BoundLane
from regression.core.errors import RegressionError
from regression.core.events import EventType
from regression.core.expression import OracleResult
from regression.core.ids import CallID, NodeID, SidekickID
from regression.core.replay import replay
from regression.core.runtime import open_run
from regression.tools import op_tool
from regression.tools.op_tool import OpToolError
from regression.tools.pixel_heuristics import ALL_BLACK, CAPTURE_FAILED

from test_regression_core_runtime import _plan, _node, _single_node_plan
from test_regression_ledger_lock import _both_lane_plan, run_node
from test_regression_pixel_heuristics import flat, png


SIDEKICK = SidekickID("sidekick:op")
TARGET = "SIMULATOR-UDID"


@dataclass(frozen=True)
class FakeInvocation:
    operation_id: str
    outputs: tuple
    result: Mapping[str, Any]


class FakeAdapter:
    def __init__(self, backend: Any) -> None:
        self.backend = backend

    def invoke(self, operation_id, arguments, context):
        return FakeInvocation(
            operation_id, (), MappingProxyType(dict(FakeAdapter.result))
        )


def adapter_returning(**result):
    FakeAdapter.result = result
    return FakeAdapter


class OpToolTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = op_tool.RegressionOperationAdapter
        self.backend = op_tool.ResidentOperationBackend
        op_tool.ResidentOperationBackend = lambda: None
        self.addCleanup(self.restore)

    def restore(self) -> None:
        op_tool.RegressionOperationAdapter = self.adapter
        op_tool.ResidentOperationBackend = self.backend

    def use(self, **result) -> None:
        op_tool.RegressionOperationAdapter = adapter_returning(**result)

    def screenshot(self, directory: Path, name: str, width, height, value) -> str:
        path = directory / name
        path.write_bytes(png(width, height, flat(width, height, value)))
        return str(path)


class LaneLockTests(OpToolTestCase):
    def test_a_locked_lane_refuses_before_the_call_is_authorized(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _both_lane_plan()
            main = open_run(plan, directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()
            before = len(replay(directory).events)

            self.use(succeeded=True)
            outcome = op_tool.run(
                plan,
                directory,
                lease.node_id,
                CallID("call:gate-evidence"),
                BoundLane.SIMULATOR,
                TARGET,
                SIDEKICK,
                now_millis=0,
            ).payload()

            self.assertTrue(outcome["refused"])
            self.assertEqual(str(lease.node_id), outcome["pendingNode"])
            after = replay(directory)
            self.assertEqual(before, len(after.events))
            self.assertFalse(
                any(
                    event.type is EventType.OPERATION_AUTHORIZED
                    for event in after.events[before:]
                )
            )

    def test_an_open_lane_is_not_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.use(succeeded=True)
            outcome = op_tool.run(
                _single_node_plan(),
                directory,
                NodeID("node:gate"),
                CallID("call:gate-evidence"),
                BoundLane.SIMULATOR,
                TARGET,
                SIDEKICK,
                now_millis=0,
            ).payload()
            self.assertNotIn("refused", outcome)
            self.assertTrue(outcome["succeeded"])


class CallSelectionTests(OpToolTestCase):
    def plan_with_two_calls(self):
        from test_regression_core_runtime import _call, MainGateBinding

        node = _node(
            "gate",
            (BoundLane.SIMULATOR,),
            calls=(_call("gate-first"), _call("gate-second")),
        )
        return _plan(
            (node,),
            (MainGateBinding(BoundLane.SIMULATOR, node.scenario_id, node.id),),
        )

    def test_a_call_out_of_plan_order_is_refused_by_name(self) -> None:
        with TemporaryDirectory() as temporary:
            self.use(succeeded=True)
            with self.assertRaisesRegex(OpToolError, "comes before"):
                op_tool.run(
                    self.plan_with_two_calls(),
                    Path(temporary),
                    NodeID("node:gate"),
                    CallID("call:gate-second"),
                    BoundLane.SIMULATOR,
                    TARGET,
                    SIDEKICK,
                    now_millis=0,
                )

    def test_a_node_the_scheduler_does_not_offer_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            self.use(succeeded=True)
            outcome = op_tool.run(
                _single_node_plan(),
                Path(temporary),
                NodeID("node:absent"),
                CallID("call:gate-evidence"),
                BoundLane.SIMULATOR,
                TARGET,
                SIDEKICK,
                now_millis=0,
            ).payload()
            self.assertTrue(outcome["refused"])
            self.assertIn("the scheduler offers", outcome["reason"])

    def test_the_second_call_runs_after_the_first_advances_the_cursor(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = self.plan_with_two_calls()
            self.use(succeeded=True)
            first = op_tool.run(
                plan, directory, NodeID("node:gate"), CallID("call:gate-first"),
                BoundLane.SIMULATOR, TARGET, SIDEKICK, now_millis=0,
            ).payload()
            second = op_tool.run(
                plan, directory, NodeID("node:gate"), CallID("call:gate-second"),
                BoundLane.SIMULATOR, TARGET, SIDEKICK, now_millis=0,
            ).payload()
            self.assertEqual("call:gate-first", first["call"])
            self.assertEqual("call:gate-second", second["call"])


class ArmRefusalTests(OpToolTestCase):
    def armed_plan(self):
        from dataclasses import replace as replace_field
        from test_regression_core_runtime import _call, MainGateBinding

        node = _node(
            "gate",
            (BoundLane.SIMULATOR,),
            calls=(
                _call("gate-first"),
                replace_field(
                    _call("gate-arm"), operation=op_tool.TRANSITION_TRACE_ARM
                ),
            ),
        )
        return _plan(
            (node,),
            (MainGateBinding(BoundLane.SIMULATOR, node.scenario_id, node.id),),
        )

    def test_a_node_holding_an_arm_is_refused_before_any_lease_is_claimed(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.use(succeeded=True)
            outcome = op_tool.run(
                self.armed_plan(), directory, NodeID("node:gate"),
                CallID("call:gate-first"), BoundLane.SIMULATOR, TARGET,
                SIDEKICK, now_millis=0,
            ).payload()

            self.assertTrue(outcome["refused"])
            self.assertIn("disarm", outcome["reason"])
            self.assertEqual((), replay(directory).leases)
            self.assertFalse(
                any(
                    event.type is EventType.NODE_CLAIMED
                    for event in replay(directory).events
                )
            )


class TargetPinTests(OpToolTestCase):
    def two_call_plan(self):
        from test_regression_core_runtime import _call, MainGateBinding

        node = _node(
            "gate",
            (BoundLane.SIMULATOR,),
            calls=(_call("gate-first"), _call("gate-second")),
        )
        return _plan(
            (node,),
            (MainGateBinding(BoundLane.SIMULATOR, node.scenario_id, node.id),),
        )

    def test_one_scenario_cannot_move_to_another_device_part_way_through(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = self.two_call_plan()
            self.use(succeeded=True)
            op_tool.run(
                plan, directory, NodeID("node:gate"), CallID("call:gate-first"),
                BoundLane.SIMULATOR, "SIM-A", SIDEKICK, now_millis=0,
            )
            with self.assertRaisesRegex(OpToolError, "already ran against SIM-A"):
                op_tool.run(
                    plan, directory, NodeID("node:gate"), CallID("call:gate-second"),
                    BoundLane.SIMULATOR, "SIM-B", SIDEKICK, now_millis=0,
                )

    def test_a_lease_belonging_to_another_sidekick_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = self.two_call_plan()
            self.use(succeeded=True)
            op_tool.run(
                plan, directory, NodeID("node:gate"), CallID("call:gate-first"),
                BoundLane.SIMULATOR, TARGET, SIDEKICK, now_millis=0,
            )
            with self.assertRaisesRegex(OpToolError, "belongs to"):
                op_tool.run(
                    plan, directory, NodeID("node:gate"), CallID("call:gate-second"),
                    BoundLane.SIMULATOR, TARGET, SidekickID("sidekick:other"),
                    now_millis=0,
                )


class PixelSignatureTests(OpToolTestCase):
    def drive(self, directory: Path, screenshot_path: str):
        self.use(succeeded=True, localScreenshotPath=screenshot_path)
        return op_tool.run(
            _single_node_plan(),
            directory,
            NodeID("node:gate"),
            CallID("call:gate-evidence"),
            BoundLane.SIMULATOR,
            TARGET,
            SIDEKICK,
            now_millis=0,
        ).payload()

    def test_a_one_by_one_screenshot_hits_the_capture_failed_signature(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            outcome = self.drive(
                directory, self.screenshot(directory, "shot.png", 1, 1, 0)
            )
            self.assertIn(str(CAPTURE_FAILED), outcome["signatures"])

    def test_a_black_screenshot_hits_the_all_black_signature(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            outcome = self.drive(
                directory, self.screenshot(directory, "shot.png", 40, 30, 0)
            )
            self.assertEqual([str(ALL_BLACK)], outcome["signatures"])

    def test_a_real_frame_hits_no_signature(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            outcome = self.drive(
                directory, self.screenshot(directory, "shot.png", 40, 30, 200)
            )
            self.assertEqual([], outcome["signatures"])
            self.assertLess(0, outcome["screenshotBytes"])

    def test_a_screenshot_nested_in_the_response_is_still_found(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            path = self.screenshot(directory, "nested.png", 1, 1, 0)
            self.use(
                succeeded=True,
                record={"playbackState": {"response": {"localScreenshotPath": path}}},
            )
            outcome = op_tool.run(
                _single_node_plan(), directory, NodeID("node:gate"),
                CallID("call:gate-evidence"), BoundLane.SIMULATOR, TARGET,
                SIDEKICK, now_millis=0,
            ).payload()
            self.assertIn(str(CAPTURE_FAILED), outcome["signatures"])

    def test_a_call_without_a_screenshot_reports_no_signature(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.use(succeeded=True)
            outcome = op_tool.run(
                _single_node_plan(), directory, NodeID("node:gate"),
                CallID("call:gate-evidence"), BoundLane.SIMULATOR, TARGET,
                SIDEKICK, now_millis=0,
            ).payload()
            self.assertEqual([], outcome["signatures"])
            self.assertEqual(0, outcome["screenshotBytes"])


class FieldPredicateTests(OpToolTestCase):
    def test_every_obligation_reports_that_no_predicate_is_compiled_yet(self) -> None:
        with TemporaryDirectory() as temporary:
            self.use(succeeded=True)
            outcome = op_tool.run(
                _single_node_plan(), Path(temporary), NodeID("node:gate"),
                CallID("call:gate-evidence"), BoundLane.SIMULATOR, TARGET,
                SIDEKICK, now_millis=0,
            ).payload()
            self.assertTrue(outcome["predicates"])
            for obligation, verdict in outcome["predicates"].items():
                with self.subTest(obligation=obligation):
                    self.assertEqual(op_tool.NO_FIELD_PREDICATE, verdict)

    def test_the_absent_predicate_is_never_reported_as_a_pass(self) -> None:
        with TemporaryDirectory() as temporary:
            self.use(succeeded=True)
            outcome = op_tool.run(
                _single_node_plan(), Path(temporary), NodeID("node:gate"),
                CallID("call:gate-evidence"), BoundLane.SIMULATOR, TARGET,
                SIDEKICK, now_millis=0,
            ).payload()
            for verdict in outcome["predicates"].values():
                self.assertNotIn(verdict.lower(), ("pass", "passed", "satisfied"))


class AdapterBridgeTests(OpToolTestCase):
    def test_a_backend_result_without_a_boolean_succeeded_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            self.use(reason="the runner never answered")
            with self.assertRaises(RegressionError) as raised:
                op_tool.run(
                    _single_node_plan(), Path(temporary), NodeID("node:gate"),
                    CallID("call:gate-evidence"), BoundLane.SIMULATOR, TARGET,
                    SIDEKICK, now_millis=0,
                )
            self.assertEqual("runtime.operation_adapter_error", raised.exception.code)
            self.assertIn("op.invalid_backend_result", raised.exception.detail)

    def test_a_failed_call_carries_its_reason_as_the_detail(self) -> None:
        with TemporaryDirectory() as temporary:
            self.use(succeeded=False, reason="the gate never appeared")
            outcome = op_tool.run(
                _single_node_plan(), Path(temporary), NodeID("node:gate"),
                CallID("call:gate-evidence"), BoundLane.SIMULATOR, TARGET,
                SIDEKICK, now_millis=0,
            ).payload()
            self.assertFalse(outcome["succeeded"])
            self.assertEqual("the gate never appeared", outcome["detail"])

    def test_the_lease_outlives_a_single_process(self) -> None:
        self.assertLessEqual(60 * 60 * 1000, op_tool.OP_LEASE_DURATION_MILLIS)

    def test_a_lane_and_target_are_both_required(self) -> None:
        with TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(OpToolError, "one concrete lane"):
                op_tool.run(
                    _single_node_plan(), Path(temporary), NodeID("node:gate"),
                    CallID("call:gate-evidence"), "simulator", TARGET, SIDEKICK,
                )
            with self.assertRaisesRegex(OpToolError, "device or simulator"):
                op_tool.run(
                    _single_node_plan(), Path(temporary), NodeID("node:gate"),
                    CallID("call:gate-evidence"), BoundLane.SIMULATOR, "", SIDEKICK,
                )


if __name__ == "__main__":
    unittest.main()
