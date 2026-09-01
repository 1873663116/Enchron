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
DEFAULT_TIMINGS_DEVICE_PATH = Path(__file__).resolve().parents[2] / "Scripts/verification/controller_timings.device.json"
DEFAULT_TIMINGS_SIMULATOR_PATH = Path(__file__).resolve().parents[2] / "Scripts/verification/controller_timings.simulator.json"
MINIMUM_SAMPLES = 3
SECONDS_CLASS_MEDIAN = 10.0


def _load_verbs(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    verbs = data.get("verbs")
    if isinstance(verbs, dict):
        return verbs
    legacy: dict = {}
    for key, value in data.items():
        if key in ("verbs", "updatedAt"):
            continue
        if isinstance(value, dict) and "samples" in value:
            legacy[key] = value
    return legacy


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
    env_path = os.environ.get("ENCHRON_TIMINGS_PATH")
    if env_path:
        timings_paths = [Path(env_path)]
        display_name = Path(env_path).name
    else:
        timings_paths = [DEFAULT_TIMINGS_DEVICE_PATH, DEFAULT_TIMINGS_SIMULATOR_PATH]
        display_name = f"{DEFAULT_TIMINGS_DEVICE_PATH.name}, {DEFAULT_TIMINGS_SIMULATOR_PATH.name}"
    tokens = set(re.findall(r"[A-Za-z][A-Za-z-]*", command))
    samples_by_action: dict[str, list[float]] = {}
    for timings_path in timings_paths:
        verbs = _load_verbs(timings_path)
        for action, entry in sorted(verbs.items()):
            if action not in tokens:
                continue
            raw_samples = (entry or {}).get("samples", []) if isinstance(entry, dict) else []
            if not isinstance(raw_samples, list):
                continue
            for item in raw_samples:
                if isinstance(item, dict):
                    if item.get("censored"):
                        continue
                    sec = item.get("seconds")
                    if isinstance(sec, (int, float)):
                        samples_by_action.setdefault(action, []).append(float(sec))
                    else:
                        try:
                            sec_f = float(sec)
                        except (TypeError, ValueError):
                            continue
                        samples_by_action.setdefault(action, []).append(float(sec_f))
                elif isinstance(item, (int, float)):
                    samples_by_action.setdefault(action, []).append(float(item))
    facts = []
    for action in sorted(samples_by_action):
        samples = samples_by_action[action]
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
        f"Measured controller timings ({display_name}): "
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
