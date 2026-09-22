from __future__ import annotations

import ast
from dataclasses import FrozenInstanceError, replace
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
REGRESSION_SCRIPTS = ROOT / "Scripts" / "regression"
if str(REGRESSION_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(REGRESSION_SCRIPTS))

from core.digest import canonical_digest
from core.errors import RegressionError
from core.review import (
    BudgetAmount,
    BudgetApproval,
    BudgetApprovedReview,
    BudgetUnit,
    CompletedReview,
    PlannedReview,
    ReviewActorIdentity,
    ReviewBudget,
    ReviewClass,
    ReviewPolicy,
    ReviewReceipt,
    ReviewUnit,
    ReviewUnitKind,
    ReviewUsage,
    approve_review_budgets,
    complete_reviews,
    plan_reviews,
)


ALL_REVIEWERS = frozenset(ReviewClass)


def amounts(**values: int):
    by_name = {
        "input_tokens": BudgetUnit.INPUT_TOKENS,
        "output_tokens": BudgetUnit.OUTPUT_TOKENS,
        "wall_seconds": BudgetUnit.WALL_SECONDS,
        "cost_micros": BudgetUnit.COST_MICROS,
        "review_items": BudgetUnit.REVIEW_ITEMS,
    }
    return tuple(BudgetAmount(by_name[name], value) for name, value in values.items())


def usage(tokens: int = 1, items: int = 1) -> ReviewUsage:
    return ReviewUsage(amounts(input_tokens=tokens, review_items=items))


def budget(tokens: int, items: int) -> ReviewBudget:
    return ReviewBudget(amounts(input_tokens=tokens, review_items=items))


def unit(
    ref: str,
    *,
    kind: ReviewUnitKind = ReviewUnitKind.SCENARIO,
    scope: str = "journey:playback",
    reviewers=ALL_REVIEWERS,
    tokens: int = 1,
) -> ReviewUnit:
    return ReviewUnit(
        kind,
        ref,
        canonical_digest({"ref": ref}),
        scope,
        reviewers,
        usage(tokens),
    )


def policy(per_packet_tokens: int = 3, total_tokens: int = 100) -> ReviewPolicy:
    return ReviewPolicy(
        budget(per_packet_tokens, per_packet_tokens),
        budget(total_tokens, total_tokens),
    )


def receipts_for(approved: BudgetApprovedReview):
    return tuple(
        ReviewReceipt(
            packet_digest=packet.packet_digest,
            reviewer=packet.reviewer,
            actor=ReviewActorIdentity(
                f"actor:{packet.reviewer.value}",
                canonical_digest(
                    {"environment": packet.reviewer.value, "version": 1}
                ),
            ),
            report_digest=canonical_digest(
                {"reportFor": str(packet.packet_digest)}
            ),
            accepted=True,
            usage=ReviewUsage(tuple(packet.approved_budget.amounts)),
            issued_at="2026-08-28T00:00:00Z",
            assessment_digest=(
                canonical_digest({"assessmentFor": str(packet.packet_digest)})
                if packet.reviewer is ReviewClass.AGENT_OPERABILITY
                else None
            ),
        )
        for packet in approved.packets
    )


class ReviewTestCase(unittest.TestCase):
    def assert_error(self, code: str, call) -> RegressionError:
        with self.assertRaises(RegressionError) as context:
            call()
        self.assertEqual(context.exception.code, code)
        return context.exception


