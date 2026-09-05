#!/usr/bin/env python3

from __future__ import annotations

import json
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
from regression.core.events import EventType
from regression.core.ledger import LedgerWriter
from regression.core.replay import read_event_log, replay
from regression.core.runview import build_run_view
from regression.core.expression import OracleResult
from regression.core.ids import NodeID, SidekickID
from regression.core.runtime import OperationResult, open_run
from regression.core.runview import (
    HARNESS_TIMEOUT_KINDS,
    MAX_NODE_ATTEMPTS,
    NodeStatus,
    deferrable_from,
)
from regression.tools import ledger_tool, session_tool
from regression.tools.ledger_lock import LedgerLockError, deferrable, verdict_payload
from regression.tools.session_tool import (
    MARK_KIND,
    SNAPSHOT_KIND,
    SessionToolError,
    TimelineEntry,
    append_entry,
    mark,
    poll_timeline,
    read_timeline,
    timeline_path,
)
from regression.tools.verdict import Attribution, Verdict

from test_regression_core_runtime import (
    FakeOperationAdapter,
    FakeOracle,
    _complete_operations,
    _envelope,
    _invoke_current,
    _single_node_plan,
)

if str(SCRIPTS / "verification") not in sys.path:
    sys.path.insert(0, str(SCRIPTS / "verification"))

from harness.failures import INSTRUMENT_KINDS

FRAME_COUNT = 0
NODE = NodeID("node:gate")


def verdict(node: NodeID, attribution: Attribution = Attribution.HARNESS) -> Verdict:
    return Verdict(node, None, "the session never answered", attribution, None)


def failed_call(failure: dict) -> OperationResult:
    return OperationResult(False, (), "", {"failure": failure})


class TimelineTests(unittest.TestCase):
    """The wearer's session leaves one file the Agent can align its frames
    against. Every line is a reading with the time it was taken, so a mark the
    wearer left lands between the readings that bracket it."""

    def scratch(self) -> Path:
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        return timeline_path(Path(directory.name))

    def test_every_line_is_one_json_object(self) -> None:
        path = self.scratch()
        stamps = iter(["2026-09-05T00:00:0{}.000Z".format(index) for index in range(4)])

        poll_timeline(
            path,
            lambda: {"lifecycle": "Playing"},
            lambda written: written >= 3,
            clock=lambda: next(stamps),
            sleep=lambda seconds: None,
        )

        lines = Path(path).read_text(encoding="utf-8").splitlines()
        self.assertEqual(3, len(lines))
        for line in lines:
            self.assertEqual(SNAPSHOT_KIND, json.loads(line)["kind"])

    def test_a_clock_that_steps_back_is_refused(self) -> None:
        """The timeline's order is a property the writer enforces, not one the
        clock is trusted to keep: a reading stamped before the last line is
        refused, and the file holds only what was in order."""
        path = self.scratch()
        stamps = iter(
            [
                "2026-09-05T00:00:05.000Z",
                "2026-09-05T00:00:06.000Z",
                "2026-09-05T00:00:01.000Z",
            ]
        )
        poll_timeline(
            path,
            lambda: {"lifecycle": "Playing"},
            lambda written: written >= 2,
            clock=lambda: next(stamps),
            sleep=lambda seconds: None,
        )

        with self.assertRaisesRegex(SessionToolError, "falls before"):
            mark(path, "the poster grid flickered", clock=lambda: next(stamps))

        recorded = [item["recordedAt"] for item in read_timeline(path)]
        self.assertEqual(
            ["2026-09-05T00:00:05.000Z", "2026-09-05T00:00:06.000Z"], recorded
        )

    def test_a_line_that_is_not_a_timeline_entry_is_refused(self) -> None:
        path = self.scratch()
        mark(path, "the poster grid flickered", clock=lambda: "2026-09-05T00:00:01.000Z")
        with Path(path).open("a", encoding="utf-8") as sink:
            sink.write("not json\n")

        with self.assertRaisesRegex(SessionToolError, "line 2 is not one JSON object"):
            read_timeline(path)

    def test_a_mark_lands_after_the_readings_that_precede_it(self) -> None:
        path = self.scratch()
        stamps = iter(["2026-09-05T00:00:0{}.000Z".format(index) for index in range(6)])
        poll_timeline(
            path,
            lambda: {"lifecycle": "Playing"},
            lambda written: written >= 2,
            clock=lambda: next(stamps),
            sleep=lambda seconds: None,
        )

        mark(path, "the poster grid flickered", clock=lambda: next(stamps))

        entries = read_timeline(path)
        self.assertEqual(MARK_KIND, entries[-1]["kind"])
        self.assertEqual(
            "the poster grid flickered", entries[-1]["reading"]["note"]
        )
        self.assertEqual(2, sum(1 for item in entries if item["kind"] == SNAPSHOT_KIND))

    def test_an_empty_mark_is_refused(self) -> None:
        path = self.scratch()

        with self.assertRaisesRegex(SessionToolError, "what the wearer saw"):
            mark(path, "   ")

    def test_a_timeline_that_was_never_written_reads_as_empty(self) -> None:
        self.assertEqual((), read_timeline(self.scratch()))

    def test_an_entry_keeps_the_reading_it_was_given(self) -> None:
        path = self.scratch()

        append_entry(
            path,
            TimelineEntry("2026-09-05T00:00:00.000Z", SNAPSHOT_KIND, {"controls": "shown"}),
        )

        self.assertEqual(
            {"controls": "shown"}, read_timeline(path)[0]["reading"]
        )


