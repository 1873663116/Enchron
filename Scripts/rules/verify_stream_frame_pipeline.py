#!/usr/bin/env python3

from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

COORDINATOR = "Modules/GameStreaming/Session/StreamSessionCoordinator.swift"
AUDIO_OUTPUT = "Modules/GameStreaming/Session/StreamAudioOutput.swift"
BRIDGE = "Packages/MoonlightClient/Sources/MoonlightBridge/MLCConnection.m"

FORBIDDEN_TOKENS = {
    COORDINATOR: (
        "awaitingKeyframe",
        "beginAwaitingKeyframe",
        "awaitKeyframeAfterDecodeFailure",
        "noteFrameDroppedAwaitingKeyframe",
        "keyframeRequestInterval",
        "decodeWarningGraceAfterKeyframe",
        "framesDroppedAwaitingKeyframe",
        "markForImmediateDisplay",
        "kCMSampleAttachmentKey_DisplayImmediately",
        "kCMSampleAttachmentKey_NotSync",
        "isKeyframe",
        "keptKeyframe",
    ),
    BRIDGE: (
        "kCMSampleAttachmentKey_NotSync",
        "kCMSampleAttachmentKey_DisplayImmediately",
    ),
    AUDIO_OUTPUT: (
        "video",
    ),
}

REQUIRED_TOKENS = {
    COORDINATOR: (
        "immediateTimingSample(",
        "presentationTime: synchronizer.currentTime()",
        "pendingVideoKeep = 2",
        "frameBufferHoldSeconds",
        "removeFirst(excess)",
    ),
    AUDIO_OUTPUT: (
        "recoverEngineIfStopped()",
        "ring.write(",
    ),
}

EXIT_KEYWORDS = ("return", "continue", "break")
CONTROL_KEYWORDS = (
    "guard ",
    "if ",
    "else if ",
    "while ",
    "for ",
    "switch ",
    "case ",
    "catch",
    "do ",
)

EXIT_COUNTS = {
    ("handleVideoSample", "pendingVideo.append("): 1,
    ("pumpVideoQueue", "videoSink.enqueueImmediately("): 3,
    ("enqueue", "ring.write("): 1,
}

REQUIRED_BEFORE = {
    ("handleVideoSample", "pendingVideo.append("): (
        "guard videoSampleDeliveryIsOpen",
    ),
    ("pumpVideoQueue", "videoSink.enqueueImmediately("): (
        "guard let head = pendingVideo.first",
        "if options.frameBuffer",
        "guard videoRenderer.isReadyForMoreMediaData",
    ),
    ("enqueue", "ring.write("): (
        "guard channels > 0",
    ),
}

FORBIDDEN_BETWEEN = {
    ("handleVideoSample", "pendingVideo.append("): (
        "pendingVideo.removeAll",
        "pendingVideo.removeFirst",
    ),
    ("pumpVideoQueue", "videoSink.enqueueImmediately("): (
        "pendingVideo.removeAll",
        "pendingVideo.removeFirst",
    ),
}

FORBIDDEN_IN_FUNCTION = {
    "pumpVideoQueue": (
        "pendingVideo.removeAll",
        "pendingVideo.removeFirst",
    ),
    "observeRenderingEvents": (
        "requestIdrFrame(",
    ),
    "handleVideoSample": (
        "pendingVideo.removeAll",
        "pendingVideo.removeFirst",
    ),
}

REQUIRED_IN_FUNCTION = {
    "videoSurfaceDidBind": ("pendingVideo.removeAll()",),
    "recoverFromFlushRequirement": ("pendingVideo.removeAll()",),
    "rebuildRendererGraph": ("pendingVideo.removeAll()",),
    "handleVideoSample": ("reportQueueDepthIfNeeded",),
    "reportQueueDepthIfNeeded": (
        "guard depth > Self.pendingVideoLimit else { return }",
        "removeFirst(excess)",
    ),
}

ALLOWED_SWITCH_CASES = {
    "pumpVideoQueue": (
        "case .accepted:",
        "case .acceptedWithWarnings:",
        "case .cancelledByFlush:",
        "case .requiresFlush:",
        "case .failed:",
    ),
}


def strip_debug_blocks(source: str) -> str:
    lines: list[str] = []
    depth = 0
    for line in source.splitlines(keepends=True):
        directive = line.strip()
        if directive == "#if DEBUG":
            depth = 1
            continue
        if depth:
            if directive.startswith("#if "):
                depth += 1
            elif directive == "#endif":
                depth -= 1
            continue
        lines.append(line)
    return "".join(lines)


