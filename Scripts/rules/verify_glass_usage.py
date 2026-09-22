#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import re
import sys


DEFAULT_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_SOURCE_ROOTS = (Path("Apps"), Path("Modules"))
RAW_GLASS_OWNER = Path("Modules/DesignSystem/View+Platform.swift")
RAW_GLASS_CALLEE = "glassBackgroundEffect"
WRAPPER_CALLEES = (
    "enchronGlassBackground",
    "enchronWindowGlassBackground",
)


@dataclass(frozen=True, order=True)
class WrapperCallIdentity:
    path: Path
    enclosing_type: str
    callee: str


ALLOWED_WRAPPER_CALLS = Counter(
    {
        WrapperCallIdentity(
            path=Path(
                "Modules/Playback/Views/EnvironmentComponents.swift"
            ),
            enclosing_type="EnvironmentCard",
            callee="enchronGlassBackground",
        ): 1,
        WrapperCallIdentity(
            path=Path("Modules/Playback/Views/PlaybackPanel.swift"),
            enclosing_type="FusedPlayerPanel",
            callee="enchronGlassBackground",
        ): 1,
        WrapperCallIdentity(
            path=Path("Apps/Enchron/MainView.swift"),
            enclosing_type="MainView",
            callee="enchronWindowGlassBackground",
        ): 1,
        WrapperCallIdentity(
            path=Path("Apps/Enchron/PlayerView.swift"),
            enclosing_type="PlayerView",
            callee="enchronWindowGlassBackground",
        ): 1,
        WrapperCallIdentity(
            path=Path("Modules/DesignSystem/Components/PlaybackChromeGlassButton.swift"),
            enclosing_type="PlaybackChromeGlassIcon",
            callee="enchronGlassBackground",
        ): 1,
    }
)


@dataclass(frozen=True)
class TypeRegion:
    name: str
    start: int
    end: int


@dataclass(frozen=True)
class SourceCall:
    path: Path
    line: int
    callee: str
    enclosing_type: str | None

    @property
    def wrapper_identity(self) -> WrapperCallIdentity | None:
        if self.callee not in WRAPPER_CALLEES or self.enclosing_type is None:
            return None
        return WrapperCallIdentity(self.path, self.enclosing_type, self.callee)


@dataclass(frozen=True, order=True)
class Violation:
    path: Path
    line: int
    rule: str
    message: str

    def diagnostic(self) -> str:
        return f"{self.path}:{self.line}: error: [{self.rule}] {self.message}"


RAW_CALL_PATTERN = re.compile(r"\bglassBackgroundEffect\s*\(")
WRAPPER_CALL_PATTERN = re.compile(
    r"\.\s*(?P<callee>enchron(?:Plate|Window)?GlassBackground)\s*\("
)
TYPE_DECLARATION_PATTERN = re.compile(
    r"\b(?:struct|class|enum|actor|extension)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_.]*)[^\{]*\{",
    flags=re.MULTILINE,
)
STRING_START_PATTERN = re.compile(r"(?P<hashes>#+)?(?P<quotes>\"\"\"|\")")


def mask_swift_noncode(source: str) -> str:
    """Masks Swift comments and strings while preserving offsets and newlines."""
    characters = list(source)
    index = 0
    block_comment_depth = 0

    while index < len(source):
        if source.startswith("//", index):
            while index < len(source) and source[index] != "\n":
                characters[index] = " "
                index += 1
            continue

        if source.startswith("/*", index):
            block_comment_depth = 1
            characters[index] = characters[index + 1] = " "
            index += 2
            while index < len(source) and block_comment_depth:
                if source.startswith("/*", index):
                    characters[index] = characters[index + 1] = " "
                    block_comment_depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    characters[index] = characters[index + 1] = " "
                    block_comment_depth -= 1
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
                    for masked_index in range(
                        index,
                        index + len(closing_delimiter),
                    ):
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


def type_regions(masked_source: str) -> tuple[TypeRegion, ...]:
    regions: list[TypeRegion] = []
    for declaration in TYPE_DECLARATION_PATTERN.finditer(masked_source):
        opening_brace = declaration.end() - 1
        depth = 0
        for index in range(opening_brace, len(masked_source)):
            character = masked_source[index]
            if character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    regions.append(
                        TypeRegion(
                            name=declaration.group("name").split(".")[-1],
                            start=opening_brace,
                            end=index,
                        )
                    )
                    break
    return tuple(regions)


