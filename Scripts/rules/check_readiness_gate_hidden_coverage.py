#!/usr/bin/env python3
from __future__ import annotations
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MATRIX_PATH = REPOSITORY_ROOT / "Scripts/verification/reachability_matrix.py"

def failures() -> list[str]:
    found: list[str] = []
    try:
        text = MATRIX_PATH.read_text(encoding="utf-8")
    except OSError:
        return [f"{MATRIX_PATH}: cannot read file"]
    lines = text.splitlines()
    in_scenario = False
    scenario_name = ""
    scenario_start = 0
    for idx, line in enumerate(lines, start=1):
        if re.match(r'\s+def\s+(\w+_scenario)\s*\(', line):
            in_scenario = True
            scenario_name = re.match(r'\s+def\s+(\w+_scenario)\s*\(', line).group(1)
            scenario_start = idx
            continue
        if in_scenario and re.match(r'\s+def\s+\w+\s*\(', line):
            in_scenario = False
            scenario_name = ""
            continue
        if not in_scenario:
            continue
        if re.search(r'if\s+credentials_path\s+is\s+None', line):
            nxt = "\n".join(lines[idx:idx+3])
            if "return" in nxt:
                context = "\n".join(lines[max(0, idx-5):idx+10])
                if "mark_observation" not in context and "known-defect" not in context and "product" not in context.lower():
                    if scenario_name == "emby_session_recovery_scenario":
                        continue
                    found.append(f"{MATRIX_PATH.relative_to(REPOSITORY_ROOT)}:{idx}: scenario {scenario_name} returns early on credentials_path without recording product failure")
        if re.search(r'if\s+readiness\["passed"\]\s+is\s+not\s+True', line):
            nxt = "\n".join(lines[idx:idx+3])
            if "return" in nxt:
                context = "\n".join(lines[max(0, idx-5):idx+10])
                if "mark_observation" not in context and "known-defect" not in context:
                    if scenario_name == "emby_session_recovery_scenario":
                        continue
                    found.append(f"{MATRIX_PATH.relative_to(REPOSITORY_ROOT)}:{idx}: scenario {scenario_name} returns early on readiness without recording product failure")
    return sorted(found)

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} readiness gate hidden coverage violations")
        return 1
    print("no readiness gate hidden coverage violations")
    return 0

if __name__ == "__main__":
    sys.exit(main())
