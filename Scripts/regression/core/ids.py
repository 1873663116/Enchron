from __future__ import annotations

import re
from types import MappingProxyType
from typing import Callable, Mapping, NewType, Pattern, Union

from .errors import RegressionError


PromiseID = NewType("PromiseID", str)
JourneyID = NewType("JourneyID", str)
ScenarioID = NewType("ScenarioID", str)
ObligationID = NewType("ObligationID", str)
PreparationID = NewType("PreparationID", str)
CallID = NewType("CallID", str)
CaseKey = NewType("CaseKey", str)
EvidenceType = NewType("EvidenceType", str)
EvidenceSchema = NewType("EvidenceSchema", str)
StateKey = NewType("StateKey", str)
StateSchema = NewType("StateSchema", str)
OperationID = NewType("OperationID", str)
OracleID = NewType("OracleID", str)
RubricID = NewType("RubricID", str)
FactID = NewType("FactID", str)
StateTag = NewType("StateTag", str)
NodeID = NewType("NodeID", str)
RunID = NewType("RunID", str)
LeaseID = NewType("LeaseID", str)
GrantID = NewType("GrantID", str)
SidekickID = NewType("SidekickID", str)
ReviewPacketID = NewType("ReviewPacketID", str)
SignatureID = NewType("SignatureID", str)
Digest = NewType("Digest", str)

Identifier = Union[
    PromiseID,
    JourneyID,
    ScenarioID,
    ObligationID,
    PreparationID,
    CallID,
    CaseKey,
    EvidenceType,
    EvidenceSchema,
    StateKey,
    StateSchema,
    OperationID,
    OracleID,
    RubricID,
    FactID,
    StateTag,
    NodeID,
    RunID,
    LeaseID,
    GrantID,
    SidekickID,
    ReviewPacketID,
    SignatureID,
    Digest,
]

_SLUG = r"[a-z0-9]+(?:-[a-z0-9]+)*"
_COLON_PATH = rf"{_SLUG}(?::{_SLUG})*"
_DOT_PATH = rf"{_SLUG}(?:\.{_SLUG})*"
_VERSION = r"[1-9][0-9]*"
_PATTERN_TEXT = {
    "promise": rf"promise:{_SLUG}:c[0-9]{{2}}",
    "journey": rf"journey:{_SLUG}",
    "scenario": rf"scenario:{_COLON_PATH}",
    "obligation": rf"obligation:{_COLON_PATH}",
    "preparation": rf"preparation:{_COLON_PATH}",
    "call": rf"call:{_COLON_PATH}",
    "case_key": _SLUG,
    "evidence_type": _DOT_PATH,
    "evidence_schema": rf"{_DOT_PATH}@{_VERSION}",
    "state_key": _SLUG,
    "state_schema": rf"{_DOT_PATH}@{_VERSION}",
    "operation": rf"operation:{_SLUG}\.{_SLUG}@{_VERSION}",
    "oracle": rf"oracle:{_DOT_PATH}@{_VERSION}",
    "rubric": rf"rubric:{_DOT_PATH}@{_VERSION}",
    "fact": rf"fact:{_DOT_PATH}",
    "state_tag": _DOT_PATH,
    "node": rf"node:{_COLON_PATH}",
    "run": rf"run:{_SLUG}",
    "lease": rf"lease:{_SLUG}",
    "grant": rf"grant:{_SLUG}",
    "sidekick": rf"sidekick:{_SLUG}",
    "review_packet": rf"review-packet:{_COLON_PATH}",
    "signature": rf"signature:{_COLON_PATH}",
    "digest": r"sha256:[0-9a-f]{64}",
}

IDENTIFIER_PATTERNS: Mapping[str, Pattern[str]] = MappingProxyType(
    {kind: re.compile(pattern) for kind, pattern in _PATTERN_TEXT.items()}
)

_IDENTIFIER_TYPES: Mapping[str, Callable[[str], Identifier]] = MappingProxyType({
    "promise": PromiseID,
    "journey": JourneyID,
    "scenario": ScenarioID,
    "obligation": ObligationID,
    "preparation": PreparationID,
    "call": CallID,
    "case_key": CaseKey,
    "evidence_type": EvidenceType,
    "evidence_schema": EvidenceSchema,
    "state_key": StateKey,
    "state_schema": StateSchema,
    "operation": OperationID,
    "oracle": OracleID,
    "rubric": RubricID,
    "fact": FactID,
    "state_tag": StateTag,
    "node": NodeID,
    "run": RunID,
    "lease": LeaseID,
    "grant": GrantID,
    "sidekick": SidekickID,
    "review_packet": ReviewPacketID,
    "signature": SignatureID,
    "digest": Digest,
})

if IDENTIFIER_PATTERNS.keys() != _IDENTIFIER_TYPES.keys():
    raise RuntimeError("Identifier pattern and constructor tables disagree.")


def parse_identifier(kind: str, value: object, location: str) -> Identifier:
    pattern = IDENTIFIER_PATTERNS.get(kind) if isinstance(kind, str) else None
    if pattern is None:
        raise RegressionError(
            "identifier.unknown_kind",
            location,
            f"Unknown identifier kind {kind!r}.",
        )
    if not isinstance(value, str):
        raise RegressionError(
            "identifier.not_string",
            location,
            f"Expected {kind} identifier to be a string.",
        )
    if pattern.fullmatch(value) is None:
        raise RegressionError(
            "identifier.invalid_format",
            location,
            f"Invalid {kind} identifier {value!r}.",
        )
    return _IDENTIFIER_TYPES[kind](value)


def parse_call_id(value: object, location: str) -> CallID:
    return CallID(parse_identifier("call", value, location))


def parse_case_key(value: object, location: str) -> CaseKey:
    return CaseKey(parse_identifier("case_key", value, location))


def parse_evidence_type(value: object, location: str) -> EvidenceType:
    return EvidenceType(parse_identifier("evidence_type", value, location))


def parse_evidence_schema(value: object, location: str) -> EvidenceSchema:
    return EvidenceSchema(parse_identifier("evidence_schema", value, location))


def parse_state_key(value: object, location: str) -> StateKey:
    return StateKey(parse_identifier("state_key", value, location))


def parse_state_schema(value: object, location: str) -> StateSchema:
    return StateSchema(parse_identifier("state_schema", value, location))


__all__ = (
    "CallID",
    "CaseKey",
    "Digest",
    "EvidenceSchema",
    "EvidenceType",
    "FactID",
    "GrantID",
    "IDENTIFIER_PATTERNS",
    "Identifier",
    "JourneyID",
    "LeaseID",
    "NodeID",
    "ObligationID",
    "OperationID",
    "OracleID",
    "PreparationID",
    "PromiseID",
    "ReviewPacketID",
    "RubricID",
    "RunID",
    "ScenarioID",
    "SidekickID",
    "SignatureID",
    "StateKey",
    "StateSchema",
    "StateTag",
    "parse_call_id",
    "parse_case_key",
    "parse_evidence_schema",
    "parse_evidence_type",
    "parse_identifier",
    "parse_state_key",
    "parse_state_schema",
)
