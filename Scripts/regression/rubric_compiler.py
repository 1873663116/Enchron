#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import re
from types import MappingProxyType
from typing import Iterator, Mapping, Tuple, Union

from regression.core.contracts import RubricContract
from regression.core.ids import RubricID

BOOLEAN_VALUES = frozenset({"true", "false"})

FIELD_VALUES: Mapping[str, frozenset] = MappingProxyType(
    {
        "controls": frozenset({"shown", "hidden"}),
        "exists": BOOLEAN_VALUES,
        "isEnabled": BOOLEAN_VALUES,
        "isHittable": BOOLEAN_VALUES,
        "isSelected": BOOLEAN_VALUES,
        "lifecycle": frozenset({"Playing", "Paused", "Stopped", "Loading"}),
        "mediaKind": frozenset({"audioOnly", "video"}),
        "succeeded": BOOLEAN_VALUES,
        "visible": BOOLEAN_VALUES,
    }
)

NEGATION_MARKERS = (
    " no ",
    " not ",
    " never",
    " without",
    " unless",
    " absence",
    " fails",
    " rather than",
    " instead of",
    " neither",
    " nor ",
)

EQUALS = "=="

SENTENCE_BOUNDARY = re.compile(r"(?<=[.;])\s+")
ASSERTION = re.compile(
    r"\b(" + "|".join(sorted(FIELD_VALUES)) + r")\s*(?:=|\s)\s*([A-Za-z]+)\b"
)


class RubricCompilerError(ValueError):
    pass


@dataclass(frozen=True)
class FieldPredicate:
    field: str
    operator: str
    value: Union[bool, str]

    def payload(self) -> dict:
        return {"field": self.field, "operator": self.operator, "value": self.value}


@dataclass(frozen=True)
class CompiledRubric:
    rubric_id: RubricID
    predicates: Tuple[FieldPredicate, ...]
    uncompiled: Tuple[str, ...]


def compile_rubric(rubric: RubricContract) -> CompiledRubric:
    if not isinstance(rubric, RubricContract):
        raise RubricCompilerError("the compiler reads one RubricContract")
    predicates, uncompiled = compile_criteria(rubric.criteria)
    return CompiledRubric(rubric.id, predicates, uncompiled)


def compile_criteria(
    criteria: Tuple[str, ...]
) -> Tuple[Tuple[FieldPredicate, ...], Tuple[str, ...]]:
    predicates: list[FieldPredicate] = []
    uncompiled: list[str] = []
    for criterion in criteria:
        found = tuple(assertions_in(criterion))
        if found:
            predicates.extend(found)
        else:
            uncompiled.append(criterion)
    return tuple(dict.fromkeys(predicates)), tuple(uncompiled)


def assertions_in(criterion: str) -> Iterator[FieldPredicate]:
    for sentence in SENTENCE_BOUNDARY.split(criterion):
        if negated(sentence):
            continue
        for field, literal in ASSERTION.findall(sentence):
            if literal in FIELD_VALUES[field]:
                yield FieldPredicate(field, EQUALS, coerce(literal))


def negated(sentence: str) -> bool:
    padded = f" {sentence.lower()} "
    return any(marker in padded for marker in NEGATION_MARKERS)


def coerce(literal: str) -> Union[bool, str]:
    if literal in BOOLEAN_VALUES:
        return literal == "true"
    return literal


__all__ = (
    "ASSERTION",
    "EQUALS",
    "FIELD_VALUES",
    "NEGATION_MARKERS",
    "CompiledRubric",
    "FieldPredicate",
    "RubricCompilerError",
    "assertions_in",
    "compile_criteria",
    "compile_rubric",
    "negated",
)
