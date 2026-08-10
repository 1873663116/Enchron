#!/usr/bin/env python3
"""PreToolUse hook: when a controller action with a measured seconds-class
record is sent to the background, inject the measured numbers as context.
It never blocks and never decides; actions without a measured record pass
in silence."""

import json
import os
import re
import statistics
import sys
from pathlib import Path

CONTROLLER_NAME = "interactive_visionpro_ui.py"
DEFAULT_TIMINGS_PATH = (
    Path(__file__).resolve().parents[2]
    / "Scripts/verification/controller_timings.json"
)
MINIMUM_SAMPLES = 3
SECONDS_CLASS_MEDIAN = 10.0


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    tool_input = payload.get("tool_input") or {}
    command = str(tool_input.get("command") or "")
    if not tool_input.get("run_in_background"):
        return 0
    if CONTROLLER_NAME not in command:
        return 0

    timings_path = Path(
        os.environ.get("ENCHRON_TIMINGS_PATH") or DEFAULT_TIMINGS_PATH
    )
    try:
        timings = json.loads(timings_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return 0

    tokens = set(re.findall(r"[A-Za-z][A-Za-z-]*", command))
    facts = []
    for action, entry in sorted(timings.items()):
        if action not in tokens:
            continue
        samples = [
            value
            for value in (entry or {}).get("samples", [])
            if isinstance(value, (int, float))
        ]
        if len(samples) < MINIMUM_SAMPLES:
            continue
        median = statistics.median(samples)
        if median > SECONDS_CLASS_MEDIAN:
            continue
        facts.append(
            f"{action} has {len(samples)} measured foreground round trips, "
            f"median {median:.1f}s, range {min(samples):.1f}-{max(samples):.1f}s"
        )
    if not facts:
        return 0

    context = (
        f"Measured controller timings ({timings_path.name}): "
        + "; ".join(facts)
        + ". Background scheduling adds one wake-up round trip per step, "
        "measured in minutes in recorded sessions. This call proceeds in "
        "the background as issued."
    )
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": context,
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
