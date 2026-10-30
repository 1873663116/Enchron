#!/usr/bin/env python3

"""Media source resolution must carry one loopback policy.

A second resolvePlayableSource overload with a caller-supplied read cap lets an
entry point silently fall back to a small backend read. SwiftLint cannot see
that semantic default, and the smaller cap produced a steady playback stall in
one entry point while another entry point stayed fast. The cap belongs to the
byte stream registration, not to a caller.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCAN_ROOTS = (REPOSITORY_ROOT / "Modules", REPOSITORY_ROOT / "Apps")
POLICY_OWNER = REPOSITORY_ROOT / "Modules/MediaSource/MediaByteStream.swift"
FORBIDDEN = ("backendReadCap", "BluRayReadPolicy")


def swift_files() -> list[Path]:
    files: list[Path] = []
    for root in SCAN_ROOTS:
        files.extend(root.rglob("*.swift"))
    return files


def main() -> int:
    violations: list[str] = []
    for path in swift_files():
        if path == POLICY_OWNER:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for number, line in enumerate(text.splitlines(), 1):
            if any(token in line for token in FORBIDDEN):
                violations.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}:{number}: {line.strip()}"
                )
    if violations:
        print("Media source resolution must use the loopback policy only.")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("Media source resolution uses the loopback policy only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
