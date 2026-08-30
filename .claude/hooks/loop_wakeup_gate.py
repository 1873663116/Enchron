#!/usr/bin/env python3

"""Refuse to end a /loop turn that left no wakeup armed.

Measured on this session's transcript: 62 arms, 7 timer firings, 132 wake-ups
that came from task notifications instead. So the loop nearly always runs on
notifications, and each new arm replaces the pending one. The combination that
actually kills it is a timer firing (which consumes the arm) on a turn that then
ends without arming another; after that nothing wakes the session at all.

The invariant is therefore per-turn: a turn that belongs to a loop ends with an
armed wakeup, or it ends the loop on purpose. Both are visible in the transcript
as a ScheduleWakeup call, so this reads the entries written since the last user
message and looks for one.

Silent unless the session is in a loop, so ordinary sessions are unaffected.
Writing `.claude/loop-off` turns it off without editing settings.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

TOOL = "ScheduleWakeup"


def entries(path: Path) -> list[dict]:
    found = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            found.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return found


def calls_since_last_user(records: list[dict]) -> list[dict]:
    """Every ScheduleWakeup input in the current turn."""
    start = 0
    for index, record in enumerate(records):
        if record.get("type") == "user" and _is_real_turn(record):
            start = index
    found = []
    for record in records[start:]:
        for block in _content(record):
            if block.get("type") == "tool_use" and block.get("name") == TOOL:
                found.append(block.get("input") or {})
    return found


def _is_tool_result(record: dict) -> bool:
    return any(block.get("type") == "tool_result" for block in _content(record))


def _is_real_turn(record: dict) -> bool:
    """A background task finishing is not the user speaking.

    Notifications and reminders arrive as user-type entries mid-turn. Counting one
    as the start of the turn moved the boundary past a ScheduleWakeup that had
    already been called, and the gate then blocked a turn that had armed one.
    """
    if _is_tool_result(record):
        return False
    text = "".join(
        block.get("text", "") for block in _content(record) if block.get("type") == "text"
    )
    return not any(
        marker in text
        for marker in ("<system-reminder>", "<task-notification>", "Stop hook feedback:")
    )


def _content(record: dict) -> list[dict]:
    message = record.get("message") or {}
    content = message.get("content")
    return [block for block in content if isinstance(block, dict)] if isinstance(content, list) else []


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    if payload.get("stop_hook_active"):
        return 0

    project = Path(payload.get("cwd") or ".")
    if (project / ".claude/loop-off").exists():
        return 0

    transcript = Path(payload.get("transcript_path") or "")
    if not transcript.is_file():
        return 0
    records = entries(transcript)

    in_loop = any(
        block.get("name") == TOOL
        for record in records
        for block in _content(record)
        if block.get("type") == "tool_use"
    )
    if not in_loop:
        return 0

    turn = calls_since_last_user(records)
    if any(call.get("stop") for call in turn):
        return 0
    if turn:
        return 0

    print(
        "This turn is part of a /loop and armed no wakeup, so nothing would wake "
        "the session again. Call ScheduleWakeup before stopping: pass the same "
        "/loop prompt with a delay and a reason, or stop:true to end the loop on "
        "purpose. Create .claude/loop-off to switch this gate off.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
