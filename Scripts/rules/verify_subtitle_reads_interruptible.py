#!/usr/bin/env python3
"""Verify that subtitle reads open only through the monitored, interruptible door."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]

BRIDGE_C = "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c"
BRIDGE_HEADER = (
    "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/include/PlaybackFFmpegBridge.h"
)
THROUGHPUT_SWIFT = (
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackSourceReadThroughput.swift"
)
DELIVERY_SWIFT = (
    "Packages/PlaybackCore/Sources/PlaybackCore/SampleBufferPlaybackSession+Delivery.swift"
)
PLAYBACK_CORE_SOURCES = "Packages/PlaybackCore/Sources"

ALLOCATE_FORMAT_CONTEXT_SIGNATURE = "static AVFormatContext *allocate_format_context("
OPEN_MEDIA_SOURCE_SIGNATURE = "static int open_media_source("
BRIDGE_DIRECTORY = "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge"

DECLARATION_NAME = re.compile(
    r"\b((?:PBSubtitleFrameRenderer|PBFFmpegSubtitleReader)[A-Za-z0-9_]*)\("
)
PATH_PARAMETER = re.compile(r"const\s+char\s*\*\s*path\b")
MONITOR_PARAMETER = re.compile(r"PBFFmpegSourceReadMonitor\s*\*")


def read(path: str) -> str:
    target = ROOT / path
    if not target.is_file():
        raise AssertionError(f"missing required file: {path}")
    return target.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def find_definition_span(source: str, signature: str) -> tuple[int, int]:
    search_start = 0
    while True:
        index = source.find(signature, search_start)
        require(index >= 0, f"no definition found for: {signature!r}")
        if index != 0 and source[index - 1] != "\n":
            search_start = index + 1
            continue
        cursor = index + len(signature)
        depth = 1
        while cursor < len(source) and depth:
            if source[cursor] == "(":
                depth += 1
            elif source[cursor] == ")":
                depth -= 1
            cursor += 1
        while cursor < len(source) and source[cursor] in " \t\r\n":
            cursor += 1
        if cursor < len(source) and source[cursor] == "{":
            break
        search_start = index + 1
    close = source.find("\n}", cursor)
    require(close >= 0, f"no closing brace at column 0 for: {signature!r}")
    return index, close + 2


C_COMMENT = re.compile(r"/\*.*?\*/|//[^\n]*", re.DOTALL)


def without_comments(source: str) -> str:
    return C_COMMENT.sub(lambda match: " " * len(match.group(0)), source)


def bridge_unit_sources() -> dict[str, str]:
    root = ROOT / BRIDGE_DIRECTORY
    return {
        str(path.relative_to(ROOT)): path.read_text(encoding="utf-8")
        for path in sorted(root.glob("*.c"))
    }


def count_calls(source: str, call: str) -> list[int]:
    positions: list[int] = []
    start = 0
    while True:
        index = source.find(call, start)
        if index < 0:
            break
        previous = source[index - 1] if index > 0 else ""
        if not (previous.isalnum() or previous == "_"):
            positions.append(index)
        start = index + 1
    return positions


def check_S1(bridge_source: str) -> None:
    body_start, body_end = find_definition_span(
        bridge_source, ALLOCATE_FORMAT_CONTEXT_SIGNATURE
    )
    calls = count_calls(bridge_source, "avformat_alloc_context(")
    require(
        len(calls) == 1,
        "S1: PlaybackFFmpegBridge.c must contain exactly one "
        f"avformat_alloc_context( call, found {len(calls)}",
    )
    require(
        body_start <= calls[0] < body_end,
        "S1: the sole avformat_alloc_context( call must live inside "
        "allocate_format_context's body",
    )


def check_S2(bridge_source: str) -> None:
    body_start, body_end = find_definition_span(
        bridge_source, OPEN_MEDIA_SOURCE_SIGNATURE
    )
    calls = count_calls(bridge_source, "avformat_open_input(")
    require(
        len(calls) == 1,
        "S2: PlaybackFFmpegBridge.c must contain exactly one "
        f"avformat_open_input( call, found {len(calls)}",
    )
    require(
        body_start <= calls[0] < body_end,
        "S2: the sole avformat_open_input( call must live inside "
        "open_media_source's body",
    )


def check_S3(unit_sources: dict[str, str]) -> None:
    for name, unit_source in unit_sources.items():
        if name.endswith("/PlaybackFFmpegBridge.c"):
            continue
        stripped = without_comments(unit_source)
        for call in (
            "avformat_open_input(",
            "avformat_alloc_context(",
            "avformat_close_input(",
        ):
            require(
                not count_calls(stripped, call),
                f"S3: {name} must not call {call} directly; every unit other than "
                "PlaybackFFmpegBridge.c reaches a format context only through "
                "PBFFmpegMonitoredSourceOpen",
            )


def function_body_by_brace_matching(source: str, signature: str) -> str:
    start = source.find(signature)
    require(start >= 0, f"S4: signature not found: {signature!r}")
    brace = source.find("{", start + len(signature))
    require(brace >= 0, f"S4: no body opening brace for: {signature!r}")
    depth = 0
    cursor = brace
    while cursor < len(source):
        character = source[cursor]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[brace : cursor + 1]
        cursor += 1
    raise AssertionError(f"S4: unbalanced braces in body of: {signature!r}")


def check_S4(
    bridge_source: str,
    header_source: str,
    throughput_source: str,
    delivery_source: str,
) -> None:
    require(
        "monitor->interrupted" in bridge_source,
        "S4: the interrupt callback in PlaybackFFmpegBridge.c no longer "
        "consults monitor->interrupted",
    )
    require(
        "PBFFmpegSourceReadMonitorInterrupt(" in header_source,
        "S4: PBFFmpegSourceReadMonitorInterrupt is no longer declared in "
        "include/PlaybackFFmpegBridge.h",
    )
    require(
        "PBFFmpegSourceReadMonitorInterrupt(" in throughput_source,
        "S4: PlaybackSourceReadThroughput.swift no longer calls "
        "PBFFmpegSourceReadMonitorInterrupt",
    )
    body = function_body_by_brace_matching(
        delivery_source, "func interruptSourceReadsForClose()"
    )
    require(
        "interruptReads()" in body,
        "S4: interruptSourceReadsForClose() no longer calls interruptReads()",
    )


def collect_playback_core_sources() -> dict[str, str]:
    root = ROOT / PLAYBACK_CORE_SOURCES
    sources: dict[str, str] = {}
    for suffix in (".c", ".h", ".swift"):
        for path in sorted(root.rglob(f"*{suffix}")):
            if path.is_file():
                sources[str(path.relative_to(ROOT))] = path.read_text(encoding="utf-8")
    return sources


def check_S5(sources: dict[str, str]) -> None:
    hits = sorted(name for name, text in sources.items() if "PreloadBacklog" in text)
    require(
        not hits,
        "S5: PreloadBacklog must appear nowhere under Packages/PlaybackCore/Sources, "
        f"found in: {', '.join(hits)}",
    )


def header_declarations(header_source: str) -> list[tuple[str, str]]:
    declarations: list[tuple[str, str]] = []
    for match in DECLARATION_NAME.finditer(header_source):
        name = match.group(1)
        params_start = match.end()
        cursor = params_start
        depth = 1
        while cursor < len(header_source) and depth:
            character = header_source[cursor]
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            cursor += 1
        require(depth == 0, f"S6: unbalanced parentheses after {name}(")
        params_end = cursor - 1
        tail = cursor
        while tail < len(header_source) and header_source[tail] in " \t\r\n":
            tail += 1
        if tail >= len(header_source) or header_source[tail] != ";":
            continue
        declarations.append((name, header_source[params_start:params_end]))
    return declarations


def check_S6(header_source: str) -> None:
    for name, parameters in header_declarations(header_source):
        if not PATH_PARAMETER.search(parameters):
            continue
        require(
            bool(MONITOR_PARAMETER.search(parameters)),
            f"S6: {name} takes a const char *path parameter without a "
            "PBFFmpegSourceReadMonitor * parameter, so its reads could not be "
            "interrupted at close",
        )


def main() -> int:
    bridge = read(BRIDGE_C)
    header = read(BRIDGE_HEADER)
    throughput = read(THROUGHPUT_SWIFT)
    delivery = read(DELIVERY_SWIFT)

    stripped_bridge = without_comments(bridge)
    check_S1(stripped_bridge)
    check_S2(stripped_bridge)
    check_S3(bridge_unit_sources())
    check_S4(bridge, header, throughput, delivery)
    check_S5(collect_playback_core_sources())
    check_S6(header)

    print("subtitle reads open only through the monitored, interruptible door")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