class ReviewValueTests(ReviewTestCase):
    def test_values_are_frozen_and_normalize_collections(self) -> None:
        review_unit = unit("scenario:b", reviewers=list(ALL_REVIEWERS))
        planned = plan_reviews([review_unit], policy())

        self.assertIsInstance(review_unit.required_reviewers, frozenset)
        self.assertIsInstance(planned.units, tuple)
        self.assertIsInstance(planned.packets, tuple)
        self.assertIsInstance(planned.packets[0].units, tuple)
        with self.assertRaises(FrozenInstanceError):
            review_unit.scope = "changed"

    def test_rejects_negative_duplicate_and_empty_budget_units(self) -> None:
        self.assert_error(
            "review.negative.budget.amount",
            lambda: BudgetAmount(BudgetUnit.INPUT_TOKENS, -1),
        )
        self.assert_error(
            "review.invalid.budget.amount",
            lambda: BudgetAmount(BudgetUnit.INPUT_TOKENS, True),
        )
        self.assert_error("review.empty.budget.units", lambda: ReviewBudget(()))
        self.assert_error(
            "review.duplicate.budget.unit",
            lambda: ReviewUsage(
                (
                    BudgetAmount(BudgetUnit.REVIEW_ITEMS, 1),
                    BudgetAmount(BudgetUnit.REVIEW_ITEMS, 2),
                )
            ),
        )

    def test_rejects_empty_units_reviewers_references_and_scopes(self) -> None:
        self.assert_error("review.empty.units", lambda: plan_reviews((), policy()))
        self.assert_error(
            "review.empty.reviewers",
            lambda: unit("scenario:none", reviewers=()),
        )
        self.assert_error("review.empty.value", lambda: unit(""))
        self.assert_error(
            "review.empty.value", lambda: unit("scenario:empty-scope", scope=" ")
        )

    def test_rejects_duplicate_review_units(self) -> None:
        duplicate = unit("scenario:duplicate")
        self.assert_error(
            "review.duplicate.unit",
            lambda: plan_reviews((duplicate, duplicate), policy()),
        )

    def test_preparation_is_a_review_unit_kind(self) -> None:
        preparation = unit(
            "preparation:library-ready",
            kind=ReviewUnitKind.PREPARATION,
        )

        self.assertEqual(preparation.kind.value, "preparation")

    def test_actor_identity_is_frozen_and_requires_identity_and_environment(
        self,
    ) -> None:
        identity = ReviewActorIdentity(
            "agent:catalog-reviewer",
            canonical_digest({"model": "reviewer", "prompt": 3}),
        )

        with self.assertRaises(FrozenInstanceError):
            identity.actor_id = "checker:changed"
        self.assert_error(
            "review.empty.value",
            lambda: ReviewActorIdentity(" ", identity.environment_digest),
        )
        self.assert_error(
            "identifier.invalid_format",
            lambda: ReviewActorIdentity("checker:catalog", "not-a-digest"),
        )


class ReviewPlanningTests(ReviewTestCase):
    def test_stably_sorts_and_splits_packets_by_each_reviewer_and_scope(self) -> None:
        units = (
            unit("scenario:c", tokens=2),
            unit("scenario:a", tokens=2),
            unit("scenario:b", tokens=1),
            unit(
                "operation:z",
                kind=ReviewUnitKind.OPERATION,
                scope="shared",
                tokens=1,
            ),
        )

        forward = plan_reviews(units, policy(per_packet_tokens=3))
        reverse = plan_reviews(reversed(units), policy(per_packet_tokens=3))

        self.assertEqual(forward, reverse)
        self.assertIsInstance(forward, PlannedReview)
        for reviewer in ReviewClass:
            scoped = [
                packet
                for packet in forward.packets
                if packet.reviewer is reviewer and packet.scope == "journey:playback"
            ]
            self.assertEqual(
                [
                    [review_unit.ref for review_unit in packet.units]
                    for packet in scoped
                ],
                [["scenario:a", "scenario:b"], ["scenario:c"]],
            )

    def test_changing_one_scope_changes_only_its_packet_digests(self) -> None:
        base = (
            unit("scenario:a", scope="journey:a"),
            unit("scenario:b", scope="journey:b"),
        )
        changed = (
            replace(base[0], content_digest=canonical_digest({"changed": True})),
            base[1],
        )

        before = plan_reviews(base, policy())
        after = plan_reviews(changed, policy())

        def digests(plan, scope):
            return {
                packet.packet_digest
                for packet in plan.packets
                if packet.scope == scope
            }

        self.assertNotEqual(digests(before, "journey:a"), digests(after, "journey:a"))
        self.assertEqual(digests(before, "journey:b"), digests(after, "journey:b"))

    def test_packet_digest_binds_reviewer_scope_leaves_budget_and_policy(self) -> None:
        planned = plan_reviews((unit("scenario:a"),), policy())
        packet = planned.packets[0]
        other_reviewer = next(
            reviewer for reviewer in ReviewClass if reviewer is not packet.reviewer
        )
        variants = (
            replace(packet, reviewer=other_reviewer),
            replace(
                packet,
                scope="another-scope",
                units=(replace(packet.units[0], scope="another-scope"),),
            ),
            replace(
                packet,
                units=(
                    replace(
                        packet.units[0],
                        content_digest=canonical_digest({"different": True}),
                    ),
                ),
            ),
            replace(packet, approved_budget=budget(2, 2)),
            replace(packet, policy_digest=canonical_digest({"policy": "different"})),
        )
        for variant in variants:
            with self.subTest(variant=variant):
                self.assertNotEqual(packet.packet_digest, variant.packet_digest)

    def test_single_unit_and_total_shortfalls_report_distinct_errors(self) -> None:
        large = unit("scenario:large", tokens=4)
        self.assert_error(
            "review.unit.exceeds.packet.limit",
            lambda: plan_reviews((large,), policy(per_packet_tokens=3)),
        )
        pair = (unit("scenario:a", tokens=2), unit("scenario:b", tokens=2))
        self.assert_error(
            "review.total.budget.insufficient",
            lambda: plan_reviews(pair, policy(per_packet_tokens=3, total_tokens=11)),
        )


