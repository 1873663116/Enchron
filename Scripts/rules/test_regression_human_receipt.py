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
from regression.core.expression import OracleResult
from regression.core.ids import Digest, NodeID, SidekickID
from regression.core.replay import replay
from regression.core.runtime import open_run
from regression.core.runview import Attribution, NodeStatus
from regression.tools import ledger_tool, receipt_tool
from regression.tools.human_receipt import (
    Checklist,
    HumanReceiptError,
    NodeAttribution,
    build_checklist,
    load_receipt,
    seal,
)
from regression.tools.receipt_tool import ReceiptToolError, open_nodes
from regression.tools.signatures import ALL_BLACK
from regression.tools.verdict import Verdict

from test_regression_core_runtime import _single_node_plan
from test_regression_ledger_lock import FRAME_COUNT, run_node, verdict

NODE = NodeID("node:gate")
BUILD = Digest("sha256:" + "1" * 64)
RECORDING = Digest("sha256:" + "2" * 64)


def attribution(node: NodeID = NODE) -> NodeAttribution:
    return NodeAttribution(
        node, Attribution.PRODUCT, "the poster grid never drew", (0, 3)
    )


class ChecklistTests(unittest.TestCase):
    """The human layer is a ledger state, not a list somebody keeps. The
    checklist is generated from the nodes the ledger deferred, and a wearer who
    widens it changes the digest the receipt seals."""

    def run_with(self, directory: Path, status: NodeStatus):
        main = open_run(_single_node_plan(), directory)
        lease = run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
        main.close()
        ledger_tool.write(directory, verdict(lease.node_id), status)
        return replay(directory)

    def test_a_checklist_is_generated_from_the_deferred_nodes(self) -> None:
        with TemporaryDirectory() as temporary:
            current = self.run_with(Path(temporary), NodeStatus.FAILED)

            self.assertEqual((), build_checklist(current).deferred)

    def test_a_deferred_node_lands_on_the_checklist(self) -> None:
        checklist = build_checklist(_deferred_view())

        self.assertEqual((NODE,), checklist.deferred)
        self.assertEqual((NODE,), checklist.nodes)

    def test_a_known_failure_does_not_block_its_successors_from_closing(
        self,
    ) -> None:
        from regression.core.runview import failure_ancestors

        blocked = failure_ancestors((_deferred_view().node(NODE),))
        self.assertEqual((), blocked)

    def test_widening_the_checklist_changes_its_digest(self) -> None:
        narrow = Checklist((NODE,), ())
        wide = Checklist((NODE,), (NodeID("node:other"),))

        self.assertNotEqual(narrow.digest(), wide.digest())
        self.assertEqual((NODE, NodeID("node:other")), wide.nodes)

    def test_widening_onto_a_node_the_run_does_not_hold_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            current = self.run_with(Path(temporary), NodeStatus.FAILED)

            with self.assertRaisesRegex(HumanReceiptError, "does not hold"):
                build_checklist(current, (NodeID("node:absent"),))


class SealTests(unittest.TestCase):
    """Every digest the receipt carries names something the reviewer can fetch.
    A receipt missing one of them is not a weaker receipt, it is not one."""

    def checklist(self) -> Checklist:
        return Checklist((NODE,), ())

    def test_a_complete_receipt_seals(self) -> None:
        receipt = seal(
            self.checklist(), BUILD, "DEVICE-UDID", RECORDING, (attribution(),)
        )

        self.assertEqual(self.checklist().digest(), receipt.checklist_digest)
        self.assertEqual((NODE,), receipt.covered())

    def test_a_missing_digest_refuses_the_seal(self) -> None:
        for build, recording, label in (
            ("", RECORDING, "build digest"),
            (BUILD, "", "recording digest"),
        ):
            with self.subTest(label=label):
                with self.assertRaisesRegex(HumanReceiptError, label):
                    seal(
                        self.checklist(),
                        build,
                        "DEVICE-UDID",
                        recording,
                        (attribution(),),
                    )

    def test_a_missing_device_refuses_the_seal(self) -> None:
        with self.assertRaisesRegex(HumanReceiptError, "names the device"):
            seal(self.checklist(), BUILD, "  ", RECORDING, (attribution(),))

    def test_a_checklist_entry_with_no_attribution_refuses_the_seal(self) -> None:
        with self.assertRaisesRegex(HumanReceiptError, "no attribution"):
            seal(self.checklist(), BUILD, "DEVICE-UDID", RECORDING, ())

    def test_an_attribution_with_no_description_refuses_the_seal(self) -> None:
        empty = NodeAttribution(NODE, Attribution.PRODUCT, "   ", ())

        with self.assertRaisesRegex(HumanReceiptError, "no description"):
            seal(self.checklist(), BUILD, "DEVICE-UDID", RECORDING, (empty,))

    def test_a_receipt_round_trips_through_its_payload(self) -> None:
        receipt = seal(
            self.checklist(), BUILD, "DEVICE-UDID", RECORDING, (attribution(),)
        )

        self.assertEqual(receipt, load_receipt(receipt.payload()))

    def test_a_document_of_another_schema_is_refused(self) -> None:
        with self.assertRaisesRegex(HumanReceiptError, "human-receipt"):
            load_receipt({"schema": "something.else"})


