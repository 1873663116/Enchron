#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import io
import json
import os
import re
import sys
import tokenize


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TOOLS_VERSION = "// swift-tools-version"


@dataclass(frozen=True)
class Comment:
    line: int
    column: int
    token: str


def string_start(source: str, index: int) -> tuple[int, int] | None:
    hashes = 0
    while index + hashes < len(source) and source[index + hashes] == "#":
        hashes += 1
    quote = index + hashes
    if quote >= len(source) or source[quote] != '"':
        return None
    quotes = 3 if source.startswith('"""', quote) else 1
    return hashes, quotes


def skip_string(source: str, index: int, hashes: int, quotes: int) -> int:
    opening = hashes + quotes
    cursor = index + opening
    terminator = '"' * quotes + "#" * hashes
    while cursor < len(source):
        if source.startswith(terminator, cursor):
            return cursor + len(terminator)
        if hashes == 0 and quotes == 1 and source[cursor] == "\\":
            cursor += 2
        else:
            cursor += 1
    return len(source)


def is_doc_comment(source: str, index: int, marker: str) -> bool:
    """Whether the comment opening at `index` documents what it sits above.

    `///` and `/**` are the document-comment spellings for Swift and C. A doc
    comment describes the declaration beneath it - what the interface already
    is - and is the one place a reader looks for it, so it is not the prose this
    gate sends to the constraints documents. A longer run of the same character
    (`////`, `/***`) is a divider and stays reported.
    """
    if marker == "//":
        return source.startswith("///", index) and not source.startswith("////", index)
    return source.startswith("/**", index) and not source.startswith("/***", index)


def swift_comments(source: str) -> tuple[Comment, ...]:
    comments: list[Comment] = []
    index = 0
    line = 1
    line_start = 0
    while index < len(source):
        start = string_start(source, index)
        if start is not None:
            end = skip_string(source, index, *start)
            segment = source[index:end]
            newlines = segment.count("\n")
            if newlines:
                line += newlines
                line_start = index + segment.rfind("\n") + 1
            index = end
            continue
        if source.startswith("//", index):
            directive = line == 1 and index == 0 and source.startswith(TOOLS_VERSION, index)
            if not directive and not is_doc_comment(source, index, "//"):
                comments.append(Comment(line, index - line_start + 1, "//"))
            newline = source.find("\n", index + 2)
            if newline < 0:
                break
            index = newline + 1
            line += 1
            line_start = index
            continue
        if source.startswith("/*", index):
            if not is_doc_comment(source, index, "/*"):
                comments.append(Comment(line, index - line_start + 1, "/*"))
            depth = 1
            cursor = index + 2
            while cursor < len(source) and depth:
                if source.startswith("/*", cursor):
                    depth += 1
                    cursor += 2
                elif source.startswith("*/", cursor):
                    depth -= 1
                    cursor += 2
                else:
                    if source[cursor] == "\n":
                        line += 1
                        line_start = cursor + 1
                    cursor += 1
            index = cursor
            continue
        if source[index] == "\n":
            line += 1
            line_start = index + 1
        index += 1
    return tuple(comments)


def python_comments(source: str) -> tuple[Comment, ...]:
    comments: list[Comment] = []
    try:
        tokens = tokenize.generate_tokens(io.StringIO(source).readline)
        for token in tokens:
            if token.type != tokenize.COMMENT:
                continue
            row, column = token.start
            if row == 1 and column == 0 and token.string.startswith("#!"):
                continue
            comments.append(Comment(row, column + 1, "#"))
    except (tokenize.TokenError, SyntaxError) as error:
        comments.append(Comment(1, 1, f"untokenizable source ({error})"))
    return tuple(comments)


