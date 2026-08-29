from __future__ import annotations

import ast
import json
import sys
import unittest
from dataclasses import FrozenInstanceError
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REGRESSION_SCRIPTS = ROOT / "Scripts" / "regression"
if str(REGRESSION_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(REGRESSION_SCRIPTS))

from core.errors import RegressionError
from core.expression import (
    AllOf,
    AnyOf,
    AtLeast,
    Not,
    ObservationRef,
    OracleResult,
    evaluate_success,
    parse_success_expression,
    referenced_obligations,
    validate_expression_obligations,
    validate_expression_semantics,
)
from core.ids import ObligationID


ONE = ObligationID("obligation:playback-starts-one")
TWO = ObligationID("obligation:playback-starts-two")
THREE = ObligationID("obligation:playback-starts-three")


class ExpressionTestCase(unittest.TestCase):
    def assert_error(self, code: str, call) -> RegressionError:
        with self.assertRaises(RegressionError) as context:
            call()
        self.assertEqual(context.exception.code, code)
        return context.exception


class ParseSuccessExpressionTests(ExpressionTestCase):
    def test_parses_every_wire_shape_into_a_frozen_ast(self) -> None:
        payload = {
            "all": [
                {"observation": str(ONE)},
                {"any": [{"observation": str(TWO)}]},
                {"not": {"observation": str(THREE)}},
                {
                    "atLeast": {
                        "count": 1,
                        "of": [{"observation": str(ONE)}],
                    }
                },
            ]
        }

        parsed = parse_success_expression(json.loads(json.dumps(payload)))

        self.assertEqual(
            parsed,
            AllOf(
                (
                    ObservationRef(ONE),
                    AnyOf((ObservationRef(TWO),)),
                    Not(ObservationRef(THREE)),
                    AtLeast(1, (ObservationRef(ONE),)),
                )
            ),
        )
        with self.assertRaises(FrozenInstanceError):
            parsed.terms = ()

    def test_locations_identify_the_invalid_nested_value(self) -> None:
        error = self.assert_error(
            "expression.empty_terms",
            lambda: parse_success_expression(
                {"not": {"all": []}}, location="$.scenario.success"
            ),
        )
        self.assertEqual(error.location, "$.scenario.success.not.all")

    def test_rejects_non_object_unknown_keys_and_mixed_operators(self) -> None:
        self.assert_error(
            "expression.not_object", lambda: parse_success_expression([])
        )
        self.assert_error(
            "expression.unknown_key",
            lambda: parse_success_expression({"script": "return true"}),
        )
        self.assert_error(
            "expression.mixed_operators",
            lambda: parse_success_expression(
                {"observation": str(ONE), "not": {"observation": str(TWO)}}
            ),
        )
        self.assert_error(
            "expression.mixed_operators", lambda: parse_success_expression({})
        )

    def test_observation_must_contain_a_valid_obligation_identifier(self) -> None:
        error = self.assert_error(
            "identifier.invalid_format",
            lambda: parse_success_expression(
                {"observation": "scenario:not-an-obligation"}
            ),
        )
        self.assertEqual(error.location, "$.observation")

    def test_rejects_non_list_and_empty_all_or_any_terms(self) -> None:
        for operator in ("all", "any"):
            with self.subTest(operator=operator, problem="not-list"):
                self.assert_error(
                    "expression.terms_not_list",
                    lambda operator=operator: parse_success_expression(
                        {operator: {"observation": str(ONE)}}
                    ),
                )
            with self.subTest(operator=operator, problem="empty"):
                self.assert_error(
                    "expression.empty_terms",
                    lambda operator=operator: parse_success_expression({operator: []}),
                )

    def test_rejects_malformed_at_least_payloads(self) -> None:
        self.assert_error(
            "expression.at_least_not_object",
            lambda: parse_success_expression({"atLeast": []}),
        )
        for payload in (
            {"count": 1},
            {"of": [{"observation": str(ONE)}]},
            {"count": 1, "of": [{"observation": str(ONE)}], "extra": True},
        ):
            with self.subTest(payload=payload):
                self.assert_error(
                    "expression.at_least_keys",
                    lambda payload=payload: parse_success_expression(
                        {"atLeast": payload}
                    ),
                )
        self.assert_error(
            "expression.terms_not_list",
            lambda: parse_success_expression({"atLeast": {"count": 1, "of": {}}}),
        )
        self.assert_error(
            "expression.empty_terms",
            lambda: parse_success_expression({"atLeast": {"count": 1, "of": []}}),
        )

    def test_rejects_boolean_non_integer_and_out_of_range_counts(self) -> None:
        terms = [{"observation": str(ONE)}, {"observation": str(TWO)}]
        for count in (True, 1.0, "1", 0, -1, 3):
            with self.subTest(count=count):
                self.assert_error(
                    "expression.invalid_count",
                    lambda count=count: parse_success_expression(
                        {"atLeast": {"count": count, "of": terms}}
                    ),
                )

    def test_rejects_expressions_beyond_the_depth_limit(self) -> None:
        payload = {"not": {"not": {"observation": str(ONE)}}}
        self.assertIsInstance(
            parse_success_expression(payload, max_depth=2), Not
        )
        error = self.assert_error(
            "expression.too_deep",
            lambda: parse_success_expression(payload, max_depth=1),
        )
        self.assertEqual(error.location, "$.not.not")


