#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
if str(SCRIPTS / "rules") not in sys.path:
    sys.path.insert(0, str(SCRIPTS / "rules"))

from regression.core.contracts import BoundLane
from regression.core.errors import RegressionError
from regression.core.events import EventType, payload_value
from regression.core.expression import OracleResult
from regression.core.ids import NodeID, SidekickID
from regression.core.ledger import LedgerWriter
from regression.core.plan import LaneGateDependency, MainGateBinding
from regression.core.replay import read_event_log, replay
from regression.core.runtime import OperationResult, open_run
from regression.core.runview import (
    NodeStatus,
    RunOutcome,
    build_run_view,
    montage_frame_bound,
)
from regression.tools import ledger_tool
from regression.tools.ledger_lock import (
    LaneLockState,
    LedgerLockError,
    admit_verdict,
    deferrable,
    lane_lock_state,
    verdict_payload,
)
from regression.tools.signatures import ALL_BLACK
from regression.tools.verdict import Attribution, Verdict

from test_regression_core_runtime import (
    FakeOperationAdapter,
    FakeOracle,
    _call,
    _complete_operations,
    _envelope,
    _invoke_current,
    _node,
    _plan,
    _single_node_plan,
)
from test_regression_ledger_lock import (
    _both_lane_plan,
    _join_follower_plan,
    run_node,
    verdict,
)

GATE = NodeID("node:gate")
FOLLOWER = NodeID("node:red")


def append(directory: Path, event_type: EventType, payload: dict, key: str) -> None:
    log = read_event_log(directory)
    with LedgerWriter(directory, log.run_id, log.plan_digest, build_run_view) as writer:
        writer.append(event_type, payload, "2026-09-05T00:00:00.000Z", key)


def forged_verdict(
    node: NodeID,
    status: NodeStatus,
    lease_id=None,
    ancestors=(),
    adjudication=None,
) -> dict:
    payload = {
        "nodeId": str(node),
        "leaseId": None if lease_id is None else str(lease_id),
        "status": status.value,
        "failureAncestors": [str(item) for item in ancestors],
    }
    if adjudication is not None:
        payload["adjudication"] = adjudication
    return payload


def adjudication(**changes) -> dict:
    base = {
        "attribution": "product",
        "bundleFrameCount": 0,
        "firstDeviantFrame": None,
        "regionObservation": "the poster grid stayed blank",
        "signature": None,
    }
    base.update(changes)
    return base


def failed_call(kind: str, failure_class: str = "instrument") -> OperationResult:
    return OperationResult(False, (), "", {"failure": {"class": failure_class, "kind": kind}})


def gate_and_follower_plan():
    gate = _node("gate", (BoundLane.SIMULATOR,), critical=500)
    follower = _node(
        "red",
        (BoundLane.SIMULATOR,),
        predecessors=(gate.id,),
        gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
        critical=100,
    )
    return _plan(
        (gate, follower),
        (MainGateBinding(BoundLane.SIMULATOR, gate.scenario_id, gate.id),),
    )


class UnleasedVerdictTests(unittest.TestCase):
    """A node that holds no lease closes only the way the run derives it. The
    ancestors a blockedBy names, and the passed a join claims, are read from
    the other nodes, not from the row that states them."""

    def test_a_blocked_by_behind_a_phantom_ancestor_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            open_run(_single_node_plan(), directory).close()

            with self.assertRaisesRegex(RegressionError, "derives nothing"):
                append(
                    directory,
                    EventType.VERDICT_RECORDED,
                    forged_verdict(
                        GATE, NodeStatus.BLOCKED_BY, ancestors=(NodeID("node:phantom"),)
                    ),
                    "verdict:forged",
                )

    def test_a_blocked_by_on_a_leased_node_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = main.claim(BoundLane.SIMULATOR, SidekickID("sidekick:one"), now_millis=0)
            main.close()

            with self.assertRaisesRegex(RegressionError, "closed by its own attempt"):
                append(
                    directory,
                    EventType.VERDICT_RECORDED,
                    forged_verdict(
                        GATE,
                        NodeStatus.BLOCKED_BY,
                        lease_id=lease.id,
                        ancestors=(NodeID("node:phantom"),),
                    ),
                    "verdict:forged",
                )

    def test_a_deferred_verdict_on_an_unclaimed_node_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            open_run(_single_node_plan(), directory).close()

            with self.assertRaisesRegex(RegressionError, "derives nothing"):
                append(
                    directory,
                    EventType.VERDICT_RECORDED,
                    forged_verdict(GATE, NodeStatus.DEFERRED_HUMAN),
                    "verdict:forged",
                )

    def test_a_join_passed_ahead_of_its_predecessors_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            open_run(_join_follower_plan(), directory).close()

            with self.assertRaisesRegex(RegressionError, "derives nothing"):
                append(
                    directory,
                    EventType.VERDICT_RECORDED,
                    forged_verdict(NodeID("node:join"), NodeStatus.PASSED),
                    "verdict:forged",
                )

    def test_the_blocked_by_the_run_derives_replays(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_both_lane_plan(), directory)
            gate = run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            main.close()
            ledger_tool.write(directory, verdict(gate.node_id), NodeStatus.FAILED)
            current = replay(directory)
            self.assertIs(NodeStatus.PENDING, current.node(FOLLOWER).status)

            append(
                directory,
                EventType.VERDICT_RECORDED,
                forged_verdict(FOLLOWER, NodeStatus.BLOCKED_BY, ancestors=(GATE,)),
                "verdict:derived",
            )

            self.assertIs(NodeStatus.BLOCKED_BY, replay(directory).node(FOLLOWER).status)


