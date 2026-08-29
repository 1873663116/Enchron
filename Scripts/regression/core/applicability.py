from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, FrozenSet, Iterable, Optional, Tuple, Union

from .digest import canonical_digest
from .errors import RegressionError
from .ids import Digest, FactID, parse_identifier


FactValue = Union[bool, int, str]


def _validate_fact_value(value: object, location: str) -> FactValue:
    if type(value) not in (bool, int, str):
        raise RegressionError(
            "applicability.invalid_fact_value",
            location,
            "fact values must be booleans, integers, or strings",
        )
    return value


@dataclass(frozen=True)
class ReviewedFact:
    id: FactID
    value: FactValue
    source_digest: Digest
    review_receipt_digest: Optional[Digest]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "id",
            FactID(parse_identifier("fact", self.id, "reviewedFact.id")),
        )
        object.__setattr__(
            self,
            "value",
            _validate_fact_value(self.value, "reviewedFact.value"),
        )
        object.__setattr__(
            self,
            "source_digest",
            Digest(
                parse_identifier(
                    "digest", self.source_digest, "reviewedFact.sourceDigest"
                )
            ),
        )
        if self.review_receipt_digest is not None:
            object.__setattr__(
                self,
                "review_receipt_digest",
                Digest(
                    parse_identifier(
                        "digest",
                        self.review_receipt_digest,
                        "reviewedFact.reviewReceiptDigest",
                    )
                ),
            )


@dataclass(frozen=True)
class Constant:
    value: bool

    def __post_init__(self) -> None:
        if type(self.value) is not bool:
            raise RegressionError(
                "applicability.constant_not_bool",
                "constant",
                "constant must be a boolean",
            )


@dataclass(frozen=True)
class FactEquals:
    fact: FactID
    value: FactValue

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "fact",
            FactID(parse_identifier("fact", self.fact, "factEquals.fact")),
        )
        object.__setattr__(
            self,
            "value",
            _validate_fact_value(self.value, "factEquals.value"),
        )


@dataclass(frozen=True)
class AllFacts:
    terms: Tuple["Applicability", ...]

    def __post_init__(self) -> None:
        terms = tuple(self.terms)
        if not terms:
            raise RegressionError(
                "applicability.empty_terms",
                "all",
                "all terms must not be empty",
            )
        object.__setattr__(self, "terms", terms)


@dataclass(frozen=True)
class AnyFact:
    terms: Tuple["Applicability", ...]

    def __post_init__(self) -> None:
        terms = tuple(self.terms)
        if not terms:
            raise RegressionError(
                "applicability.empty_terms",
                "any",
                "any terms must not be empty",
            )
        object.__setattr__(self, "terms", terms)


@dataclass(frozen=True)
class NotFact:
    term: "Applicability"


Applicability = Union[Constant, FactEquals, AllFacts, AnyFact, NotFact]

_OPERATORS = frozenset(("constant", "factEquals", "all", "any", "not"))
_FACT_EQUALS_KEYS = frozenset(("fact", "value"))


def parse_applicability(
    payload: Any, location: str = "$", max_depth: int = 64
) -> Applicability:
    if type(max_depth) is not int or max_depth < 0:
        raise RegressionError(
            "applicability.invalid_depth_limit",
            location,
            "max_depth must be a non-negative integer",
        )
    return _parse_applicability(payload, location, max_depth, 0)


def _parse_applicability(
    payload: Any, location: str, max_depth: int, depth: int
) -> Applicability:
    if depth > max_depth:
        raise RegressionError(
            "applicability.too_deep",
            location,
            f"applicability depth exceeds max_depth {max_depth}",
        )
    if not isinstance(payload, dict):
        raise RegressionError(
            "applicability.not_object",
            location,
            "applicability must be a JSON object",
        )

    unknown_keys = sorted(set(payload) - _OPERATORS, key=repr)
    if unknown_keys:
        raise RegressionError(
            "applicability.unknown_key",
            location,
            "unknown applicability key(s): "
            + ", ".join(map(repr, unknown_keys)),
        )
    if len(payload) != 1:
        raise RegressionError(
            "applicability.mixed_operators",
            location,
            "applicability must contain exactly one operator",
        )

    operator = next(iter(payload))
    value = payload[operator]
    if operator == "constant":
        if type(value) is not bool:
            raise RegressionError(
                "applicability.constant_not_bool",
                f"{location}.constant",
                "constant must be a boolean",
            )
        return Constant(value)

    if operator == "factEquals":
        return _parse_fact_equals(value, f"{location}.factEquals")

    if operator == "not":
        return NotFact(
            _parse_applicability(
                value, f"{location}.not", max_depth, depth + 1
            )
        )

    terms = _parse_terms(
        value, f"{location}.{operator}", max_depth, depth + 1
    )
    if operator == "all":
        return AllFacts(terms)
    return AnyFact(terms)