class EvaluateSuccessExpressionTests(ExpressionTestCase):
    def test_observation_and_not_cover_all_three_results(self) -> None:
        reference = ObservationRef(ONE)
        for result in OracleResult:
            with self.subTest(result=result):
                self.assertEqual(evaluate_success(reference, {ONE: result}), result)

        self.assertEqual(
            evaluate_success(Not(reference), {ONE: OracleResult.SATISFIED}),
            OracleResult.VIOLATED,
        )
        self.assertEqual(
            evaluate_success(Not(reference), {ONE: OracleResult.VIOLATED}),
            OracleResult.SATISFIED,
        )
        self.assertEqual(
            evaluate_success(Not(reference), {ONE: OracleResult.INDETERMINATE}),
            OracleResult.INDETERMINATE,
        )

    def test_all_covers_all_three_results(self) -> None:
        expression = AllOf((ObservationRef(ONE), ObservationRef(TWO)))
        cases = (
            ((OracleResult.SATISFIED, OracleResult.SATISFIED), OracleResult.SATISFIED),
            ((OracleResult.SATISFIED, OracleResult.VIOLATED), OracleResult.VIOLATED),
            (
                (OracleResult.SATISFIED, OracleResult.INDETERMINATE),
                OracleResult.INDETERMINATE,
            ),
        )
        for inputs, expected in cases:
            with self.subTest(inputs=inputs):
                self.assertEqual(
                    evaluate_success(expression, dict(zip((ONE, TWO), inputs))),
                    expected,
                )

    def test_any_covers_all_three_results(self) -> None:
        expression = AnyOf((ObservationRef(ONE), ObservationRef(TWO)))
        cases = (
            ((OracleResult.VIOLATED, OracleResult.SATISFIED), OracleResult.SATISFIED),
            ((OracleResult.VIOLATED, OracleResult.VIOLATED), OracleResult.VIOLATED),
            (
                (OracleResult.VIOLATED, OracleResult.INDETERMINATE),
                OracleResult.INDETERMINATE,
            ),
        )
        for inputs, expected in cases:
            with self.subTest(inputs=inputs):
                self.assertEqual(
                    evaluate_success(expression, dict(zip((ONE, TWO), inputs))),
                    expected,
                )

    def test_at_least_covers_all_three_results(self) -> None:
        expression = AtLeast(
            2, (ObservationRef(ONE), ObservationRef(TWO), ObservationRef(THREE))
        )
        cases = (
            (
                (
                    OracleResult.SATISFIED,
                    OracleResult.SATISFIED,
                    OracleResult.VIOLATED,
                ),
                OracleResult.SATISFIED,
            ),
            (
                (
                    OracleResult.SATISFIED,
                    OracleResult.VIOLATED,
                    OracleResult.VIOLATED,
                ),
                OracleResult.VIOLATED,
            ),
            (
                (
                    OracleResult.SATISFIED,
                    OracleResult.INDETERMINATE,
                    OracleResult.VIOLATED,
                ),
                OracleResult.INDETERMINATE,
            ),
        )
        for inputs, expected in cases:
            with self.subTest(inputs=inputs):
                self.assertEqual(
                    evaluate_success(expression, dict(zip((ONE, TWO, THREE), inputs))),
                    expected,
                )

    def test_nested_expression_evaluates_recursively(self) -> None:
        expression = Not(
            AnyOf(
                (
                    ObservationRef(ONE),
                    AllOf((ObservationRef(TWO), ObservationRef(THREE))),
                )
            )
        )
        self.assertEqual(
            evaluate_success(
                expression,
                {
                    ONE: OracleResult.VIOLATED,
                    TWO: OracleResult.SATISFIED,
                    THREE: OracleResult.VIOLATED,
                },
            ),
            OracleResult.SATISFIED,
        )

    def test_missing_result_is_rejected_even_if_boolean_short_circuit_would_decide(self) -> None:
        expression = AnyOf((ObservationRef(ONE), ObservationRef(TWO)))
        error = self.assert_error(
            "expression.missing_result",
            lambda: evaluate_success(expression, {ONE: OracleResult.SATISFIED}),
        )
        self.assertIn(str(TWO), error.detail)

    def test_extra_result_is_rejected_instead_of_becoming_hidden_evidence(self) -> None:
        error = self.assert_error(
            "expression.unknown_result",
            lambda: evaluate_success(
                ObservationRef(ONE),
                {
                    ONE: OracleResult.SATISFIED,
                    TWO: OracleResult.SATISFIED,
                },
            ),
        )
        self.assertIn(str(TWO), error.detail)

    def test_invalid_result_is_rejected_after_an_earlier_term_decides(self) -> None:
        expression = AnyOf((ObservationRef(ONE), ObservationRef(TWO)))
        error = self.assert_error(
            "expression.invalid_result",
            lambda: evaluate_success(
                expression,
                {ONE: OracleResult.SATISFIED, TWO: "violated"},
            ),
        )
        self.assertEqual(error.location, f"$results[{TWO}]")


