from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Callable, Sequence

from harness.controller import CompletedInvocation

RunCallable = Callable[[Sequence[str], float], CompletedInvocation]

VOLATILE_FLAG_VALUES = frozenset({"--timeout-seconds"})


class ReplayDrift(RuntimeError):
    pass


def normalize_command(command: Sequence[str]) -> list[str]:
    normalized: list[str] = []
    skip_next = False
    for token in command:
        if skip_next:
            skip_next = False
            continue
        if token in VOLATILE_FLAG_VALUES:
            skip_next = True
            continue
        normalized.append(str(token))
    return normalized


class RecordingTap:
    def __init__(self, inner: RunCallable, transcript_path: Path | str) -> None:
        self.inner = inner
        self.transcript_path = Path(transcript_path)
        self.transcript_path.parent.mkdir(parents=True, exist_ok=True)
        self.transcript_path.write_text("", encoding="utf-8")

    def __call__(
        self, command: Sequence[str], timeout_seconds: float
    ) -> CompletedInvocation:
        try:
            completed = self.inner(command, timeout_seconds)
        except (subprocess.TimeoutExpired, TimeoutError):
            self._append(
                {
                    "command": normalize_command(command),
                    "timeout": True,
                    "timeoutSeconds": timeout_seconds,
                }
            )
            raise
        self._append(
            {
                "command": normalize_command(command),
                "returncode": completed.returncode,
                "stdout": completed.stdout,
                "stderr": completed.stderr,
            }
        )
        return completed

    def _append(self, entry: dict[str, object]) -> None:
        with self.transcript_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")


class ReplayRun:
    def __init__(self, transcript_path: Path | str) -> None:
        text = Path(transcript_path).read_text(encoding="utf-8")
        self.entries = [
            json.loads(line) for line in text.splitlines() if line.strip()
        ]
        self.cursor = 0

    def __call__(
        self, command: Sequence[str], timeout_seconds: float
    ) -> CompletedInvocation:
        actual = normalize_command(command)
        if self.cursor >= len(self.entries):
            raise ReplayDrift(
                f"the recording holds {len(self.entries)} calls but the scenario "
                f"issued another one: {actual!r}"
            )
        entry = self.entries[self.cursor]
        self.cursor += 1
        recorded = list(entry["command"])
        if recorded != actual:
            raise ReplayDrift(
                f"replay call {self.cursor} diverged from the recording; "
                f"recorded {recorded!r} but the scenario issued {actual!r}"
            )
        if entry.get("timeout"):
            raise subprocess.TimeoutExpired(list(command), timeout_seconds)
        return CompletedInvocation(
            returncode=int(entry["returncode"]),
            stdout=str(entry["stdout"]),
            stderr=str(entry["stderr"]),
        )

    def exhausted(self) -> bool:
        return self.cursor >= len(self.entries)


RECORD_ENV = "ENCHRON_RECORD"
REPLAY_ENV = "ENCHRON_REPLAY"
_ENABLED = frozenset({"1", "true", "on", "yes"})


def select_run(
    default_run: RunCallable,
    *,
    record: str,
    replay: str,
    default_transcript: Path | str,
) -> tuple[RunCallable, str]:
    if replay:
        return ReplayRun(replay), "replay"
    if record:
        transcript = (
            str(default_transcript) if record.lower() in _ENABLED else record
        )
        return RecordingTap(default_run, transcript), "record"
    return default_run, "live"
