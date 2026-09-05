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
from regression.core.ids import NodeID, ScenarioID, SidekickID, SignatureID
from regression.core.ledger import LedgerWriter
from regression.core.replay import read_event_log, replay
from regression.core.runtime import open_run
from regression.core.plan import BothJoinNode, LaneGateDependency, MainGateBinding
from regression.core.runview import (
    MAX_NODE_ATTEMPTS,
    NodeStatus,
    build_run_view,
    nodes_awaiting_adjudication,
)
from regression.tools.ledger_lock import (
    LOCKED_BY_INTERRUPTION,
    STATES_REFUSING_AN_OPERATION,
    LaneLock,
    LaneLockState,
    LOCKED_BY_RUN_CLOSURE,
    LOCKED_UNTIL_ADJUDICATED,
    LOCKED_WHILE_UNDETERMINED,
    UNLOCKED,
    LedgerLockError,
    admit_verdict,
    attempts,
    lane_lock_state,
)
from datetime import date

from regression.rubric_compiler import FieldPredicate
from regression.tools import known_defects, ledger_tool
from regression.tools.signatures import ALL_BLACK
from regression.tools.verdict import Attribution, Verdict

from test_regression_core_runtime import (
    FakeOperationAdapter,
    OperationResult,
    _invoke_current,
    FakeOracle,
    _complete_operations,
    _copy_tree,
    _envelope,
    _half_evaluated_run,
    _node,
    _plan,
    _single_node_plan,
    _two_obligation_plan,
)


FRAME_COUNT = 12


def _both_lane_plan():
    gate = _node("gate", (BoundLane.SIMULATOR,), critical=500)
    red = _node(
        "red",
        (BoundLane.SIMULATOR,),
        predecessors=(gate.id,),
        gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
        critical=400,
    )
    third = _node(
        "third",
        (BoundLane.SIMULATOR,),
        predecessors=(gate.id,),
        gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
        critical=100,
    )
    device = _node("device-gate", (BoundLane.DEVICE,), critical=500)
    return _plan(
        (gate, red, third, device),
        (
            MainGateBinding(BoundLane.SIMULATOR, gate.scenario_id, gate.id),
            MainGateBinding(BoundLane.DEVICE, device.scenario_id, device.id),
        ),
    )


def _join_follower_plan():
    simulator = _node("sim-gate", (BoundLane.SIMULATOR,), critical=500)
    device = _node("device-gate", (BoundLane.DEVICE,), critical=500)
    join = BothJoinNode(
        NodeID("node:join"),
        simulator.scenario_id,
        simulator.journey_id,
        (simulator.id, device.id),
        400,
    )
    follower = _node(
        "follower",
        (BoundLane.SIMULATOR,),
        predecessors=(join.id,),
        gates=(LaneGateDependency(BoundLane.SIMULATOR, simulator.id),),
        critical=100,
    )
    return _plan(
        (simulator, device, join, follower),
        (
            MainGateBinding(BoundLane.SIMULATOR, simulator.scenario_id, simulator.id),
            MainGateBinding(BoundLane.DEVICE, device.scenario_id, device.id),
        ),
    )


def verdict(node: NodeID, **overrides) -> Verdict:
    fields = {
        "node": node,
        "first_deviant_frame": 0,
        "region_observation": "the poster grid stayed blank",
        "attribution": Attribution.PRODUCT,
        "signature": None,
    }
    fields.update(overrides)
    return Verdict(**fields)


def run_node(main, lane: BoundLane, result: OracleResult, sidekick: str):
    lease = main.claim(lane, SidekickID(f"sidekick:{sidekick}"), now_millis=0)
    _complete_operations(main, lease, screenshots=True)
    main.accept_evidence(_envelope(main, lease), FakeOracle(result))
    return lease


