#!/usr/bin/env python3

"""Probes for the Stop gate.

The predecessor of this file fed the gate a `wakeup()` content block where a
transcript record belonged, so three of its four idle cases asserted nothing
while printing OK. Every case here builds a real record list, and every refusal
case asserts a phrase belonging to the rule under test, so one rule cannot pass
another rule's probe.

Run against a mutated copy by setting ENCHRON_CLAUDE_DIR.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

CLAUDE = Path(os.environ.get("ENCHRON_CLAUDE_DIR") or Path(__file__).resolve().parents[1])
HOOK = CLAUDE / "hooks/loop_wakeup_gate.py"
DONE = "<task-notification><status>completed</status></task-notification>"


def user(text="go"):
    return {"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": text}]}}


def assistant(*blocks):
    return {"type": "assistant", "message": {"role": "assistant", "content": list(blocks)}}


def wakeup(**kwargs):
    return {"type": "tool_use", "name": "ScheduleWakeup", "input": kwargs}


def other(command="ls"):
    return {"type": "tool_use", "name": "Bash", "input": {"command": command}}


def notification(text=DONE):
    return {"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": text}]}}


def ledger(project: Path, watches: dict, turn: int) -> None:
    state = {"session": "probe", "turn": turn, "dispatches": [], "sweeps": [],
             "watches": watches, "wakes": []}
    (project / ".claude/state").mkdir(parents=True, exist_ok=True)
    (project / ".claude/state/coordinator.json").write_text(json.dumps(state), encoding="utf-8")


def run(records, project: Path, extra=None) -> tuple[int, str]:
    path = project / "transcript.jsonl"
    with path.open("w", encoding="utf-8") as sink:
        for record in records:
            sink.write(json.dumps(record) + "\n")
    payload = {"transcript_path": str(path), "cwd": str(project), "session_id": "probe"}
    payload.update(extra or {})
    done = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(payload),
                          capture_output=True, text=True)
    return done.returncode, (done.stderr or "").strip()


def watch(run_id="run_x", observations=None, closed=None):
    return {"channel": {"kind": "orca-run", "run": run_id},
            "openedTurn": 1,
            "observations": observations if observations is not None else [],
            "closedTurn": closed}


def observation(turn, total=8, settled=0, digest="d0"):
    return {"turn": turn, "total": total, "settled": settled, "digest": digest}


LOOP = [
    ("loop-armed-passes",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(wakeup(delaySeconds=900))],
     0, ""),
    ("loop-unarmed-blocks",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(other())],
     2, "armed no wakeup"),
    ("loop-stop-true-passes",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(wakeup(stop=True))],
     0, ""),
    ("never-a-loop-passes", [user(), assistant(other())], 0, ""),
    ("previous-turn-arm-does-not-count",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(other()), assistant(other())],
     2, "armed no wakeup"),
    ("notification-after-arming-does-not-reset-the-turn",
     [user(), assistant(wakeup(delaySeconds=900)), notification("<task-notification>x</task-notification>"),
      assistant(other())],
     0, ""),
]

IDLE = [
    ("completion-then-only-a-wakeup-blocks",
     [user(), assistant(other()), notification(), assistant(wakeup(delaySeconds=1200))],
     2, "parked work"),
    ("completion-then-a-short-wakeup-still-blocks",
     [user(), assistant(other()), notification(), assistant(wakeup(delaySeconds=60))],
     2, "parked work"),
    ("completion-then-work-passes",
     [user(), notification(), assistant(other()), assistant(wakeup(delaySeconds=1800))],
     0, ""),
    ("no-completion-any-delay-passes",
     [user(), assistant(other()), assistant(wakeup(delaySeconds=1800))], 0, ""),
]


def main() -> int:
    failures = []

    def check(name, got, want, message, phrase):
        if got != want or (phrase and phrase not in message):
            failures.append(name)
            print(f"FAIL {name}: exit {got} want {want} phrase {phrase!r} in {message[:140]!r}")
        else:
            print(f"OK   {name}")

    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        ledger(project, {}, turn=2)
        for name, records, expected, phrase in LOOP + IDLE:
            code, message = run(records, project)
            check(name, code, expected, message, phrase)

        code, message = run([user(), assistant(wakeup(delaySeconds=1)), user(), assistant(other())],
                            project, extra={"stop_hook_active": True})
        check("stop-hook-active-does-not-recurse", code, 0, message, "")

        (project / ".claude/hooks-off").write_text("")
        code, message = run([user(), assistant(wakeup(delaySeconds=900)), user(), assistant(other())],
                            project)
        check("hooks-off-switch", code, 0, message, "")
        (project / ".claude/hooks-off").unlink()

    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        records = [user(), assistant(other()), user(), assistant(other(), wakeup(delaySeconds=900))]
        turn = 2

        ledger(project, {"watch_a": watch(observations=[observation(1)])}, turn)
        code, message = run(records, project)
        check("open-watch-unread-this-turn-blocks", code, 2, message, "never sampled it")

        ledger(project, {"watch_a": watch(observations=[observation(1), observation(2)])}, turn)
        code, message = run(records, project)
        check("open-watch-read-this-turn-passes", code, 0, message, "")

        ledger(project, {"watch_a": watch(observations=[observation(1)], closed=1)}, turn)
        code, message = run(records, project)
        check("closed-watch-is-not-a-wait", code, 0, message, "")

        ledger(project,
               {"watch_a": watch(observations=[observation(2, total=8, settled=8)])}, turn)
        code, message = run(records, project)
        check("all-settled-without-a-drain-blocks", code, 2, message, "settled")

        drained = [user(), assistant(other()), user(),
                   assistant(other("python3 .claude/tools/orca_channel.py sweep --run run_x"),
                             wakeup(delaySeconds=900))]
        ledger(project,
               {"watch_a": watch(observations=[observation(2, total=8, settled=8)])}, turn)
        code, message = run(drained, project)
        check("all-settled-after-a-sweep-passes", code, 0, message, "")

        ledger(project,
               {"watch_b": {"channel": {"kind": "background-task", "task": "bg1"},
                            "openedTurn": 1, "observations": [observation(1)], "closedTurn": None}},
               turn)
        code, message = run(records, project)
        check("background-task-watch-needs-no-poll", code, 0, message, "")

    total = len(LOOP) + len(IDLE) + 2 + 6
    print(f"stop probes: {total - len(failures)} passed, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
