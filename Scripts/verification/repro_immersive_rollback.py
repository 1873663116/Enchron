#!/usr/bin/env python3
"""Reproduce the immersive presentation rolling back to the flat window.

Opens the same clip repeatedly from the library and reads the device probe
after each attempt. An attempt is a rollback when the main window scene comes
back while the immersive space is still the requested presentation. The report
carries the delay from settlement to rollback and the executor's confirmation
timeout fields, which separate "the space never opened" from "the executor
never saw it open"."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import statistics
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from playback_mode_matrix import copy_probe_lines, parse_probe_timestamp  # noqa: E402

DEVICE = "00008142-001871A11491401C"
DEVELOPER_DIR = subprocess.run(
    ["xcode-select", "-p"], capture_output=True, text=True, check=True
).stdout.strip()
CONTROLLER = Path(__file__).resolve().parent / "interactive_visionpro_ui.py"


def controller(output_directory: Path, *arguments: str) -> dict[str, object]:
    completed = subprocess.run(
        [
            sys.executable, str(CONTROLLER),
            "--device", DEVICE,
            "--developer-dir", DEVELOPER_DIR,
            "--output-directory", str(output_directory),
            *arguments,
        ],
        capture_output=True, text=True, timeout=900,
    )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {"success": False, "error": (completed.stderr or completed.stdout)[-400:]}


def parse_fields(line: str, marker: str) -> dict[str, str] | None:
    if f" {marker} " not in line:
        return None
    payload = line.split(f" {marker} ", 1)[1]
    return dict(part.split("=", 1) for part in payload.split() if "=" in part)


def classify(lines: list[str]) -> dict[str, object]:
    appeared_at: datetime | None = None
    settled_at: datetime | None = None
    rolled_back_at: datetime | None = None
    confirm_timeout: dict[str, str] | None = None
    shell_names: list[str] = []

    for line in lines:
        timestamp = parse_probe_timestamp(line)
        if " immersiveSpaceAppeared " in line:
            appeared_at = timestamp
            settled_at = None
            rolled_back_at = None
            confirm_timeout = None
            shell_names = []
        elif appeared_at is None:
            continue
        elif " settlement settled=true" in line and settled_at is None:
            settled_at = timestamp
        elif " immersiveConfirmTimeout " in line:
            confirm_timeout = parse_fields(line, "immersiveConfirmTimeout")
        elif " shellAttached " in line:
            fields = parse_fields(line, "shellAttached") or {}
            shell_names.append(fields.get("name", "?"))
        elif " mainWindowScene appeared " in line and rolled_back_at is None:
            rolled_back_at = timestamp

    def delay(start: datetime | None, end: datetime | None) -> float | None:
        if start is None or end is None:
            return None
        return round((end - start).total_seconds(), 2)

    return {
        "enteredImmersive": appeared_at is not None,
        "reachedSettled": settled_at is not None,
        "rolledBack": rolled_back_at is not None,
        "settleDelaySeconds": delay(appeared_at, settled_at),
        "rollbackDelaySeconds": delay(settled_at or appeared_at, rolled_back_at),
        "shellSequence": shell_names,
        "confirmTimeout": confirm_timeout,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--clip", default="180_3D_loop10.mp4")
    parser.add_argument("--attempts", type=int, default=8)
    parser.add_argument("--observe-seconds", type=float, default=25.0)
    arguments = parser.parse_args()

    evidence = arguments.evidence_dir.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=True)

    session = controller(evidence, "ensure-session")
    if session.get("stage") != "ready":
        print(f"session not ready: {session}", file=sys.stderr)
        return 1

    attempts: list[dict[str, object]] = []
    for index in range(1, arguments.attempts + 1):
        controller(evidence, "relaunch")
        time.sleep(6)
        baseline, _ = copy_probe_lines(evidence)
        offset = len(baseline or [])

        opened = controller(
            evidence, "tap", "--identifier",
            f"MediaLibrary-grid-video-{arguments.clip}", "--no-screenshot",
        )
        time.sleep(arguments.observe_seconds)

        lines, error = copy_probe_lines(evidence)
        delta = (lines or [])[offset:]
        attempt = {
            "attempt": index,
            "tapSucceeded": opened.get("success") is True,
            "probeError": error,
            **classify(delta),
        }
        attempts.append(attempt)
        (evidence / f"attempt-{index:02d}-probe.log").write_text(
            "\n".join(delta) + "\n", encoding="utf-8"
        )
        print(json.dumps(attempt, sort_keys=True), flush=True)

    entered = [a for a in attempts if a["enteredImmersive"]]
    rolled = [a for a in entered if a["rolledBack"]]
    delays = [
        a["rollbackDelaySeconds"] for a in rolled
        if a["rollbackDelaySeconds"] is not None
    ]
    report = {
        "clip": arguments.clip,
        "attempts": len(attempts),
        "enteredImmersive": len(entered),
        "rolledBack": len(rolled),
        "rollbackRate": round(len(rolled) / len(entered), 3) if entered else None,
        "rollbackDelaySeconds": {
            "values": delays,
            "median": round(statistics.median(delays), 2) if delays else None,
        },
        "withConfirmTimeout": sum(1 for a in rolled if a["confirmTimeout"]),
        "detail": attempts,
    }
    (evidence / "rollback-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps({k: v for k, v in report.items() if k != "detail"}, indent=2,
                     sort_keys=True))
    return 0 if not rolled else 2


if __name__ == "__main__":
    raise SystemExit(main())