class LaneLockTests(unittest.TestCase):
    def test_a_green_step_leaves_its_lane_open(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.SATISFIED, "green")
            lock = lane_lock_state(main.view, BoundLane.SIMULATOR)
            main.close()

            self.assertFalse(lock.locked)
            self.assertIsNone(lock.pending_node)
            self.assertEqual(UNLOCKED, lock.reason)

    def test_a_non_satisfied_step_locks_its_lane_and_names_the_pending_node(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            lock = lane_lock_state(main.view, BoundLane.SIMULATOR)

            self.assertTrue(lock.locked)
            self.assertEqual(lease.node_id, lock.pending_node)
            self.assertEqual(LOCKED_UNTIL_ADJUDICATED, lock.reason)

            with self.assertRaises(RegressionError) as raised:
                main.claim(
                    BoundLane.SIMULATOR, SidekickID("sidekick:next"), now_millis=0
                )
            self.assertEqual("runtime.lane_busy", raised.exception.code)
            main.close()

    def test_writing_the_verdict_unlocks_the_lane_for_the_next_claim(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _both_lane_plan()
            main = open_run(plan, directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.SATISFIED, "gate")
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()

            ledger_tool.write(
                directory, verdict(lease.node_id), NodeStatus.FAILED)
            unlocked = replay(directory)
            lock = lane_lock_state(unlocked, BoundLane.SIMULATOR)

            self.assertFalse(lock.locked)
            self.assertEqual(
                NodeStatus.FAILED, unlocked.node(lease.node_id).status
            )
            reopened = open_run(plan, directory)
            self.assertNotEqual(
                lease.node_id,
                reopened.claim(
                    BoundLane.SIMULATOR, SidekickID("sidekick:next"), now_millis=0
                ).node_id,
            )
            reopened.close()

    def test_one_locked_lane_leaves_the_other_lane_open(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_both_lane_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            device = lane_lock_state(main.view, BoundLane.DEVICE)
            simulator = lane_lock_state(main.view, BoundLane.SIMULATOR)
            main.close()

            self.assertTrue(simulator.locked)
            self.assertFalse(device.locked)

    def test_an_interrupted_lane_reports_its_interruption(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            main.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:red"), now_millis=0
            )
            main.interrupt_lane(BoundLane.SIMULATOR, "device-detached")
            lock = lane_lock_state(main.view, BoundLane.SIMULATOR)
            main.close()

            self.assertTrue(lock.locked)
            self.assertEqual(LOCKED_BY_INTERRUPTION, lock.reason)

    def test_an_interrupted_lane_whose_node_stays_leased_names_the_interruption(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan = _single_node_plan()
            complete = root / "complete"
            main = open_run(plan, complete)
            main.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:red"), now_millis=0
            )
            main.interrupt_lane(BoundLane.SIMULATOR, "device-detached")
            main.close()

            crashed = root / "crashed"
            crashed.mkdir()
            kept = []
            for line in (
                complete / "ledger.jsonl"
            ).read_bytes().splitlines(keepends=True):
                kept.append(line)
                if b'"LaneInterrupted"' in line:
                    break
            (crashed / "ledger.jsonl").write_bytes(b"".join(kept))

            view = replay(crashed)
            self.assertEqual(
                NodeStatus.LEASED, view.node(NodeID("node:gate")).status
            )
            lock = lane_lock_state(view, BoundLane.SIMULATOR)
            self.assertTrue(lock.locked)
            self.assertEqual(LOCKED_BY_INTERRUPTION, lock.reason)

    def test_a_working_lane_is_locked_to_a_claim_but_open_to_its_own_next_call(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            main.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:working"), now_millis=0
            )
            lock = lane_lock_state(main.view, BoundLane.SIMULATOR)
            main.close()

            self.assertIs(LaneLockState.WORKING, lock.state)
            self.assertTrue(lock.locked)
            self.assertFalse(lock.refuses_an_operation)

    def test_every_state_that_refuses_an_operation_is_also_locked(self) -> None:
        for state in STATES_REFUSING_AN_OPERATION:
            with self.subTest(state=state):
                lock = LaneLock(BoundLane.SIMULATOR, state, None, "reason")
                self.assertTrue(lock.locked)
                self.assertTrue(lock.refuses_an_operation)
        open_lane = LaneLock(BoundLane.SIMULATOR, LaneLockState.OPEN, None, UNLOCKED)
        self.assertFalse(open_lane.locked)
        self.assertFalse(open_lane.refuses_an_operation)

    def test_an_undetermined_lease_locks_without_owing_a_verdict(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            crashed, _ = _half_evaluated_run(
                root, _two_obligation_plan(), OracleResult.SATISFIED
            )
            lock = lane_lock_state(replay(crashed), BoundLane.SIMULATOR)

            self.assertTrue(lock.locked)
            self.assertIsNone(lock.pending_node)
            self.assertEqual(LOCKED_WHILE_UNDETERMINED, lock.reason)


class AdmitVerdictTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        main = open_run(_single_node_plan(), self.directory)
        self.lease = run_node(
            main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
        )
        main.close()
        self.view = replay(self.directory)
        self.addCleanup(self.temporary.cleanup)

    def admit(self, **overrides) -> None:
        status = overrides.pop("status", NodeStatus.FAILED)
        frames = overrides.pop("bundle_frame_count", FRAME_COUNT)
        admit_verdict(
            self.view, verdict(self.lease.node_id, **overrides), status, frames
        )

    def test_a_complete_product_verdict_is_admitted(self) -> None:
        self.admit()

    def test_a_frame_beyond_the_montage_is_refused(self) -> None:
        with self.assertRaisesRegex(LedgerLockError, "outside the 12 frames"):
            self.admit(first_deviant_frame=FRAME_COUNT)

    def test_the_last_frame_of_the_montage_is_admitted(self) -> None:
        self.admit(first_deviant_frame=FRAME_COUNT - 1)

    def test_an_empty_region_observation_is_refused(self) -> None:
        with self.assertRaisesRegex(LedgerLockError, "observation is empty"):
            self.admit(region_observation="   ")

    def test_a_known_defect_is_admitted_whether_or_not_it_names_a_signature(
        self,
    ) -> None:
        self.admit(status=NodeStatus.FAILED_KNOWN)
        self.admit(status=NodeStatus.FAILED_KNOWN, signature=ALL_BLACK)

    def test_a_status_the_oracle_result_forbids_is_refused(self) -> None:
        for status in (
            NodeStatus.PASSED,
            NodeStatus.INDETERMINATE,
            NodeStatus.DEFERRED_HUMAN,
        ):
            with self.subTest(status=status):
                with self.assertRaisesRegex(LedgerLockError, "Oracle result violated"):
                    self.admit(status=status)

    def test_a_node_that_owes_nothing_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.SATISFIED, "green"
            )
            current = main.view
            main.close()

            with self.assertRaisesRegex(LedgerLockError, "owes no verdict"):
                admit_verdict(
                    current, verdict(lease.node_id), NodeStatus.FAILED, FRAME_COUNT
                )

    def test_an_unknown_node_and_a_malformed_frame_count_are_refused(self) -> None:
        with self.assertRaisesRegex(LedgerLockError, "holds no node"):
            admit_verdict(
                self.view,
                verdict(NodeID("node:absent")),
                NodeStatus.FAILED,
                FRAME_COUNT,
            )
        with self.assertRaisesRegex(LedgerLockError, "derived from the run"):
            self.admit(bundle_frame_count=-1)


class LedgerToolTests(unittest.TestCase):
    def test_the_view_carries_the_lock_and_the_written_adjudication(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_both_lane_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()

            locked = ledger_tool.view(directory, BoundLane.SIMULATOR)
            self.assertEqual(1, len(locked["locks"]))
            self.assertTrue(locked["locks"][0]["locked"])
            self.assertEqual(
                str(lease.node_id), locked["locks"][0]["pendingNode"]
            )

            written = ledger_tool.write(
                directory,
                verdict(lease.node_id),
                NodeStatus.FAILED)
            adjudicated = next(
                item
                for item in written["nodes"]
                if item["node"] == str(lease.node_id)
            )
            self.assertEqual("failed", adjudicated["status"])
            self.assertEqual(
                {
                    "attribution": "product",
                    "bundleFrameCount": 1,
                    "firstDeviantFrame": 0,
                    "regionObservation": "the poster grid stayed blank",
                    "signature": None,
                },
                adjudicated["adjudication"],
            )

    def test_a_frame_the_run_captured_no_image_for_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()

            with self.assertRaisesRegex(LedgerLockError, "outside the 1 frames"):
                ledger_tool.write(
                    directory,
                    verdict(lease.node_id, first_deviant_frame=1),
                    NodeStatus.FAILED,
                )

    def test_resume_withholds_a_sibling_on_the_locked_lane(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_both_lane_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.SATISFIED, "gate")
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()

            locked = ledger_tool.resume(directory)
            self.assertEqual([str(lease.node_id)], locked["awaitingVerdict"])
            self.assertNotIn("node:third", locked["ready"])
            self.assertIn("node:device-gate", locked["ready"])

            ledger_tool.write(
                directory, verdict(lease.node_id), NodeStatus.FAILED)
            released = ledger_tool.resume(directory)
            self.assertEqual([], released["awaitingVerdict"])
            self.assertIn("node:third", released["ready"])

    def test_resume_lists_a_node_the_next_claim_settles_into_reach(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan = _join_follower_plan()
            complete = root / "complete"
            main = open_run(plan, complete)
            run_node(main, BoundLane.SIMULATOR, OracleResult.SATISFIED, "sim")
            run_node(main, BoundLane.DEVICE, OracleResult.SATISFIED, "device")
            main.close()

            crashed = root / "crashed"
            crashed.mkdir()
            lines = (complete / "ledger.jsonl").read_bytes().splitlines(keepends=True)
            (crashed / "ledger.jsonl").write_bytes(b"".join(lines[:-1]))
            for item in complete.iterdir():
                if item.name not in ("ledger.jsonl", "ledger.lock"):
                    _copy_tree(item, crashed / item.name)

            self.assertEqual(
                NodeStatus.PENDING, replay(crashed).node(NodeID("node:join")).status
            )
            self.assertIn("node:follower", ledger_tool.resume(crashed)["ready"])

            reopened = open_run(plan, crashed)
            claimed = reopened.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:next"), now_millis=0
            )
            reopened.close()
            self.assertEqual(NodeID("node:follower"), claimed.node_id)

    def test_a_closed_run_reports_every_lane_shut(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.SATISFIED, "green")
            main.finalize()

            closed = replay(directory)
            lock = lane_lock_state(closed, BoundLane.SIMULATOR)
            self.assertTrue(lock.locked)
            self.assertEqual(LOCKED_BY_RUN_CLOSURE, lock.reason)
            self.assertTrue(
                ledger_tool.view(directory)["locks"][0]["locked"]
            )

    def test_a_second_verdict_on_the_same_node_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()

            ledger_tool.write(
                directory, verdict(lease.node_id), NodeStatus.FAILED)
            with self.assertRaisesRegex(LedgerLockError, "owes no verdict"):
                ledger_tool.write(
                    directory,
                    verdict(lease.node_id),
                    NodeStatus.FAILED)

    def test_a_forged_claim_on_a_locked_lane_does_not_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_both_lane_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            main.close()

            log = read_event_log(directory)
            claim = next(
                event for event in log.events if event.type is EventType.NODE_CLAIMED
            )
            forged = dict(payload_value(claim.payload))
            forged["nodeId"] = "node:red"
            forged["leaseId"] = "lease:forged-01"
            before = (directory / "ledger.jsonl").read_bytes()

            with LedgerWriter(
                directory, log.run_id, log.plan_digest, build_run_view
            ) as writer:
                with self.assertRaisesRegex(
                    RegressionError, "lane cannot accept this claim"
                ):
                    writer.append(
                        EventType.NODE_CLAIMED,
                        forged,
                        "2026-09-04T00:00:00.000Z",
                        "claim:lease:forged-01",
                    )
            self.assertEqual(before, (directory / "ledger.jsonl").read_bytes())

    def test_a_refused_verdict_leaves_the_ledger_byte_identical(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()
            before = (directory / "ledger.jsonl").read_bytes()

            with self.assertRaises(LedgerLockError):
                ledger_tool.write(
                    directory,
                    verdict(lease.node_id, first_deviant_frame=FRAME_COUNT),
                    NodeStatus.FAILED)
            self.assertEqual(before, (directory / "ledger.jsonl").read_bytes())


class ReopenTests(unittest.TestCase):
    """A node was claimed once and never returned to pending, so a second attempt
    could not exist and the human layer's entry condition -- two consecutive
    harness timeouts on one node -- could never be met. Reopening is its own
    fact in the ledger, admitted only out of an indeterminate node whose
    adjudication blamed the harness."""

    def indeterminate_run(self, directory: Path):
        main = open_run(_single_node_plan(), directory)
        lease = run_node(
            main, BoundLane.SIMULATOR, OracleResult.INDETERMINATE, "amber"
        )
        main.close()
        ledger_tool.write(
            directory,
            verdict(lease.node_id, attribution=Attribution.HARNESS),
            NodeStatus.INDETERMINATE)
        return lease

    def test_a_harness_indeterminate_node_returns_to_pending(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.indeterminate_run(directory)

            ledger_tool.reopen(directory, lease.node_id)
            reopened = replay(directory)
            node = reopened.node(lease.node_id)

            self.assertIs(NodeStatus.PENDING, node.status)
            self.assertIsNone(node.lease_id)
            self.assertIs(Attribution.HARNESS, node.adjudication.attribution)
            self.assertFalse(lane_lock_state(reopened, BoundLane.SIMULATOR).locked)

    def test_the_earlier_attempt_stays_in_the_ledger(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.indeterminate_run(directory)

            ledger_tool.reopen(directory, lease.node_id)
            reopened = replay(directory)

            self.assertEqual(1, attempts(reopened, lease.node_id))
            self.assertTrue(reopened.lease(lease.id).invocations)

    def test_a_reopened_node_can_be_claimed_again(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.indeterminate_run(directory)
            ledger_tool.reopen(directory, lease.node_id)

            main = open_run(_single_node_plan(), directory)
            second = run_node(
                main, BoundLane.SIMULATOR, OracleResult.SATISFIED, "green"
            )
            current = main.view
            main.close()

            self.assertNotEqual(lease.id, second.id)
            self.assertEqual(2, attempts(current, lease.node_id))

    def test_a_third_attempt_is_refused_by_the_cap(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.indeterminate_run(directory)
            ledger_tool.reopen(directory, lease.node_id)
            main = open_run(_single_node_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.INDETERMINATE, "amber2")
            main.close()
            ledger_tool.write(
                directory,
                verdict(lease.node_id, attribution=Attribution.HARNESS),
                NodeStatus.INDETERMINATE)

            with self.assertRaisesRegex(LedgerLockError, f"of {MAX_NODE_ATTEMPTS}"):
                ledger_tool.reopen(directory, lease.node_id)

    def test_a_later_session_does_not_recover_the_stopped_first_attempt(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.indeterminate_run(directory)
            ledger_tool.reopen(directory, lease.node_id)
            main = open_run(_single_node_plan(), directory)
            second = main.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:green"), now_millis=0
            )
            main.close()

            reopened = open_run(_single_node_plan(), directory)
            current = reopened.view
            reopened.close()

            self.assertFalse(current.lane(BoundLane.SIMULATOR).interrupted)
            self.assertEqual(
                second.id, current.node(lease.node_id).lease_id
            )
            self.assertFalse(
                lane_lock_state(current, BoundLane.SIMULATOR).refuses_an_operation
            )

    def test_the_second_attempt_is_adjudicated_against_its_own_evaluations(
        self,
    ) -> None:
        """Lease identifiers are digest prefixes, so the run's leases sort in an
        order unrelated to the order they were claimed in. Picking "the lease of
        this node" by node id therefore reads the stopped attempt about half the
        time. Ten runs make that coin toss decide the test."""
        for trial in range(10):
            with self.subTest(trial=trial), TemporaryDirectory() as temporary:
                directory = Path(temporary)
                lease = self.indeterminate_run(directory)
                ledger_tool.reopen(directory, lease.node_id)
                main = open_run(_single_node_plan(), directory)
                run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
                main.close()

                ledger_tool.write(
                    directory, verdict(lease.node_id), NodeStatus.FAILED)

                self.assertIs(
                    NodeStatus.FAILED, replay(directory).node(lease.node_id).status
                )

    def test_a_reopen_onto_interrupted_lanes_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.indeterminate_run(directory)
            main = open_run(_single_node_plan(), directory)
            main.interrupt_lane(BoundLane.SIMULATOR, "device fault", None)
            main.close()

            with self.assertRaisesRegex(LedgerLockError, "is interrupted"):
                ledger_tool.reopen(directory, lease.node_id)

    def test_a_reopen_that_misreports_the_attempt_count_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.indeterminate_run(directory)
            log = read_event_log(directory)
            with LedgerWriter(
                directory, log.run_id, log.plan_digest, build_run_view
            ) as writer:
                with self.assertRaises(RegressionError):
                    writer.append(
                        EventType.NODE_REOPENED,
                        {"nodeId": str(lease.node_id), "attemptsBefore": 0},
                        "2026-09-05T00:00:00.000Z",
                        "reopen:forged",
                    )

    def test_a_product_attribution_does_not_reopen(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.INDETERMINATE, "amber"
            )
            main.close()
            ledger_tool.write(
                directory,
                verdict(lease.node_id, attribution=Attribution.PRODUCT),
                NodeStatus.INDETERMINATE)

            with self.assertRaisesRegex(LedgerLockError, "product is a conclusion"):
                ledger_tool.reopen(directory, lease.node_id)

    def test_a_failed_node_does_not_reopen(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            main.close()
            ledger_tool.write(
                directory, verdict(lease.node_id), NodeStatus.FAILED)

            with self.assertRaisesRegex(LedgerLockError, "reopened out of"):
                ledger_tool.reopen(directory, lease.node_id)

    def test_a_node_the_run_does_not_hold_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.indeterminate_run(directory)

            with self.assertRaisesRegex(LedgerLockError, "does not hold"):
                ledger_tool.reopen(directory, NodeID("node:absent"))


class KnownDefectRoutingTests(unittest.TestCase):
    """A failure that matches the known-defect ledger is written as a different
    terminal state, not as the same state with a note beside it. Every input the
    match reads is taken from the run itself: the Scenario from the plan the run
    pinned, the field readings from what the Operation recorded."""

    def failed_run(self, directory: Path, outputs=None):
        main = open_run(_single_node_plan(), directory)
        lease = main.claim(BoundLane.SIMULATOR, SidekickID("sidekick:red"), now_millis=0)
        while True:
            call = main.view.lease(lease.id).current_call
            if call is None:
                break
            _invoke_current(
                main,
                lease,
                FakeOperationAdapter(
                    [OperationResult(True, (), "", dict(outputs or {}))]
                ),
            )
        main.accept_evidence(_envelope(main, lease), FakeOracle(OracleResult.VIOLATED))
        main.close()
        return lease

    def with_defects(self, *records):
        original = known_defects.load
        known_defects.load = lambda path=None: records
        self.addCleanup(setattr, known_defects, "load", original)

    def defect(self, scenario, match):
        return known_defects.KnownDefect(
            ScenarioID(scenario),
            "the poster grid renders one frame late",
            match,
            date(2026, 9, 1),
            "the grid stops rendering before its first layout pass",
        )

    def test_a_matching_record_is_written_as_its_own_terminal_state(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory)
            self.with_defects(self.defect("scenario:gate", ALL_BLACK))

            ledger_tool.write(
                directory,
                verdict(lease.node_id, signature=ALL_BLACK, first_deviant_frame=None),
                NodeStatus.FAILED)

            self.assertIs(
                NodeStatus.FAILED_KNOWN, replay(directory).node(lease.node_id).status
            )

    def test_a_field_matched_exemption_closes_and_records_what_matched(
        self,
    ) -> None:
        from regression.rubric_compiler import FieldPredicate

        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            lease = run_node(
                main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red"
            )
            main.close()
            fields = ledger_tool.recorded_fields(replay(directory), lease.node_id)
            field, value = next(iter(fields.items()))
            self.with_defects(
                self.defect(
                    ledger_tool.scenario_of(directory, lease.node_id),
                    FieldPredicate(field, "==", value),
                )
            )

            written = ledger_tool.write(
                directory,
                verdict(lease.node_id, first_deviant_frame=None, signature=None),
                NodeStatus.FAILED,
            )

            node = written["nodes"][0]
            self.assertEqual("failed(known)", node["status"])
            self.assertEqual(
                {"field": field, "operator": "==", "value": value},
                node["adjudication"]["knownDefect"]["match"],
            )
            self.assertEqual(
                NodeStatus.FAILED_KNOWN, replay(directory).node(lease.node_id).status
            )

    def test_a_record_for_another_scenario_does_not_reach_this_node(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory)
            self.with_defects(self.defect("scenario:elsewhere", ALL_BLACK))

            ledger_tool.write(
                directory,
                verdict(lease.node_id, signature=ALL_BLACK, first_deviant_frame=None),
                NodeStatus.FAILED)

            self.assertIs(
                NodeStatus.FAILED, replay(directory).node(lease.node_id).status
            )

    def test_the_scenario_comes_from_the_plan_the_run_pinned(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory)

            self.assertEqual(
                "scenario:gate", str(ledger_tool.scenario_of(directory, lease.node_id))
            )
            self.assertIsNone(
                ledger_tool.scenario_of(directory, NodeID("node:absent"))
            )

    def test_the_field_readings_come_from_the_recorded_outputs(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory, {"lifecycle": "Paused"})
            current = replay(directory)

            recorded = ledger_tool.recorded_fields(current, lease.node_id)

            self.assertEqual({"lifecycle": "Paused"}, dict(recorded))
            self.assertEqual(
                {}, ledger_tool.recorded_fields(current, NodeID("node:absent"))
            )

    def test_a_field_match_reads_the_recorded_output(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory, {"lifecycle": "Paused"})
            self.with_defects(
                self.defect(
                    "scenario:gate", FieldPredicate("lifecycle", "==", "Paused")
                )
            )

            ledger_tool.write(
                directory,
                verdict(lease.node_id, signature=ALL_BLACK, first_deviant_frame=None),
                NodeStatus.FAILED)

            self.assertIs(
                NodeStatus.FAILED_KNOWN, replay(directory).node(lease.node_id).status
            )

    def test_a_caller_cannot_ask_for_the_known_failure_state(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory)
            self.with_defects()

            with self.assertRaisesRegex(LedgerLockError, "derived from the known"):
                ledger_tool.write(
                    directory,
                    verdict(lease.node_id, signature=ALL_BLACK, first_deviant_frame=None),
                    NodeStatus.FAILED_KNOWN)

            self.assertIs(
                NodeStatus.LEASED, replay(directory).node(lease.node_id).status
            )

    def test_a_run_whose_only_failure_is_known_closes_as_passed(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory)
            self.with_defects(self.defect("scenario:gate", ALL_BLACK))
            ledger_tool.write(
                directory,
                verdict(lease.node_id, signature=ALL_BLACK, first_deviant_frame=None),
                NodeStatus.FAILED)

            main = open_run(_single_node_plan(), directory)
            closed = main.finalize()
            main.close()

            self.assertIs(
                NodeStatus.FAILED_KNOWN, closed.node(lease.node_id).status
            )
            self.assertEqual("passed", closed.outcome.value)

    def test_a_known_failure_leaves_its_lane_open(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            lease = self.failed_run(directory)
            self.with_defects(self.defect("scenario:gate", ALL_BLACK))

            ledger_tool.write(
                directory,
                verdict(lease.node_id, signature=ALL_BLACK, first_deviant_frame=None),
                NodeStatus.FAILED)
            current = replay(directory)

            self.assertFalse(lane_lock_state(current, BoundLane.SIMULATOR).locked)
            self.assertEqual((), nodes_awaiting_adjudication(current))


if __name__ == "__main__":
    unittest.main()
