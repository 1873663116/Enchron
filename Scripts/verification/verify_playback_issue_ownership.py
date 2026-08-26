#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import re
import sys


DEFAULT_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
OWNER = Path("Modules/Playback/PlaybackRuntime.swift")
ALLOWED_WRITE = (OWNER, "setUserVisibleIssue")
AUDITED_LEGACY_PATHS = (
    Path("Apps/Enchron/AppModel.swift"),
    Path("Apps/Enchron/EnchronApplication.swift"),
    Path("Apps/Enchron/MainView.swift"),
    Path("Modules/Emby"),
    Path("Modules/Playback"),
    Path("Modules/Playback"),
)
PRODUCTION_ROOTS = (Path("Apps"), Path("Modules"))
LEGACY_IDENTIFIERS = (
    "lastErrorMessage",
    "subtitleErrorMessage",
    "presentationConversionFailureMessage",
    "deferPresentationConversionFailureUntilMediaLibraryIsVisible",
    "presentDeferredPresentationConversionFailure",
    "setRuntimeError",
)


@dataclass(frozen=True, order=True)
class WriteIdentity:
    path: Path
    enclosing_function: str | None


@dataclass(frozen=True, order=True)
class Violation:
    path: Path
    line: int
    rule: str
    message: str

    def diagnostic(self) -> str:
        return f"{self.path}:{self.line}: error: [{self.rule}] {self.message}"


@dataclass(frozen=True)
class FunctionRegion:
    name: str
    start: int
    end: int


STRING_START_PATTERN = re.compile(r'(?P<hashes>#+)?(?P<quotes>"""|")')
FUNCTION_PATTERN = re.compile(
    r"\bfunc\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)[^\{]*\{",
    flags=re.MULTILINE,
)
ISSUE_WRITE_PATTERN = re.compile(
    r"(?<![=!<>])\b(?:self\.)?userVisibleIssue\s*=(?!=)"
)
READ_ONLY_PROPERTY_PATTERN = re.compile(
    r"\bpublic\s+private\s*\(\s*set\s*\)\s+var\s+userVisibleIssue\s*:"
    r"\s*PlaybackUserVisibleIssue\s*\?"
)


def mask_swift_noncode(source: str) -> str:
    """Mask Swift comments and strings while preserving offsets and newlines."""
    characters = list(source)
    index = 0

    while index < len(source):
        if source.startswith("//", index):
            while index < len(source) and source[index] != "\n":
                characters[index] = " "
                index += 1
            continue

        if source.startswith("/*", index):
            depth = 1
            characters[index] = characters[index + 1] = " "
            index += 2
            while index < len(source) and depth:
                if source.startswith("/*", index):
                    characters[index] = characters[index + 1] = " "
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    characters[index] = characters[index + 1] = " "
                    depth -= 1
                    index += 2
                else:
                    if source[index] != "\n":
                        characters[index] = " "
                    index += 1
            continue

        string_start = STRING_START_PATTERN.match(source, index)
        if string_start is not None:
            hashes = string_start.group("hashes") or ""
            quotes = string_start.group("quotes")
            closing_delimiter = quotes + hashes
            start_length = len(hashes) + len(quotes)
            for masked_index in range(index, index + start_length):
                characters[masked_index] = " "
            index += start_length
            while index < len(source):
                if source.startswith(closing_delimiter, index):
                    for masked_index in range(index, index + len(closing_delimiter)):
                        characters[masked_index] = " "
                    index += len(closing_delimiter)
                    break
                if not hashes and source[index] == "\\":
                    characters[index] = " "
                    index += 1
                    if index < len(source):
                        if source[index] != "\n":
                            characters[index] = " "
                        index += 1
                    continue
                if source[index] != "\n":
                    characters[index] = " "
                index += 1
            continue

        index += 1

    return "".join(characters)


def matching_brace(masked_source: str, opening_brace: int) -> int | None:
    depth = 0
    for index in range(opening_brace, len(masked_source)):
        if masked_source[index] == "{":
            depth += 1
        elif masked_source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def function_regions(masked_source: str) -> tuple[FunctionRegion, ...]:
    regions: list[FunctionRegion] = []
    for declaration in FUNCTION_PATTERN.finditer(masked_source):
        opening_brace = declaration.end() - 1
        end = matching_brace(masked_source, opening_brace)
        if end is not None:
            regions.append(
                FunctionRegion(declaration.group("name"), opening_brace, end)
            )
    return tuple(regions)


