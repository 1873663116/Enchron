#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = (
    REPOSITORY_ROOT / "Apps/Enchron",
    REPOSITORY_ROOT / "Modules",
    REPOSITORY_ROOT / "Packages/PlaybackCore/Sources",
)


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


def product_sources() -> tuple[Path, ...]:
    return tuple(
        sorted(
            path
            for root in SOURCE_ROOTS
            for path in root.rglob("*.swift")
            if path.is_file()
        )
    )


def violations(paths: tuple[Path, ...]) -> list[str]:
    found: list[str] = []
    for path in paths:
        for comment in swift_comments(path.read_text(encoding="utf-8")):
            relative = path.relative_to(REPOSITORY_ROOT)
            found.append(
                f"{relative}:{comment.line}:{comment.column}: "
                f"product source comment {comment.token} is forbidden"
            )
    return found


def main() -> int:
    paths = product_sources()
    found = violations(paths)
    if found:
        for violation in found:
            print(f"error: {violation}", file=sys.stderr)
        print(
            "Move external constraints to the owning constraints document and "
            "encode invariants in types or checks.",
            file=sys.stderr,
        )
        return 1
    print(f"{len(paths)} product Swift files contain no source comments")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
