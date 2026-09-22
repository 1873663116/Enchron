from __future__ import annotations

import ast
from dataclasses import FrozenInstanceError
from pathlib import Path
import sys
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from regression.core.applicability import (
    AllFacts,
    AnyFact,
    Constant,
    FactEquals,
    NotFact,
    ReviewedFact,
    evaluate_applicability,
    parse_applicability,
    referenced_facts,
    reviewed_facts_digest,
)
from regression.core.errors import RegressionError
from regression.core.ids import Digest, FactID


HDR = FactID("fact:media-library-has-hdr")
REMOTE = FactID("fact:remote-library-available")
PROFILE = FactID("fact:preferred-playback-profile")
SOURCE_A = Digest("sha256:" + "a" * 64)
SOURCE_B = Digest("sha256:" + "b" * 64)
REVIEW_A = Digest("sha256:" + "c" * 64)
REVIEW_B = Digest("sha256:" + "d" * 64)


def reviewed(
    fact_id: FactID,
    value,
    source_digest: Digest = SOURCE_A,
    review_digest=REVIEW_A,
) -> ReviewedFact:
    return ReviewedFact(fact_id, value, source_digest, review_digest)


class ApplicabilityTestCase(unittest.TestCase):
    def assert_error(self, code: str, call) -> RegressionError:
        with self.assertRaises(RegressionError) as context:
            call()
        self.assertEqual(code, context.exception.code)
        return context.exception


class ParseApplicabilityTests(ApplicabilityTestCase):
    def test_parses_every_wire_shape_into_a_frozen_ast(self) -> None:
        payload = {
            "all": [
                {"constant": True},
                {"factEquals": {"fact": str(HDR), "value": True}},
                {
                    "any": [
                        {
                            "factEquals": {
                                "fact": str(PROFILE),
                                "value": "cinema",
                            }
                        },
                        {"not": {"constant": False}},
                    ]
                },
            ]
        }

        parsed = parse_applicability(payload)

        self.assertEqual(
            parsed,
            AllFacts(
                (
                    Constant(True),
                    FactEquals(HDR, True),
                    AnyFact(
                        (
                            FactEquals(PROFILE, "cinema"),
                            NotFact(Constant(False)),
                        )
                    ),
                )
            ),
        )
        with self.assertRaises(FrozenInstanceError):
            parsed.terms = ()

    def test_rejects_non_object_unknown_keys_empty_and_mixed_operators(self) -> None:
        self.assert_error(
            "applicability.not_object", lambda: parse_applicability([])
        )
        error = self.assert_error(
            "applicability.unknown_key",
            lambda: parse_applicability({"script": "return true"}),
        )
        self.assertIn("script", error.detail)
        self.assert_error(
            "applicability.unknown_key",
            lambda: parse_applicability(
                {"constant": True, "unexpected": False}
            ),
        )
        self.assert_error(
            "applicability.mixed_operators",
            lambda: parse_applicability({}),
        )
        self.assert_error(
            "applicability.mixed_operators",
            lambda: parse_applicability(
                {"constant": True, "not": {"constant": False}}
            ),
        )

    def test_constant_requires_an_actual_boolean(self) -> None:
        for value in (1, 0, "true", None, [], {}):
            with self.subTest(value=value):
                self.assert_error(
                    "applicability.constant_not_bool",
                    lambda value=value: parse_applicability(
                        {"constant": value}
                    ),
                )

    def test_fact_equals_requires_exact_known_keys(self) -> None:
        self.assert_error(
            "applicability.fact_equals_not_object",
            lambda: parse_applicability({"factEquals": str(HDR)}),
        )
        for payload in ({}, {"fact": str(HDR)}, {"value": True}):
            with self.subTest(payload=payload):
                self.assert_error(
                    "applicability.fact_equals_keys",
                    lambda payload=payload: parse_applicability(
                        {"factEquals": payload}
                    ),
                )
        error = self.assert_error(
            "applicability.fact_equals_unknown_key",
            lambda: parse_applicability(
                {
                    "factEquals": {
                        "fact": str(HDR),
                        "value": True,
                        "source": "runtime",
                    }
                }
            ),
        )
        self.assertIn("source", error.detail)

    def test_fact_equals_requires_a_valid_fact_id_and_fact_value(self) -> None:
        error = self.assert_error(
            "identifier.invalid_format",
            lambda: parse_applicability(
                {
                    "factEquals": {
                        "fact": "scenario:not-a-fact",
                        "value": True,
                    }
                }
            ),
        )
        self.assertEqual("$.factEquals.fact", error.location)

        for value in (None, 1.5, [], {}, ("tuple",)):
            with self.subTest(value=value):
                self.assert_error(
                    "applicability.invalid_fact_value",
                    lambda value=value: parse_applicability(
                        {
                            "factEquals": {
                                "fact": str(HDR),
                                "value": value,
                            }
                        }
                    ),
                )

    def test_all_and_any_require_non_empty_arrays(self) -> None:
        for operator in ("all", "any"):
            with self.subTest(operator=operator, problem="not-list"):
                self.assert_error(
                    "applicability.terms_not_list",
                    lambda operator=operator: parse_applicability(
                        {operator: {"constant": True}}
                    ),
                )
            with self.subTest(operator=operator, problem="empty"):
                self.assert_error(
                    "applicability.empty_terms",
                    lambda operator=operator: parse_applicability(
                        {operator: []}
                    ),
                )

    def test_depth_limit_is_inclusive_and_reports_the_nested_location(self) -> None:
        payload = {"not": {"not": {"constant": True}}}
        self.assertIsInstance(
            parse_applicability(payload, max_depth=2), NotFact
        )
        error = self.assert_error(
            "applicability.too_deep",
            lambda: parse_applicability(payload, max_depth=1),
        )
        self.assertEqual("$.not.not", error.location)

        for limit in (-1, True, 1.5, "64"):
            with self.subTest(limit=limit):
                self.assert_error(
                    "applicability.invalid_depth_limit",
                    lambda limit=limit: parse_applicability(
                        {"constant": True}, max_depth=limit
                    ),
                )

    def test_default_depth_limit_is_exactly_sixty_four(self) -> None:
        at_limit = {"constant": True}
        for _ in range(64):
            at_limit = {"not": at_limit}
        self.assertIsInstance(parse_applicability(at_limit), NotFact)

        beyond_limit = {"not": at_limit}
        self.assert_error(
            "applicability.too_deep",
            lambda: parse_applicability(beyond_limit),
        )


