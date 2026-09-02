#!/usr/bin/env python3
from __future__ import annotations
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PATTERN = re.compile(r"\b(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})\b")
WALL_CLOCK_PATTERN = re.compile(r"\b(?:controlsAutoHideSeconds|settleDelayMillis)\s*[:=]\s*\d+")
ABSOLUTE_PATH_PATTERN = re.compile(r'":\s*"/[^"]*"')
DEVICE_ID_PATTERN = re.compile(r"\bdevice[_-]?id\b.*[0-9a-fA-F-]{8,}", re.IGNORECASE)
PORT_PATTERN = re.compile(r":\s*\d{4,5}\b")

def scan_roots() -> tuple[Path, ...]:
    return (
        REPOSITORY_ROOT / "Scripts/verification",
        REPOSITORY_ROOT / "Scripts/regression",
        REPOSITORY_ROOT / "Config",
    )

def r5_scan_roots() -> tuple[Path, ...]:
    return (
        REPOSITORY_ROOT / "Regression/operations",
        REPOSITORY_ROOT / "Regression/preparations",
        REPOSITORY_ROOT / "Config/regression/catalog-v2.json",
    )

def failures() -> list[str]:
    found: list[str] = []
    for root in scan_roots():
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix not in {".py", ".json", ".md", ".txt", ".sh", ".zsh"}:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for index, line in enumerate(text.splitlines(), start=1):
                if PATTERN.search(line):
                    relative = path.relative_to(REPOSITORY_ROOT).as_posix()
                    found.append(f"{relative}:{index}: contains literal RFC1918 address")
    for root in r5_scan_roots():
        if root.is_file():
            paths = [root]
        elif root.is_dir():
            paths = sorted(root.rglob("*"))
        else:
            continue
        for path in paths:
            if not path.is_file():
                continue
            if path.suffix not in {".py", ".json", ".md"}:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            relative = path.relative_to(REPOSITORY_ROOT).as_posix()
            for index, line in enumerate(text.splitlines(), start=1):
                if WALL_CLOCK_PATTERN.search(line):
                    if "estimatedCostMillis" in line:
                        continue
                    found.append(f"{relative}:{index}: contains literal wall-clock timeout")
                if ABSOLUTE_PATH_PATTERN.search(line):
                    if "repo://" in line or "workspace://" in line or "result://" in line:
                        continue
                    stripped = line.strip()
                    if '"/' in line and not stripped.startswith('"'):
                        if re.search(r'"/(?:Users|var|tmp|private|Volumes)/', line):
                            found.append(f"{relative}:{index}: contains absolute path literal")
    return sorted(found)

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} literal RFC1918 violations")
        return 1
    count = 0
    for root in scan_roots():
        if root.is_dir():
            count += sum(1 for _ in root.rglob("*") if _.is_file())
    print(f"no literal RFC1918 in {count} files")
    return 0

if __name__ == "__main__":
    sys.exit(main())