def function_body(source: str, name: str) -> str:
    marker = f"func {name}("
    start = source.find(marker)
    if start < 0:
        raise AssertionError(f"missing function: {name}")
    opening = source.find("{", start)
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1 : index]
    raise AssertionError(f"unterminated function: {name}")


def normalise(statement: str) -> str:
    return " ".join(statement.replace("{", " ").split())


def early_exits(body: str, marker: str) -> list[tuple[str, str]]:
    lines = body.splitlines()
    marker_index = next(
        (index for index, line in enumerate(lines) if marker in line),
        None,
    )
    if marker_index is None:
        raise AssertionError(f"missing marker: {marker}")
    exits: list[tuple[str, str]] = []
    for index in range(marker_index):
        stripped = lines[index].strip()
        keyword = next(
            (word for word in EXIT_KEYWORDS if stripped.startswith(word)),
            None,
        )
        if keyword is None:
            continue
        indent = len(lines[index]) - len(lines[index].lstrip())
        condition = f"<{keyword} without a control statement>"
        for previous in range(index - 1, -1, -1):
            line = lines[previous]
            previous_indent = len(line) - len(line.lstrip())
            statement = line.strip()
            if previous_indent < indent and statement.startswith(CONTROL_KEYWORDS):
                condition = normalise(statement)
                break
        exits.append((keyword, condition))
    return exits


def switch_cases(body: str) -> list[str]:
    return [
        line.strip()
        for line in body.splitlines()
        if line.strip().startswith("case .")
    ]


def line_of(source: str, token: str) -> int:
    return source.count("\n", 0, source.index(token)) + 1


def check() -> list[str]:
    violations: list[str] = []
    sources = {
        relative: strip_debug_blocks(
            (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
        )
        for relative in (COORDINATOR, AUDIO_OUTPUT, BRIDGE)
    }
    for relative, tokens in FORBIDDEN_TOKENS.items():
        source = sources[relative]
        for token in tokens:
            if token in source:
                violations.append(
                    f"{relative}:{line_of(source, token)}: {token} is not allowed "
                    "in the stream frame pipeline"
                )
    for relative, tokens in REQUIRED_TOKENS.items():
        source = sources[relative]
        for token in tokens:
            if token not in source:
                violations.append(f"{relative}: missing {token}")

    for (name, marker), expected_count in EXIT_COUNTS.items():
        source = sources[COORDINATOR if name != "enqueue" else AUDIO_OUTPUT]
        body = function_body(source, name)
        before = body[: body.find(marker)]
        observed = len(re.findall(r"\b(?:return|continue|break)\b", before))
        if observed != expected_count:
            violations.append(
                f"{name}: {observed} early exits before {marker}, "
                f"expected {expected_count}; an extra exit can drop delivered frames"
            )
        for condition in REQUIRED_BEFORE[(name, marker)]:
            if condition not in before:
                violations.append(f"{name}: missing early-exit condition {condition}")
        for token in FORBIDDEN_BETWEEN.get((name, marker), ()):
            if token in body[: body.find(marker)]:
                violations.append(
                    f"{name}: {token} appears before {marker}; "
                    "the delivery path must not skip or clear frames"
                )

    for name, tokens in FORBIDDEN_IN_FUNCTION.items():
        body = function_body(sources[COORDINATOR], name)
        for token in tokens:
            if token in body:
                violations.append(f"{name}: {token} is not allowed")
    for name, tokens in REQUIRED_IN_FUNCTION.items():
        body = function_body(sources[COORDINATOR], name)
        for token in tokens:
            if token not in body:
                violations.append(f"{name}: missing {token}")
    for name, cases in ALLOWED_SWITCH_CASES.items():
        observed = switch_cases(function_body(sources[COORDINATOR], name))
        if observed != list(cases):
            violations.append(
                f"{name}: enqueue outcomes are {observed}, expected {list(cases)}"
            )
    return violations


def main() -> int:
    try:
        violations = check()
    except (AssertionError, KeyError, OSError) as error:
        print(f"stream frame pipeline check could not run: {error}")
        return 1
    if violations:
        print("stream frame pipeline drifted from the delivery baseline:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("stream frame pipeline matches the delivery baseline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
