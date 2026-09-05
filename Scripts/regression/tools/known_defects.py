#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
import json
from pathlib import Path
from typing import Any, Mapping, Optional, Tuple, Union

from regression.core.fields import ABSENT, field_value, reads_equal
from regression.core.ids import ScenarioID, SignatureID, parse_identifier
from regression.core.runview import NodeStatus
from regression.rubric_compiler import FieldPredicate
from regression.tools.signatures import SignatureError, signature
from regression.tools.verdict import Verdict

DEFECTS_PATH = (
    Path(__file__).resolve().parents[3] / "Config/regression/known_defects.json"
)
DEFECTS_SCHEMA = "enchron.regression.known-defects"
RECORD_FIELDS = frozenset(
    {"scenario", "description", "match", "recorded", "expiresWhen"}
)
MATCH_FIELDS = frozenset({"signature", "field", "operator", "value"})
EQUALS = "=="


class KnownDefectError(ValueError):
    pass


@dataclass(frozen=True)
class KnownDefect:
    scenario: ScenarioID
    description: str
    match: Union[SignatureID, FieldPredicate]
    recorded: date
    expires_when: str


def load(path: Path = DEFECTS_PATH) -> Tuple[KnownDefect, ...]:
    if not Path(path).is_file():
        raise KnownDefectError(f"{path} holds no known defect ledger")
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, Mapping) or payload.get("schema") != DEFECTS_SCHEMA:
        raise KnownDefectError(f"{path} is not a {DEFECTS_SCHEMA} document")
    entries = payload.get("defects")
    if not isinstance(entries, list):
        raise KnownDefectError(f"{path} carries no defects list")
    return tuple(_record(item, f"{path}[{index}]") for index, item in enumerate(entries))


def _record(value: Any, location: str) -> KnownDefect:
    if not isinstance(value, Mapping):
        raise KnownDefectError(f"{location} is not an object")
    unknown = set(value) - RECORD_FIELDS
    if unknown:
        raise KnownDefectError(
            f"{location} carries unrecognised field(s): {', '.join(sorted(unknown))}"
        )
    missing = sorted(RECORD_FIELDS - set(value))
    if missing:
        raise KnownDefectError(f"{location} omits {', '.join(missing)}")
    expires = value["expiresWhen"]
    if not isinstance(expires, str) or not expires.strip():
        raise KnownDefectError(
            f"{location} leaves expiresWhen empty; a record with no condition for "
            "revisiting it never gets revisited"
        )
    description = value["description"]
    if not isinstance(description, str) or not description.strip():
        raise KnownDefectError(f"{location} leaves description empty")
    try:
        recorded = date.fromisoformat(str(value["recorded"]))
    except ValueError as error:
        raise KnownDefectError(
            f"{location} records a date that is not ISO 8601: {value['recorded']!r}"
        ) from error
    scenario = ScenarioID(
        parse_identifier("scenario", value["scenario"], f"{location}.scenario")
    )
    return KnownDefect(
        scenario, description, _match(value["match"], f"{location}.match"), recorded, expires
    )


def _match(value: Any, location: str) -> Union[SignatureID, FieldPredicate]:
    if not isinstance(value, Mapping):
        raise KnownDefectError(f"{location} is not an object")
    unknown = set(value) - MATCH_FIELDS
    if unknown:
        raise KnownDefectError(
            f"{location} carries unrecognised field(s): {', '.join(sorted(unknown))}"
        )
    if "signature" in value:
        if set(value) != {"signature"}:
            raise KnownDefectError(
                f"{location} names a signature and a field predicate; a record "
                "matches on one of them"
            )
        identifier = SignatureID(
            parse_identifier("signature", value["signature"], location)
        )
        try:
            signature(identifier)
        except SignatureError as error:
            raise KnownDefectError(str(error)) from error
        return identifier
    if set(value) != {"field", "operator", "value"}:
        raise KnownDefectError(
            f"{location} is neither a signature nor a field, operator and value"
        )
    if value["operator"] != EQUALS:
        raise KnownDefectError(
            f"{location} compares with {value['operator']!r}; the ledger matches on "
            f"{EQUALS}"
        )
    if not isinstance(value["field"], str) or not value["field"]:
        raise KnownDefectError(f"{location} names no field")
    if type(value["value"]) not in (bool, str):
        raise KnownDefectError(
            f"{location} compares against {value['value']!r}; a field predicate "
            "reads a boolean or a string"
        )
    return FieldPredicate(value["field"], EQUALS, value["value"])


def matching_defect(
    scenario: Optional[ScenarioID],
    verdict: Verdict,
    fields: Mapping[str, Any],
    defects: Optional[Tuple[KnownDefect, ...]] = None,
) -> Optional[KnownDefect]:
    """The record that exempted a failure is the record the ledger has to be
    able to name, so the lookup returns it rather than only its consequence."""
    if not isinstance(verdict, Verdict):
        raise KnownDefectError("a known defect is classified from a Verdict")
    if scenario is None:
        return None
    records = load() if defects is None else defects
    for record in records:
        if record.scenario != scenario:
            continue
        if _hits(record.match, verdict, fields):
            return record
    return None


def classify(
    scenario: Optional[ScenarioID],
    verdict: Verdict,
    fields: Mapping[str, Any],
    defects: Optional[Tuple[KnownDefect, ...]] = None,
) -> NodeStatus:
    found = matching_defect(scenario, verdict, fields, defects)
    return NodeStatus.FAILED if found is None else NodeStatus.FAILED_KNOWN


def _hits(
    match: Union[SignatureID, FieldPredicate],
    verdict: Verdict,
    fields: Mapping[str, Any],
) -> bool:
    if isinstance(match, FieldPredicate):
        read = field_value(fields, match.field)
        return read is not ABSENT and reads_equal(read, match.value)
    return verdict.signature == match


__all__ = (
    "DEFECTS_PATH",
    "DEFECTS_SCHEMA",
    "KnownDefect",
    "KnownDefectError",
    "classify",
    "matching_defect",
    "load",
)