class ReviewApprovalTests(ReviewTestCase):
    def test_approval_returns_a_distinct_state_type(self) -> None:
        planned = plan_reviews((unit("scenario:a"),), policy())
        approved = approve_review_budgets(planned)

        self.assertIsInstance(planned, PlannedReview)
        self.assertIsInstance(approved, BudgetApprovedReview)
        self.assertNotIsInstance(planned, BudgetApprovedReview)

    def test_approval_requires_exactly_one_sufficient_approval_per_packet(self) -> None:
        planned = plan_reviews((unit("scenario:a"),), policy())
        approval = BudgetApproval(
            planned.packets[0].packet_id, planned.packets[0].approved_budget
        )
        self.assert_error(
            "review.missing.approval",
            lambda: approve_review_budgets(planned, ()),
        )
        self.assert_error(
            "review.duplicate.approval",
            lambda: approve_review_budgets(planned, (approval, approval)),
        )
        self.assert_error(
            "review.approved.budget.insufficient",
            lambda: approve_review_budgets(
                planned,
                tuple(
                    BudgetApproval(
                        packet.packet_id,
                        budget(0, 1)
                        if packet.packet_id == approval.packet_id
                        else packet.approved_budget,
                    )
                    for packet in planned.packets
                ),
            ),
        )


