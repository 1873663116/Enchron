from __future__ import annotations

import ast
from dataclasses import replace
from pathlib import Path
import re
import sys
from tempfile import TemporaryDirectory
from typing import Dict, Tuple
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT))
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from regression.core.catalog import load_catalog
from regression.core.contracts import DraftCatalog
from regression.core.digest import canonical_digest
from regression.core.errors import RegressionError
from regression.core.review import (
    BudgetAmount,
    BudgetUnit,
    CompletedReview,
    ReviewActorIdentity,
    ReviewBudget,
    ReviewClass,
    ReviewPacket,
    ReviewPolicy,
    ReviewReceipt,
    ReviewUnitKind,
    ReviewUsage,
    approve_review_budgets,
    complete_reviews,
)
from regression.core.review_catalog import (
    build_catalog_review_units,
    plan_catalog_reviews,
    verify_completed_catalog_reviews,
)
from test_regression_core_catalog import CatalogFixture


def _amounts(input_tokens: int, review_items: int) -> Tuple[BudgetAmount, ...]:
    return (
        BudgetAmount(BudgetUnit.INPUT_TOKENS, input_tokens),
        BudgetAmount(BudgetUnit.REVIEW_ITEMS, review_items),
    )


def _policy() -> ReviewPolicy:
    return ReviewPolicy(
        ReviewBudget(_amounts(1_000_000, 1_000_000)),
        ReviewBudget(_amounts(100_000_000, 100_000_000)),
    )


def _receipt(packet: ReviewPacket) -> ReviewReceipt:
    return ReviewReceipt(
        packet_digest=packet.packet_digest,
        reviewer=packet.reviewer,
        actor=ReviewActorIdentity(
            f"actor:{packet.reviewer.value}",
            canonical_digest({"environment": packet.reviewer.value}),
        ),
        report_digest=canonical_digest(
            {"packetDigest": str(packet.packet_digest)}
        ),
        accepted=True,
        usage=ReviewUsage(tuple(packet.approved_budget.amounts)),
        issued_at="2026-08-29T00:00:00Z",
        assessment_digest=(
            canonical_digest({"assessmentFor": str(packet.packet_digest)})
            if packet.reviewer is ReviewClass.AGENT_OPERABILITY
            else None
        ),
    )


def _complete(catalog: DraftCatalog) -> CompletedReview:
    units = build_catalog_review_units(catalog)
    approved = approve_review_budgets(plan_catalog_reviews(catalog, _policy()))
    return complete_reviews(
        units,
        approved,
        tuple(_receipt(packet) for packet in approved.packets),
        catalog.catalog_digest,
    )


def _replace_packet(
    completed: CompletedReview, index: int, packet: ReviewPacket
) -> CompletedReview:
    old_packet = completed.packets[index]
    packets = tuple(
        packet if offset == index else current
        for offset, current in enumerate(completed.packets)
    )
    receipts = tuple(
        replace(
            receipt,
            packet_digest=packet.packet_digest,
            reviewer=packet.reviewer,
        )
        if receipt.packet_digest == old_packet.packet_digest
        else receipt
        for receipt in completed.receipts
    )
    return CompletedReview(completed.catalog_root, packets, receipts)


class CatalogReviewTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "Regression"
        self.fixture = CatalogFixture(self.root)
        self.fixture.write()
        self.catalog = load_catalog(self.root)
        self.completed = _complete(self.catalog)

    def assert_fails_closed(self, call) -> RegressionError:
        with self.assertRaises(RegressionError) as raised:
            call()
        self.assertIsNotNone(
            re.fullmatch(r"[a-z]+(?:\.[a-z]+)+", raised.exception.code),
            raised.exception.code,
        )
        return raised.exception


