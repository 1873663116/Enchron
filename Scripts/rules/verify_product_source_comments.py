#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import io
import sys
import tokenize


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SWIFT_ROOTS = (
    REPOSITORY_ROOT / "Apps/Enchron",
    REPOSITORY_ROOT / "Modules",
    REPOSITORY_ROOT / "Packages/PlaybackCore/Sources",
    REPOSITORY_ROOT / "Packages/PlaybackCore/Tests",
    REPOSITORY_ROOT / "Packages/EnvironmentSceneContract/Sources",
    REPOSITORY_ROOT / "Packages/OceanEnvironment/Sources",
    REPOSITORY_ROOT / "Packages/QuietRoomEnvironment/Sources",
    REPOSITORY_ROOT / "Tests",
)
SWIFT_MANIFESTS = (
    REPOSITORY_ROOT / "Package.swift",
    REPOSITORY_ROOT / "Packages/PlaybackCore/Package.swift",
    REPOSITORY_ROOT / "Packages/EnvironmentSceneContract/Package.swift",
    REPOSITORY_ROOT / "Packages/OceanEnvironment/Package.swift",
    REPOSITORY_ROOT / "Packages/QuietRoomEnvironment/Package.swift",
    REPOSITORY_ROOT / "Tests/MediaByteStreamConformance/Package.swift",
)
C_ROOTS = (
    REPOSITORY_ROOT / "Packages/PlaybackCore/Sources",
    REPOSITORY_ROOT / "Scripts/verification",
)
PYTHON_ROOTS = (
    REPOSITORY_ROOT / "Scripts",
    REPOSITORY_ROOT / ".claude/hooks",
)
EXCLUDED_SEGMENTS = frozenset(
    {"Vendor", ".build", ".scratch", ".git", "DerivedData", "SourcePackages", "checkouts"}
)
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
            if not directive:
                comments.append(Comment(line, index - line_start + 1, "//"))
            newline = source.find("\n", index + 2)
            if newline < 0:
                break
            index = newline + 1
            line += 1
            line_start = index
            continue
        if source.startswith("/*", index):
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


def owned(path: Path) -> bool:
    if not path.is_file():
        return False
    return not EXCLUDED_SEGMENTS.intersection(path.relative_to(REPOSITORY_ROOT).parts)


def product_sources() -> tuple[Path, ...]:
    found = {
        path
        for root in SWIFT_ROOTS
        for path in root.rglob("*.swift")
        if owned(path)
    }
    found.update(path for path in SWIFT_MANIFESTS if owned(path))
    return tuple(sorted(found))


def bridge_sources() -> tuple[Path, ...]:
    return tuple(
        sorted(
            path
            for root in C_ROOTS
            for suffix in ("*.c", "*.h", "*.m", "*.mm")
            for path in root.rglob(suffix)
            if owned(path)
        )
    )


def script_sources() -> tuple[Path, ...]:
    return tuple(
        sorted(
            path
            for root in PYTHON_ROOTS
            for path in root.rglob("*.py")
            if owned(path)
        )
    )


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
            comments.append(Comment(line, index - line_start + 1, "//"))
            newline = source.find("\n", index + 2)
            if newline < 0:
                break
            index = newline + 1
            line += 1
            line_start = index
            continue
        if source.startswith("/*", index):
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


def comments_in(path: Path) -> tuple[Comment, ...]:
    source = path.read_text(encoding="utf-8")
    if path.suffix == ".py":
        return python_comments(source)
    if path.suffix in (".c", ".h", ".m", ".mm"):
        return c_comments(source)
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


def main() -> int:
    swift = product_sources()
    bridge = bridge_sources()
    python = script_sources()
    found = violations(swift + bridge + python)
    if found:
        for violation in found:
            print(f"error: {violation}", file=sys.stderr)
        print(
            "Move external constraints to the owning constraints document, "
            "put measured values behind named constants, and encode invariants "
            "in types or checks.",
            file=sys.stderr,
        )
        return 1
    print(
        f"{len(swift)} Swift files, {len(bridge)} C bridge and probe files and "
        f"{len(python)} Python files contain no source comments"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
