#!/usr/bin/env python3

"""Checks that the shipping product carries no test or diagnostics surface.

Two rules, both checked against a per-file `#if DEBUG` region model:

- no `ProcessInfo.processInfo.environment` key reads outside `#if DEBUG`,
  except declared injection-seam captures listed in ALLOWED_ENV_CAPTURES;
- no `print(` calls outside `#if DEBUG`, because release diagnostics belong
  in Logger or nowhere.

A file whose first non-comment line is `#if DEBUG` is treated as fully gated.
The region model understands `#if DEBUG`, `#if !DEBUG`, `#elseif DEBUG`,
`#else`, and `#endif`; `#if` with any other condition is a neutral scope —
its `#else` stays release-visible.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RULE = "release-surface"

SCAN_ROOTS = ("Apps", "Modules", "Packages")

"""Sites where the process environment is captured only to forward it into a
test seam; every consumer of the captured dictionary is #if DEBUG gated.
Keyed by repository-relative path, each entry is a substring that must
appear on the same line as the capture."""
ALLOWED_ENV_CAPTURES = {
    "Apps/Enchron/EnchronApplication.swift": (
        "init(environment: [String: String] = ProcessInfo.processInfo.environment",
        "let environment = ProcessInfo.processInfo.environment",
    ),
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDemuxBuffering.swift": (
        "environment: [String: String] = ProcessInfo.processInfo.environment",
    ),
    "Packages/OceanEnvironment/Sources/OceanEnvironment/Vendor/OceanProbe/"
    "OceanProbeRenderer.swift": (
        "init(environment: [String: String] = ProcessInfo.processInfo.environment",
    ),
}

ENV_READ = re.compile(r"ProcessInfo\.processInfo\.environment")
ENV_SUBSCRIPT = re.compile(r"\benvironment\[|\benvironment\s*\[")
PRINT_CALL = re.compile(r"(?<![\w.])print\(")


def production_swift_files() -> list[Path]:
    files: list[Path] = []
    for root_name in SCAN_ROOTS:
        root = REPOSITORY_ROOT / root_name
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.swift")):
            parts = path.relative_to(REPOSITORY_ROOT).parts
            if ".build" in parts or "Tests" in parts:
                continue
            if "Sources" not in parts and parts[0] == "Packages":
                continue
            files.append(path)
    return files


def whole_file_gated(lines: list[str]) -> bool:
    body = [
        line.strip()
        for line in lines
        if line.strip() and not line.strip().startswith("//")
    ]
    return bool(body) and body[0] == "#if DEBUG" and body[-1] == "#endif"


def audit_file(path: Path) -> list[str]:
    relative = path.relative_to(REPOSITORY_ROOT)
    lines = path.read_text(encoding="utf-8").splitlines()
    if whole_file_gated(lines):
        return []
    scopes: list[str] = []
    failures: list[str] = []
    allowed = ALLOWED_ENV_CAPTURES.get(str(relative), ())
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            condition = stripped[3:].strip()
            if condition == "DEBUG":
                scopes.append("debug")
            elif condition == "!DEBUG":
                scopes.append("inverted")
            else:
                scopes.append("release")
            continue
        if stripped.startswith("#elseif"):
            if scopes:
                condition = stripped[7:].strip()
                if "DEBUG" in condition and "!DEBUG" not in condition:
                    scopes[-1] = "debug" if scopes[-1] != "debug" else "release"
                else:
                    scopes[-1] = "release"
            continue
        if stripped == "#else":
            if scopes:
                top = scopes[-1]
                scopes[-1] = (
                    "release" if top == "debug"
                    else "debug" if top == "inverted"
                    else "release"
                )
            continue
        if stripped == "#endif":
            if not scopes:
                failures.append(
                    f"{relative}:{number}: error: [{RULE}] #endif without #if"
                )
            else:
                scopes.pop()
            continue
        if "debug" in scopes:
            continue
        if ENV_READ.search(line) and not any(token in line for token in allowed):
            failures.append(
                f"{relative}:{number}: error: [{RULE}] process environment read "
                "compiles into Release; gate it behind #if DEBUG or declare the "
                "capture seam in verify_release_surface.py"
            )
        if ENV_SUBSCRIPT.search(line):
            failures.append(
                f"{relative}:{number}: error: [{RULE}] environment key read "
                "compiles into Release; gate it behind #if DEBUG"
            )
        if PRINT_CALL.search(line):
            failures.append(
                f"{relative}:{number}: error: [{RULE}] print() runs in Release; "
                "use Logger or gate it behind #if DEBUG"
            )
    if scopes:
        failures.append(
            f"{relative}: error: [{RULE}] unclosed #if scope(s): {len(scopes)} "
            "still open at end of file"
        )
    return failures


def main() -> int:
    failures: list[str] = []
    for path in production_swift_files():
        failures.extend(audit_file(path))
    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        print(f"{len(failures)} release-surface violation(s)", file=sys.stderr)
        return 1
    print("release surface clean: no ungated environment reads or print calls")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
