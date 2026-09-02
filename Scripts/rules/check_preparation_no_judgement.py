#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PREPARATIONS_ROOT = REPOSITORY_ROOT / "Regression/preparations"

def failures() -> list[str]:
    found: list[str] = []
    if not PREPARATIONS_ROOT.exists():
        return []
    for path in sorted(PREPARATIONS_ROOT.glob("*.md")):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        if not text.startswith("---\n"):
            continue
        try:
            front, _ = text[4:].split("\n---\n", 1)
            data = json.loads(front)
        except Exception:
            continue
        ops = data.get("operations", [])
        if not ops:
            continue
        last = ops[-1]
        last_op = last.get("operation", "")
        last_args = last.get("arguments", {})
        if last_op == "operation:accessibility.inspect@2" and last_args.get("requireMatchedElement") is True:
            found.append(f"{path.relative_to(REPOSITORY_ROOT)}: terminal operation is accessibility.inspect with requireMatchedElement:true")
        for op in ops:
            if op.get("operation") == "operation:accessibility.inspect@2" and op.get("arguments", {}).get("requireMatchedElement") is True:
                if op == last:
                    continue
                # Only flag if the preparation's inspect is with requireMatchedElement true and it decides readiness
                # For now, flag any preparation that contains such inspect as terminal or as readiness gate
                # We already flagged terminal, now check if any inspect decides readiness: if readiness is ready and ops contains such inspect
                pass
        # Check if preparation decides readiness by inspect: if any inspect with requireMatchedElement true exists and readiness is ready
        has_inspect = any(op.get("operation") == "operation:accessibility.inspect@2" and op.get("arguments", {}).get("requireMatchedElement") is True for op in ops)
        readiness = data.get("readiness")
        if has_inspect and readiness == "ready":
            # Check if the preparation's file still contains requireMatchedElement true (we already flagged terminal, but also flag any)
            # For our final tree, no preparation should have such inspect at all, so flag any
            if has_inspect:
                # To avoid double reporting, only report once per file if not already reported as terminal
                if not any(f.startswith(str(path.relative_to(REPOSITORY_ROOT))) and "terminal" in f for f in found):
                    found.append(f"{path.relative_to(REPOSITORY_ROOT)}: preparation with readiness ready contains accessibility.inspect requireMatchedElement:true")
    return sorted(set(found))

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} preparation judgement violations")
        return 1
    print("no preparation judgement violations")
    return 0

if __name__ == "__main__":
    sys.exit(main())
