#!/usr/bin/env python3
"""Report which feature promises have no evidence owner.

The feature map under .agents/skills/vp-e2e/features/ is the promise
list. Each file carries an "## 证据" table naming, per evidence kind, what the
criterion is and who enforces it. A cell reading 待建 or 待做 is a promise nobody
is watching.

This script answers "which promises are unguarded right now" by reading those
tables. It fails loudly when the map itself is malformed or missing, because a
coverage check that silently reports zero gaps is worse than no check.

Exit codes: 0 every promise owned, 1 gaps found, 2 the check could not run.
"""

import os
import re
import sys
from pathlib import Path

FEATURES = Path(".agents/skills/vp-e2e/features")
UNOWNED = ("待建", "待做")
KINDS = ("结构", "物理", "感知")


def features_root() -> Path:
    root = Path(os.environ.get("ENCHRON_FEATURE_MAP_ROOT", ".")).resolve()
    return root / FEATURES


def parse_evidence(text: str, path: Path) -> list[tuple[str, str, str]]:
    section = re.search(r"^## 证据\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not section:
        raise ValueError(f"{path.name} has no '## 证据' section")
    rows = []
    for line in section.group(1).splitlines():
        line = line.strip()
        if not line.startswith("|") or set(line) <= set("|- "):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 3 or cells[0] in ("种类", ""):
            continue
        rows.append((cells[0], cells[1], cells[2]))
    if not rows:
        raise ValueError(f"{path.name} has an empty 证据 table")
    for kind, _, _ in rows:
        if kind not in KINDS:
            raise ValueError(f"{path.name} has unknown evidence kind {kind!r}")
    return rows


def main() -> int:
    root = features_root()
    if not root.is_dir():
        print(f"feature map not found at {root}", file=sys.stderr)
        return 2

    files = sorted(p for p in root.glob("*.md") if p.name != "README.md")
    if not files:
        print(f"no feature files under {root}", file=sys.stderr)
        return 2

    gaps: list[tuple[str, str, str]] = []
    for path in files:
        try:
            rows = parse_evidence(path.read_text(encoding="utf-8"), path)
        except ValueError as error:
            print(f"malformed feature map: {error}", file=sys.stderr)
            return 2
        for kind, criterion, owner in rows:
            if any(marker in owner for marker in UNOWNED):
                gaps.append((path.stem, kind, criterion))

    print(f"feature evidence coverage: {len(files)} features")
    if not gaps:
        print("  every declared evidence has an owner")
        return 0

    print(f"  {len(gaps)} unguarded:")
    for feature, kind, criterion in gaps:
        print(f"    {feature} [{kind}] {criterion}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
