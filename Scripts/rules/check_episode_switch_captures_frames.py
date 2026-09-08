#!/usr/bin/env python3
"""An episode switch driven inside a Scenario must be followed by captured frames.

A black screen with audio satisfies the accessibility tree and the window
control plane; only pixels refuse it (2026-09-08, docked → 180_3D.mp4). Every
accessibility.activate whose identifiers name an episodes menu therefore needs
a later evidence.capture-frames call in the same Scenario.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT = REPOSITORY_ROOT / "Config/regression/catalog-v2.json"
ACTIVATE = "operation:accessibility.activate@"
CAPTURE = "operation:evidence.capture-frames@"
EPISODES_MENU_SUFFIX = "-menu-episodes"


def selects_an_episode(call: dict) -> bool:
    if not str(call.get("operation", "")).startswith(ACTIVATE):
        return False
    identifiers = call.get("arguments", {}).get("identifiers", [])
    return any(str(identifier).endswith(EPISODES_MENU_SUFFIX) for identifier in identifiers)


def violations(catalog: dict) -> list[str]:
    found: list[str] = []
    for scenario in catalog.get("scenarios", []):
        operations = scenario.get("operations", [])
        for index, call in enumerate(operations):
            if not selects_an_episode(call):
                continue
            later = operations[index + 1:]
            if any(str(item.get("operation", "")).startswith(CAPTURE) for item in later):
                continue
            found.append(
                f"{scenario.get('id')}: {call.get('callId')} selects an episode "
                "without a later evidence.capture-frames call"
            )
    return found


def main() -> int:
    catalog = json.loads(BLUEPRINT.read_text(encoding="utf-8"))
    found = violations(catalog)
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} episode switch(es) without captured frames")
        return 1
    print("every episode switch captures frames")
    return 0


if __name__ == "__main__":
    sys.exit(main())
