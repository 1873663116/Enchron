#!/usr/bin/env python3
from __future__ import annotations
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHANNEL_PATH = REPOSITORY_ROOT / "Apps/Enchron/TestCommandChannel.swift"
INVENTORY_PATH = REPOSITORY_ROOT / "Config/reachability_operation_inventory.json"

def failures() -> list[str]:
    found: list[str] = []
    try:
        text = CHANNEL_PATH.read_text(encoding="utf-8")
    except OSError:
        return [f"{CHANNEL_PATH}: cannot read file"]
    verbs = sorted(set(re.findall(r'case\s+"([^"]+)"', text)))
    try:
        inventory_text = INVENTORY_PATH.read_text(encoding="utf-8") if INVENTORY_PATH.exists() else ""
    except OSError:
        inventory_text = ""
    scripts_text = ""
    for root in [REPOSITORY_ROOT / "Scripts", REPOSITORY_ROOT / "Regression/operations"]:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in {".py", ".md", ".json", ".sh", ".zsh"}:
                continue
            try:
                scripts_text += path.read_text(encoding="utf-8", errors="ignore") + "\n"
            except OSError:
                continue
    combined = scripts_text + inventory_text
    for verb in verbs:
        if verb == "prepareEmbyAccount":
            continue
        if verb not in combined:
            found.append(f"{CHANNEL_PATH.relative_to(REPOSITORY_ROOT)}: orphan verb \"{verb}\" has no owner in Scripts/, Regression/operations or Config/reachability_operation_inventory.json")
    return sorted(found)

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} orphan verb violations")
        return 1
    print("no orphan verb violations")
    return 0

if __name__ == "__main__":
    sys.exit(main())