def enclosing_type(offset: int, regions: tuple[TypeRegion, ...]) -> str | None:
    containing = [region for region in regions if region.start < offset < region.end]
    if not containing:
        return None
    return min(containing, key=lambda region: region.end - region.start).name


def source_calls(path: Path, source: str) -> tuple[SourceCall, ...]:
    masked_source = mask_swift_noncode(source)
    regions = type_regions(masked_source)
    calls: list[SourceCall] = []

    for match in RAW_CALL_PATTERN.finditer(masked_source):
        calls.append(
            SourceCall(
                path=path,
                line=masked_source.count("\n", 0, match.start()) + 1,
                callee=RAW_GLASS_CALLEE,
                enclosing_type=enclosing_type(match.start(), regions),
            )
        )

    for match in WRAPPER_CALL_PATTERN.finditer(masked_source):
        calls.append(
            SourceCall(
                path=path,
                line=masked_source.count("\n", 0, match.start()) + 1,
                callee=match.group("callee"),
                enclosing_type=enclosing_type(match.start(), regions),
            )
        )

    return tuple(calls)


def production_swift_sources(repository_root: Path) -> tuple[Path, ...]:
    sources: list[Path] = []
    for relative_root in PRODUCTION_SOURCE_ROOTS:
        source_root = repository_root / relative_root
        if source_root.is_dir():
            sources.extend(source_root.rglob("*.swift"))
    return tuple(sorted(sources))


def audit_repository(repository_root: Path) -> list[Violation]:
    calls: list[SourceCall] = []
    for source_path in production_swift_sources(repository_root):
        relative_path = source_path.relative_to(repository_root)
        calls.extend(source_calls(relative_path, source_path.read_text(encoding="utf-8")))

    violations = [
        Violation(
            path=call.path,
            line=call.line,
            rule="raw-glass-outside-owner",
            message=(
                f"{RAW_GLASS_CALLEE} is owned by {RAW_GLASS_OWNER}; "
                "use an approved Enchron wrapper at a legal host surface"
            ),
        )
        for call in calls
        if call.callee == RAW_GLASS_CALLEE and call.path != RAW_GLASS_OWNER
    ]

    wrapper_calls = [call for call in calls if call.callee in WRAPPER_CALLEES]
    actual_wrapper_calls = Counter(
        call.wrapper_identity for call in wrapper_calls if call.wrapper_identity is not None
    )

    for call in wrapper_calls:
        identity = call.wrapper_identity
        if identity is None or actual_wrapper_calls[identity] > ALLOWED_WRAPPER_CALLS[identity]:
            violations.append(
                Violation(
                    path=call.path,
                    line=call.line,
                    rule="unexpected-glass-wrapper-call",
                    message=(
                        f"{call.enclosing_type or 'top-level code'} may not call "
                        f"{call.callee}; use DesignTokens or enchronListGroupSurface"
                    ),
                )
            )

    for identity, expected_count in ALLOWED_WRAPPER_CALLS.items():
        actual_count = actual_wrapper_calls[identity]
        if actual_count < expected_count:
            violations.append(
                Violation(
                    path=identity.path,
                    line=1,
                    rule="missing-glass-wrapper-call",
                    message=(
                        f"expected {expected_count} {identity.callee} call(s) in "
                        f"{identity.enclosing_type}, found {actual_count}"
                    ),
                )
            )

    return sorted(set(violations))


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Enforce Enchron's exact platform-glass ownership and allowlist."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=DEFAULT_REPOSITORY_ROOT,
        help="repository root to inspect",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    repository_root = arguments.root.resolve()
    try:
        violations = audit_repository(repository_root)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"glass usage inspection failed: {error}", file=sys.stderr)
        return 2

    if violations:
        for violation in violations:
            print(violation.diagnostic(), file=sys.stderr)
        return 1

    print(
        "Glass usage check passed: raw glass is platform-owned and wrapper calls "
        f"match {sum(ALLOWED_WRAPPER_CALLS.values())} allowed occurrence(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
