#!/usr/bin/env python3

"""Probes for the PreToolUse gate.

Every case names a measured failure or a lane that must stay open. A probe that
asserts nothing is worse than no probe: this repository has shipped a hook probe
that fed the gate a content block instead of a transcript record, so three of
its four cases exercised nothing. Each case here therefore asserts the exit code
AND, when it expects a refusal, a phrase from that specific rule's message, so a
rule cannot be satisfied by some other rule's refusal.

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
HOOK = CLAUDE / "hooks/orca_channel_gate.py"


def transcript(directory: Path, turns: int) -> Path:
    path = directory / "transcript.jsonl"
    with path.open("w", encoding="utf-8") as sink:
        for index in range(turns):
            sink.write(json.dumps({
                "type": "user",
                "message": {"role": "user", "content": [{"type": "text", "text": f"go {index}"}]},
            }) + "\n")
    return path


def run(command: str, project: Path, turns: int = 1, background: bool = False) -> tuple[int, str]:
    payload = json.dumps({
        "tool_name": "Bash",
        "tool_input": {"command": command, "run_in_background": background},
        "cwd": str(project),
        "session_id": "probe-session",
        "transcript_path": str(transcript(project, turns)),
    })
    done = subprocess.run([sys.executable, str(HOOK)], input=payload,
                          capture_output=True, text=True)
    return done.returncode, (done.stderr or "").strip()


CASES = [
    ("detach-nohup", "nohup python3 run_workers.py --specs a", 2, "detaches"),
    ("detach-setsid", "setsid python3 listen.py", 2, "detaches"),
    ("detach-disown", "python3 x.py; disown", 2, "detaches"),
    ("trailing-ampersand", "python3 run_workers.py > log 2>&1 &", 2, "trailing &"),
    ("check-without-run", "orca orchestration check --json", 2, "default binding"),
    ("check-with-run", "orca orchestration check --run run_88ce8141de0a --json", 0, ""),
    ("check-with-terminal", "orca orchestration check --terminal term_abc", 0, ""),
    ("chained-ack-names-its-run",
     'orca orchestration check --run r --ack "$LAST"', 0, ""),
    ("ack-without-run",
     'orca orchestration check --ack "$LAST"', 2, "acknowledges against"),
    ("peek", "orca orchestration check --run r --peek", 2, "one consumer"),
    ("unsupervised-dispatch",
     'orca terminal create --worktree active --command "opencode" --title w7', 2,
     "unsupervised dispatch"),
    ("ps-liveness", 'ps aux | grep -c "[c]laude --dangerously"', 2, "process table"),
    ("pgrep-agent", "pgrep -fl xcodebuild", 2, "process table"),
    ("pipeline-status",
     'timeout 2400 xcodebuild build | tail -5; echo "exit=$?"', 2, "PIPESTATUS"),
    ("pipeline-status-across-and",
     'python3 run_verification.py | tail -3 && echo "exit=$?"', 2, "PIPESTATUS"),
    ("wait-flag",
     "orca orchestration worker-list --run r1 --wait", 2, "holds the whole turn"),
    ("file-poll-while",
     'while [ ! -f .scratch/w7/report.md ]; do sleep 20; done', 2, "waiting on a file"),
    ("file-poll-until-test",
     "until test -f out/done; do sleep 5; done", 2, "waiting on a file"),
    ("heredoc-then-a-real-detacher",
     "cat > note.md <<'EOF'\nharmless prose\nEOF\nsetsid python3 x.py", 2, "detaches"),
]

OPEN_LANES = [
    ("lane-repository", "git status --porcelain"),
    ("lane-repository-diff", "git diff --stat HEAD~1"),
    ("lane-worker-list", "orca orchestration worker-list --run run_x --json"),
    ("lane-send", "orca orchestration send --from term_a --type heartbeat"),
    ("lane-watch-read", "python3 .claude/tools/orca_channel.py watch read"),
    ("lane-ps-unrelated", "ps aux | head -3"),
    ("lane-pipestatus", 'xcodebuild build | tail -5; echo "${PIPESTATUS[0]}"'),
    ("lane-plain-status", "python3 Scripts/rules/run_verification.py; echo $?"),
    ("lane-logical-and", "make build && make test"),
    ("lane-redirect", "python3 x.py > log 2>&1"),
    ("lane-heredoc-quoting-a-banned-word",
     "cat > DESIGN.md <<'MDEOF'\nRule 1 refuses nohup, setsid and disown.\n"
     "Rule 3 refuses `orca orchestration check` with no --run.\n"
     "A line may even end in &\nMDEOF"),
    ("lane-one-shot-file-test",
     "test -f Config/regression/catalog-v2.json && echo present"),
    ("lane-bracket-file-test",
     "[ -f .scratch/w7/report.md ] && wc -l .scratch/w7/report.md"),
    ("lane-loop-over-a-list",
     'for f in Config/regression/catalog-root/*.json; do echo "$f"; done'),
    ("lane-waiting-flag-elsewhere",
     "xcodebuild -showBuildSettings | grep -i wait"),
    ("lane-heredoc-then-ordinary-work",
     "cat > note.md <<'EOF'\nnohup is refused\nEOF\ngit status --porcelain"),
]


def main() -> int:
    failures = []

    def check(name: str, got: int, want: int, message: str, phrase: str) -> None:
        if got != want or (phrase and phrase not in message):
            failures.append(name)
            print(f"FAIL {name}: exit {got} want {want} phrase {phrase!r} in {message[:120]!r}")
        else:
            print(f"OK   {name}")

    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        (project / ".claude/state").mkdir(parents=True)
        for name, command, expected, phrase in CASES:
            code, message = run(command, project)
            check(name, code, expected, message, phrase)
        for name, command in OPEN_LANES:
            code, message = run(command, project)
            check(name, code, 0, message, "")

    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        (project / ".claude/state").mkdir(parents=True)
        start = "orca orchestration worker-start --task task_a --worktree current --agent claude"
        code, message = run(start, project, turns=1)
        check("dispatch-first-is-allowed", code, 0, message, "")
        code, message = run(start, project, turns=1)
        check("dispatch-fanout-same-turn", code, 0, message, "")
        code, message = run(start, project, turns=2)
        check("dispatch-next-turn-needs-sweep", code, 2, message, "not been swept")

        state = json.loads((project / ".claude/state/coordinator.json").read_text())
        state["dispatches"] = []
        (project / ".claude/state/coordinator.json").write_text(json.dumps(state))
        code, message = run(start, project, turns=2)
        check("dispatch-after-sweep", code, 0, message, "")

    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        (project / ".claude/state").mkdir(parents=True)
        (project / ".claude/hooks-off").write_text("")
        code, message = run("nohup python3 x.py", project)
        check("hooks-off-switch", code, 0, message, "")

    print(f"gate probes: {len(CASES) + len(OPEN_LANES) + 5 - len(failures)} passed, "
          f"{len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