class ReviewedFactTests(ApplicabilityTestCase):
    def test_reviewed_fact_is_frozen_and_accepts_only_fact_values(self) -> None:
        fact = reviewed(HDR, 1)
        with self.assertRaises(FrozenInstanceError):
            fact.value = 2

        for value in (None, 1.5, [], {}, ("tuple",)):
            with self.subTest(value=value):
                self.assert_error(
                    "applicability.invalid_fact_value",
                    lambda value=value: reviewed(HDR, value),
                )

    def test_reviewed_fact_validates_fact_and_digest_identifiers(self) -> None:
        cases = (
            (
                "identifier.invalid_format",
                lambda: ReviewedFact(
                    FactID("scenario:not-a-fact"), True, SOURCE_A, REVIEW_A
                ),
            ),
            (
                "identifier.invalid_format",
                lambda: ReviewedFact(
                    HDR, True, Digest("sha256:short"), REVIEW_A
                ),
            ),
            (
                "identifier.invalid_format",
                lambda: ReviewedFact(
                    HDR, True, SOURCE_A, Digest("sha256:short")
                ),
            ),
        )
        for code, call in cases:
            with self.subTest(call=call):
                self.assert_error(code, call)

    def test_missing_review_digest_can_reach_fail_closed_evaluation(
        self,
    ) -> None:
        fact = reviewed(HDR, True, review_digest=None)
        self.assertIsNone(fact.review_receipt_digest)


