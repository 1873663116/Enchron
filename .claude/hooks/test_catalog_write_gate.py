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
    ("catalog-v2-edit", "Edit", "Config/regression/catalog-v2.json", 2, "materialize_catalog_v2"),
    ("catalog-v2-absolute", "Write",
     "/Volumes/x/Enchron/Config/regression/catalog-v2.json", 2, "materialize_catalog_v2"),
    ("catalog-root-member", "Write",
     "Config/regression/catalog-root/scenarios/playback.json", 2, "digests the materializer"),
    ("lane-catalog-source-elsewhere", "Write",
     "Config/reachability_operation_inventory.json", 0, ""),
    ("lane-the-materializer-itself", "Edit",
     "Scripts/regression/materialize_catalog_v2.py", 0, ""),
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

        code, _ = run(project, "Read", "Config/regression/catalog-v2.json")
        if code != 0:
            failures.append("lane-reading-is-never-blocked")
            print(f"FAIL lane-reading-is-never-blocked: exit {code}")
        else:
            print("OK   lane-reading-is-never-blocked")

        (project / ".claude/hooks-off").write_text("")
        code, _ = run(project, "Write", "Config/regression/catalog-v2.json")
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