class MergeReceiptTests(unittest.TestCase):
    """A merge receipt closes when every node is closed. A node the ledger
    deferred to a human closes only when a human receipt covers it; a known
    defect closes on its own."""

    def closed_run(self, directory: Path, status: NodeStatus, defects=()):
        main = open_run(_single_node_plan(), directory)
        lease = run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
        main.close()
        if defects:
            from regression.tools import known_defects

            original = known_defects.load
            known_defects.load = lambda path=None: defects
            self.addCleanup(setattr, known_defects, "load", original)
        ledger_tool.write(
            directory,
            verdict(lease.node_id, signature=ALL_BLACK),
            status)
        return lease

    def test_a_failed_node_closes_the_receipt(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.closed_run(directory, NodeStatus.FAILED)

            result = receipt_tool.run(directory)

            self.assertEqual(receipt_tool.RECEIPT_SCHEMA, result["schema"])
            self.assertNotIn("refused", result)

    def test_a_leased_node_leaves_the_receipt_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_single_node_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            main.close()

            result = receipt_tool.run(directory)

            self.assertIn("refused", result)
            self.assertEqual([str(NODE)], result["openNodes"])

    def test_a_deferred_node_stays_open_until_a_human_receipt_covers_it(
        self,
    ) -> None:
        view = _deferred_view()

        self.assertEqual((NODE,), open_nodes(view, None))
        self.assertEqual(
            (),
            open_nodes(
                view,
                seal(
                    Checklist((NODE,), ()),
                    BUILD,
                    "DEVICE-UDID",
                    RECORDING,
                    (attribution(),),
                ),
            ),
        )

    def test_a_human_receipt_covering_another_node_leaves_this_one_open(
        self,
    ) -> None:
        view = _deferred_view()
        elsewhere = seal(
            Checklist((NodeID("node:other"),), ()),
            BUILD,
            "DEVICE-UDID",
            RECORDING,
            (attribution(NodeID("node:other")),),
        )

        self.assertEqual((NODE,), open_nodes(view, elsewhere))

    def test_a_known_defect_does_not_block_the_receipt(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            from datetime import date

            from regression.tools.known_defects import KnownDefect

            self.closed_run(
                directory,
                NodeStatus.FAILED,
                defects=(
                    KnownDefect(
                        "scenario:gate",
                        "the poster grid renders late",
                        ALL_BLACK,
                        date(2026, 9, 1),
                        "the grid stops rendering late",
                    ),
                ),
            )

            result = receipt_tool.run(directory)

            self.assertNotIn("refused", result)
            self.assertEqual(
                "failed(known)", result["nodes"][0]["status"]
            )

    def test_a_receipt_sealed_against_another_checklist_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.closed_run(directory, NodeStatus.FAILED)
            elsewhere = seal(
                Checklist((NODE,), ()),
                BUILD,
                "DEVICE-UDID",
                RECORDING,
                (attribution(),),
            )
            path = directory / "receipt.json"
            path.write_text(json.dumps(elsewhere.payload()), encoding="utf-8")

            result = receipt_tool.run(directory, path)

            self.assertIn("refused", result)
            self.assertIn("sealed against", result["refused"])

    def test_a_receipt_naming_a_digest_that_is_not_one_is_refused(self) -> None:
        payload = seal(
            Checklist((NODE,), ()), BUILD, "DEVICE-UDID", RECORDING, (attribution(),)
        ).payload()
        payload["buildDigest"] = 7

        with self.assertRaisesRegex(HumanReceiptError, "build digest"):
            load_receipt(payload)

    def test_a_human_receipt_path_that_does_not_exist_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.closed_run(directory, NodeStatus.FAILED)

            with self.assertRaisesRegex(ReceiptToolError, "no human receipt"):
                receipt_tool.run(directory, Path(temporary) / "absent.json")

    def test_a_malformed_human_receipt_is_refused(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.closed_run(directory, NodeStatus.FAILED)
            path = Path(temporary) / "receipt.json"
            path.write_text(json.dumps({"schema": "wrong"}), encoding="utf-8")

            with self.assertRaises(ReceiptToolError):
                receipt_tool.run(directory, path)


def _deferred_view():
    from dataclasses import replace

    with TemporaryDirectory() as temporary:
        directory = Path(temporary)
        main = open_run(_single_node_plan(), directory)
        run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
        current = main.view
        main.close()
    node = replace(
        current.node(NODE), status=NodeStatus.DEFERRED_HUMAN, lease_id=None
    )
    return replace(current, nodes=(node,))


if __name__ == "__main__":
    unittest.main()
