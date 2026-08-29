from __future__ import annotations

import fcntl
import os
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from .errors import RegressionError
from .events import EventType, LedgerEvent, canonical_payload_bytes, command_digest
from .ids import Digest, RunID, parse_identifier
from .replay import LEDGER_FILENAME, read_event_log


LOCK_FILENAME = "ledger.lock"


class LedgerWriter:
    def __init__(self, directory: Path, run_id: RunID, plan_digest: Digest) -> None:
        self.directory = Path(directory)
        self.run_id = parse_identifier("run", run_id, "runId")
        self.plan_digest = parse_identifier("digest", plan_digest, "planDigest")
        self.directory.mkdir(parents=True, exist_ok=True)
        self._closed = False
        lock_path = self.directory / LOCK_FILENAME
        self._lock = lock_path.open("a+b")
        try:
            fcntl.flock(self._lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (BlockingIOError, OSError) as error:
            self._lock.close()
            self._closed = True
            raise RegressionError(
                "ledger.writer_locked",
                str(lock_path),
                "another LedgerWriter holds the run lock",
            ) from error

        try:
            event_log = read_event_log(self.directory)
            if event_log.events and (
                event_log.run_id != self.run_id
                or event_log.plan_digest != self.plan_digest
            ):
                raise RegressionError(
                    "ledger.identity_mismatch",
                    str(self.directory / LEDGER_FILENAME),
                    "existing ledger belongs to a different run or plan",
                )
            self._events = list(event_log.events)
            self._idempotency: Dict[str, Tuple[Digest, LedgerEvent]] = {}
            for event in self._events:
                if event.idempotency_key is not None:
                    self._idempotency[event.idempotency_key] = (
                        command_digest(event.type, event.payload),
                        event,
                    )
            self._ledger = (self.directory / LEDGER_FILENAME).open("ab")
        except BaseException:
            fcntl.flock(self._lock.fileno(), fcntl.LOCK_UN)
            self._lock.close()
            self._closed = True
            raise

    def append(
        self,
        event_type: EventType,
        payload: Any,
        recorded_at: str,
        idempotency_key: Optional[str] = None,
    ) -> LedgerEvent:
        self._require_open()
        if not isinstance(event_type, EventType):
            raise RegressionError(
                "ledger.unknown_event_type", "type", "event type is not recognized"
            )
        encoded_payload = canonical_payload_bytes(payload)
        digest = command_digest(event_type, encoded_payload)
        if idempotency_key is not None:
            if not isinstance(idempotency_key, str) or not idempotency_key:
                raise RegressionError(
                    "ledger.invalid_idempotency_key",
                    "idempotencyKey",
                    "idempotency key must be a non-empty string",
                )
            existing = self._idempotency.get(idempotency_key)
            if existing is not None:
                existing_digest, existing_event = existing
                if existing_digest == digest:
                    return existing_event
                raise RegressionError(
                    "ledger.idempotency_conflict",
                    idempotency_key,
                    "idempotency key was already used for a different command",
                )

        sequence = len(self._events) + 1
        previous_digest = (
            self._events[-1].event_digest if self._events else None
        )
        event = LedgerEvent.create(
            sequence,
            previous_digest,
            recorded_at,
            self.run_id,
            self.plan_digest,
            event_type,
            encoded_payload,
            idempotency_key,
        )
        if event.sequence != sequence or event.previous_digest != previous_digest:
            raise RegressionError(
                "ledger.append_invariant",
                str(self.directory),
                "new event does not extend the current hash chain",
            )
        self._ledger.write(event.canonical_line())
        self._ledger.flush()
        os.fsync(self._ledger.fileno())
        self._events.append(event)
        if idempotency_key is not None:
            self._idempotency[idempotency_key] = (digest, event)
        return event

    @property
    def events(self) -> Tuple[LedgerEvent, ...]:
        return tuple(self._events)

    def close(self) -> None:
        if self._closed:
            return
        self._ledger.close()
        fcntl.flock(self._lock.fileno(), fcntl.LOCK_UN)
        self._lock.close()
        self._closed = True

    def _require_open(self) -> None:
        if self._closed:
            raise RegressionError(
                "ledger.writer_closed", str(self.directory), "LedgerWriter is closed"
            )

    def __enter__(self) -> "LedgerWriter":
        self._require_open()
        return self

    def __exit__(self, exception_type: Any, exception: Any, traceback: Any) -> None:
        self.close()

    def __del__(self) -> None:
        try:
            self.close()
        except BaseException:
            pass


__all__ = ("LOCK_FILENAME", "LedgerWriter")
