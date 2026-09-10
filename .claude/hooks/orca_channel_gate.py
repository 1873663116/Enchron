#!/usr/bin/env python3

"""PreToolUse gate: refuse the shell shapes that detach a wait from the channel
carrying its completion fact.

Every measured coordinator failure in the 41-hour session was a bypass, not a
defect in the push mechanism. Background tasks launched without a detacher
answered in a median of five seconds across ninety-six calls; `check --run`
returned the real queue; a supervised dispatch pushed its worker_done. The
losses came from six shapes that each replace a channel with a surrogate, and
every one of them is visible in the command text before it runs:

    detach          nohup/setsid/disown or a trailing & throws the notification
                    away; six such calls produced zero notifications.
    unbound check   `orca orchestration check` without --run reads the
                    terminal's default binding; ninety-three of a hundred and
                    twenty did, and fifty messages went unread, one of them a
                    worker's question that was auto-acknowledged unread.
    hand-rolled ack --peek does not mark anything read, so a separate --ack
                    names a batch nobody consumed; six rejection reports came
                    back every twenty seconds for an hour.
    process liveness  a TUI stays alive when the agent behind it dies, and a
                    99-minute-old xcodebuild matched a grep and blocked seven
                    minutes; the dispatch's own status is the liveness fact.
    pipeline status a `$?` read after a pipeline is the last stage's code.
    unsupervised dispatch  a worker bound through `terminal create` has no
                    dispatch record, so it can neither report nor be acked.

A seventh rule has no shell shape: dispatching again while an earlier turn's
dispatches are unswept. Fifteen rounds of that left 297 unreleased terminals
and a load average near 17, and the last round's workers could not start. The
ledger holds what was dispatched and what was swept, so the gate can see it.

Blocking is exit 2 with the reason on stderr, the same mechanism the Stop gate
in this directory already uses. The JSON permissionDecision form was not chosen
because an unsupported field fails open, and a guard that fails open is the
false green this repository has already been bitten by twice.

Writing `.claude/hooks-off` disables every rule. `orca_channel.py status`
reports that file's presence, so switching the gate off is loud.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import coordinator_state as ledger

TOOL = "python3 .claude/tools/orca_channel.py"
DETACHERS = re.compile(r"(?<![\w-])(?:nohup|setsid|disown)(?![\w-])")
TRAILING_AMPERSAND = re.compile(r"(?<![&>|])&\s*(?:$|[;\n])")
CHECK = re.compile(r"orca\s+orchestration\s+check(?![\w-])")
WORKER_START = re.compile(r"orca\s+orchestration\s+worker-start(?![\w-])")
TERMINAL_DISPATCH = re.compile(
    r"orca\s+terminal\s+create(?=[^\n]*--command)"
    r"(?=[^\n]*(?:opencode|claude|codex|cursor|amp|aider))"
)
PROCESS_LISTERS = re.compile(r"(?<![\w-])(?:ps|pgrep|pkill)(?![\w-])")
FILE_POLL = re.compile(
    r"(?<![\w-])(?:while|until)(?![\w-])[^\n]*?"
    r"(?:\[\[?\s*!?\s*-[ef]\s|(?<![\w-])test\s+!?\s*-[ef]\s)"
)
"""A loop whose exit condition is a path is waiting on a file, not on a worker."""
WAIT_FLAG = re.compile(r"orca\s+orchestration(?=[^\n]*(?<![\w-])--wait(?![\w-]))")
BRACKET_ESCAPE = re.compile(r"\[(\w)\]")
"""`grep "[c]laude"` is how a grep excludes itself, and it hides the token."""
AGENT_TOKENS = re.compile(
    r"(?<![\w-])(?:opencode|claude|codex|cursor|xcodebuild|run_verification"
    r"|worker|dispatch|listen\.py|orca)(?![\w-])"
)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def executable_text(command: str) -> str:
    """Drop heredoc bodies before matching.

    A heredoc body is data on its way into a file, not a command being run, and
    every rule below matches literal tokens: a document that quotes a banned
    word to explain why it is banned would otherwise be refused itself. What
    this cannot see is a detacher written into a script that some later command
    executes; that residual is recorded in DESIGN.md.
    """
    lines = command.splitlines()
    kept, index = [], 0
    while index < len(lines):
        line = lines[index]
        kept.append(line)
        match = HEREDOC.search(line)
        index += 1
        if match is None:
            continue
        delimiter = match.group(2)
        while index < len(lines) and lines[index].strip() != delimiter:
            index += 1
        if index < len(lines):
            index += 1
    return "\n".join(kept)


def deny(reason: str) -> int:
    print(reason, file=sys.stderr)
    return 2


def segments(command: str) -> list[str]:
    """Split on statement separators so `$?` can be attributed to one statement."""
    parts, current, depth, quote = [], [], 0, ""
    index = 0
    while index < len(command):
        character = command[index]
        if quote:
            current.append(character)
            if character == quote:
                quote = ""
            index += 1
            continue
        if character in "'\"":
            quote = character
            current.append(character)
        elif character in "([{":
            depth += 1
            current.append(character)
        elif character in ")]}":
            depth = max(0, depth - 1)
            current.append(character)
        elif depth == 0 and character in ";\n":
            parts.append("".join(current))
            current = []
        elif depth == 0 and character == "&" and command[index : index + 2] == "&&":
            parts.append("".join(current))
            current = []
            index += 1
        else:
            current.append(character)
        index += 1
    parts.append("".join(current))
    return [part for part in parts if part.strip()]


def has_top_level_pipe(segment: str) -> bool:
    depth, quote = 0, ""
    index = 0
    while index < len(segment):
        character = segment[index]
        if quote:
            if character == quote:
                quote = ""
        elif character in "'\"":
            quote = character
        elif character in "([{":
            depth += 1
        elif character in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0 and character == "|":
            if segment[index : index + 2] == "||":
                index += 1
            else:
                return True
        index += 1
    return False


def pipeline_status_reader(command: str) -> str | None:
    """A `$?` whose preceding statement is a pipeline reads the last stage."""
    previous = None
    for segment in segments(command):
        if "$?" in segment and previous is not None and has_top_level_pipe(previous):
            return previous.strip()
        previous = segment
    return None


def verdict(text: str, project: Path, turn: int) -> str | None:
    command = executable_text(text)
    if DETACHERS.search(command):
        return (
            "This command detaches the process, so nothing will notify the session "
            "when it finishes. Six detached calls in the recorded session produced "
            "zero notifications; ninety-six plain background calls answered in a "
            "median of five seconds. Drop nohup/setsid/disown and pass "
            "run_in_background: true instead."
        )
    if TRAILING_AMPERSAND.search(command):
        return (
            "A trailing & backgrounds the process inside the shell, which leaves "
            "the session with no completion signal at all. Remove the & and pass "
            "run_in_background: true, which is the path that pushes a "
            "task-notification when the command exits."
        )
    if CHECK.search(command):
        if "--peek" in command:
            return (
                "--peek does not mark anything read, so a separate --ack names a "
                "batch nobody consumed and the same messages return on the next "
                "poll; that replayed six rejection reports every twenty seconds "
                f"for an hour. The queue has exactly one consumer: {TOOL} drain "
                "--run <id>, which chains each delivery's --ack into the next "
                "check."
            )
        if "--ack" in command and "--run" not in command:
            return (
                "An --ack without --run acknowledges against this terminal's "
                "default binding rather than the Run whose delivery it names, so "
                f"the batch stays unread. Use {TOOL} drain --run <id>, or pass "
                "--run alongside --ack."
            )
        if "--run" not in command and "--terminal" not in command:
            return (
                "`orca orchestration check` without --run reads this terminal's "
                "default binding, not the Run. Ninety-three of a hundred and "
                "twenty checks did that and fifty messages piled up unread, "
                "including a worker's question. Name the Run: "
                f"`{TOOL} drain --run <id>`, or pass --run/--terminal explicitly "
                "for a read that does not consume."
            )
    if WAIT_FLAG.search(command):
        return (
            "--wait holds the whole turn inside one subscription, so the "
            "coordinator cannot read the repository or any other Run until that "
            "single worker answers. The watch is meant to be sampled, not "
            f"blocked on: open it with `{TOOL} watch open --run <id>` and sample "
            f"it with `{TOOL} watch read`, which leaves the turn free."
        )
    if FILE_POLL.search(command):
        return (
            "A loop that exits when a path appears is waiting on a file, not on "
            "the worker. A partial report is on disk long before it is complete, "
            "and one such poll declared a worker finished at one delivery of "
            f"four and destroyed the rest. Wait on the channel: `{TOOL} watch "
            f"read`, or `{TOOL} drain --run <id>` for the settled form."
        )
    if TERMINAL_DISPATCH.search(command):
        return (
            "Binding a worker through `terminal create --command` produces an "
            "unsupervised dispatch: no dispatch record, no worker_done push, and "
            "its rejected reports cannot be acknowledged. Use `orca orchestration "
            "worker-start --task <id> --worktree current --agent <id>`."
        )
    unescaped = BRACKET_ESCAPE.sub(r"\1", command)
    if PROCESS_LISTERS.search(unescaped) and AGENT_TOKENS.search(unescaped):
        return (
            "The process table does not carry the completion fact. A TUI stays "
            "alive when the agent behind it has failed, and a grep for xcodebuild "
            "matched a 99-minute-old leftover and blocked seven minutes. Read the "
            f"dispatch's own status: `orca orchestration worker-list --run <id>`, "
            f"or `{TOOL} watch read` for the sampled form."
        )
    pipeline = pipeline_status_reader(command)
    if pipeline is not None:
        return (
            f"`$?` after a pipeline is the last stage's exit code, not the "
            f"command's: `{pipeline[:80]}`. Read ${{PIPESTATUS[0]}}, or drop the "
            "pipe and inspect the captured output separately."
        )
    if WORKER_START.search(command):
        payload = ledger.load(project)
        stale = ledger.unswept_dispatches(payload, turn)
        if stale:
            return (
                f"{len(stale)} dispatch(es) from an earlier turn have not been "
                "swept. Dispatching without retiring left 297 unreleased "
                "terminals and a load average near 17, and the last round's "
                f"workers could not start. Run `{TOOL} sweep --run <id>` first; "
                "it drains the queue and closes settled terminals, so the "
                "mailbox is read as a side effect of dispatching again."
            )
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    if payload.get("tool_name") not in (None, "Bash"):
        return 0
    project = Path(payload.get("cwd") or ".")
    if (project / ".claude/hooks-off").exists():
        return 0

    tool_input = payload.get("tool_input") or {}
    command = str(tool_input.get("command") or "")
    if not command:
        return 0

    transcript = payload.get("transcript_path")
    turn = ledger.turn_from_transcript(Path(transcript) if transcript else None)
    state = ledger.adopt(project, payload.get("session_id"), turn)

    reason = verdict(command, project, turn)
    if reason is None and WORKER_START.search(executable_text(command)):
        state["dispatches"].append({"turn": turn, "command": command[:400]})
    try:
        ledger.save(project, state)
    except OSError:
        pass
    if reason is None:
        return 0
    return deny(reason)


if __name__ == "__main__":
    sys.exit(main())
