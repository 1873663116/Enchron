from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple

from .digest import canonical_bytes
from .errors import RegressionError
from .events import LedgerEvent, command_digest, decode_json_bytes, event_from_wire
from .ids import Digest, RunID
from .runview import RunView, build_run_view


LEDGER_FILENAME = "ledger.jsonl"


@dataclass(frozen=True)
class EventLog:
    events: Tuple[LedgerEvent, ...]

    def __post_init__(self) -> None:
        events = tuple(self.events)
        if any(not isinstance(event, LedgerEvent) for event in events):
            raise RegressionError(
                "ledger.invalid_event_log",
                "events",
                "EventLog accepts only LedgerEvent values",
            )
        object.__setattr__(self, "events", events)

    @property
    def run_id(self) -> Optional[RunID]:
        return self.events[0].run_id if self.events else None

    @property
    def plan_digest(self) -> Optional[Digest]:
        return self.events[0].plan_digest if self.events else None

    @property
    def last_event(self) -> Optional[LedgerEvent]:
        return self.events[-1] if self.events else None


def read_event_log(directory: Path) -> EventLog:
    ledger_path = Path(directory) / LEDGER_FILENAME
    if ledger_path.is_symlink():
        raise RegressionError(
            "ledger.invalid_file", str(ledger_path), "ledger cannot be a symlink"
        )
    if not ledger_path.exists():
        return EventLog(())
    if not ledger_path.is_file():
        raise RegressionError(
            "ledger.invalid_file", str(ledger_path), "ledger must be a regular file"
        )
    source = ledger_path.read_bytes()
    if not source:
        return EventLog(())
    if not source.endswith(b"\n"):
        raise RegressionError(
            "ledger.truncated_tail",
            str(ledger_path),
            "a non-empty ledger must end with a newline",
        )

    events = []
    previous = None
    run_id = None
    plan_digest = None
    idempotency: Dict[str, Digest] = {}
    for index, line in enumerate(source.splitlines(), start=1):
        location = f"{ledger_path}:{index}"
        if not line:
            raise RegressionError(
                "ledger.blank_line", location, "ledger lines cannot be empty"
            )
        value = decode_json_bytes(line, location)
        if canonical_bytes(value) != line:
            raise RegressionError(
                "ledger.noncanonical_json",
                location,
                "ledger lines must use canonical JSON encoding",
            )
        event = event_from_wire(value, location)
        if event.sequence != index:
            raise RegressionError(
                "ledger.sequence_gap",
                location,
                f"expected sequence {index}, found {event.sequence}",
            )
        if event.previous_digest != previous:
            raise RegressionError(
                "ledger.previous_digest_mismatch",
                location,
                f"expected previous digest {previous}, found {event.previous_digest}",
            )
        if run_id is None:
            run_id = event.run_id
            plan_digest = event.plan_digest
        elif event.run_id != run_id or event.plan_digest != plan_digest:
            raise RegressionError(
                "ledger.identity_mismatch",
                location,
                "runId and planDigest must remain constant within a ledger",
            )
        if event.idempotency_key is not None:
            digest = command_digest(event.type, event.payload)
            if event.idempotency_key in idempotency:
                raise RegressionError(
                    "ledger.duplicate_idempotency_key",
                    location,
                    f"idempotency key {event.idempotency_key!r} appears more than once",
                )
            idempotency[event.idempotency_key] = digest
        events.append(event)
        previous = event.event_digest
    return EventLog(tuple(events))


def replay(directory: Path) -> RunView:
    return build_run_view(read_event_log(directory).events)


__all__ = ("EventLog", "LEDGER_FILENAME", "read_event_log", "replay")