GENERATED_PREFIXES = (
    ".scratch/",
    "TestEvidence/",
    "Config/regression/catalog-root/",
)
GENERATED_FILES = frozenset({"Config/regression/catalog-v2.json"})
GENERATED_SEGMENTS = frozenset({".build", ".swiftpm", "DerivedData"})
MACHINE_MANAGED_SUFFIXES = frozenset({".pbxproj"})
SCANNED_SUFFIXES = frozenset(
    {".swift", ".py", ".c", ".h", ".m", ".mm", ".sh", ".yml", ".yaml", ".plist", ".json"}
)
THIRD_PARTY_REGISTRY = REPOSITORY_ROOT / "Config/third_party_sources.json"


def third_party_prefixes() -> tuple[str, ...]:
    if not THIRD_PARTY_REGISTRY.is_file():
        return ()
    recorded = json.loads(THIRD_PARTY_REGISTRY.read_text(encoding="utf-8"))
    return tuple(recorded.get("paths", ()))


PRUNED_DIRECTORIES = frozenset(
    {
        ".git",
        ".build",
        ".swiftpm",
        "DerivedData",
        "node_modules",
        ".scratch",
        "TestEvidence",
        "SourcePackages",
        "checkouts",
    }
)


def first_party_files() -> tuple[Path, ...]:
    prefixes = third_party_prefixes()
    selected: list[Path] = []
    for directory, subdirectories, names in os.walk(REPOSITORY_ROOT):
        subdirectories[:] = [
            name for name in subdirectories if name not in PRUNED_DIRECTORIES
        ]
        for name in names:
            path = Path(directory) / name
            relative = path.relative_to(REPOSITORY_ROOT).as_posix()
            if relative in GENERATED_FILES:
                continue
            if any(relative.startswith(prefix) for prefix in prefixes):
                continue
            if any(relative.startswith(prefix) for prefix in GENERATED_PREFIXES):
                continue
            parts = Path(relative).parts
            if parts and parts[0] == "Packages" and "build" in parts:
                continue
            if path.suffix in MACHINE_MANAGED_SUFFIXES or path.suffix not in SCANNED_SUFFIXES:
                continue
            try:
                path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            selected.append(path)
    return tuple(sorted(selected))


def c_comments(source: str) -> tuple[Comment, ...]:
    comments: list[Comment] = []
    index = 0
    line = 1
    line_start = 0
    while index < len(source):
        character = source[index]
        if character in ('"', "'"):
            cursor = index + 1
            while cursor < len(source) and source[cursor] != character:
                if source[cursor] == "\\":
                    cursor += 1
                elif source[cursor] == "\n":
                    line += 1
                    line_start = cursor + 1
                cursor += 1
            index = cursor + 1
            continue
        if source.startswith("//", index):
            if not is_doc_comment(source, index, "//"):
                comments.append(Comment(line, index - line_start + 1, "//"))
            newline = source.find("\n", index + 2)
            if newline < 0:
                break
            index = newline + 1
            line += 1
            line_start = index
            continue
        if source.startswith("/*", index):
            if not is_doc_comment(source, index, "/*"):
                comments.append(Comment(line, index - line_start + 1, "/*"))
            cursor = source.find("*/", index + 2)
            cursor = len(source) if cursor < 0 else cursor + 2
            segment = source[index:cursor]
            newlines = segment.count("\n")
            if newlines:
                line += newlines
                line_start = index + segment.rfind("\n") + 1
            index = cursor
            continue
        if character == "\n":
            line += 1
            line_start = index + 1
        index += 1
    return tuple(comments)


def shell_comments(source: str) -> tuple[Comment, ...]:
    comments: list[Comment] = []
    quote = ""
    escaped = False
    depth = 0
    for number, line in enumerate(source.splitlines(), start=1):
        index = 0
        while index < len(line):
            character = line[index]
            following = line[index + 1 : index + 2]
            if escaped:
                escaped = False
            elif character == "\\" and quote != "'":
                escaped = True
            elif quote:
                if character == quote:
                    quote = ""
            elif character in ("'", '"'):
                quote = character
            elif character == "$" and following == "{":
                depth += 1
                index += 1
            elif character == "}" and depth:
                depth -= 1
            elif character == "#" and depth == 0:
                if number == 1 and index == 0:
                    break
                if line[index - 1 : index] == "$":
                    index += 1
                    continue
                comments.append(Comment(number, index + 1, "#"))
                break
            index += 1
        quote = ""
        escaped = False
    return tuple(comments)


