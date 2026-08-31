#!/usr/bin/env python3

"""PreToolUse gate on Write/Edit: refuse a hand write to a materialized file.

`Config/regression/catalog-v2.json` and the trees under
`Config/regression/catalog-root` are outputs. `Scripts/regression/materialize_catalog_v2.py`
builds the first from the second and binds each obligation to the summary and
digest the runner later checks. A hand edit to either one changes the bytes
without changing that binding, and the result is a Catalog that passes its own
structural checks while naming evidence the run cannot produce.

The rule is a path test, not a content test: it does not read what was written,
only where. `.claude/hooks-off` disables it, as it does the Bash gate.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

MATERIALIZED = {
    "Config/regression/catalog-v2.json": (
        "catalog-v2.json is the output of Scripts/regression/materialize_catalog_v2.py. "
        "Editing it directly changes the bytes without rebuilding the summary and "
        "digest bindings the runner verifies, which produces a Catalog that passes "
        "its own structure checks while naming evidence no run can produce. Edit the "
        "source under Config/regression/catalog-root and re-materialize."
    ),
    "Config/regression/catalog-root": (
        "Files under catalog-root carry digests the materializer recomputes. Write "
        "through the materializer so the digest and the content stay one fact: "
        "python3 Scripts/regression/materialize_catalog_v2.py."
    ),
}


def verdict(file_path: str) -> str | None:
    if not file_path:
        return None
    posix = Path(file_path).as_posix()
    for prefix, reason in MATERIALIZED.items():
        if prefix in posix:
            return reason
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    if payload.get("tool_name") not in ("Write", "Edit", "NotebookEdit"):
        return 0
    project = Path(payload.get("cwd") or ".")
    if (project / ".claude/hooks-off").exists():
        return 0
    reason = verdict(str((payload.get("tool_input") or {}).get("file_path") or ""))
    if reason is None:
        return 0
    print(reason, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