class ReviewCompletionTests(ReviewTestCase):
    def setUp(self) -> None:
        self.units = (unit("scenario:a"), unit("scenario:b"))
        self.approved = approve_review_budgets(plan_reviews(self.units, policy()))
        self.receipts = receipts_for(self.approved)
        self.catalog_root = canonical_digest({"catalog": "current"})

    def test_completes_only_with_all_three_review_classes(self) -> None:
        completed = complete_reviews(
            self.units, self.approved, self.receipts, self.catalog_root
        )

        self.assertIsInstance(completed, CompletedReview)
        self.assertEqual(
            {packet.reviewer for packet in completed.packets}, set(ReviewClass)
        )
        self.assertEqual(completed.catalog_root, self.catalog_root)

    def test_receipt_digest_binds_review_identity_report_decision_and_usage(
        self,
    ) -> None:
        receipt = self.receipts[0]
        other_reviewer = next(
            reviewer
            for reviewer in ReviewClass
            if reviewer is not receipt.reviewer
        )
        variants = {
            "packet": replace(
                receipt,
                packet_digest=canonical_digest({"packet": "changed"}),
            ),
            "reviewer": replace(
                receipt,
                reviewer=other_reviewer,
                assessment_digest=(
                    receipt.assessment_digest
                    if other_reviewer is ReviewClass.AGENT_OPERABILITY
                    else None
                ),
            ),
            "actor": replace(
                receipt,
                actor=replace(receipt.actor, actor_id="actor:replacement"),
            ),
            "environment": replace(
                receipt,
                actor=replace(
                    receipt.actor,
                    environment_digest=canonical_digest(
                        {"environment": "changed"}
                    ),
                ),
            ),
            "report": replace(
                receipt,
                report_digest=canonical_digest({"report": "changed"}),
            ),
            "decision": replace(receipt, accepted=False),
            "usage": replace(receipt, usage=usage(tokens=0, items=0)),
            "issuedAt": replace(
                receipt, issued_at="2026-08-28T00:00:01Z"
            ),
        }
        agent = next(
            item
            for item in self.receipts
            if item.reviewer is ReviewClass.AGENT_OPERABILITY
        )

        self.assertEqual(receipt.digest, receipt.receipt_digest)
        for field_name, variant in variants.items():
            with self.subTest(field_name=field_name):
                self.assertNotEqual(receipt.receipt_digest, variant.receipt_digest)
        self.assertNotEqual(
            agent.receipt_digest,
            replace(
                agent,
                assessment_digest=canonical_digest({"assessment": "changed"}),
            ).receipt_digest,
        )

    def test_receipt_requires_actor_report_and_issue_time(self) -> None:
        receipt = self.receipts[0]

        self.assert_error(
            "review.invalid.actor",
            lambda: replace(receipt, actor="agent:untyped"),
        )
        self.assert_error(
            "identifier.invalid_format",
            lambda: replace(receipt, report_digest="not-a-digest"),
        )
        self.assert_error(
            "review.empty.value",
            lambda: replace(receipt, issued_at=" "),
        )

    def test_completion_digest_uses_current_partition_and_receipt_digests(
        self,
    ) -> None:
        completed = complete_reviews(
            self.units, self.approved, self.receipts, self.catalog_root
        )

        self.assertEqual(
            completed.completion_digest,
            canonical_digest(
                {
                    "catalogDigest": str(self.catalog_root),
                    "packetPartition": [
                        str(packet.packet_digest)
                        for packet in completed.packets
                    ],
                    "receiptDigests": sorted(
                        str(receipt.receipt_digest)
                        for receipt in completed.receipts
                    ),
                }
            ),
        )

        changed_receipt = replace(
            completed.receipts[0],
            actor=replace(
                completed.receipts[0].actor,
                actor_id="checker:replacement",
            ),
        )
        changed = replace(
            completed,
            receipts=(changed_receipt,) + completed.receipts[1:],
        )
        self.assertNotEqual(completed.completion_digest, changed.completion_digest)

    def test_reuses_unchanged_packet_receipts_after_an_unrelated_scope_change(
        self,
    ) -> None:
        original_units = (
            unit("scenario:a", scope="journey:a"),
            unit("scenario:b", scope="journey:b"),
        )
        original = approve_review_budgets(
            plan_reviews(original_units, policy())
        )
        original_receipts = receipts_for(original)
        original_by_packet = {
            receipt.packet_digest: receipt for receipt in original_receipts
        }

        current_units = (
            original_units[0],
            replace(
                original_units[1],
                content_digest=canonical_digest({"scenario:b": "changed"}),
            ),
        )
        current = approve_review_budgets(plan_reviews(current_units, policy()))
        fresh_by_packet = {
            receipt.packet_digest: receipt for receipt in receipts_for(current)
        }
        adopted_receipts = tuple(
            original_by_packet.get(
                packet.packet_digest,
                fresh_by_packet[packet.packet_digest],
            )
            for packet in current.packets
        )

        completed = complete_reviews(
            current_units,
            current,
            adopted_receipts,
            canonical_digest({"catalog": "after-change"}),
        )
        unchanged_packet_digests = {
            packet.packet_digest
            for packet in current.packets
            if packet.scope == "journey:a"
        }
        self.assertTrue(unchanged_packet_digests)
        self.assertTrue(
            all(
                receipt is original_by_packet[receipt.packet_digest]
                for receipt in completed.receipts
                if receipt.packet_digest in unchanged_packet_digests
            )
        )

        stale_packet = next(
            packet
            for packet in original.packets
            if packet.scope == "journey:b"
        )
        spliced = replace(
            current,
            packets=tuple(
                stale_packet
                if packet.scope == stale_packet.scope
                and packet.reviewer is stale_packet.reviewer
                else packet
                for packet in current.packets
            ),
        )
        self.assert_error(
            "review.packet.partition.mismatch",
            lambda: complete_reviews(
                current_units,
                spliced,
                receipts_for(spliced),
                canonical_digest({"catalog": "after-change"}),
            ),
        )

    def test_rejects_missing_overlap_extra_and_stale_packet_coverage(self) -> None:
        missing_packet = replace(self.approved, packets=self.approved.packets[1:])
        self.assert_error(
            "review.packet.partition.mismatch",
            lambda: complete_reviews(
                self.units, missing_packet, self.receipts[1:], self.catalog_root
            ),
        )

        duplicate_packet = replace(
            self.approved,
            packets=self.approved.packets + (self.approved.packets[0],),
        )
        self.assert_error(
            "review.duplicate.packet.partition",
            lambda: complete_reviews(
                self.units,
                duplicate_packet,
                self.receipts,
                self.catalog_root,
            ),
        )

        changed_units = (
            replace(
                self.units[0], content_digest=canonical_digest({"catalog": "new"})
            ),
            self.units[1],
        )
        self.assert_error(
            "review.stale.plan",
            lambda: complete_reviews(
                changed_units, self.approved, self.receipts, self.catalog_root
            ),
        )

    def test_rejects_a_different_split_even_when_leaf_coverage_is_equal(self) -> None:
        units = (
            unit("scenario:a"),
            unit("scenario:b"),
        )
        approved = approve_review_budgets(
            plan_reviews(units, policy(per_packet_tokens=1))
        )
        packets = list(approved.packets)
        same_reviewer = [
            packet
            for packet in packets
            if packet.reviewer is ReviewClass.HUMAN_COVERAGE
        ]
        merged = replace(
            same_reviewer[0],
            units=same_reviewer[0].units + same_reviewer[1].units,
            approved_budget=budget(2, 2),
        )
        spliced = replace(
            approved,
            packets=tuple(
                packet
                for packet in packets
                if packet not in same_reviewer
            )
            + (merged,),
        )

        self.assert_error(
            "review.packet.partition.mismatch",
            lambda: complete_reviews(
                units,
                spliced,
                receipts_for(spliced),
                self.catalog_root,
            ),
        )

    def test_rejects_receipt_mismatch_rejection_overuse_and_duplicates(
        self,
    ) -> None:
        first = self.receipts[0]
        other_reviewer = next(
            reviewer
            for reviewer in ReviewClass
            if reviewer is not first.reviewer
        )
        self.assert_error(
            "review.receipt.packet.mismatch",
            lambda: complete_reviews(
                self.units,
                self.approved,
                (replace(first, packet_digest=canonical_digest({"old": True})),)
                + self.receipts[1:],
                self.catalog_root,
            ),
        )
        self.assert_error(
            "review.receipt.reviewer.mismatch",
            lambda: complete_reviews(
                self.units,
                self.approved,
                (
                    replace(
                        first,
                        reviewer=other_reviewer,
                        assessment_digest=(
                            first.assessment_digest
                            if other_reviewer is ReviewClass.AGENT_OPERABILITY
                            else None
                        ),
                    ),
                )
                + self.receipts[1:],
                self.catalog_root,
            ),
        )
        self.assert_error(
            "review.receipt.rejected",
            lambda: complete_reviews(
                self.units,
                self.approved,
                (replace(first, accepted=False),) + self.receipts[1:],
                self.catalog_root,
            ),
        )
        self.assert_error(
            "review.receipt.usage.exceeds.budget",
            lambda: complete_reviews(
                self.units,
                self.approved,
                (replace(first, usage=usage(tokens=99)),) + self.receipts[1:],
                self.catalog_root,
            ),
        )
        self.assert_error(
            "review.receipt.usage.exceeds.budget",
            lambda: complete_reviews(
                self.units,
                self.approved,
                (
                    replace(
                        first,
                        usage=ReviewUsage(
                            (BudgetAmount(BudgetUnit.OUTPUT_TOKENS, 1),)
                        ),
                    ),
                )
                + self.receipts[1:],
                self.catalog_root,
            ),
        )
        self.assert_error(
            "review.receipt.usage.exceeds.budget",
            lambda: complete_reviews(
                self.units,
                self.approved,
                (
                    replace(
                        first,
                        usage=ReviewUsage(
                            (
                                BudgetAmount(BudgetUnit.INPUT_TOKENS, 0),
                                BudgetAmount(BudgetUnit.REVIEW_ITEMS, 99),
                            )
                        ),
                    ),
                )
                + self.receipts[1:],
                self.catalog_root,
            ),
        )
        self.assert_error(
            "review.duplicate.receipt",
            lambda: complete_reviews(
                self.units,
                self.approved,
                self.receipts + (first,),
                self.catalog_root,
            ),
        )
        self.assert_error(
            "review.missing.receipt",
            lambda: complete_reviews(
                self.units, self.approved, self.receipts[1:], self.catalog_root
            ),
        )

    def test_budget_shortfall_cannot_be_traded_for_acceptance(self) -> None:
        packet = self.approved.packets[0]
        undersized = replace(packet, approved_budget=budget(0, 1))
        approved = replace(
            self.approved,
            packets=(undersized,) + self.approved.packets[1:],
        )
        receipts = receipts_for(approved)

        self.assert_error(
            "review.approved.budget.insufficient",
            lambda: complete_reviews(self.units, approved, receipts, self.catalog_root),
        )

    def test_completion_rechecks_packet_and_total_approval_limits(self) -> None:
        packet = self.approved.packets[0]
        oversized = replace(packet, approved_budget=budget(4, 4))
        oversized_approval = replace(
            self.approved,
            packets=(oversized,) + self.approved.packets[1:],
        )
        self.assert_error(
            "review.approval.exceeds.packet.limit",
            lambda: complete_reviews(
                self.units,
                oversized_approval,
                receipts_for(oversized_approval),
                self.catalog_root,
            ),
        )

        tight_policy = policy(per_packet_tokens=3, total_tokens=6)
        tight_approval = approve_review_budgets(
            plan_reviews(self.units, tight_policy)
        )
        expanded_packet = replace(
            tight_approval.packets[0], approved_budget=budget(3, 3)
        )
        expanded_approval = replace(
            tight_approval,
            packets=(expanded_packet,) + tight_approval.packets[1:],
        )
        self.assert_error(
            "review.approval.exceeds.total.budget",
            lambda: complete_reviews(
                self.units,
                expanded_approval,
                receipts_for(expanded_approval),
                self.catalog_root,
            ),
        )

    def test_review_classes_cannot_be_removed_to_reduce_budget(self) -> None:
        reduced_reviewers = frozenset(
            (
                ReviewClass.HUMAN_COVERAGE,
                ReviewClass.AGENT_OPERABILITY,
            )
        )
        reduced_units = tuple(
            replace(review_unit, required_reviewers=reduced_reviewers)
            for review_unit in self.units
        )
        reduced = approve_review_budgets(
            plan_reviews(reduced_units, policy())
        )

        self.assert_error(
            "review.class.incomplete",
            lambda: complete_reviews(
                reduced_units,
                reduced,
                receipts_for(reduced),
                self.catalog_root,
            ),
        )

    def test_completion_binds_catalog_root_and_complete_packet_partition(self) -> None:
        completed = complete_reviews(
            self.units, self.approved, self.receipts, self.catalog_root
        )
        changed_catalog = complete_reviews(
            self.units,
            self.approved,
            self.receipts,
            canonical_digest({"catalog": "another"}),
        )
        self.assertNotEqual(
            completed.completion_digest, changed_catalog.completion_digest
        )

        changed_partition = replace(
            completed, packets=completed.packets[:-1]
        )
        self.assertNotEqual(
            completed.completion_digest, changed_partition.completion_digest
        )
        self.assertFalse(hasattr(self.receipts[0], "catalog_root"))


class PythonCompatibilityTests(unittest.TestCase):
    def test_module_parses_as_python_3_9(self) -> None:
        source = (REGRESSION_SCRIPTS / "core" / "review.py").read_text(
            encoding="utf-8"
        )
        ast.parse(source, filename="review.py", feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