def enclosing_function(
    offset: int,
    regions: tuple[FunctionRegion, ...],
) -> str | None:
    containing = [region for region in regions if region.start < offset < region.end]
    if not containing:
        return None
    return min(containing, key=lambda region: region.end - region.start).name


def swift_sources(root: Path) -> tuple[Path, ...]:
    sources: list[Path] = []
    for relative_root in PRODUCTION_ROOTS:
        source_root = root / relative_root
        if source_root.is_dir():
            sources.extend(source_root.rglob("*.swift"))
    return tuple(sorted(sources))


def legacy_sources(root: Path) -> tuple[Path, ...]:
    sources: set[Path] = set()
    for relative_path in AUDITED_LEGACY_PATHS:
        path = root / relative_path
        if path.is_file():
            sources.add(path)
        elif path.is_dir():
            sources.update(path.rglob("*.swift"))
    return tuple(sorted(sources))


def audit_repository(root: Path) -> list[Violation]:
    violations: list[Violation] = []
    writes: list[tuple[WriteIdentity, int]] = []

    for source_path in swift_sources(root):
        relative_path = source_path.relative_to(root)
        source = source_path.read_text(encoding="utf-8")
        masked = mask_swift_noncode(source)
        regions = function_regions(masked)
        for match in ISSUE_WRITE_PATTERN.finditer(masked):
            line = masked.count("\n", 0, match.start()) + 1
            writes.append(
                (
                    WriteIdentity(
                        relative_path,
                        enclosing_function(match.start(), regions),
                    ),
                    line,
                )
            )

    expected = WriteIdentity(*ALLOWED_WRITE)
    counts = Counter(identity for identity, _ in writes)
    for identity, line in writes:
        if identity != expected or counts[identity] > 1:
            violations.append(
                Violation(
                    identity.path,
                    line,
                    "playback-issue-write-outside-owner",
                    "userVisibleIssue may only be assigned once, inside "
                    f"{OWNER}:setUserVisibleIssue",
                )
            )
    if counts[expected] != 1:
        violations.append(
            Violation(
                OWNER,
                1,
                "playback-issue-owner-count",
                "expected exactly one userVisibleIssue assignment inside "
                f"setUserVisibleIssue; found {counts[expected]}",
            )
        )

    owner_path = root / OWNER
    if not owner_path.is_file():
        violations.append(
            Violation(OWNER, 1, "playback-issue-owner-missing", "owner file is missing")
        )
    else:
        owner_source = mask_swift_noncode(owner_path.read_text(encoding="utf-8"))
        if READ_ONLY_PROPERTY_PATTERN.search(owner_source) is None:
            violations.append(
                Violation(
                    OWNER,
                    1,
                    "playback-issue-not-read-only",
                    "userVisibleIssue must be declared public private(set)",
                )
            )

    for source_path in legacy_sources(root):
        relative_path = source_path.relative_to(root)
        masked = mask_swift_noncode(source_path.read_text(encoding="utf-8"))
        for identifier in LEGACY_IDENTIFIERS:
            for match in re.finditer(rf"\b{re.escape(identifier)}\b", masked):
                violations.append(
                    Violation(
                        relative_path,
                        masked.count("\n", 0, match.start()) + 1,
                        "legacy-playback-error-channel",
                        f"{identifier} is a removed playback error channel",
                    )
                )

    return sorted(violations)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Enforce the single typed playback-issue publication point."
    )
    parser.add_argument("--root", type=Path, default=DEFAULT_REPOSITORY_ROOT)
    arguments = parser.parse_args()
    root = arguments.root.resolve()

    try:
        violations = audit_repository(root)
    except (OSError, UnicodeError) as error:
        print(f"playback issue ownership check could not read the repository: {error}")
        return 2

    if violations:
        for violation in violations:
            print(violation.diagnostic())
        print(f"Playback issue ownership check failed: {len(violations)} violation(s)")
        return 1

    print(
        "Playback issue ownership check passed: typed state is read-only and "
        "has one approved writer; legacy playback error channels are absent."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
