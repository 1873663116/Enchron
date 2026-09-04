#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import FrozenInstanceError
from pathlib import Path
import sys
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.ids import NodeID, SignatureID
from regression.core.runview import (
    PRODUCT_FAILURE_NODE_STATUSES,
    PRODUCT_NODE_STATUSES,
    TERMINAL_NODE_STATUSES,
    NodeStatus,
)
from regression.tools.verdict import Attribution, Verdict, VerdictError


NODE = NodeID("node:emby:poster-wall")
SIGNATURE = SignatureID("signature:blank-frame")


def verdict(**overrides) -> Verdict:
    fields = {
        "node": NODE,
        "first_deviant_frame": 12,
        "region_observation": "the poster grid is blank",
        "attribution": Attribution.PRODUCT,
        "signature": SIGNATURE,
    }
    fields.update(overrides)
    return Verdict(**fields)


class NodeStatusTests(unittest.TestCase):
    def test_the_enum_carries_the_designed_wire_values(self) -> None:
        self.assertEqual(
            {
                "pending",
                "leased",
                "passed",
                "failed",
                "failed(known)",
                "blockedBy",
                "deferred(human)",
                "indeterminate",
            },
            {status.value for status in NodeStatus},
        )

    def test_pending_and_leased_are_the_only_non_terminal_states(self) -> None:
        non_terminal = set(NodeStatus) - set(TERMINAL_NODE_STATUSES)
        self.assertEqual({NodeStatus.PENDING, NodeStatus.LEASED}, non_terminal)

    def test_a_known_defect_carries_the_same_evidence_duty_as_a_failure(self) -> None:
        self.assertIn(NodeStatus.FAILED_KNOWN, PRODUCT_NODE_STATUSES)
        self.assertIn(NodeStatus.FAILED_KNOWN, PRODUCT_FAILURE_NODE_STATUSES)

    def test_deferring_to_a_human_is_not_a_product_verdict(self) -> None:
        for absent in (NodeStatus.DEFERRED_HUMAN, NodeStatus.INDETERMINATE):
            with self.subTest(status=absent):
                self.assertNotIn(absent, PRODUCT_NODE_STATUSES)

    def test_every_product_status_is_terminal(self) -> None:
        self.assertTrue(set(PRODUCT_NODE_STATUSES) <= set(TERMINAL_NODE_STATUSES))
        self.assertTrue(
            set(PRODUCT_FAILURE_NODE_STATUSES) <= set(PRODUCT_NODE_STATUSES)
        )


class VerdictTests(unittest.TestCase):
    def test_a_complete_verdict_keeps_every_field(self) -> None:
        item = verdict()
        self.assertEqual(NODE, item.node)
        self.assertEqual(12, item.first_deviant_frame)
        self.assertIs(Attribution.PRODUCT, item.attribution)
        self.assertEqual(SIGNATURE, item.signature)

    def test_a_verdict_is_frozen(self) -> None:
        with self.assertRaises(FrozenInstanceError):
            verdict().attribution = Attribution.HARNESS

    def test_an_absent_frame_and_signature_are_accepted(self) -> None:
        item = verdict(first_deviant_frame=None, signature=None)
        self.assertIsNone(item.first_deviant_frame)
        self.assertIsNone(item.signature)

    def test_the_first_frame_of_a_segment_is_accepted(self) -> None:
        self.assertEqual(0, verdict(first_deviant_frame=0).first_deviant_frame)

    def test_a_negative_or_non_integer_frame_is_refused(self) -> None:
        for rejected in (-1, 1.5, "12", True):
            with self.subTest(frame=rejected):
                with self.assertRaisesRegex(VerdictError, "non-negative integer"):
                    verdict(first_deviant_frame=rejected)

    def test_an_attribution_outside_the_closed_enum_is_refused(self) -> None:
        for rejected in ("product", None, 1):
            with self.subTest(attribution=rejected):
                with self.assertRaisesRegex(VerdictError, "product, harness or spec"):
                    verdict(attribution=rejected)

    def test_a_malformed_node_or_signature_is_refused_as_a_verdict_error(self) -> None:
        with self.assertRaisesRegex(VerdictError, "node identifier"):
            verdict(node="emby:poster-wall")
        with self.assertRaisesRegex(VerdictError, "signature identifier"):
            verdict(signature="blank-frame")

    def test_every_attribution_the_design_names_is_constructible(self) -> None:
        self.assertEqual(
            {"product", "harness", "spec"},
            {item.value for item in Attribution},
        )


if __name__ == "__main__":
    unittest.main()
