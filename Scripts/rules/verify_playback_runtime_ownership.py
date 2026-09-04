#!/usr/bin/env python3

"""Checks who owns what in the playback runtime.

`PlaybackRuntime` is the facade the views talk to. It publishes observable
product state, wires events, and forwards one command at a time. Everything
underneath belongs to a named collaborator:

    PlaybackRuntime            observable projection + command forwarding
      ├─ RendererTransferCoordinator   which driver is active, cutover, surface
      │    └─ PlaybackMediaSessionDriver   the session, transport, tracks
      └─ MediaFormatInterpreter        projection, stereo, profile, resolution

The rule is stated as what the facade may not reach for, not as a line count.
A line budget says nothing about whether the runtime is still picking drivers;
a reference to `activeDriver` says exactly that it is.

`MediaFormatInterpreter` is checked from the other direction: it is a pure
domain component, so it must not import the playback engine or a platform
media framework at all.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

RUNTIME_SOURCE = "Modules/Playback/PlaybackRuntime.swift"
INTERPRETER_SOURCE = "Modules/Playback/Domain/MediaFormatInterpreter.swift"

COMMENT = re.compile(r"^\s*(//|\*|/\*)")


@dataclass(frozen=True)
class Rule:
    name: str
    reason: str
    patterns: tuple[str, ...]


RUNTIME_RULES = (
    Rule(
        "driver-selection",
        "choosing the active, prepared or departing driver belongs to RendererTransferCoordinator",
        (r"\bactiveDriver\b", r"\bpreparedDriver\b", r"\bdepartingDriver\b"),
    ),
    Rule(
        "core-session-types",
        "opening and holding a session belongs to PlaybackMediaSessionDriver",
        (
            r"\bPlaybackMediaSessionDriver\s*\.\s*SessionResource\b",
            r"\bAVSampleBufferVideoRenderer\b",
            r"\bPlaybackCoreController\b",
        ),
    ),
    Rule(
        "transfer-internals",
        "cutover tokens, transfer keys and continuity belong to RendererTransferCoordinator",
        (r"\bCutoverToken\b", r"\bTransferKey\b", r"\bRendererTransferCoordinator\s*\.\s*Continuity\b"),
    ),
    Rule(
        "format-policy",
        "projection, stereo layout and field of view belong to MediaFormatInterpreter",
        (
            r"\bPlaybackModel\s*\.\s*ProjectionType\b",
            r"\bVideoStereoLayout\b",
            r"\bnormalizedHorizontalFieldOfViewDegrees\b",
            r"\beffectiveHorizontalFieldOfViewDegrees\b",
        ),
    ),
)

INTERPRETER_FORBIDDEN_IMPORTS = ("PlaybackCore", "AVFoundation", "AVKit", "CoreMedia", "RealityKit")


def source_lines(relative: str) -> list[tuple[int, str]]:
    path = REPOSITORY_ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(relative)
    return [
        (number, line)
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if line.strip() and not COMMENT.match(line)
    ]


def runtime_failures() -> list[str]:
    try:
        lines = source_lines(RUNTIME_SOURCE)
    except FileNotFoundError:
        return [f"{RUNTIME_SOURCE} is absent"]
    failures = []
    for rule in RUNTIME_RULES:
        hits = [
            (number, line.strip())
            for number, line in lines
            if any(re.search(pattern, line) for pattern in rule.patterns)
        ]
        if hits:
            number, text = hits[0]
            failures.append(
                f"{RUNTIME_SOURCE}:{number}: {rule.name}: {rule.reason} "
                f"({len(hits)} reference(s), first: {text[:70]})"
            )
    return failures


def interpreter_failures() -> list[str]:
    try:
        lines = source_lines(INTERPRETER_SOURCE)
    except FileNotFoundError:
        return [f"{INTERPRETER_SOURCE} is absent"]
    failures = []
    for number, line in lines:
        match = re.match(r"\s*import\s+([\w.]+)", line)
        if match and match.group(1).split(".")[0] in INTERPRETER_FORBIDDEN_IMPORTS:
            failures.append(
                f"{INTERPRETER_SOURCE}:{number}: pure-domain: MediaFormatInterpreter "
                f"must not import {match.group(1)}"
            )
    return failures


def failures() -> list[str]:
    return runtime_failures() + interpreter_failures()


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} ownership failures")
        return 1
    print(
        "Playback ownership holds: the runtime picks no driver, holds no session "
        "or transfer internals, decides no format policy, and the interpreter "
        "imports neither the engine nor a platform media framework"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
