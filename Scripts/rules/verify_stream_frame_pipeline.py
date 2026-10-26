#!/usr/bin/env python3

from pathlib import Path
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

COORDINATOR = "Modules/GameStreaming/Session/StreamSessionCoordinator.swift"
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
}

REQUIRED_TOKENS = {
    COORDINATOR: (
        "immediateTimingSample(",
        "presentationTime: synchronizer.currentTime()",
        "pendingVideoKeep = 2",
        "frameBufferHoldSeconds",
    ),
}


def line_of(source: str, token: str) -> int:
    return source.count("\n", 0, source.index(token)) + 1


def main() -> int:
    violations: list[str] = []
    for relative, tokens in FORBIDDEN_TOKENS.items():
        source = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
        for token in tokens:
            if token in source:
                violations.append(f"{relative}:{line_of(source, token)}: {token}")
    for relative, tokens in REQUIRED_TOKENS.items():
        source = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
        for token in tokens:
            if token not in source:
                violations.append(f"{relative}: missing {token}")
    if violations:
        print("stream frame pipeline drifted from the PR baseline:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("stream frame pipeline matches the PR baseline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