class CatalogReviewUnitTests(CatalogReviewTestCase):
    def test_evidence_case_and_readiness_fields_change_leaf_and_packet_digests(self) -> None:
        before = plan_catalog_reviews(self.catalog, _policy())
        scenario = self.fixture.scenario
        scenario["staticCases"] = ["alternate"]
        scenario["obligations"][0]["caseKey"] = "alternate"
        scenario["obligations"][0]["evidenceSchema"] = "ui.screenshot@2"
        pair = {
            "evidenceType": "ui.screenshot",
            "evidenceSchema": "ui.screenshot@2",
        }
        self.fixture.documents["operations/observe.md"]["evidenceSchemas"] = [pair]
        self.fixture.documents["oracles/visible.md"]["evidenceSchemas"] = [pair]
        preparation = self.fixture.documents["preparations/library-simulator.md"]
        preparation["readiness"] = "implementation-gap"
        preparation["blockers"] = [
            {
                "kind": "implementation-gap",
                "capability": "fixture-stage",
                "detail": "The simulator fixture producer is unavailable.",
            }
        ]
        preparation["produces"][0]["producedByCall"] = None
        self.fixture.write()
        changed = load_catalog(self.root)
        after = plan_catalog_reviews(changed, _policy())

        original_scenario = self.catalog.scenarios[0]
        changed_scenario = changed.scenarios[0]
        self.assertNotEqual(
            original_scenario.leaf_digest, changed_scenario.leaf_digest
        )
        original_preparation = next(
            item
            for item in self.catalog.preparations
            if item.id == "preparation:library-ready:simulator"
        )
        changed_preparation = next(
            item
            for item in changed.preparations
            if item.id == original_preparation.id
        )
        self.assertNotEqual(
            original_preparation.leaf_digest, changed_preparation.leaf_digest
        )
        self.assertNotEqual(
            {item.packet_digest for item in before.packets},
            {item.packet_digest for item in after.packets},
        )

    def test_builds_the_fixed_reviewer_matrix(self) -> None:
        expected = {
            ReviewUnitKind.PROMISE: frozenset(
                (ReviewClass.HUMAN_COVERAGE, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.FACT: frozenset(
                (ReviewClass.HUMAN_COVERAGE, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.PREPARATION: frozenset(
                (ReviewClass.AGENT_OPERABILITY, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.OPERATION: frozenset(
                (ReviewClass.AGENT_OPERABILITY, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.ORACLE: frozenset(
                (ReviewClass.AGENT_OPERABILITY, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.RUBRIC: frozenset(ReviewClass),
            ReviewUnitKind.JOURNEY: frozenset(ReviewClass),
            ReviewUnitKind.SCENARIO: frozenset(ReviewClass),
        }

        units = build_catalog_review_units(self.catalog)

        self.assertEqual({unit.kind for unit in units}, set(ReviewUnitKind))
        for unit in units:
            self.assertEqual(unit.required_reviewers, expected[unit.kind])

    def test_uses_stable_local_scopes_and_leaf_digests(self) -> None:
        units = build_catalog_review_units(self.catalog)
        by_ref = {unit.ref: unit for unit in units}

        for promise in self.catalog.promises:
            feature = str(promise.id).split(":")[1]
            self.assertEqual(by_ref[str(promise.id)].scope, f"feature:{feature}")
        for preparation in self.catalog.preparations:
            self.assertEqual(
                by_ref[str(preparation.id)].scope,
                f"lane:{preparation.lane.value}",
            )
        for journey in self.catalog.journeys:
            self.assertEqual(by_ref[str(journey.id)].scope, str(journey.id))
        for scenario in self.catalog.scenarios:
            self.assertEqual(by_ref[str(scenario.id)].scope, str(scenario.journey))
        for contract in (
            self.catalog.facts
            + self.catalog.operations
            + self.catalog.oracles
            + self.catalog.rubrics
        ):
            self.assertEqual(by_ref[str(contract.id)].scope, "shared")
        for contract in self.catalog.contracts:
            unit = by_ref[str(contract.id)]
            self.assertEqual(unit.content_digest, contract.leaf_digest)
            self.assertNotEqual(str(unit.content_digest), str(contract.id))

    def test_units_are_tuples_with_stable_order_and_typed_usage(self) -> None:
        forward = build_catalog_review_units(self.catalog)
        reversed_catalog = replace(
            self.catalog,
            promises=tuple(reversed(self.catalog.promises)),
            facts=tuple(reversed(self.catalog.facts)),
            operations=tuple(reversed(self.catalog.operations)),
            oracles=tuple(reversed(self.catalog.oracles)),
            rubrics=tuple(reversed(self.catalog.rubrics)),
            preparations=tuple(reversed(self.catalog.preparations)),
            journeys=tuple(reversed(self.catalog.journeys)),
            scenarios=tuple(reversed(self.catalog.scenarios)),
        )
        backward = build_catalog_review_units(reversed_catalog)

        self.assertIsInstance(forward, tuple)
        self.assertEqual(forward, backward)
        self.assertEqual(
            tuple((unit.kind.value, unit.ref) for unit in forward),
            tuple(sorted((unit.kind.value, unit.ref) for unit in forward)),
        )
        for unit in forward:
            self.assertEqual(
                {amount.unit for amount in unit.estimated_usage.amounts},
                {BudgetUnit.INPUT_TOKENS, BudgetUnit.REVIEW_ITEMS},
            )
            self.assertTrue(
                all(amount.amount >= 1 for amount in unit.estimated_usage.amounts)
            )
            self.assertEqual(
                unit.estimated_usage.amount_for(BudgetUnit.REVIEW_ITEMS), 1
            )

        planned = plan_catalog_reviews(self.catalog, _policy())
        self.assertEqual(planned.units, forward)
        self.assertIsInstance(planned.packets, tuple)
        self.assertTrue(all(isinstance(packet.units, tuple) for packet in planned.packets))

    def test_one_leaf_change_only_changes_its_local_packets(self) -> None:
        before = plan_catalog_reviews(self.catalog, _policy())
        promise = next(
            item
            for item in self.catalog.promises
            if str(item.id) == "promise:playback:c01"
        )
        changed_promise = replace(
            promise,
            source_digest=canonical_digest({"promise": "changed"}),
        )
        changed = replace(
            self.catalog,
            promises=tuple(
                changed_promise if item.id == promise.id else item
                for item in self.catalog.promises
            ),
        )
        after = plan_catalog_reviews(changed, _policy())

        def packet_digests(plan) -> Dict[Tuple[ReviewClass, str], object]:
            return {
                (packet.reviewer, packet.scope): packet.packet_digest
                for packet in plan.packets
            }

        original = packet_digests(before)
        current = packet_digests(after)
        changed_keys = {
            key for key in original if original[key] != current[key]
        }
        self.assertEqual(
            changed_keys,
            {
                (ReviewClass.HUMAN_COVERAGE, "feature:playback"),
                (ReviewClass.DETERMINISTIC, "feature:playback"),
            },
        )

    def test_usage_tracks_contract_text_and_structure(self) -> None:
        rubric = self.catalog.rubrics[0]
        expanded_rubric = replace(
            rubric,
            criteria=rubric.criteria
            + (
                "The complete rendered title remains readable throughout the frame.",
            ),
            source_digest=canonical_digest({"rubric": "expanded"}),
        )
        expanded_catalog = replace(
            self.catalog,
            rubrics=(expanded_rubric,) + self.catalog.rubrics[1:],
        )
        before = {
            unit.ref: unit for unit in build_catalog_review_units(self.catalog)
        }[str(rubric.id)]
        after = {
            unit.ref: unit
            for unit in build_catalog_review_units(expanded_catalog)
        }[str(rubric.id)]

        self.assertGreater(
            after.estimated_usage.amount_for(BudgetUnit.INPUT_TOKENS),
            before.estimated_usage.amount_for(BudgetUnit.INPUT_TOKENS),
        )
        self.assertEqual(
            after.estimated_usage.amount_for(BudgetUnit.REVIEW_ITEMS),
            before.estimated_usage.amount_for(BudgetUnit.REVIEW_ITEMS),
        )


class CatalogReviewVerificationTests(CatalogReviewTestCase):
    def test_accepts_current_complete_bijective_review(self) -> None:
        self.assertIsNone(
            verify_completed_catalog_reviews(self.catalog, self.completed)
        )

    def test_rejects_old_catalog_and_changed_leaf(self) -> None:
        promise = self.catalog.promises[0]
        changed = replace(
            self.catalog,
            promises=(
                replace(
                    promise,
                    source_digest=canonical_digest({"leaf": "changed"}),
                ),
            )
            + self.catalog.promises[1:],
        )

        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(changed, self.completed)
        )
        self.assertEqual(error.code, "review.catalog.digest.mismatch")

    def test_rejects_missing_extra_and_duplicate_packets(self) -> None:
        removed = self.completed.packets[0]
        missing = CompletedReview(
            self.completed.catalog_root,
            self.completed.packets[1:],
            tuple(
                receipt
                for receipt in self.completed.receipts
                if receipt.packet_digest != removed.packet_digest
            ),
        )
        self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(self.catalog, missing)
        )

        duplicate = CompletedReview(
            self.completed.catalog_root,
            self.completed.packets + (self.completed.packets[0],),
            self.completed.receipts,
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(self.catalog, duplicate)
        )
        self.assertEqual(error.code, "review.catalog.packet.duplicate")

        first = self.completed.packets[0]
        expanded_budget = ReviewBudget(
            tuple(
                BudgetAmount(amount.unit, amount.amount + 1)
                for amount in first.approved_budget.amounts
            )
        )
        extra_packet = replace(first, approved_budget=expanded_budget)
        extra = CompletedReview(
            self.completed.catalog_root,
            self.completed.packets + (extra_packet,),
            self.completed.receipts + (_receipt(extra_packet),),
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(self.catalog, extra)
        )
        self.assertEqual(error.code, "review.catalog.coverage.duplicate")

    def test_rejects_missing_extra_and_duplicate_receipts(self) -> None:
        missing = CompletedReview(
            self.completed.catalog_root,
            self.completed.packets,
            self.completed.receipts[1:],
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(self.catalog, missing)
        )
        self.assertEqual(error.code, "review.catalog.receipt.missing")

        duplicate = CompletedReview(
            self.completed.catalog_root,
            self.completed.packets,
            self.completed.receipts + (self.completed.receipts[0],),
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(self.catalog, duplicate)
        )
        self.assertEqual(error.code, "review.catalog.receipt.duplicate")

        extra_receipt = replace(
            self.completed.receipts[0],
            packet_digest=canonical_digest({"packet": "unknown"}),
        )
        extra = CompletedReview(
            self.completed.catalog_root,
            self.completed.packets,
            self.completed.receipts + (extra_receipt,),
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(self.catalog, extra)
        )
        self.assertEqual(error.code, "review.catalog.receipt.extra")

    def test_rejects_wrong_reviewer_rejection_and_budget_overuse(self) -> None:
        receipt = self.completed.receipts[0]
        receipt_packet = next(
            packet
            for packet in self.completed.packets
            if packet.packet_digest == receipt.packet_digest
        )
        other_reviewer = next(
            reviewer
            for reviewer in ReviewClass
            if reviewer is not receipt.reviewer
        )
        variants = (
            (
                "review.catalog.receipt.reviewer.mismatch",
                replace(receipt, reviewer=other_reviewer),
            ),
            (
                "review.catalog.receipt.rejected",
                replace(receipt, accepted=False),
            ),
            (
                "review.catalog.receipt.budget.exceeded",
                replace(
                    receipt,
                    usage=ReviewUsage(
                        _amounts(
                            receipt_packet.approved_budget.amount_for(
                                BudgetUnit.INPUT_TOKENS
                            )
                            + 1,
                            1,
                        )
                    ),
                ),
            ),
        )
        for code, changed_receipt in variants:
            with self.subTest(code=code):
                changed = CompletedReview(
                    self.completed.catalog_root,
                    self.completed.packets,
                    (changed_receipt,) + self.completed.receipts[1:],
                )
                error = self.assert_fails_closed(
                    lambda: verify_completed_catalog_reviews(
                        self.catalog, changed
                    )
                )
                self.assertEqual(error.code, code)

    def test_rejects_leaf_scope_and_required_budget_changes(self) -> None:
        packet = self.completed.packets[0]
        unit = packet.units[0]
        changed_leaf = replace(
            unit,
            content_digest=canonical_digest({"unit": "changed"}),
        )
        leaf_packet = replace(
            packet,
            units=(changed_leaf,) + packet.units[1:],
        )
        leaf_completion = _replace_packet(self.completed, 0, leaf_packet)
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(
                self.catalog, leaf_completion
            )
        )
        self.assertEqual(error.code, "review.catalog.unit.mismatch")

        changed_scope_units = tuple(
            replace(current, scope="feature:changed")
            for current in packet.units
        )
        scope_packet = replace(
            packet,
            scope="feature:changed",
            units=changed_scope_units,
        )
        scope_completion = _replace_packet(self.completed, 0, scope_packet)
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(
                self.catalog, scope_completion
            )
        )
        self.assertEqual(error.code, "review.catalog.unit.mismatch")

        reduced_unit = replace(
            unit,
            required_reviewers=frozenset((packet.reviewer,)),
            estimated_usage=ReviewUsage(_amounts(1, 1)),
        )
        reduced_packet = replace(
            packet,
            units=(reduced_unit,) + packet.units[1:],
        )
        reduced_completion = _replace_packet(
            self.completed, 0, reduced_packet
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(
                self.catalog, reduced_completion
            )
        )
        self.assertEqual(error.code, "review.catalog.unit.mismatch")

        zero_budget = ReviewBudget(_amounts(0, 0))
        budget_packet = replace(packet, approved_budget=zero_budget)
        budget_completion = _replace_packet(self.completed, 0, budget_packet)
        budget_completion = CompletedReview(
            budget_completion.catalog_root,
            budget_completion.packets,
            tuple(
                replace(receipt, usage=ReviewUsage(_amounts(0, 0)))
                if receipt.packet_digest == budget_packet.packet_digest
                else receipt
                for receipt in budget_completion.receipts
            ),
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(
                self.catalog, budget_completion
            )
        )
        self.assertEqual(
            error.code, "review.catalog.packet.budget.insufficient"
        )

    def test_recomputes_packet_receipt_and_completion_digests(self) -> None:
        packet = replace(self.completed.packets[0])
        object.__setattr__(
            packet,
            "packet_digest",
            canonical_digest({"forged": "packet"}),
        )
        forged_packet = CompletedReview(
            self.completed.catalog_root,
            (packet,) + self.completed.packets[1:],
            self.completed.receipts,
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(
                self.catalog, forged_packet
            )
        )
        self.assertEqual(error.code, "review.catalog.packet.digest.invalid")

        receipt = replace(self.completed.receipts[0])
        object.__setattr__(
            receipt,
            "receipt_digest",
            canonical_digest({"forged": "receipt"}),
        )
        forged_receipt = CompletedReview(
            self.completed.catalog_root,
            self.completed.packets,
            (receipt,) + self.completed.receipts[1:],
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(
                self.catalog, forged_receipt
            )
        )
        self.assertEqual(error.code, "review.catalog.receipt.digest.invalid")

        completion = replace(self.completed)
        object.__setattr__(
            completion,
            "completion_digest",
            canonical_digest({"forged": "completion"}),
        )
        error = self.assert_fails_closed(
            lambda: verify_completed_catalog_reviews(
                self.catalog, completion
            )
        )
        self.assertEqual(
            error.code, "review.catalog.completion.digest.invalid"
        )


class CatalogReviewPythonCompatibilityTests(unittest.TestCase):
    def test_modules_parse_as_python_3_9(self) -> None:
        paths = (
            REPOSITORY_ROOT / "Scripts/regression/core/review_catalog.py",
            Path(__file__),
        )
        for path in paths:
            with self.subTest(path=path.name):
                ast.parse(
                    path.read_text(encoding="utf-8"),
                    filename=path.name,
                    feature_version=(3, 9),
                )


if __name__ == "__main__":
    unittest.main()
