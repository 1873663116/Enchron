#!/usr/bin/env python3

from __future__ import annotations

import ast
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest


SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.digest import canonical_bytes, canonical_digest
from regression.core.errors import RegressionError
from regression.core.review import (
    BudgetAmount,
    BudgetUnit,
    ReviewActorIdentity,
    ReviewClass,
    ReviewReceipt,
    ReviewUsage,
)
from regression.review_io import (
    load_review_policy,
    load_review_receipt,
    load_review_receipts,
    load_review_report,
    receipt_path,
    review_receipt_payload,
    write_review_receipt,
    write_review_report,
)


def receipt(reviewer: ReviewClass = ReviewClass.DETERMINISTIC) -> ReviewReceipt:
    return ReviewReceipt(
        canonical_digest({"packet": reviewer.value}),
        reviewer,
        ReviewActorIdentity(
            "checker:catalog",
            canonical_digest({"environment": "python39", "version": 1}),
        ),
        canonical_digest({"report": reviewer.value}),
        True,
        ReviewUsage(
            (
                BudgetAmount(BudgetUnit.INPUT_TOKENS, 7),
                BudgetAmount(BudgetUnit.REVIEW_ITEMS, 1),
            )
        ),
        "2026-08-28T15:00:00Z",
    )


class ReviewIOTests(unittest.TestCase):
    def test_loads_strict_json_frontmatter_policy(self) -> None:
        with TemporaryDirectory() as temporary:
            path = Path(temporary) / "review-policy.md"
            path.write_text(
                "---\n"
                '{"perPacketLimit":{"inputTokens":100,"reviewItems":5},'
                '"schema":"enchron.regression.review-policy",'
                '"schemaVersion":1,'
                '"totalBudget":{"inputTokens":1000,"reviewItems":50}}\n'
                "---\nPolicy rationale.\n",
                encoding="utf-8",
            )
            policy = load_review_policy(path)
            self.assertEqual(
                policy.per_packet_limit.amount_for(BudgetUnit.REVIEW_ITEMS), 5
            )
            self.assertEqual(
                policy.total_budget.amount_for(BudgetUnit.INPUT_TOKENS), 1000
            )

    def test_receipt_round_trip_binds_path_and_canonical_wire(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = receipt()
            path = write_review_receipt(root, expected)

            self.assertEqual(path, receipt_path(root, expected))
            self.assertEqual(load_review_receipt(path), expected)
            self.assertEqual(load_review_receipts(root), (expected,))
            self.assertEqual(
                path.read_bytes(),
                canonical_bytes(review_receipt_payload(expected)) + b"\n",
            )
            self.assertEqual(write_review_receipt(root, expected), path)

    def test_tamper_noncanonical_json_and_wrong_path_fail_closed(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = receipt()
            path = write_review_receipt(root, expected)
            value = dict(review_receipt_payload(expected))
            value["receiptDigest"] = "sha256:" + "0" * 64
            path.write_bytes(canonical_bytes(value) + b"\n")
            with self.assertRaises(RegressionError) as mismatch:
                load_review_receipt(path)
            self.assertEqual(
                mismatch.exception.code, "review.io.receipt_digest_mismatch"
            )

            path.write_bytes(canonical_bytes(review_receipt_payload(expected)))
            with self.assertRaises(RegressionError) as noncanonical:
                load_review_receipt(path)
            self.assertEqual(
                noncanonical.exception.code, "review.io.noncanonical_json"
            )

            path.write_bytes(
                canonical_bytes(review_receipt_payload(expected)) + b"\n"
            )
            wrong = root / "agent-operability" / path.name
            wrong.parent.mkdir()
            path.replace(wrong)
            with self.assertRaises(RegressionError) as wrong_path:
                load_review_receipts(root)
            self.assertEqual(
                wrong_path.exception.code, "review.io.invalid_receipt_path"
            )

    def test_report_store_is_content_addressed_and_detects_tamper(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            digest, path = write_review_report(root, "# Result\r\n\r\nAccepted.")
            self.assertEqual(load_review_report(root, digest), "# Result\n\nAccepted.\n")
            self.assertEqual(write_review_report(root, "# Result\n\nAccepted."), (digest, path))

            path.write_text("changed\n", encoding="utf-8")
            with self.assertRaises(RegressionError) as mismatch:
                load_review_report(root, digest)
            self.assertEqual(
                mismatch.exception.code, "review.io.report_digest_mismatch"
            )

    def test_concurrent_publication_is_atomic_and_leaves_no_temporary_files(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected_receipt = receipt()
            report = "# Concurrent review\n\nAccepted."

            with ThreadPoolExecutor(max_workers=8) as executor:
                report_results = tuple(
                    executor.map(
                        lambda _: write_review_report(root, report),
                        range(32),
                    )
                )
                receipt_paths = tuple(
                    executor.map(
                        lambda _: write_review_receipt(root, expected_receipt),
                        range(32),
                    )
                )

            self.assertEqual(len(set(report_results)), 1)
            self.assertEqual(len(set(receipt_paths)), 1)
            report_digest, report_path = report_results[0]
            self.assertEqual(
                load_review_report(root, report_digest),
                "# Concurrent review\n\nAccepted.\n",
            )
            self.assertEqual(
                load_review_receipt(receipt_paths[0]), expected_receipt
            )
            self.assertTrue(report_path.is_file())
            self.assertEqual(
                tuple(root.rglob(".review-*")),
                (),
            )

    def test_rejects_unknown_policy_units_and_receipt_fields(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            policy = root / "review-policy.md"
            policy.write_text(
                "---\n"
                '{"perPacketLimit":{"tokens":1},'
                '"schema":"enchron.regression.review-policy",'
                '"schemaVersion":1,"totalBudget":{"tokens":1}}\n'
                "---\nReason.\n",
                encoding="utf-8",
            )
            with self.assertRaises(RegressionError) as unit_error:
                load_review_policy(policy)
            self.assertEqual(
                unit_error.exception.code, "review.io.unknown_budget_unit"
            )

            expected = receipt()
            path = receipt_path(root, expected)
            path.parent.mkdir(parents=True)
            value = dict(review_receipt_payload(expected))
            value["unexpected"] = True
            path.write_bytes(canonical_bytes(value) + b"\n")
            with self.assertRaises(RegressionError) as field_error:
                load_review_receipt(path)
            self.assertEqual(field_error.exception.code, "review.io.unknown_field")

    def test_receipt_json_rejects_duplicate_fields_and_nonfinite_numbers(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = receipt()
            path = receipt_path(root, expected)
            path.parent.mkdir(parents=True)
            path.write_bytes(b'{"schema":1,"schema":1}\n')
            with self.assertRaises(RegressionError) as duplicate:
                load_review_receipt(path)
            self.assertEqual(duplicate.exception.code, "review.io.duplicate_field")

            path.write_bytes(b'{"usage":NaN}\n')
            with self.assertRaises(RegressionError) as constant:
                load_review_receipt(path)
            self.assertEqual(constant.exception.code, "review.io.invalid_json")

    def test_module_parses_with_python_39_grammar(self) -> None:
        path = SCRIPTS / "regression/review_io.py"
        ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
