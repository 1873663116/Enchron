from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from itertools import product
from typing import Any, FrozenSet, Iterable, Mapping, Tuple, Union

from .errors import RegressionError
from .ids import ObligationID, parse_identifier


class OracleResult(Enum):
    SATISFIED = "satisfied"
    VIOLATED = "violated"
    INDETERMINATE = "indeterminate"


@dataclass(frozen=True)
class ObservationRef:
    ref: ObligationID


@dataclass(frozen=True)
class AllOf:
    terms: Tuple["SuccessExpression", ...]


@dataclass(frozen=True)
class AnyOf:
    terms: Tuple["SuccessExpression", ...]


@dataclass(frozen=True)
class Not:
    term: "SuccessExpression"


@dataclass(frozen=True)
class AtLeast:
    count: int
    terms: Tuple["SuccessExpression", ...]


SuccessExpression = Union[ObservationRef, AllOf, AnyOf, Not, AtLeast]

_OPERATORS = frozenset(("observation", "all", "any", "not", "atLeast"))
_MAX_SEMANTIC_OBLIGATIONS = 12
_MAX_SEMANTIC_DEPTH = 6
_MAX_COMBINATION_TERMS = 12
_RESULT_VALUES = tuple(OracleResult)
_RESULT_CODES = {
    OracleResult.SATISFIED: 0,
    OracleResult.VIOLATED: 1,
    OracleResult.INDETERMINATE: 2,
}


def parse_success_expression(
    payload: Any, location: str = "$", max_depth: int = 64
) -> SuccessExpression:
    if type(max_depth) is not int or max_depth < 0:
        raise RegressionError(
            "expression.invalid_depth_limit",
            location,
            "max_depth must be a non-negative integer",
        )
    return _parse_success_expression(payload, location, max_depth, 0)


def _parse_success_expression(
    payload: Any, location: str, max_depth: int, depth: int
) -> SuccessExpression:
    if depth > max_depth:
        raise RegressionError(
            "expression.too_deep",
            location,
            f"expression depth exceeds max_depth {max_depth}",
        )
    if not isinstance(payload, dict):
        raise RegressionError(
            "expression.not_object", location, "expression must be a JSON object"
        )

    unknown_keys = sorted(set(payload) - _OPERATORS, key=repr)
    if unknown_keys:
        raise RegressionError(
            "expression.unknown_key",
            location,
            "unknown expression key(s): " + ", ".join(map(repr, unknown_keys)),
        )
    if len(payload) != 1:
        raise RegressionError(
            "expression.mixed_operators",
            location,
            "expression must contain exactly one operator",
        )

    operator = next(iter(payload))
    value = payload[operator]
    if operator == "observation":
        return ObservationRef(
            ObligationID(
                parse_identifier("obligation", value, f"{location}.observation")
            )
        )
    if operator == "not":
        return Not(
            _parse_success_expression(
                value, f"{location}.not", max_depth, depth + 1
            )
        )
    if operator == "all":
        return AllOf(
            _parse_terms(value, f"{location}.all", max_depth, depth + 1)
        )
    if operator == "any":
        return AnyOf(
            _parse_terms(value, f"{location}.any", max_depth, depth + 1)
        )

    if not isinstance(value, dict):
        raise RegressionError(
            "expression.at_least_not_object",
            f"{location}.atLeast",
            "atLeast must be a JSON object",
        )
    if set(value) != {"count", "of"}:
        raise RegressionError(
            "expression.at_least_keys",
            f"{location}.atLeast",
            "atLeast must contain exactly count and of",
        )
    terms = _parse_terms(
        value["of"], f"{location}.atLeast.of", max_depth, depth + 1
    )
    count = value["count"]
    if type(count) is not int or not 1 <= count <= len(terms):
        raise RegressionError(
            "expression.invalid_count",
            f"{location}.atLeast.count",
            f"count must be an integer from 1 through {len(terms)}",
        )
    return AtLeast(count, terms)


