#!/usr/bin/env python3

"""Rewrite the Modules folder membership exceptions in Enchron.xcodeproj from disk.

The app target carries the whole Modules tree as a synchronized folder and excludes
every file the SwiftPM package compiles. That list is a pure function of the files on
disk, so it is regenerated here instead of hand-edited; `verify_package_membership.py`
still guards the result. Run this after adding, moving or deleting any Modules/*.swift
file, in the same change.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROJECT = REPOSITORY_ROOT / "Enchron.xcodeproj/project.pbxproj"
MODULES = REPOSITORY_ROOT / "Modules"
EXCEPTION_SET_ID = "E10000162FA1000100E1C001"

START = f"\t\t{EXCEPTION_SET_ID} /* Exceptions for \"Modules\" folder in \"Enchron\" target */ = {{"
HEADER = "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n"
FOOTER = "\t\t\t);\n\t\t\ttarget = C3B0F97F2F5726B30064596E /* Enchron */;\n\t\t};"


def module_files() -> list[str]:
    paths = [
        str(path.relative_to(MODULES))
        for path in MODULES.rglob("*.swift")
        if path.is_file()
    ]
    return sorted(paths)


def quoted(name: str) -> str:
    return f'"{name}"' if re.search(r"[^A-Za-z0-9/._]", name) else name


def rewrite(project: str, files: list[str]) -> str:
    start = project.find(START)
    if start == -1:
        raise SystemExit("membership exceptions block not found")
    body_start = project.find("membershipExceptions = (\n", start)
    body_end = project.find("\t\t\t);", body_start)
    if body_start == -1 or body_end == -1:
        raise SystemExit("membership exceptions list not found")
    block = "".join(f"\t\t\t\t{quoted(name)},\n" for name in files)
    return project[:body_start] + "membershipExceptions = (\n" + block + project[body_end:]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail when a rewrite would change the project")
    arguments = parser.parse_args()

    files = module_files()
    original = PROJECT.read_text(encoding="utf-8")
    updated = rewrite(original, files)
    if arguments.check:
        if original != updated:
            print("membership exceptions are stale", file=sys.stderr)
            return 1
        print(f"membership exceptions match {len(files)} files")
        return 0
    if original != updated:
        PROJECT.write_text(updated, encoding="utf-8")
        print(f"wrote {len(files)} membership exceptions")
    else:
        print(f"membership exceptions already current ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
