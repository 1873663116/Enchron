from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
import json
from types import MappingProxyType
from typing import Any, Dict, List, Mapping, Optional, Tuple

from .digest import canonical_bytes, canonical_digest
from .errors import RegressionError
from .ids import Digest, RunID, parse_identifier


class EventType(Enum):
    RUN_OPENED = "RunOpened"
    LANE_BOOTSTRAPPED = "LaneBootstrapped"
    NODE_CLAIMED = "NodeClaimed"
    OPERATION_AUTHORIZED = "OperationAuthorized"
    OPERATION_INVOKED = "OperationInvoked"
    OPERATION_COMPLETED = "OperationCompleted"
    ENVELOPE_RECEIVED = "EnvelopeReceived"
    EVIDENCE_ACCEPTED = "EvidenceAccepted"
    ORACLE_EVALUATED = "OracleEvaluated"
    VERDICT_RECORDED = "VerdictRecorded"
    LANE_INTERRUPTED = "LaneInterrupted"
    RUN_CLOSED = "RunClosed"


_REQUIRED_WIRE_FIELDS = frozenset(
    {
        "sequence",
        "previousDigest",
        "recordedAt",
        "runId",
        "planDigest",
        "type",
        "payload",
        "eventDigest",
    }
)
_OPTIONAL_WIRE_FIELDS = frozenset({"idempotencyKey"})


class _DuplicateKeyError(ValueError):
    def __init__(self, key: str) -> None:
        self.key = key
        super().__init__(key)


class _InvalidConstantError(ValueError):
    pass


def _object_without_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateKeyError(key)
        result[key] = value
    return result


def _reject_constant(value: str) -> Any:
    raise _InvalidConstantError(value)


def decode_json_bytes(source: bytes, location: str) -> Any:
    try:
        text = source.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RegressionError(
            "ledger.invalid_utf8", location, "ledger JSON must be valid UTF-8"
        ) from error
    try:
        return json.loads(
            text,
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_constant,
        )
    except _DuplicateKeyError as error:
        raise RegressionError(
            "ledger.duplicate_field",
            location,
            f"JSON field {error.key!r} appears more than once",
        ) from error
    except (_InvalidConstantError, json.JSONDecodeError) as error:
        raise RegressionError(
            "ledger.invalid_json", location, f"invalid ledger JSON: {error}"
        ) from error


def canonical_payload_bytes(payload: Any, location: str = "payload") -> bytes:
    if isinstance(payload, bytes):
        value = decode_json_bytes(payload, location)
        encoded = canonical_bytes(value)
        if payload != encoded:
            raise RegressionError(
                "ledger.noncanonical_payload",
                location,
                "payload bytes must use canonical JSON encoding",
            )
        return payload
    try:
        return canonical_bytes(payload)
    except (TypeError, ValueError) as error:
        raise RegressionError(
            "ledger.invalid_payload", location, f"payload is not JSON: {error}"
        ) from error


def payload_value(payload: bytes, location: str = "payload") -> Any:
    return decode_json_bytes(payload, location)


def now_rfc3339_millis() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def command_digest(event_type: EventType, payload: bytes) -> Digest:
    return canonical_digest(
        {"type": event_type.value, "payload": payload_value(payload)}
    )


