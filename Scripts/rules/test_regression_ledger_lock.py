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
from regression.core.ids import NodeID, SidekickID, SignatureID
from regression.core.ledger import LedgerWriter
from regression.core.replay import read_event_log, replay
from regression.core.runtime import open_run
from regression.core.plan import BothJoinNode, LaneGateDependency, MainGateBinding
from regression.core.runview import NodeStatus, build_run_view
from regression.tools.ledger_lock import (
    LOCKED_BY_INTERRUPTION,
    LOCKED_BY_RUN_CLOSURE,
    LOCKED_UNTIL_ADJUDICATED,
    LOCKED_WHILE_UNDETERMINED,
    UNLOCKED,
    LedgerLockError,
    admit_verdict,
    lane_lock_state,
)
from regression.tools import ledger_tool
from regression.tools.verdict import Attribution, Verdict

from test_regression_core_runtime import (
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
        "first_deviant_frame": 3,
        "region_observation": "the poster grid stayed blank",
        "attribution": Attribution.PRODUCT,
        "signature": None,
    }
    fields.update(overrides)
    return Verdict(**fields)


def run_node(main, lane: BoundLane, result: OracleResult, sidekick: str):
    lease = main.claim(lane, SidekickID(f"sidekick:{sidekick}"), now_millis=0)
    _complete_operations(main, lease)
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
                directory, verdict(lease.node_id), NodeStatus.FAILED, FRAME_COUNT
            )
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

    def test_a_known_defect_without_its_signature_is_refused(self) -> None:
        with self.assertRaisesRegex(LedgerLockError, "names the signature"):
            self.admit(status=NodeStatus.FAILED_KNOWN)
        self.admit(
            status=NodeStatus.FAILED_KNOWN,
            signature=SignatureID("signature:blank-frame"),
        )

    def test_a_status_the_oracle_result_forbids_is_refused(self) -> None:
        for status in (
            NodeStatus.PASSED,
            NodeStatus.INDETERMINATE,
            NodeStatus.DEFERRED_HUMAN,
        ):
            with self.subTest(status=status):
                with self.assertRaisesRegex(LedgerLockError, "was violated"):
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
        with self.assertRaisesRegex(LedgerLockError, "positive integer"):
            self.admit(bundle_frame_count=0)


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
                NodeStatus.FAILED,
                FRAME_COUNT,
            )
            adjudicated = next(
                item
                for item in written["nodes"]
                if item["node"] == str(lease.node_id)
            )
            self.assertEqual("failed", adjudicated["status"])
            self.assertEqual(
                {
                    "attribution": "product",
                    "bundleFrameCount": FRAME_COUNT,
                    "firstDeviantFrame": 3,
                    "regionObservation": "the poster grid stayed blank",
                    "signature": None,
                },
                adjudicated["adjudication"],
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
                directory, verdict(lease.node_id), NodeStatus.FAILED, FRAME_COUNT
            )
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
                directory, verdict(lease.node_id), NodeStatus.FAILED, FRAME_COUNT
            )
            with self.assertRaisesRegex(LedgerLockError, "owes no verdict"):
                ledger_tool.write(
                    directory,
                    verdict(lease.node_id),
                    NodeStatus.FAILED,
                    FRAME_COUNT,
                )

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
                    NodeStatus.FAILED,
                    FRAME_COUNT,
                )
            self.assertEqual(before, (directory / "ledger.jsonl").read_bytes())


if __name__ == "__main__":
    unittest.main()
