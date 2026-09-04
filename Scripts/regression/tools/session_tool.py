#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import sys
from typing import Any, Callable, Dict, Mapping, Optional, Tuple

from regression.core.events import now_rfc3339_millis


VERIFICATION = Path(__file__).resolve().parents[2] / "verification"
if str(VERIFICATION) not in sys.path:
    sys.path.insert(0, str(VERIFICATION))

from interactive_visionpro_ui import (
    ensure_session,
    halt_session,
    parse_arguments,
)


TIMELINE_FILENAME = "timeline.jsonl"
POLL_INTERVAL_SECONDS = 2.5
SNAPSHOT_KIND = "snapshot"
MARK_KIND = "mark"

AGENT_MODE = "agent"
HUMAN_MODE = "human"
SESSION_MODES = (AGENT_MODE, HUMAN_MODE)

ENSURE_STAGE = "ensure"
HALT_STAGE = "halt"
SESSION_STAGES = (ENSURE_STAGE, HALT_STAGE)

ENSURE_SESSION_ACTION = "ensure-session"
HALT_ACTION = "halt"

ENSURE_RESULT_STAGES = (
    "adopted",
    "ready",
    "halt",
    "firstCommand",
    "readyTimeout",
)

CONTROLLER_FAILURES = (OSError, RuntimeError, ValueError)


class SessionToolError(ValueError):
    pass


@dataclass(frozen=True)
class TimelineEntry:
    recorded_at: str
    kind: str
    reading: Mapping[str, Any]

    def payload_line(self) -> Dict[str, Any]:
        return {
            "recordedAt": self.recorded_at,
            "kind": self.kind,
            "reading": dict(self.reading),
        }


def run(
    mode: str,
    device: str,
    stage: str,
    execution_input: Optional[str] = None,
    output_directory: Optional[str] = None,
) -> Dict[str, Any]:
    if mode not in SESSION_MODES:
        joined = " or ".join(SESSION_MODES)
        raise SessionToolError(f"session runs in {joined} mode, not {mode!r}")
    if stage not in SESSION_STAGES:
        joined = " or ".join(SESSION_STAGES)
        raise SessionToolError(f"session drives the {joined} stage, not {stage!r}")
    if not isinstance(device, str) or not device:
        raise SessionToolError("session needs the device it drives")

    argv = [f"--device={device}"]
    if output_directory is not None:
        argv.append(f"--output-directory={output_directory}")
    if stage == ENSURE_STAGE:
        if execution_input is not None:
            argv.append(f"--execution-input={execution_input}")
        result = _forward(ensure_session, argv + [ENSURE_SESSION_ACTION])
        if mode == HUMAN_MODE and output_directory is not None:
            path = timeline_path(Path(output_directory))
            append_entry(
                path,
                TimelineEntry(
                    now_rfc3339_millis(),
                    SNAPSHOT_KIND,
                    {"stage": ENSURE_STAGE, "device": device},
                ),
            )
            result["timeline"] = str(path)
        return result
    return _forward(halt_session, argv + [HALT_ACTION])


def timeline_path(output_directory: Path) -> Path:
    return Path(output_directory) / TIMELINE_FILENAME


def append_entry(path: Path, entry: TimelineEntry) -> TimelineEntry:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with Path(path).open("a", encoding="utf-8") as sink:
        sink.write(json.dumps(entry.payload_line(), sort_keys=True) + "\n")
        sink.flush()
        os.fsync(sink.fileno())
    return entry


def mark(path: Path, note: str, clock: Callable[[], str] = now_rfc3339_millis) -> TimelineEntry:
    if not isinstance(note, str) or not note.strip():
        raise SessionToolError("a mark carries what the wearer saw at that moment")
    return append_entry(path, TimelineEntry(clock(), MARK_KIND, {"note": note}))


def poll_timeline(
    path: Path,
    read: Callable[[], Mapping[str, Any]],
    until: Callable[[int], bool],
    sleep: Callable[[float], None],
    clock: Callable[[], str] = now_rfc3339_millis,
    interval: float = POLL_INTERVAL_SECONDS,
) -> Tuple[TimelineEntry, ...]:
    written = []
    while not until(len(written)):
        written.append(
            append_entry(path, TimelineEntry(clock(), SNAPSHOT_KIND, dict(read())))
        )
        if not until(len(written)):
            sleep(interval)
    return tuple(written)


def read_timeline(path: Path) -> Tuple[Mapping[str, Any], ...]:
    if not Path(path).is_file():
        return ()
    return tuple(
        json.loads(line)
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip()
    )


def _forward(call: Callable[[Any], Mapping[str, Any]], argv: list) -> Dict[str, Any]:
    try:
        arguments = parse_arguments(argv)
    except SystemExit as error:
        raise SessionToolError(
            f"the controller refused these session arguments: {argv}"
        ) from error
    try:
        return dict(call(arguments))
    except CONTROLLER_FAILURES as error:
        return {"success": False, "error": str(error)}


__all__ = (
    "AGENT_MODE",
    "CONTROLLER_FAILURES",
    "ENSURE_RESULT_STAGES",
    "ENSURE_SESSION_ACTION",
    "ENSURE_STAGE",
    "HALT_ACTION",
    "HALT_STAGE",
    "HUMAN_MODE",
    "MARK_KIND",
    "POLL_INTERVAL_SECONDS",
    "SNAPSHOT_KIND",
    "TIMELINE_FILENAME",
    "TimelineEntry",
    "append_entry",
    "mark",
    "poll_timeline",
    "read_timeline",
    "timeline_path",
    "SESSION_MODES",
    "SESSION_STAGES",
    "SessionToolError",
    "run",
)