def yaml_comments(source: str) -> tuple[Comment, ...]:
    comments: list[Comment] = []
    block_indent = -1
    for number, line in enumerate(source.splitlines(), start=1):
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if block_indent >= 0:
            if stripped and indent <= block_indent:
                block_indent = -1
            else:
                continue
        quote = ""
        index = 0
        while index < len(line):
            character = line[index]
            if quote:
                if character == quote:
                    quote = ""
            elif character in ("'", '"'):
                quote = character
            elif character == "#" and (index == 0 or line[index - 1].isspace()):
                comments.append(Comment(number, index + 1, "#"))
                break
            index += 1
        if quote == "" and stripped.endswith(("|", ">", "|-", ">-", "|+", ">+")):
            block_indent = indent
    return tuple(comments)


def xml_comments(source: str) -> tuple[Comment, ...]:
    comments: list[Comment] = []
    index = 0
    while True:
        start = source.find("<!--", index)
        if start < 0:
            break
        line = source.count("\n", 0, start) + 1
        column = start - source.rfind("\n", 0, start)
        comments.append(Comment(line, column, "<!--"))
        index = start + 4
    return tuple(comments)


def json_comments(source: str) -> tuple[Comment, ...]:
    comments: list[Comment] = []
    in_string = False
    escaped = False
    index = 0
    line = 1
    column = 1
    while index < len(source):
        character = source[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character == "/" and source[index : index + 2] in ("//", "/*"):
            comments.append(Comment(line, column, source[index : index + 2]))
            break
        if character == "\n":
            line += 1
            column = 1
        else:
            column += 1
        index += 1
    return tuple(comments)


def comments_in(path: Path) -> tuple[Comment, ...]:
    source = path.read_text(encoding="utf-8")
    suffix = path.suffix
    if suffix == ".py":
        return python_comments(source)
    if suffix in (".c", ".h", ".m", ".mm"):
        return c_comments(source)
    if suffix == ".sh":
        return shell_comments(source)
    if suffix in (".yml", ".yaml"):
        return yaml_comments(source)
    if suffix == ".plist":
        return xml_comments(source)
    if suffix == ".json":
        return json_comments(source)
    return swift_comments(source)


def violations(paths: tuple[Path, ...]) -> list[str]:
    found: list[str] = []
    for path in paths:
        for comment in comments_in(path):
            relative = path.relative_to(REPOSITORY_ROOT)
            found.append(
                f"{relative}:{comment.line}:{comment.column}: "
                f"source comment {comment.token} is forbidden"
            )
    return found


LICENSE_HEADER = re.compile(
    r"copyright\s*(\(c\)|©|\d{4})|SPDX-License-Identifier|Licensed under", re.IGNORECASE
)


def unregistered_license_headers(paths: tuple[Path, ...]) -> list[str]:
    found: list[str] = []
    for path in paths:
        head = "\n".join(path.read_text(encoding="utf-8").splitlines()[:15])
        if LICENSE_HEADER.search(head):
            relative = path.relative_to(REPOSITORY_ROOT)
            found.append(f"{relative}: carries a license header outside the registry")
    return found


def main() -> int:
    paths = first_party_files()
    found = violations(paths) + unregistered_license_headers(paths)
    if found:
        for violation in found:
            print(f"error: {violation}", file=sys.stderr)
        print(
            "Move external constraints to the owning constraints document, "
            "put measured values behind named constants, and encode invariants "
            "in types or checks. A doc comment (/// or /**) describes the "
            "declaration it sits above and is allowed.",
            file=sys.stderr,
        )
        return 1
    print(f"{len(paths)} first-party text files carry no prose comments")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