class ExpressionObligationTests(ExpressionTestCase):
    def test_collects_unique_references_and_accepts_a_closed_expression(self) -> None:
        expression = AllOf(
            (ObservationRef(ONE), Not(ObservationRef(TWO)), ObservationRef(ONE))
        )
        self.assertEqual(referenced_obligations(expression), frozenset((ONE, TWO)))
        self.assertIsNone(validate_expression_obligations(expression, (ONE, TWO)))

    def test_rejects_unknown_references_before_unused_obligations(self) -> None:
        error = self.assert_error(
            "expression.unknown_obligation",
            lambda: validate_expression_obligations(ObservationRef(THREE), (ONE, TWO)),
        )
        self.assertIn(str(THREE), error.detail)

    def test_rejects_declared_but_unused_obligations(self) -> None:
        error = self.assert_error(
            "expression.unused_obligation",
            lambda: validate_expression_obligations(ObservationRef(ONE), (ONE, TWO)),
        )
        self.assertIn(str(TWO), error.detail)

    def test_rejects_duplicate_declared_obligations(self) -> None:
        self.assert_error(
            "expression.duplicate_obligation",
            lambda: validate_expression_obligations(
                ObservationRef(ONE), (ONE, ONE)
            ),
        )


class ExpressionSemanticValidationTests(ExpressionTestCase):
    def test_accepts_the_supported_operator_semantics(self) -> None:
        cases = (
            (AllOf((ObservationRef(ONE), ObservationRef(TWO))), (ONE, TWO)),
            (AnyOf((ObservationRef(ONE), ObservationRef(TWO))), (ONE, TWO)),
            (Not(ObservationRef(ONE)), (ONE,)),
            (
                AtLeast(
                    2,
                    (
                        ObservationRef(ONE),
                        ObservationRef(TWO),
                        ObservationRef(THREE),
                    ),
                ),
                (ONE, TWO, THREE),
            ),
        )

        for expression, obligations in cases:
            with self.subTest(expression=expression):
                self.assertIsNone(
                    validate_expression_semantics(expression, obligations)
                )

    def test_accepts_depth_six_and_twelve_direct_terms(self) -> None:
        depth_six = ObservationRef(ONE)
        for _ in range(5):
            depth_six = Not(depth_six)
        self.assertIsNone(validate_expression_semantics(depth_six, (ONE,)))

        fanout_twelve = AllOf(tuple(ObservationRef(ONE) for _ in range(12)))
        self.assertIsNone(validate_expression_semantics(fanout_twelve, (ONE,)))

    def test_reference_closure_errors_precede_new_semantic_limits(self) -> None:
        oversized_unknown = AllOf(
            tuple(ObservationRef(THREE) for _ in range(13))
        )
        self.assert_error(
            "expression.unknown_obligation",
            lambda: validate_expression_semantics(oversized_unknown, (ONE,)),
        )
        self.assert_error(
            "expression.unused_obligation",
            lambda: validate_expression_semantics(ObservationRef(ONE), (ONE, TWO)),
        )

    def test_rejects_obligation_counts_outside_one_through_twelve(self) -> None:
        error = self.assert_error(
            "expression.invalid_obligation_count",
            lambda: validate_expression_semantics(
                AllOf(()), (), location="$.scenario.success"
            ),
        )
        self.assertEqual(error.location, "$.scenario.success")
        self.assertIn("0", error.detail)

        obligations = tuple(
            ObligationID(f"obligation:semantic:item-{index}")
            for index in range(1, 14)
        )
        expression = AllOf(tuple(ObservationRef(item) for item in obligations))
        error = self.assert_error(
            "expression.invalid_obligation_count",
            lambda: validate_expression_semantics(
                expression, obligations, location="$.scenario.success"
            ),
        )
        self.assertEqual(error.location, "$.scenario.success")
        self.assertIn("13", error.detail)

    def test_rejects_depth_seven_at_the_offending_node(self) -> None:
        expression = ObservationRef(ONE)
        for _ in range(6):
            expression = Not(expression)

        error = self.assert_error(
            "expression.too_deep",
            lambda: validate_expression_semantics(
                expression, (ONE,), location="$.scenario.success"
            ),
        )
        self.assertEqual(
            error.location,
            "$.scenario.success.not.not.not.not.not.not",
        )

    def test_rejects_thirteen_direct_terms_at_the_combination(self) -> None:
        expression = AllOf(tuple(ObservationRef(ONE) for _ in range(13)))
        error = self.assert_error(
            "expression.too_many_terms",
            lambda: validate_expression_semantics(
                expression, (ONE,), location="$.scenario.success"
            ),
        )
        self.assertEqual(error.location, "$.scenario.success.all")
        self.assertIn("13", error.detail)

    def test_rejects_invalid_programmatic_at_least_count(self) -> None:
        self.assert_error(
            "expression.invalid_count",
            lambda: validate_expression_semantics(
                AtLeast(2, (ObservationRef(ONE),)), (ONE,)
            ),
        )

    def test_rejects_expressions_that_can_never_satisfy_or_violate(self) -> None:
        contradiction = AllOf(
            (ObservationRef(ONE), Not(ObservationRef(ONE)))
        )
        error = self.assert_error(
            "expression.never_satisfied",
            lambda: validate_expression_semantics(
                contradiction, (ONE,), location="$.scenario.success"
            ),
        )
        self.assertEqual(error.location, "$.scenario.success")

        tautology = AnyOf((ObservationRef(ONE), Not(ObservationRef(ONE))))
        error = self.assert_error(
            "expression.never_violated",
            lambda: validate_expression_semantics(
                tautology, (ONE,), location="$.scenario.success"
            ),
        )
        self.assertEqual(error.location, "$.scenario.success")

    def test_rejects_a_semantically_redundant_obligation_deterministically(self) -> None:
        expression = AllOf(
            (
                ObservationRef(ONE),
                AnyOf((ObservationRef(ONE), ObservationRef(TWO))),
                AnyOf((ObservationRef(ONE), ObservationRef(THREE))),
            )
        )
        first_redundant = min((TWO, THREE), key=str)

        for obligations in ((THREE, TWO, ONE), frozenset((ONE, TWO, THREE))):
            with self.subTest(obligations=obligations):
                error = self.assert_error(
                    "expression.redundant_obligation",
                    lambda obligations=obligations: validate_expression_semantics(
                        expression,
                        obligations,
                        location="$.scenario.success",
                    ),
                )
                self.assertEqual(error.location, "$.scenario.success")
                self.assertIn(str(first_redundant), error.detail)


class PythonCompatibilityTests(unittest.TestCase):
    def test_module_parses_as_python_3_9(self) -> None:
        source = (REGRESSION_SCRIPTS / "core" / "expression.py").read_text(
            encoding="utf-8"
        )
        ast.parse(source, filename="expression.py", feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
