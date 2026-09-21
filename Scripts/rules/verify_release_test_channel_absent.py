#!/usr/bin/env python3

"""Checks that the test command channel cannot exist in the shipping product.

The channel drives product state directly, without going through hit testing.
That is what makes it useful to a UI test and what makes it unacceptable in a
shipped build, so the guarantee is a compile boundary rather than a runtime
flag: the whole file lives inside `#if DEBUG`, and the Release configuration
does not define DEBUG. Both halves are checked here, because either one alone
is only half an argument.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

CHANNEL_SOURCE = "Apps/Enchron/TestCommandChannel.swift"
PROJECT_FILE = "Enchron.xcodeproj/project.pbxproj"

INSTALL_CALL = "installTestCommandChannelIfEnabled"
INSTALL_SITE = "Apps/Enchron/EnchronApplication.swift"

PRODUCTION_RELEASE_CONFIGURATION_IDS = (
    "C3B0F99B2F5726B40064596E",
    "C3B0F99D2F5726B40064596E",
)
RELEASE_CONFIGURATION = re.compile(
    rf"(?:{'|'.join(PRODUCTION_RELEASE_CONFIGURATION_IDS)} )"
    r"/\* Release \*/ = \{.*?\n\t\t\};",
    re.DOTALL,
)
ANY_RELEASE_CONFIGURATION = re.compile(
    r"/\* Release \*/ = \{.*?\n\t\t\};", re.DOTALL
)
DEBUG_CONDITION = re.compile(
    r"SWIFT_ACTIVE_COMPILATION_CONDITIONS[^;]*\bDEBUG\b"
)
DEBUG_MACRO = re.compile(r"GCC_PREPROCESSOR_DEFINITIONS[^;]*\bDEBUG=1")


def channel_file_failures() -> list[str]:
    path = REPOSITORY_ROOT / CHANNEL_SOURCE
    if not path.is_file():
        return [f"{CHANNEL_SOURCE} is absent"]
    lines = path.read_text(encoding="utf-8").splitlines()
    body = [
        (number, line)
        for number, line in enumerate(lines, 1)
        if line.strip() and not line.strip().startswith("//")
    ]
    if not body:
        return [f"{CHANNEL_SOURCE} has no code"]
    first_number, first_line = body[0]
    last_number, last_line = body[-1]
    failures = []
    if first_line.strip() != "#if DEBUG":
        failures.append(
            f"{CHANNEL_SOURCE}:{first_number}: the file must open with #if DEBUG, "
            f"found {first_line.strip()!r}"
        )
    if last_line.strip() != "#endif":
        failures.append(
            f"{CHANNEL_SOURCE}:{last_number}: the file must close the #if DEBUG, "
            f"found {last_line.strip()!r}"
        )
    depth = 0
    for number, line in body:
        stripped = line.strip()
        if stripped.startswith("#if"):
            depth += 1
        elif stripped == "#endif":
            depth -= 1
            if depth == 0 and number != last_number:
                failures.append(
                    f"{CHANNEL_SOURCE}:{number}: code leaves the file's #if DEBUG "
                    "before the end of the file"
                )
        if depth < 0:
            failures.append(f"{CHANNEL_SOURCE}:{number}: unbalanced #endif")
            break
    if depth > 0:
        failures.append(f"{CHANNEL_SOURCE}: {depth} unclosed #if")
    return failures


def install_site_failures() -> list[str]:
    path = REPOSITORY_ROOT / INSTALL_SITE
    if not path.is_file():
        return [f"{INSTALL_SITE} is absent"]
    guarded = False
    failures = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped == "#if DEBUG":
            guarded = True
        elif stripped == "#endif":
            guarded = False
        elif INSTALL_CALL in stripped and not guarded:
            failures.append(
                f"{INSTALL_SITE}:{number}: {INSTALL_CALL} is the only way the "
                "channel reaches a running app and is reachable outside #if DEBUG"
            )
    return failures


def release_configuration_failures() -> list[str]:
    path = REPOSITORY_ROOT / PROJECT_FILE
    if not path.is_file():
        return [f"{PROJECT_FILE} is absent"]
    source = path.read_text(encoding="utf-8")
    blocks = RELEASE_CONFIGURATION.findall(source)
    if not blocks:
        blocks = ANY_RELEASE_CONFIGURATION.findall(source)
    if not blocks:
        return [f"{PROJECT_FILE}: no Release build configuration was found"]
    failures = []
    for block in blocks:
        if DEBUG_CONDITION.search(block) or DEBUG_MACRO.search(block):
            failures.append(
                f"{PROJECT_FILE}: a Release configuration defines DEBUG, "
                "so the channel would compile into a Release product"
            )
            break
    return failures


def failures() -> list[str]:
    return (
        channel_file_failures()
        + install_site_failures()
        + release_configuration_failures()
    )


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} failures")
        return 1
    print(
        "Shipping Release test channel absent: the channel file is entirely "
        "#if DEBUG, its install site is guarded, and the shipping Enchron "
        "Release configuration does not define DEBUG"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