def _parse_fact_equals(payload: Any, location: str) -> FactEquals:
    if not isinstance(payload, dict):
        raise RegressionError(
            "applicability.fact_equals_not_object",
            location,
            "factEquals must be a JSON object",
        )
    unknown_keys = sorted(set(payload) - _FACT_EQUALS_KEYS, key=repr)
    if unknown_keys:
        raise RegressionError(
            "applicability.fact_equals_unknown_key",
            location,
            "unknown factEquals key(s): "
            + ", ".join(map(repr, unknown_keys)),
        )
    if set(payload) != _FACT_EQUALS_KEYS:
        raise RegressionError(
            "applicability.fact_equals_keys",
            location,
            "factEquals must contain exactly fact and value",
        )
    return FactEquals(
        FactID(parse_identifier("fact", payload["fact"], f"{location}.fact")),
        _validate_fact_value(payload["value"], f"{location}.value"),
    )


def _parse_terms(
    payload: Any, location: str, max_depth: int, depth: int
) -> Tuple[Applicability, ...]:
    if not isinstance(payload, list):
        raise RegressionError(
            "applicability.terms_not_list",
            location,
            "terms must be a JSON array",
        )
    if not payload:
        raise RegressionError(
            "applicability.empty_terms",
            location,
            "terms must not be empty",
        )
    return tuple(
        _parse_applicability(item, f"{location}[{index}]", max_depth, depth)
        for index, item in enumerate(payload)
    )


def referenced_facts(expression: Applicability) -> FrozenSet[FactID]:
    if isinstance(expression, Constant):
        return frozenset()
    if isinstance(expression, FactEquals):
        return frozenset((expression.fact,))
    if isinstance(expression, NotFact):
        return referenced_facts(expression.term)
    if isinstance(expression, (AllFacts, AnyFact)):
        references = set()
        for term in expression.terms:
            references.update(referenced_facts(term))
        return frozenset(references)
    raise TypeError(f"unsupported applicability: {type(expression).__name__}")


def _index_reviewed_facts(
    reviewed_facts: Iterable[ReviewedFact],
) -> Dict[FactID, ReviewedFact]:
    facts: Dict[FactID, ReviewedFact] = {}
    for index, fact in enumerate(reviewed_facts):
        if not isinstance(fact, ReviewedFact):
            raise RegressionError(
                "applicability.invalid_reviewed_fact",
                f"$reviewedFacts[{index}]",
                "expected a ReviewedFact",
            )
        if fact.id in facts:
            raise RegressionError(
                "applicability.duplicate_fact",
                f"$reviewedFacts[{index}].id",
                f"duplicate reviewed fact {fact.id!r}",
            )
        facts[fact.id] = fact
    return facts


def evaluate_applicability(
    expression: Applicability, reviewed_facts: Iterable[ReviewedFact]
) -> bool:
    facts = _index_reviewed_facts(reviewed_facts)
    for fact_id in referenced_facts(expression):
        fact = facts.get(fact_id)
        if fact is None:
            raise RegressionError(
                "applicability.unknown_fact",
                str(fact_id),
                "applicability references a fact absent from the reviewed fact set",
            )
        if fact.review_receipt_digest is None:
            raise RegressionError(
                "applicability.unreviewed_fact",
                str(fact_id),
                "applicability cannot use a fact without a review receipt",
            )
    return _evaluate_applicability(expression, facts)


def _evaluate_applicability(
    expression: Applicability, facts: Dict[FactID, ReviewedFact]
) -> bool:
    if isinstance(expression, Constant):
        return expression.value
    if isinstance(expression, FactEquals):
        actual = facts[expression.fact].value
        return type(actual) is type(expression.value) and actual == expression.value
    if isinstance(expression, AllFacts):
        return all(_evaluate_applicability(term, facts) for term in expression.terms)
    if isinstance(expression, AnyFact):
        return any(_evaluate_applicability(term, facts) for term in expression.terms)
    if isinstance(expression, NotFact):
        return not _evaluate_applicability(expression.term, facts)
    raise TypeError(f"unsupported applicability: {type(expression).__name__}")


def reviewed_facts_digest(
    reviewed_facts: Iterable[ReviewedFact],
) -> Digest:
    facts = _index_reviewed_facts(reviewed_facts)
    payload = [
        {
            "fact": str(fact.id),
            "value": fact.value,
            "sourceDigest": str(fact.source_digest),
            "reviewReceiptDigest": (
                str(fact.review_receipt_digest)
                if fact.review_receipt_digest is not None
                else None
            ),
        }
        for fact in sorted(facts.values(), key=lambda item: item.id)
    ]
    return canonical_digest(payload)


__all__ = (
    "AllFacts",
    "AnyFact",
    "Applicability",
    "Constant",
    "FactEquals",
    "FactValue",
    "NotFact",
    "ReviewedFact",
    "evaluate_applicability",
    "parse_applicability",
    "referenced_facts",
    "reviewed_facts_digest",
)