class EvaluateApplicabilityTests(ApplicabilityTestCase):
    def test_combines_constant_fact_all_any_and_not_semantics(self) -> None:
        expression = AllFacts(
            (
                Constant(True),
                FactEquals(HDR, True),
                AnyFact(
                    (
                        FactEquals(PROFILE, "flat"),
                        NotFact(FactEquals(REMOTE, True)),
                    )
                ),
            )
        )
        facts = (
            reviewed(HDR, True),
            reviewed(REMOTE, False),
            reviewed(PROFILE, "cinema"),
        )

        self.assertTrue(evaluate_applicability(expression, facts))
        self.assertFalse(
            evaluate_applicability(
                expression,
                (
                    reviewed(HDR, False),
                    reviewed(REMOTE, False),
                    reviewed(PROFILE, "cinema"),
                ),
            )
        )
        self.assertFalse(evaluate_applicability(Constant(False), facts))

    def test_bool_and_int_values_do_not_compare_as_equal(self) -> None:
        self.assertFalse(
            evaluate_applicability(
                FactEquals(HDR, True), (reviewed(HDR, 1),)
            )
        )
        self.assertFalse(
            evaluate_applicability(
                FactEquals(HDR, 1), (reviewed(HDR, True),)
            )
        )

    def test_unknown_fact_is_rejected_even_under_not_or_true_any_branch(self) -> None:
        unknown = FactEquals(HDR, True)
        for expression in (
            unknown,
            NotFact(unknown),
            AnyFact((Constant(True), unknown)),
        ):
            with self.subTest(expression=expression), self.assertRaises(
                RegressionError
            ) as found:
                evaluate_applicability(expression, ())
            self.assertEqual("applicability.unknown_fact", found.exception.code)

    def test_missing_review_digest_is_rejected_even_under_not(self) -> None:
        facts = (reviewed(HDR, True, review_digest=None),)
        for expression in (
            FactEquals(HDR, True),
            NotFact(FactEquals(HDR, False)),
        ):
            with self.subTest(expression=expression), self.assertRaises(
                RegressionError
            ) as found:
                evaluate_applicability(expression, facts)
            self.assertEqual("applicability.unreviewed_fact", found.exception.code)

    def test_unreferenced_facts_do_not_change_constant_semantics(self) -> None:
        self.assertTrue(
            evaluate_applicability(
                Constant(True),
                (reviewed(HDR, True, review_digest=None),),
            )
        )

    def test_referenced_facts_are_unique(self) -> None:
        expression = AllFacts(
            (
                FactEquals(HDR, True),
                NotFact(FactEquals(REMOTE, False)),
                FactEquals(HDR, False),
            )
        )
        self.assertEqual(referenced_facts(expression), frozenset((HDR, REMOTE)))

    def test_duplicate_and_non_reviewed_fact_entries_are_rejected(self) -> None:
        duplicate = (reviewed(HDR, True), reviewed(HDR, False))
        error = self.assert_error(
            "applicability.duplicate_fact",
            lambda: evaluate_applicability(Constant(True), duplicate),
        )
        self.assertEqual("$reviewedFacts[1].id", error.location)
        self.assertIn(str(HDR), error.detail)

        self.assert_error(
            "applicability.invalid_reviewed_fact",
            lambda: evaluate_applicability(Constant(True), (object(),)),
        )


class ReviewedFactsDigestTests(ApplicabilityTestCase):
    def test_digest_is_stable_across_input_order_and_iterable_type(self) -> None:
        facts = (
            reviewed(REMOTE, False, SOURCE_B, REVIEW_B),
            reviewed(HDR, True, SOURCE_A, REVIEW_A),
            reviewed(PROFILE, "cinema", SOURCE_A, None),
        )

        expected = reviewed_facts_digest(facts)

        self.assertEqual(expected, reviewed_facts_digest(reversed(facts)))
        self.assertEqual(expected, reviewed_facts_digest(iter(facts)))
        self.assertTrue(expected.startswith("sha256:"))

    def test_digest_binds_id_value_source_and_review_digests(self) -> None:
        baseline = (reviewed(HDR, True, SOURCE_A, REVIEW_A),)
        variants = (
            (reviewed(REMOTE, True, SOURCE_A, REVIEW_A),),
            (reviewed(HDR, False, SOURCE_A, REVIEW_A),),
            (reviewed(HDR, True, SOURCE_B, REVIEW_A),),
            (reviewed(HDR, True, SOURCE_A, REVIEW_B),),
            (reviewed(HDR, True, SOURCE_A, None),),
        )

        baseline_digest = reviewed_facts_digest(baseline)
        for variant in variants:
            with self.subTest(variant=variant):
                self.assertNotEqual(
                    baseline_digest, reviewed_facts_digest(variant)
                )

    def test_digest_rejects_duplicate_fact_ids(self) -> None:
        duplicate = (reviewed(HDR, True), reviewed(HDR, True))
        self.assert_error(
            "applicability.duplicate_fact",
            lambda: reviewed_facts_digest(duplicate),
        )


class PythonCompatibilityTests(unittest.TestCase):
    def test_module_and_tests_parse_as_python_3_9(self) -> None:
        paths = (
            REPOSITORY_ROOT / "Scripts/regression/core/applicability.py",
            REPOSITORY_ROOT
            / "Scripts/rules/tests/test_regression_core_applicability.py",
        )
        for path in paths:
            with self.subTest(path=path):
                ast.parse(
                    path.read_text(encoding="utf-8"),
                    filename=str(path),
                    feature_version=(3, 9),
                )


if __name__ == "__main__":
    unittest.main()
