#!/usr/bin/env python3

"""Stop gate: refuse to end a turn that is waiting on something it did not read.

Measured on the recorded session: 62 arms, 7 timer firings, 132 wake-ups that
came from task notifications instead. The loop nearly always runs on
notifications, and each new arm replaces the pending one. The combination that
kills it is a timer firing on a turn that then ends without arming another;
after that nothing wakes the session at all.

Three further shapes cost more than the dead loop did, and all three are the
same shape: the turn ended while a wait was open and unread.

    A  the turn ended, the work had already finished, nobody picked it up; the
       longest such gap was 476 minutes.
    B  the gate was satisfied with a wakeup and nothing else -- 24 of 47
       interceptions answered with a lone ScheduleWakeup -- while the thing
       being waited for had finished in 20 to 30 seconds.
    C  a wait was held on something that does not carry the completion fact: a
       file count, a process table, a terminal's tail.

The previous version of this file policed B with a duration: a task-notification
carrying `completed` plus a delay above 300 seconds. That criterion fired zero
times, because the runs it was aimed at were launched with `nohup` and produced
no notification at all -- it was bound to a channel the failure never crossed.
Two things replace it. The detacher is now denied before it runs, so the
notification exists; and the criterion here drops the threshold entirely, since
the fault in B is that ready work was parked, not that the number was large.

Duration is absent on purpose everywhere in this file. A regression round is
driven by its operation units and its length is not knowable in advance, so
progress is the only sound criterion: whether the channel moved, and whether
the coordinator looked.

Writing `.claude/hooks-off` turns the gate off; `orca_channel.py status`
reports that file, so switching it off is loud.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import coordinator_state as ledger  # noqa: E402

TOOL = "python3 .claude/tools/orca_channel.py"
WAKEUP = "ScheduleWakeup"


def turn_start(records: list[dict]) -> int:
    start = 0
    for index, record in enumerate(records):
        if ledger.is_real_turn(record):
            start = index
    return start


def tool_uses(records: list[dict], start: int) -> list[tuple[int, str, dict]]:
    found = []
    for index, record in enumerate(records[start:], start):
        for block in ledger.content_blocks(record):
            if block.get("type") == "tool_use":
                found.append((index, str(block.get("name") or ""), block.get("input") or {}))
    return found


def completion_without_followup(records: list[dict], start: int) -> bool:
    """A task reported completion in this turn and only a wakeup followed it."""
    finished = None
    for index, record in enumerate(records[start:], start):
        text = ledger.record_text(record)
        if "<task-notification>" in text and "completed" in text:
            finished = index
    if finished is None:
        return False
    return not any(name != WAKEUP for index, name, _ in tool_uses(records, finished))


def drained_this_turn(records: list[dict], start: int) -> bool:
    for _, name, arguments in tool_uses(records, start):
        if name != "Bash":
            continue
        command = str(arguments.get("command") or "")
        if "orca_channel.py" in command and (" drain" in command or " sweep" in command):
            return True
    return False


def verdict(records: list[dict], project: Path) -> str | None:
    start = turn_start(records)
    uses = tool_uses(records, start)
    arms = [arguments for _, name, arguments in uses if name == WAKEUP]
    ended_loop = any(arguments.get("stop") for arguments in arms)

    payload = ledger.load(project)
    turn = ledger.turn_of(records)
    watching = ledger.open_watches(payload)

    for identifier, watch in watching.items():
        channel = watch.get("channel") or {}
        if channel.get("kind") not in ledger.POLLED_KINDS:
            continue
        if not ledger.read_this_turn(watch, turn):
            return (
                f"{identifier} is an open wait on {channel.get('run')} and this "
                "turn never sampled it, so ending here leaves work that may "
                "already be finished with nobody to pick it up; the longest such "
                f"gap in the recorded session was 476 minutes. Run `{TOOL} watch "
                f"read`, then act on what it says, or `{TOOL} watch close --id "
                f"{identifier}` if the wait is over."
            )
        observation = ledger.latest_observation(watch) or {}
        total = observation.get("total") or 0
        if total and observation.get("settled") == total and not drained_this_turn(records, start):
            return (
                f"{identifier} reports {observation.get('settled')}/{total} "
                "dispatches settled, so the work is finished and its reports are "
                f"sitting unread in the queue. Run `{TOOL} sweep --run "
                f"{channel.get('run')}` before ending the turn."
            )

    if completion_without_followup(records, start):
        return (
            "A background task reported completion in this turn and nothing but a "
            "wakeup followed it, so the turn ends having parked work that is ready "
            "now. In the recorded session that pattern accounted for 138 minutes "
            "of pure noticing delay across eight artefacts. Read the result and "
            "act on it, or end the loop with stop:true."
        )

    if ended_loop:
        return None
    in_loop = any(name == WAKEUP for _, name, _ in tool_uses(records, 0))
    if in_loop and not arms:
        return (
            "This turn is part of a /loop and armed no wakeup, so nothing would "
            "wake the session again. Call ScheduleWakeup before stopping: pass "
            "the same /loop prompt with a delay and a reason, or stop:true to end "
            "the loop on purpose."
        )
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    if payload.get("stop_hook_active"):
        return 0

    project = Path(payload.get("cwd") or ".")
    if (project / ".claude/hooks-off").exists() or (project / ".claude/loop-off").exists():
        return 0

    transcript = Path(payload.get("transcript_path") or "")
    if not transcript.is_file():
        return 0
    records = ledger.transcript_records(transcript)
    if not records:
        return 0

    reason = verdict(records, project)
    if reason is None:
        return 0
    print(reason, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