class KnownDefectExemptionTests(unittest.TestCase):
    """The record an exemption names is checked against the run: the Scenario
    the plan gave the node and the field the last call recorded. A row that
    names another Scenario, another comparison or a reading the call did not
    make fails replay, however well formed it is."""

    def violated_run(self, directory: Path, outputs: dict):
        main = open_run(_single_node_plan(), directory)
        lease = main.claim(BoundLane.SIMULATOR, SidekickID("sidekick:one"), now_millis=0)
        _invoke_current(
            main, lease, FakeOperationAdapter([OperationResult(True, (), "", outputs)])
        )
        main.accept_evidence(_envelope(main, lease), FakeOracle(OracleResult.VIOLATED))
        main.close()
        return lease

    def exemption(self, directory: Path, lease, scenario: str, match) -> None:
        append(
            directory,
            EventType.VERDICT_RECORDED,
            forged_verdict(
                GATE,
                NodeStatus.FAILED_KNOWN,
                lease_id=lease.id,
                adjudication=adjudication(
                    signature=str(ALL_BLACK) if isinstance(match, str) else None,
                    knownDefect={"scenario": scenario, "match": match},
                ),
            ),
            "verdict:forged",
        )

    def test_an_exemption_for_another_scenario_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.violated_run(directory, {"lifecycle": "Paused"})

            with self.assertRaisesRegex(RegressionError, "exempts scenario:other"):
                self.exemption(directory, lease, "scenario:other", str(ALL_BLACK))

    def test_a_field_exemption_the_call_did_not_record_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.violated_run(directory, {"lifecycle": "Playing"})

            with self.assertRaisesRegex(RegressionError, "did not record lifecycle"):
                self.exemption(
                    directory,
                    lease,
                    "scenario:gate",
                    {"field": "lifecycle", "operator": "==", "value": "Paused"},
                )

    def test_a_field_exemption_with_another_comparison_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.violated_run(directory, {"lifecycle": "Playing"})

            with self.assertRaisesRegex(RegressionError, "with ==, not '!='"):
                self.exemption(
                    directory,
                    lease,
                    "scenario:gate",
                    {"field": "lifecycle", "operator": "!=", "value": "Paused"},
                )

    def test_a_boolean_reading_does_not_match_an_integer(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.violated_run(directory, {"retries": True})

            with self.assertRaisesRegex(RegressionError, "did not record retries"):
                self.exemption(
                    directory,
                    lease,
                    "scenario:gate",
                    {"field": "retries", "operator": "==", "value": 1},
                )

    def test_a_field_exemption_the_call_recorded_replays(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.violated_run(directory, {"lifecycle": "Paused"})

            self.exemption(
                directory,
                lease,
                "scenario:gate",
                {"field": "lifecycle", "operator": "==", "value": "Paused"},
            )

            node = replay(directory).node(GATE)
            self.assertIs(NodeStatus.FAILED_KNOWN, node.status)
            self.assertEqual("scenario:gate", node.adjudication.known_defect["scenario"])


class ReopenReplayTests(unittest.TestCase):
    """Every reason the ledger tool refuses a reopen is a reason the replay
    refuses the row. Each refusal here is appended directly, so the tool's
    check cannot stand in for the replay's."""

    def indeterminate_run(self, directory: Path, attribution=Attribution.HARNESS):
        main = open_run(_single_node_plan(), directory)
        lease = run_node(main, BoundLane.SIMULATOR, OracleResult.INDETERMINATE, "amber")
        main.close()
        ledger_tool.write(
            directory, verdict(lease.node_id, attribution=attribution), NodeStatus.INDETERMINATE
        )
        return lease

    def reopen(self, directory: Path, node: NodeID = GATE, attempts_before=1) -> None:
        append(
            directory,
            EventType.NODE_REOPENED,
            {"nodeId": str(node), "attemptsBefore": attempts_before},
            "reopen:forged",
        )

    def test_a_boolean_attempt_count_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.indeterminate_run(directory)

            with self.assertRaisesRegex(RegressionError, "attemptsBefore"):
                self.reopen(directory, attempts_before=True)

    def test_a_third_attempt_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.indeterminate_run(directory)
            ledger_tool.reopen(directory, GATE)
            main = open_run(_single_node_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.INDETERMINATE, "amber2")
            main.close()
            ledger_tool.write(directory, verdict(GATE, attribution=Attribution.HARNESS), NodeStatus.INDETERMINATE)

            with self.assertRaisesRegex(RegressionError, "already ran 2 of 2"):
                self.reopen(directory, attempts_before=2)

    def test_a_product_attribution_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.indeterminate_run(directory, attribution=Attribution.PRODUCT)

            with self.assertRaisesRegex(RegressionError, "product is a conclusion"):
                self.reopen(directory)

    def test_a_failed_node_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            main.close()
            ledger_tool.write(directory, verdict(lease.node_id), NodeStatus.FAILED)

            with self.assertRaisesRegex(RegressionError, "reopened out of"):
                self.reopen(directory)

    def test_a_reopen_onto_interrupted_lanes_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.indeterminate_run(directory)
            main = open_run(_single_node_plan(), directory)
            main.interrupt_lane(BoundLane.SIMULATOR, "device fault", None)
            main.close()

            with self.assertRaisesRegex(RegressionError, "is interrupted"):
                self.reopen(directory)

    def test_a_node_the_run_does_not_hold_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.indeterminate_run(directory)

            with self.assertRaisesRegex(RegressionError, "does not hold"):
                self.reopen(directory, node=NodeID("node:absent"), attempts_before=0)

    def test_a_reopened_node_carries_no_lane(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.indeterminate_run(directory)
            ledger_tool.reopen(directory, GATE)

            node = replay(directory).node(GATE)
            self.assertIs(NodeStatus.PENDING, node.status)
            self.assertIsNone(node.lane)

    def test_finalize_interrupts_the_attempt_the_node_holds(self) -> None:
        """Lease ids sort in an order unrelated to claim order, so a sweep that
        picks a lease by its node about half the time picked the stopped first
        attempt. Six runs make the coin toss decide the test."""
        for trial in range(6):
            with self.subTest(trial=trial), TemporaryDirectory() as temporary:
                directory = Path(temporary)
                self.indeterminate_run(directory)
                ledger_tool.reopen(directory, GATE)
                main = open_run(_single_node_plan(), directory)
                second = main.claim(BoundLane.SIMULATOR, SidekickID("sidekick:two"), now_millis=0)
                closed = main.finalize()

                interruptions = [
                    payload_value(event.payload)
                    for event in closed.events
                    if event.type is EventType.LANE_INTERRUPTED
                ]
                self.assertEqual([str(second.id)], [item["leaseId"] for item in interruptions])


class InstrumentFaultTests(unittest.TestCase):
    """An attempt that ends on an instrument fault is a non-satisfied attempt:
    the node stays leased and the lane stays locked until the ledger receives
    the verdict, exactly as a violated Oracle result holds it. The verdict is
    attributed to the harness because the fault was the instrument's, and the
    node can then be reopened for its second attempt."""

    def faulted_attempt(self, directory: Path, kind: str = "transport-timeout"):
        main = open_run(_single_node_plan(), directory)
        lease = main.claim(BoundLane.SIMULATOR, SidekickID("sidekick:one"), now_millis=0)
        _invoke_current(main, lease, FakeOperationAdapter([failed_call(kind)]))
        current = main.view
        main.close()
        return lease, current

    def test_an_instrument_fault_holds_the_node_for_adjudication(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease, current = self.faulted_attempt(directory)

            self.assertIs(NodeStatus.LEASED, current.node(GATE).status)
            self.assertFalse(current.lane(BoundLane.SIMULATOR).interrupted)
            lock = lane_lock_state(current, BoundLane.SIMULATOR)
            self.assertIs(LaneLockState.AWAITING_VERDICT, lock.state)
            self.assertEqual(GATE, lock.pending_node)

            with self.assertRaisesRegex(LedgerLockError, "instrument fault"):
                admit_verdict(current, verdict(GATE), NodeStatus.FAILED, 0)
            with self.assertRaisesRegex(LedgerLockError, "attributed to the harness"):
                admit_verdict(
                    current,
                    verdict(GATE, first_deviant_frame=None, attribution=Attribution.PRODUCT),
                    NodeStatus.INDETERMINATE,
                    0,
                )

    def test_a_harness_verdict_closes_the_attempt_and_the_node_reopens(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease, _ = self.faulted_attempt(directory)

            ledger_tool.write(
                directory,
                verdict(GATE, first_deviant_frame=None, attribution=Attribution.HARNESS),
                NodeStatus.INDETERMINATE,
            )
            adjudicated = replay(directory)
            self.assertIs(NodeStatus.INDETERMINATE, adjudicated.node(GATE).status)
            self.assertIs(Attribution.HARNESS, adjudicated.node(GATE).adjudication.attribution)
            self.assertFalse(lane_lock_state(adjudicated, BoundLane.SIMULATOR).locked)

            ledger_tool.reopen(directory, GATE)
            main = open_run(_single_node_plan(), directory)
            second = main.claim(BoundLane.SIMULATOR, SidekickID("sidekick:two"), now_millis=0)
            main.close()
            self.assertNotEqual(lease.id, second.id)

    def test_a_forged_product_attribution_on_an_instrument_fault_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease, _ = self.faulted_attempt(directory)

            with self.assertRaisesRegex(RegressionError, "attributed to the harness"):
                append(
                    directory,
                    EventType.VERDICT_RECORDED,
                    forged_verdict(
                        GATE,
                        NodeStatus.INDETERMINATE,
                        lease_id=lease.id,
                        adjudication=adjudication(attribution="product"),
                    ),
                    "verdict:forged",
                )

    def test_a_product_fault_still_interrupts_the_lane(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = main.claim(BoundLane.SIMULATOR, SidekickID("sidekick:one"), now_millis=0)
            _invoke_current(
                main, lease, FakeOperationAdapter([failed_call("app-crashed", "product")])
            )
            current = main.view
            main.close()

            self.assertTrue(current.lane(BoundLane.SIMULATOR).interrupted)
            self.assertIs(NodeStatus.INDETERMINATE, current.node(GATE).status)
            self.assertIsNone(current.node(GATE).adjudication)

    def test_a_retried_timeout_does_not_count_as_a_timed_out_attempt(self) -> None:
        plan = _single_node_plan(calls=(_call("gate-evidence", max_invocations=2),))
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for index in range(2):
                if index:
                    ledger_tool.reopen(directory, GATE)
                main = open_run(plan, directory)
                lease = main.claim(
                    BoundLane.SIMULATOR, SidekickID(f"sidekick:{index}"), now_millis=0
                )
                _invoke_current(
                    main, lease, FakeOperationAdapter([failed_call("transport-timeout")])
                )
                _complete_operations(main, lease)
                main.accept_evidence(
                    _envelope(main, lease, path_suffix=str(index)),
                    FakeOracle(OracleResult.INDETERMINATE),
                )
                main.close()
                if index == 0:
                    ledger_tool.write(
                        directory,
                        verdict(GATE, first_deviant_frame=None, attribution=Attribution.HARNESS),
                        NodeStatus.INDETERMINATE,
                    )

            self.assertFalse(deferrable(replay(directory), GATE))
            with self.assertRaisesRegex(LedgerLockError, "human layer"):
                ledger_tool.write(
                    directory,
                    verdict(GATE, first_deviant_frame=None, attribution=Attribution.HARNESS),
                    NodeStatus.DEFERRED_HUMAN,
                )

    def test_two_faulted_attempts_defer_the_node_and_block_its_successors(self) -> None:
        plan = gate_and_follower_plan()
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for index in range(2):
                if index:
                    ledger_tool.reopen(directory, GATE)
                main = open_run(plan, directory)
                lease = main.claim(
                    BoundLane.SIMULATOR, SidekickID(f"sidekick:{index}"), now_millis=0
                )
                _invoke_current(
                    main, lease, FakeOperationAdapter([failed_call("wait-expired")])
                )
                main.close()
                if index == 0:
                    ledger_tool.write(
                        directory,
                        verdict(GATE, first_deviant_frame=None, attribution=Attribution.HARNESS),
                        NodeStatus.INDETERMINATE,
                    )

            ledger_tool.write(
                directory,
                verdict(GATE, first_deviant_frame=None, attribution=Attribution.HARNESS),
                NodeStatus.DEFERRED_HUMAN,
            )
            closed = open_run(plan, directory).finalize()

            self.assertIs(NodeStatus.DEFERRED_HUMAN, closed.node(GATE).status)
            self.assertIs(NodeStatus.BLOCKED_BY, closed.node(FOLLOWER).status)
            self.assertEqual((GATE,), closed.node(FOLLOWER).failure_ancestors)
            self.assertIs(RunOutcome.DEFERRED, closed.outcome)

    def test_the_frame_bound_counts_the_screenshots_of_the_last_two_calls(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            current = main.view
            main.close()

            self.assertEqual(1, montage_frame_bound(current.lease(lease.id)))


if __name__ == "__main__":
    unittest.main()
