from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Callable, Sequence

from harness.controller import CompletedInvocation

RunCallable = Callable[[Sequence[str], float], CompletedInvocation]

VOLATILE_FLAG_VALUES = frozenset({"--timeout-seconds", "--output-directory"})
_UUID = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)


class ReplayDrift(RuntimeError):
    pass


def redact_secret_marker(secret: str) -> str:
    return f"<redacted secret, {len(secret)} chars>"


def redact_secrets_in_text(text: str, secrets: Sequence[str]) -> str:
    redacted = text
    for secret in sorted((item for item in secrets if item), key=len, reverse=True):
        redacted = redacted.replace(secret, redact_secret_marker(secret))
    return redacted


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
        normalized.append(_UUID.sub("<uuid>", str(token)))
    return normalized


class RecordingTap:
    def __init__(
        self,
        inner: RunCallable,
        transcript_path: Path | str,
        redact: Sequence[str] = (),
    ) -> None:
        self.inner = inner
        self.transcript_path = Path(transcript_path)
        self.transcript_path.parent.mkdir(parents=True, exist_ok=True)
        self.transcript_path.write_text("", encoding="utf-8")
        self.redact = redact

    def __call__(
        self, command: Sequence[str], timeout_seconds: float
    ) -> CompletedInvocation:
        secrets = tuple(item for item in self.redact if item)
        try:
            completed = self.inner(command, timeout_seconds)
        except (subprocess.TimeoutExpired, TimeoutError):
            self._append(
                {
                    "command": [redact_secrets_in_text(str(token), secrets) for token in normalize_command(command)],
                    "timeout": True,
                    "timeoutSeconds": timeout_seconds,
                }
            )
            raise
        self._append(
            {
                "command": [redact_secrets_in_text(str(token), secrets) for token in normalize_command(command)],
                "returncode": completed.returncode,
                "stdout": redact_secrets_in_text(completed.stdout, secrets),
                "stderr": redact_secrets_in_text(completed.stderr, secrets),
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
        recorded = normalize_command(entry["command"])
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
    redact: Sequence[str] = (),
) -> tuple[RunCallable, str]:
    if replay:
        return ReplayRun(replay), "replay"
    if record:
        transcript = (
            str(default_transcript) if record.lower() in _ENABLED else record
        )
        return RecordingTap(default_run, transcript, redact=redact), "record"
    return default_run, "live"
