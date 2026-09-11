#!/usr/bin/env python3

"""PreToolUse gate on Write/Edit: refuse a hand write to Catalog output.

Three trees carry three different roles, and only the first two are output.

`Regression/` is materialized. `Scripts/regression/materialize_catalog_v2.py`
renders every contract in it from the blueprint and the persistent source, and
binds each obligation to the summary and digest the runner later checks;
`Regression/reviews/` holds receipts `Scripts/regression/reviewctl.py` writes
against those digests. A hand edit to either changes the bytes without changing
the binding, and the result is a Catalog that passes its own structural checks
while naming evidence no run can produce.

`Config/regression/catalog-v2.json` is the blueprint. It signs itself with
`contentDigest` over its own canonical bytes and carries one `copyDocuments`
digest per persistent source document. Both are computed from content that is
already written, so a hand edit leaves a blueprint whose signature no longer
belongs to it. It is changed by a program that recomputes both and then
re-materializes.

`Config/regression/catalog-root/` is the persistent source: README, the
protocols, `semantic-authority.json`, `facts/` and `promises/`. It is
maintained by hand. Editing it is the intended way to change those documents;
the blueprint's digest for the edited file is recomputed afterwards.

The rule is a path test, not a content test: it does not read what was written,
only where. Matching is by whole path segments, so `Config/regression` and a
`VisionProCoreRegression` build directory are not `Regression`.
`.claude/hooks-off` disables it, as it does the Bash gate.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

MATERIALIZED: tuple[tuple[tuple[str, ...], str], ...] = (
    (
        ("Regression",),
        "Regression/ is output, not source. Its contracts are rendered by "
        "Scripts/regression/materialize_catalog_v2.py and its reviews/ receipts "
        "by Scripts/regression/reviewctl.py, both bound to digests the runner "
        "verifies. A hand edit changes the bytes and not the binding. Change the "
        "hand-maintained source under Config/regression/catalog-root, or the "
        "blueprint Config/regression/catalog-v2.json through a program that "
        "re-signs it, then re-materialize.",
    ),
    (
        ("Config", "regression", "catalog-v2.json"),
        "catalog-v2.json is a signed blueprint: contentDigest covers its own "
        "canonical bytes and every copyDocuments entry carries the digest of a "
        "file under Config/regression/catalog-root. Both are computed, not "
        "typed, so a hand edit leaves a blueprint whose signature is no longer "
        "its own. Change it from a script that recomputes the copyDocuments "
        "digests and contentDigest, then run "
        "python3 Scripts/regression/materialize_catalog_v2.py. Documents under "
        "Config/regression/catalog-root are hand-maintained and are not gated.",
    ),
)


def verdict(file_path: str) -> str | None:
    if not file_path:
        return None
    segments = Path(file_path).as_posix().split("/")
    for prefix, reason in MATERIALIZED:
        width = len(prefix)
        for start in range(len(segments) - width + 1):
            if tuple(segments[start : start + width]) == prefix:
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