def _parse_terms(
    payload: Any, location: str, max_depth: int, depth: int
) -> Tuple[SuccessExpression, ...]:
    if not isinstance(payload, list):
        raise RegressionError(
            "expression.terms_not_list", location, "terms must be a JSON array"
        )
    if not payload:
        raise RegressionError(
            "expression.empty_terms", location, "terms must not be empty"
        )
    return tuple(
        _parse_success_expression(item, f"{location}[{index}]", max_depth, depth)
        for index, item in enumerate(payload)
    )


def referenced_obligations(
    expression: SuccessExpression,
) -> FrozenSet[ObligationID]:
    if isinstance(expression, ObservationRef):
        return frozenset((expression.ref,))
    if isinstance(expression, Not):
        return referenced_obligations(expression.term)
    if isinstance(expression, (AllOf, AnyOf, AtLeast)):
        references = set()
        for term in expression.terms:
            references.update(referenced_obligations(term))
        return frozenset(references)
    raise TypeError(f"unsupported success expression: {type(expression).__name__}")


def validate_expression_obligations(
    expression: SuccessExpression,
    obligations: Iterable[ObligationID],
    location: str = "$",
) -> None:
    references = referenced_obligations(expression)
    obligation_values = tuple(obligations)
    declared = frozenset(obligation_values)
    if len(obligation_values) != len(declared):
        raise RegressionError(
            "expression.duplicate_obligation",
            location,
            "declared obligations must be unique",
        )
    unknown = references - declared
    if unknown:
        raise RegressionError(
            "expression.unknown_obligation",
            location,
            "unknown obligation reference(s): " + ", ".join(sorted(unknown)),
        )
    unused = declared - references
    if unused:
        raise RegressionError(
            "expression.unused_obligation",
            location,
            "unused obligation(s): " + ", ".join(sorted(unused)),
        )


def validate_expression_semantics(
    expression: SuccessExpression,
    obligations: Iterable[ObligationID],
    location: str = "$",
) -> None:
    obligation_values = tuple(obligations)
    validate_expression_obligations(expression, obligation_values, location)
    declared = frozenset(obligation_values)

    obligation_count = len(declared)
    if not 1 <= obligation_count <= _MAX_SEMANTIC_OBLIGATIONS:
        raise RegressionError(
            "expression.invalid_obligation_count",
            location,
            "obligation count must be from 1 through "
            f"{_MAX_SEMANTIC_OBLIGATIONS}; found {obligation_count}",
        )

    _validate_semantic_shape(expression, location, 1)
    ordered_obligations = tuple(sorted(declared, key=str))
    result_codes = bytearray()
    has_satisfied = False
    has_violated = False

    for values in product(_RESULT_VALUES, repeat=obligation_count):
        results = dict(zip(ordered_obligations, values))
        result = _evaluate_success(expression, results)
        result_codes.append(_RESULT_CODES[result])
        if result is OracleResult.SATISFIED:
            has_satisfied = True
        elif result is OracleResult.VIOLATED:
            has_violated = True

    if not has_satisfied:
        raise RegressionError(
            "expression.never_satisfied",
            location,
            "success expression can never evaluate to satisfied",
        )
    if not has_violated:
        raise RegressionError(
            "expression.never_violated",
            location,
            "success expression can never evaluate to violated",
        )

    for index, obligation in enumerate(ordered_obligations):
        if not _obligation_can_change_result(
            result_codes, obligation_count, index
        ):
            raise RegressionError(
                "expression.redundant_obligation",
                location,
                f"obligation {obligation} cannot change the expression result",
            )


