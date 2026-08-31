#!/usr/bin/env python3

"""The coordinator's ledger: which waits are open, what each one last saw, and
which dispatches have not been swept.

One ledger per worktree. A change of session id resets it, because a watch
names work only the session that opened it can act on. Two coordinator sessions
sharing one worktree would share this file; that topology is unsupported and
`status` prints the owning session so the collision is visible rather than
silent.

The turn number is derived, never stamped. A turn that never executes -- the
API refusing it, for one -- runs no Stop hook, so a counter incremented there
would freeze exactly when the session is in trouble. Every writer counts real
user messages in the transcript instead, so the number is a property of the
record rather than of a hook having run.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

LEDGER = ".claude/state/coordinator.json"
POLLED_KINDS = {"orca-run"}
PUSH_KINDS = {"orca-run", "background-task"}
STALE_OBSERVATIONS = 3
"""Consecutive identical samples that retire a dispatch.

Counted in samples, not seconds: a review round's duration is not knowable in
advance, and the run that measured this used three identical terminal tails.
"""


def ledger_path(project: Path) -> Path:
    return project / LEDGER


def load(project: Path) -> dict[str, Any]:
    try:
        payload = json.loads(ledger_path(project).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    payload.setdefault("session", None)
    payload.setdefault("turn", 0)
    payload.setdefault("dispatches", [])
    payload.setdefault("sweeps", [])
    payload.setdefault("watches", {})
    payload.setdefault("wakes", [])
    return payload


def save(project: Path, payload: dict[str, Any]) -> None:
    target = ledger_path(project)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")


def adopt(project: Path, session: str | None, turn: int) -> dict[str, Any]:
    """Point the ledger at the live session and the turn the transcript shows."""
    payload = load(project)
    if session and payload.get("session") not in (None, session):
        payload = {
            "session": session,
            "turn": turn,
            "dispatches": [],
            "sweeps": [],
            "watches": {},
            "wakes": [],
        }
    if session:
        payload["session"] = session
    payload["turn"] = max(int(payload.get("turn") or 0), turn)
    return payload


def content_blocks(record: dict) -> list[dict]:
    message = record.get("message") or {}
    content = message.get("content")
    if not isinstance(content, list):
        return []
    return [block for block in content if isinstance(block, dict)]


def record_text(record: dict) -> str:
    return "".join(
        block.get("text", "")
        for block in content_blocks(record)
        if block.get("type") == "text"
    )


def is_tool_result(record: dict) -> bool:
    return any(block.get("type") == "tool_result" for block in content_blocks(record))


def is_real_turn(record: dict) -> bool:
    """A background task finishing is not the user speaking.

    Notifications and reminders arrive as user-type entries mid-turn. Counting
    one as the start of a turn moved the boundary past a ScheduleWakeup that had
    already been called, and the gate then blocked a turn that had armed one.
    """
    if record.get("type") != "user" or is_tool_result(record):
        return False
    text = record_text(record)
    return not any(
        marker in text
        for marker in ("<system-reminder>", "<task-notification>", "Stop hook feedback:")
    )


def transcript_records(path: Path) -> list[dict]:
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    found = []
    for line in raw.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            found.append(value)
    return found


def turn_of(records: list[dict]) -> int:
    return sum(1 for record in records if is_real_turn(record))


def turn_from_transcript(path: Path | None) -> int:
    if path is None or not path.is_file():
        return 0
    return turn_of(transcript_records(path))


def unswept_dispatches(payload: dict[str, Any], turn: int) -> list[dict]:
    """Dispatches recorded in an earlier turn that no sweep has cleared."""
    return [
        entry
        for entry in payload.get("dispatches") or []
        if isinstance(entry, dict) and int(entry.get("turn") or 0) < turn
    ]


def open_watches(payload: dict[str, Any]) -> dict[str, dict]:
    return {
        identifier: watch
        for identifier, watch in (payload.get("watches") or {}).items()
        if isinstance(watch, dict) and watch.get("closedTurn") is None
    }


def latest_observation(watch: dict) -> dict | None:
    observations = watch.get("observations") or []
    return observations[-1] if observations else None


def read_this_turn(watch: dict, turn: int) -> bool:
    return any(
        int((observation or {}).get("turn") or -1) == turn
        for observation in watch.get("observations") or []
    )


def is_stalled(watch: dict) -> bool:
    observations = [
        observation
        for observation in watch.get("observations") or []
        if isinstance(observation, dict)
    ]
    if len(observations) < STALE_OBSERVATIONS:
        return False
    tail = observations[-STALE_OBSERVATIONS:]
    if any(observation.get("settled") == observation.get("total") for observation in tail):
        return False
    return len({observation.get("digest") for observation in tail}) == 1
