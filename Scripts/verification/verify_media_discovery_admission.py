#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import sys


DEFAULT_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_SOURCE_ROOTS = (Path("Apps"), Path("Modules"))


@dataclass(frozen=True, order=True)
class SuffixArrayIdentity:
    path: Path
    enclosing_type: str
    label: str


ALLOWED_SUFFIX_ARRAY = SuffixArrayIdentity(
    path=Path("Modules/MediaLibrary/Model/MediaBrowsing.swift"),
    enclosing_type="MediaDiscoveryAdmissionPolicy",
    label="allowedExtensions",
)


@dataclass(frozen=True)
class TypeRegion:
    name: str
    start: int
    end: int


@dataclass(frozen=True)
class StringArray:
    path: Path
    line: int
    values: tuple[str, ...]
    identity: SuffixArrayIdentity | None


@dataclass(frozen=True, order=True)
class Violation:
    path: Path
    line: int
    rule: str
    message: str

    def diagnostic(self) -> str:
        return f"{self.path}:{self.line}: error: [{self.rule}] {self.message}"


TYPE_DECLARATION_PATTERN = re.compile(
    r"\b(?:struct|class|enum|actor|extension)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_.]*)[^\{]*\{",
    flags=re.MULTILINE,
)
STRING_START_PATTERN = re.compile(r'(?P<hashes>#+)?(?P<quotes>"""|")')
STRING_ITEM_PATTERN = r'"(?:[^"\\]|\\.)*"'
STRING_ARRAY_PATTERN = re.compile(
    rf"\[\s*{STRING_ITEM_PATTERN}(?:\s*,\s*{STRING_ITEM_PATTERN})*\s*,?\s*\]",
    flags=re.DOTALL,
)
STRING_VALUE_PATTERN = re.compile(STRING_ITEM_PATTERN)
ARRAY_LABEL_PATTERN = re.compile(
    r"(?:(?:let|var)\s+)?(?P<label>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?:\s*:\s*[^=\n]+)?\s*(?:=|:)\s*$"
)


def mask_swift_noncode(source: str) -> str:
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
            closing = quotes + hashes
            opening_length = len(hashes) + len(quotes)
            for masked_index in range(index, index + opening_length):
                characters[masked_index] = " "
            index += opening_length
            while index < len(source):
                if source.startswith(closing, index):
                    for masked_index in range(index, index + len(closing)):
                        characters[masked_index] = " "
                    index += len(closing)
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


def source_without_comments(source: str) -> str:
    masked = list(source)
    noncode = mask_swift_noncode(source)
    for index, character in enumerate(noncode):
        if character == " " and source[index] not in " \t\r\n":
            masked[index] = " "
    for match in STRING_VALUE_PATTERN.finditer(source):
        masked[match.start():match.end()] = source[match.start():match.end()]
    return "".join(masked)


def type_regions(masked_source: str) -> tuple[TypeRegion, ...]:
    regions: list[TypeRegion] = []
    for declaration in TYPE_DECLARATION_PATTERN.finditer(masked_source):
        opening_brace = declaration.end() - 1
        depth = 0
        for index in range(opening_brace, len(masked_source)):
            if masked_source[index] == "{":
                depth += 1
            elif masked_source[index] == "}":
                depth -= 1
                if depth == 0:
                    regions.append(
                        TypeRegion(
                            declaration.group("name").split(".")[-1],
                            opening_brace,
                            index,
                        )
                    )
                    break
    return tuple(regions)


def enclosing_type(offset: int, regions: tuple[TypeRegion, ...]) -> str | None:
    containing = [region for region in regions if region.start < offset < region.end]
    if not containing:
        return None
    return min(containing, key=lambda region: region.end - region.start).name


def string_arrays(path: Path, source: str) -> tuple[StringArray, ...]:
    searchable = source_without_comments(source)
    regions = type_regions(mask_swift_noncode(source))
    arrays: list[StringArray] = []
    for match in STRING_ARRAY_PATTERN.finditer(searchable):
        values: tuple[str, ...] = tuple(
            swift_string_value(value.group(0))
            for value in STRING_VALUE_PATTERN.finditer(match.group(0))
        )
        prefix = searchable[max(0, match.start() - 240):match.start()]
        label_match = ARRAY_LABEL_PATTERN.search(prefix)
        type_name = enclosing_type(match.start(), regions)
        identity = None
        if label_match is not None and type_name is not None:
            identity = SuffixArrayIdentity(path, type_name, label_match.group("label"))
        arrays.append(
            StringArray(
                path=path,
                line=source.count("\n", 0, match.start()) + 1,
                values=values,
                identity=identity,
            )
        )
    return tuple(arrays)


def swift_string_value(literal: str) -> str:
    try:
        return json.loads(literal)
    except json.JSONDecodeError:
        return literal[1:-1]


def production_arrays(repository_root: Path) -> tuple[StringArray, ...]:
    arrays: list[StringArray] = []
    for relative_root in PRODUCTION_SOURCE_ROOTS:
        source_root = repository_root / relative_root
        if not source_root.is_dir():
            continue
        for source_path in sorted(source_root.rglob("*.swift")):
            relative_path = source_path.relative_to(repository_root)
            arrays.extend(
                string_arrays(relative_path, source_path.read_text(encoding="utf-8"))
            )
    return tuple(arrays)


def canonical_suffixes(arrays: tuple[StringArray, ...]) -> frozenset[str]:
    owners = [array for array in arrays if array.identity == ALLOWED_SUFFIX_ARRAY]
    if len(owners) != 1:
        raise ValueError(
            f"expected one {ALLOWED_SUFFIX_ARRAY.enclosing_type}."
            f"{ALLOWED_SUFFIX_ARRAY.label} literal, found {len(owners)}"
        )
    values = owners[0].values
    if len(values) != len(set(values)):
        raise ValueError("media discovery admission contains duplicate suffixes")
    if any(value != value.lower() or value.startswith(".") for value in values):
        raise ValueError("media discovery admission suffixes must be lowercase and dotless")
    return frozenset(values)


def audit_repository(repository_root: Path) -> list[Violation]:
    arrays = production_arrays(repository_root)
    try:
        suffixes = canonical_suffixes(arrays)
    except ValueError as error:
        return [
            Violation(
                ALLOWED_SUFFIX_ARRAY.path,
                1,
                "media-discovery-owner",
                str(error),
            )
        ]

    violations: list[Violation] = []
    for array in arrays:
        if array.identity == ALLOWED_SUFFIX_ARRAY:
            continue
        overlap = sorted(suffixes.intersection(array.values))
        if overlap:
            violations.append(
                Violation(
                    array.path,
                    array.line,
                    "duplicate-media-suffix-array",
                    "video suffix arrays are owned by "
                    f"{ALLOWED_SUFFIX_ARRAY.path}; duplicated: {', '.join(overlap)}",
                )
            )
    return sorted(set(violations))


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Enforce one typed owner for media discovery suffixes."
    )
    parser.add_argument("--root", type=Path, default=DEFAULT_REPOSITORY_ROOT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    repository_root = parse_arguments(argv).root.resolve()
    try:
        violations = audit_repository(repository_root)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"media discovery admission inspection failed: {error}", file=sys.stderr)
        return 2
    if violations:
        for violation in violations:
            print(violation.diagnostic(), file=sys.stderr)
        return 1
    print("Media discovery admission check passed: one suffix owner and no duplicates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