@dataclass(frozen=True)
class LedgerEvent:
    sequence: int
    previous_digest: Optional[Digest]
    recorded_at: str
    run_id: RunID
    plan_digest: Digest
    type: EventType
    payload: bytes
    event_digest: Digest
    idempotency_key: Optional[str] = None

    def __post_init__(self) -> None:
        if type(self.sequence) is not int or self.sequence < 1:
            raise RegressionError(
                "ledger.invalid_sequence",
                "sequence",
                "event sequence must be a positive integer",
            )
        if self.previous_digest is not None:
            parse_identifier("digest", self.previous_digest, "previousDigest")
        if not isinstance(self.recorded_at, str) or not self.recorded_at:
            raise RegressionError(
                "ledger.invalid_recorded_at",
                "recordedAt",
                "recordedAt must be a non-empty string",
            )
        parse_identifier("run", self.run_id, "runId")
        parse_identifier("digest", self.plan_digest, "planDigest")
        if not isinstance(self.type, EventType):
            raise RegressionError(
                "ledger.unknown_event_type", "type", "event type is not recognized"
            )
        canonical_payload_bytes(self.payload)
        if self.idempotency_key is not None and (
            not isinstance(self.idempotency_key, str) or not self.idempotency_key
        ):
            raise RegressionError(
                "ledger.invalid_idempotency_key",
                "idempotencyKey",
                "idempotency key must be a non-empty string",
            )
        parse_identifier("digest", self.event_digest, "eventDigest")
        expected = self.calculate_digest()
        if self.event_digest != expected:
            raise RegressionError(
                "ledger.event_digest_mismatch",
                f"sequence:{self.sequence}",
                f"expected {expected}, found {self.event_digest}",
            )

    @classmethod
    def create(
        cls,
        sequence: int,
        previous_digest: Optional[Digest],
        recorded_at: str,
        run_id: RunID,
        plan_digest: Digest,
        event_type: EventType,
        payload: Any,
        idempotency_key: Optional[str] = None,
    ) -> "LedgerEvent":
        encoded_payload = canonical_payload_bytes(payload)
        fields = _wire_fields(
            sequence,
            previous_digest,
            recorded_at,
            run_id,
            plan_digest,
            event_type,
            encoded_payload,
            idempotency_key,
        )
        return cls(
            sequence=sequence,
            previous_digest=previous_digest,
            recorded_at=recorded_at,
            run_id=run_id,
            plan_digest=plan_digest,
            type=event_type,
            payload=encoded_payload,
            event_digest=canonical_digest(fields),
            idempotency_key=idempotency_key,
        )

    def calculate_digest(self) -> Digest:
        return canonical_digest(dict(self.wire_fields()))

    def wire_fields(self) -> Mapping[str, Any]:
        return MappingProxyType(
            _wire_fields(
                self.sequence,
                self.previous_digest,
                self.recorded_at,
                self.run_id,
                self.plan_digest,
                self.type,
                self.payload,
                self.idempotency_key,
            )
        )

    def as_dict(self) -> Mapping[str, Any]:
        value = dict(self.wire_fields())
        value["eventDigest"] = str(self.event_digest)
        return MappingProxyType(value)

    def canonical_line(self) -> bytes:
        return canonical_bytes(dict(self.as_dict())) + b"\n"


def _wire_fields(
    sequence: int,
    previous_digest: Optional[Digest],
    recorded_at: str,
    run_id: RunID,
    plan_digest: Digest,
    event_type: EventType,
    payload: bytes,
    idempotency_key: Optional[str],
) -> Dict[str, Any]:
    value: Dict[str, Any] = {
        "sequence": sequence,
        "previousDigest": (
            None if previous_digest is None else str(previous_digest)
        ),
        "recordedAt": recorded_at,
        "runId": str(run_id),
        "planDigest": str(plan_digest),
        "type": event_type.value,
        "payload": payload_value(payload),
    }
    if idempotency_key is not None:
        value["idempotencyKey"] = idempotency_key
    return value


def event_from_wire(value: Any, location: str) -> LedgerEvent:
    if not isinstance(value, dict):
        raise RegressionError(
            "ledger.event_not_object",
            location,
            "each ledger line must be a JSON object",
        )
    fields = frozenset(value)
    missing = _REQUIRED_WIRE_FIELDS - fields
    unknown = fields - _REQUIRED_WIRE_FIELDS - _OPTIONAL_WIRE_FIELDS
    if missing:
        raise RegressionError(
            "ledger.missing_field",
            location,
            "missing field(s): " + ", ".join(sorted(missing)),
        )
    if unknown:
        raise RegressionError(
            "ledger.unknown_field",
            location,
            "unknown field(s): " + ", ".join(sorted(unknown)),
        )
    raw_type = value["type"]
    try:
        event_type = EventType(raw_type)
    except (TypeError, ValueError) as error:
        raise RegressionError(
            "ledger.unknown_event_type",
            f"{location}.type",
            f"unknown event type {raw_type!r}",
        ) from error
    return LedgerEvent(
        sequence=value["sequence"],
        previous_digest=(
            None
            if value["previousDigest"] is None
            else parse_identifier(
                "digest", value["previousDigest"], f"{location}.previousDigest"
            )
        ),
        recorded_at=value["recordedAt"],
        run_id=parse_identifier("run", value["runId"], f"{location}.runId"),
        plan_digest=parse_identifier(
            "digest", value["planDigest"], f"{location}.planDigest"
        ),
        type=event_type,
        payload=canonical_payload_bytes(value["payload"], f"{location}.payload"),
        idempotency_key=value.get("idempotencyKey"),
        event_digest=parse_identifier(
            "digest", value["eventDigest"], f"{location}.eventDigest"
        ),
    )


__all__ = (
    "EventType",
    "LedgerEvent",
    "canonical_payload_bytes",
    "command_digest",
    "decode_json_bytes",
    "event_from_wire",
    "now_rfc3339_millis",
    "payload_value",
)
