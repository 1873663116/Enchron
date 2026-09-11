#!/usr/bin/env python3

"""Probes for the materialized-output write gate.

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
GATE = CLAUDE / "hooks/catalog_write_gate.py"

CASES = [
    ("catalog-v2-write", "Write", "Config/regression/catalog-v2.json", 2, "materialize_catalog_v2"),
    ("catalog-v2-edit", "Edit", "Config/regression/catalog-v2.json", 2, "contentDigest"),
    ("catalog-v2-absolute", "Write",
     "/Volumes/x/Enchron/Config/regression/catalog-v2.json", 2, "materialize_catalog_v2"),
    ("materialized-contract", "Edit",
     "Regression/journeys/dynamic-range-interpretation/journey.md", 2,
     "Regression/ is output"),
    ("materialized-promise", "Write", "Regression/promises/viewing-state.md", 2,
     "re-materialize"),
    ("materialized-review-receipt", "Write",
     "Regression/reviews/reports/sha256/0f.md", 2, "reviewctl"),
    ("materialized-absolute", "Write", "/Volumes/x/Enchron/Regression/README.md", 2,
     "Regression/ is output"),
    ("lane-catalog-root-promise", "Write",
     "Config/regression/catalog-root/promises/viewing-state.md", 0, ""),
    ("lane-catalog-root-readme", "Edit",
     "Config/regression/catalog-root/README.md", 0, ""),
    ("lane-catalog-root-absolute", "Write",
     "/Volumes/x/Enchron/Config/regression/catalog-root/facts/a.md", 0, ""),
    ("lane-catalog-sibling-config", "Write",
     "Config/regression/known_defects.json", 0, ""),
    ("lane-catalog-source-elsewhere", "Write",
     "Config/reachability_operation_inventory.json", 0, ""),
    ("lane-the-materializer-itself", "Edit",
     "Scripts/regression/materialize_catalog_v2.py", 0, ""),
    ("lane-lowercase-regression-rule", "Edit",
     "Scripts/rules/test_regression_core_catalog.py", 0, ""),
    ("lane-longer-segment-is-not-regression", "Write",
     ".scratch/DerivedData/VisionProCoreRegression/Build/settings.json", 0, ""),
    ("lane-device-test-plan", "Edit", "VisionProCoreRegression.xctestplan", 0, ""),
    ("lane-a-note-about-the-catalog", "Write",
     ".scratch/notes/catalog-v2.md", 0, ""),
    ("lane-ordinary-source", "Edit", "Apps/Enchron/MainView.swift", 0, ""),
]


def run(project: Path, tool: str, path: str) -> tuple[int, str]:
    payload = json.dumps({"tool_name": tool, "cwd": str(project),
                          "tool_input": {"file_path": path}})
    done = subprocess.run([sys.executable, str(GATE)], input=payload,
                          capture_output=True, text=True)
    return done.returncode, done.stderr


def main() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        (project / ".claude").mkdir()
        for name, tool, path, want, phrase in CASES:
            code, message = run(project, tool, path)
            if code != want or (phrase and phrase not in message):
                failures.append(name)
                print(f"FAIL {name}: exit {code} want {want} phrase {phrase!r} "
                      f"in {message[:120]!r}")
            else:
                print(f"OK   {name}")

        code, _ = run(project, "Read", "Regression/promises/viewing-state.md")
        if code != 0:
            failures.append("lane-reading-is-never-blocked")
            print(f"FAIL lane-reading-is-never-blocked: exit {code}")
        else:
            print("OK   lane-reading-is-never-blocked")

        (project / ".claude/hooks-off").write_text("")
        code, _ = run(project, "Write", "Regression/promises/viewing-state.md")
        if code != 0:
            failures.append("hooks-off-switch")
            print(f"FAIL hooks-off-switch: exit {code}")
        else:
            print("OK   hooks-off-switch")

    print(f"catalog write probes: {len(CASES) + 2 - len(failures)} passed, "
          f"{len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
