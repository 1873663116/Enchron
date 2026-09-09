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

Leaving playback is one entry with one stated reason. `leavePlayback`,
`leavePlaybackAndWait` and `stopForNextRequest` are called from
`PlaybackLaunchCoordinator` only; a view, a scene or the application wiring
reaching past the coordinator is how the reason gets lost, and a caller that
replaces the request behind the coordinator's back leaves the page state and
the launch generation disagreeing. The unqualified `stop` the coordinator used
to forward is gone, so no product source may call it.

The page the main window shows is decided from `PlaybackResidency`:
`MainView.showsWindowPlayback` reads the runtime's residency and
`primaryContent` switches on it, so a failed open keeps the player page while
`hasActivePlaybackRequest` says nothing about which page is up. The close the
runtime runs is bounded by `PlaybackCloseBudget.deadline`.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

RUNTIME_SOURCE = "Modules/Playback/PlaybackRuntime.swift"
INTERPRETER_SOURCE = "Modules/Playback/Domain/MediaFormatInterpreter.swift"
COORDINATOR_SOURCE = "Modules/Playback/PlaybackLaunchCoordinator.swift"
PAGE_SOURCE = "Apps/Enchron/MainView.swift"
PRODUCT_ROOTS = ("Apps", "Modules")

COMMENT = re.compile(r"^\s*(//|\*|/\*)")
LEAVE_CALL = re.compile(
    r"\.\s*(?:leavePlayback(?:AndWait)?|stopForNextRequest)\s*\("
)
LEGACY_STOP_CALL = re.compile(r"\bplaybackRuntime\s*\.\s*stop\s*\(")
WINDOW_PAGE_DECISION = re.compile(
    r"private\s+var\s+showsWindowPlayback:\s*Bool\s*\{\s*\n"
    r"\s*switch\s+playbackRuntime\.residency\s*\{"
)
PRIMARY_CONTENT_PAGE = re.compile(
    r"private\s+var\s+primaryContent:\s*some\s+View\s*\{[^}]*?"
    r"if\s+showsWindowPlayback\s*\{",
    re.DOTALL,
)
CLOSE_BUDGET = re.compile(r"\bPlaybackCloseBudget\s*\.\s*deadline\b")


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


def product_sources() -> list[Path]:
    found: list[Path] = []
    for root in PRODUCT_ROOTS:
        base = REPOSITORY_ROOT / root
        if not base.is_dir():
            continue
        found.extend(sorted(base.rglob("*.swift")))
    return found


def leave_entry_failures() -> list[str]:
    permitted = {COORDINATOR_SOURCE}
    failures = []
    for path in product_sources():
        relative = path.relative_to(REPOSITORY_ROOT).as_posix()
        if relative in permitted:
            continue
        for number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), 1
        ):
            if not line.strip() or COMMENT.match(line):
                continue
            if LEAVE_CALL.search(line):
                failures.append(
                    f"{relative}:{number}: leave-entry: leaving playback goes "
                    f"through PlaybackLaunchCoordinator, not through "
                    f"PlaybackRuntime directly ({line.strip()[:70]})"
                )
    return failures


def legacy_stop_failures() -> list[str]:
    failures = []
    for path in product_sources():
        relative = path.relative_to(REPOSITORY_ROOT).as_posix()
        for number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), 1
        ):
            if not line.strip() or COMMENT.match(line):
                continue
            if LEGACY_STOP_CALL.search(line):
                failures.append(
                    f"{relative}:{number}: leave-reason: stopping playback "
                    f"without a PlaybackLeaveReason is gone; call "
                    f"leavePlayback(reason:) ({line.strip()[:70]})"
                )
    return failures


def page_authority_failures() -> list[str]:
    path = REPOSITORY_ROOT / PAGE_SOURCE
    if not path.is_file():
        return [f"{PAGE_SOURCE} is absent"]
    contents = path.read_text(encoding="utf-8")
    failures = []
    if not WINDOW_PAGE_DECISION.search(contents):
        failures.append(
            f"{PAGE_SOURCE}: page-authority: showsWindowPlayback reads "
            f"PlaybackRuntime.residency, not hasActivePlaybackRequest"
        )
    if not PRIMARY_CONTENT_PAGE.search(contents):
        failures.append(
            f"{PAGE_SOURCE}: page-authority: primaryContent picks the page from "
            f"showsWindowPlayback"
        )
    return failures


def close_budget_failures() -> list[str]:
    path = REPOSITORY_ROOT / RUNTIME_SOURCE
    if not path.is_file():
        return [f"{RUNTIME_SOURCE} is absent"]
    if CLOSE_BUDGET.search(path.read_text(encoding="utf-8")):
        return []
    return [
        f"{RUNTIME_SOURCE}: close-budget: the close the runtime runs is bounded "
        f"by PlaybackCloseBudget.deadline"
    ]


def failures() -> list[str]:
    return (
        runtime_failures()
        + interpreter_failures()
        + leave_entry_failures()
        + legacy_stop_failures()
        + page_authority_failures()
        + close_budget_failures()
    )


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} ownership failures")
        return 1
    print(
        "Playback ownership holds: the runtime picks no driver, holds no session "
        "or transfer internals, decides no format policy, the interpreter "
        "imports neither the engine nor a platform media framework, leaving "
        "and replacing playback go through the launch coordinator, the page "
        "follows PlaybackResidency and the close is bounded"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