class DeferrableTests(unittest.TestCase):
    """The human layer takes a node only when the harness, not the product, kept
    it from being decided. Two consecutive attempts that both timed out on the
    instrument is the condition; a product failure at either attempt is a
    conclusion and stays one."""

    def timed_out_run(
        self,
        directory: Path,
        kinds,
        adjudicate_last: bool = True,
        product_last: bool = False,
    ):
        """Each attempt ends the way op_tool records an instrument fault: the
        call fails and its outputs carry the failure. A None kind is an attempt
        that ran clean and left an INDETERMINATE Oracle result instead."""
        leases = []
        for index, kind in enumerate(kinds):
            if index:
                ledger_tool.reopen(directory, NODE)
            main = open_run(_single_node_plan(), directory)
            lease = main.claim(
                BoundLane.SIMULATOR, SidekickID(f"sidekick:one{index}"), now_millis=0
            )
            leases.append(lease)
            failure_class = (
                "product" if product_last and index + 1 == len(kinds) else "instrument"
            )
            if kind is None:
                _complete_operations(main, lease)
                main.accept_evidence(
                    _envelope(main, lease, path_suffix=str(index)),
                    FakeOracle(OracleResult.INDETERMINATE),
                )
            else:
                _invoke_current(
                    main,
                    lease,
                    FakeOperationAdapter(
                        [failed_call({"class": failure_class, "kind": kind})]
                    ),
                )
            main.close()
            owed = failure_class == "instrument" or kind is None
            if owed and (adjudicate_last or index + 1 < len(kinds)):
                ledger_tool.write(directory, verdict(NODE), NodeStatus.INDETERMINATE)
            main = open_run(_single_node_plan(), directory)
            main.close()
        return leases

    def test_an_instrument_failure_that_is_not_a_timeout_does_not_defer(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(directory, ("transport-timeout", "runner-crashed"))

            self.assertFalse(deferrable(replay(directory), NODE))

    def test_a_product_failure_does_not_defer(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(
                directory, ("transport-timeout", "transport-timeout"), product_last=True
            )

            self.assertFalse(deferrable(replay(directory), NODE))

    def test_a_forged_deferred_verdict_fails_replay(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(
                directory, ("transport-timeout", None), adjudicate_last=False
            )
            current = replay(directory)
            node = current.node(NODE)
            log = read_event_log(directory)
            with LedgerWriter(
                directory, log.run_id, log.plan_digest, build_run_view
            ) as writer:
                with self.assertRaises(RegressionError):
                    writer.append(
                        EventType.VERDICT_RECORDED,
                        verdict_payload(
                            str(node.lease_id),
                            verdict(NODE),
                            NodeStatus.DEFERRED_HUMAN,
                            FRAME_COUNT,
                        ),
                        "2026-09-05T00:00:00.000Z",
                        "verdict:forged",
                    )

    def test_two_harness_timeouts_make_a_node_deferrable(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(directory, ("transport-timeout", "wait-expired"))

            self.assertTrue(deferrable(replay(directory), NODE))

    def test_one_clean_attempt_is_not_deferrable(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(directory, ("transport-timeout", None))

            self.assertFalse(deferrable(replay(directory), NODE))

    def test_a_single_attempt_is_not_deferrable(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(directory, ("transport-timeout",))

            self.assertFalse(deferrable(replay(directory), NODE))

    def test_the_human_layer_takes_only_instrument_timeouts(self) -> None:
        """The kinds that reach the human layer are a subset of the kinds the
        harness itself classifies as instrument faults, so a kind renamed on
        one side turns this red rather than widening or narrowing the gate."""
        self.assertLessEqual(HARNESS_TIMEOUT_KINDS, INSTRUMENT_KINDS)
        self.assertNotIn("assertion-mismatch", HARNESS_TIMEOUT_KINDS)
        self.assertNotIn("app-crashed", HARNESS_TIMEOUT_KINDS)
        for kind in ("transport-timeout", "response-timeout"):
            with self.subTest(kind=kind):
                self.assertIn(kind, HARNESS_TIMEOUT_KINDS)

    def test_a_response_timeout_pair_reaches_the_human_layer(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(directory, ("response-timeout", "response-timeout"))

            self.assertTrue(deferrable(replay(directory), NODE))

    def test_a_node_with_no_lease_is_not_deferrable(self) -> None:
        self.assertFalse(deferrable_from(NODE, {}))

    def test_a_clean_second_attempt_cannot_reach_the_human_layer(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(
                directory, ("transport-timeout", None), adjudicate_last=False
            )

            with self.assertRaises(LedgerLockError):
                ledger_tool.write(
                    directory, verdict(NODE), NodeStatus.DEFERRED_HUMAN)

    def test_two_timed_out_attempts_reach_the_human_layer(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.timed_out_run(
                directory,
                ("transport-timeout", "wait-expired"),
                adjudicate_last=False,
            )

            ledger_tool.write(
                directory, verdict(NODE), NodeStatus.DEFERRED_HUMAN)

            self.assertIs(
                NodeStatus.DEFERRED_HUMAN, replay(directory).node(NODE).status
            )


class ForwardShapeTests(unittest.TestCase):
    """A controller that fell over refuses the way every other tool refuses. An
    Agent reading the reply overnight reads one shape, not three."""

    def test_a_controller_failure_refuses_rather_than_returning_a_payload(
        self,
    ) -> None:
        import regression.tools.session_tool as tool

        original = tool.ensure_session
        tool.ensure_session = lambda arguments: (_ for _ in ()).throw(
            RuntimeError("the simulator is not booted")
        )
        self.addCleanup(setattr, tool, "ensure_session", original)

        with self.assertRaisesRegex(SessionToolError, "not booted"):
            tool.run("agent", "SIM-UDID", "ensure")


if __name__ == "__main__":
    unittest.main()