def _validate_semantic_shape(
    expression: SuccessExpression, location: str, depth: int
) -> None:
    if depth > _MAX_SEMANTIC_DEPTH:
        raise RegressionError(
            "expression.too_deep",
            location,
            f"expression depth exceeds {_MAX_SEMANTIC_DEPTH}",
        )
    if isinstance(expression, ObservationRef):
        return
    if isinstance(expression, Not):
        _validate_semantic_shape(expression.term, f"{location}.not", depth + 1)
        return
    if isinstance(expression, AllOf):
        terms_location = f"{location}.all"
    elif isinstance(expression, AnyOf):
        terms_location = f"{location}.any"
    elif isinstance(expression, AtLeast):
        terms_location = f"{location}.atLeast.of"
        if type(expression.count) is not int or not 1 <= expression.count <= len(
            expression.terms
        ):
            raise RegressionError(
                "expression.invalid_count",
                f"{location}.atLeast.count",
                f"count must be an integer from 1 through {len(expression.terms)}",
            )
    else:
        raise TypeError(
            f"unsupported success expression: {type(expression).__name__}"
        )

    if not expression.terms:
        raise RegressionError(
            "expression.empty_terms",
            terms_location,
            "terms must not be empty",
        )
    if len(expression.terms) > _MAX_COMBINATION_TERMS:
        raise RegressionError(
            "expression.too_many_terms",
            terms_location,
            "combination must contain at most "
            f"{_MAX_COMBINATION_TERMS} direct terms; "
            f"found {len(expression.terms)}",
        )
    for index, term in enumerate(expression.terms):
        _validate_semantic_shape(
            term, f"{terms_location}[{index}]", depth + 1
        )


def _obligation_can_change_result(
    result_codes: bytearray, obligation_count: int, obligation_index: int
) -> bool:
    stride = len(_RESULT_VALUES) ** (obligation_count - obligation_index - 1)
    block_size = stride * len(_RESULT_VALUES)
    for block_start in range(0, len(result_codes), block_size):
        for offset in range(stride):
            first = result_codes[block_start + offset]
            if any(
                result_codes[block_start + value_index * stride + offset]
                != first
                for value_index in range(1, len(_RESULT_VALUES))
            ):
                return True
    return False


def evaluate_success(
    expression: SuccessExpression,
    results: Mapping[ObligationID, OracleResult],
) -> OracleResult:
    references = referenced_obligations(expression)
    provided = frozenset(results)
    missing = references - provided
    if missing:
        raise RegressionError(
            "expression.missing_result",
            "$results",
            "missing result(s): " + ", ".join(sorted(missing)),
        )
    unknown = provided - references
    if unknown:
        raise RegressionError(
            "expression.unknown_result",
            "$results",
            "unknown result(s): " + ", ".join(sorted(unknown)),
        )
    return _evaluate_success(expression, results)


def _evaluate_success(
    expression: SuccessExpression,
    results: Mapping[ObligationID, OracleResult],
) -> OracleResult:
    if isinstance(expression, ObservationRef):
        result = results[expression.ref]
        if not isinstance(result, OracleResult):
            raise RegressionError(
                "expression.invalid_result",
                f"$results[{expression.ref}]",
                "obligation result must be an OracleResult",
            )
        return result

    if isinstance(expression, Not):
        result = _evaluate_success(expression.term, results)
        if result is OracleResult.SATISFIED:
            return OracleResult.VIOLATED
        if result is OracleResult.VIOLATED:
            return OracleResult.SATISFIED
        return OracleResult.INDETERMINATE

    if isinstance(expression, (AllOf, AnyOf, AtLeast)):
        term_results = tuple(
            _evaluate_success(term, results) for term in expression.terms
        )
        satisfied = sum(
            result is OracleResult.SATISFIED for result in term_results
        )
        violated = sum(result is OracleResult.VIOLATED for result in term_results)

        if isinstance(expression, AllOf):
            if satisfied == len(term_results):
                return OracleResult.SATISFIED
            if violated:
                return OracleResult.VIOLATED
            return OracleResult.INDETERMINATE

        if isinstance(expression, AnyOf):
            if satisfied:
                return OracleResult.SATISFIED
            if violated == len(term_results):
                return OracleResult.VIOLATED
            return OracleResult.INDETERMINATE

        indeterminate = len(term_results) - satisfied - violated
        if satisfied >= expression.count:
            return OracleResult.SATISFIED
        if satisfied + indeterminate < expression.count:
            return OracleResult.VIOLATED
        return OracleResult.INDETERMINATE

    raise TypeError(f"unsupported success expression: {type(expression).__name__}")


__all__ = (
    "AllOf",
    "AnyOf",
    "AtLeast",
    "Not",
    "ObservationRef",
    "OracleResult",
    "SuccessExpression",
    "evaluate_success",
    "parse_success_expression",
    "referenced_obligations",
    "validate_expression_obligations",
    "validate_expression_semantics",
)
