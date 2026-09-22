#!/usr/bin/env python3

"""Checks that marker-named debug code stays behind the debug boundary.

The naming convention in ARCHITECTURE.md's ownership rules makes
development-only code mechanically recognizable: it carries a marker word
(Debug, Harness, Automation, TestHook, Fixture) in its file or declaration
name. This checker enforces the
placement half of that convention against the same per-file `#if DEBUG`
region model as verify_release_surface.py:

- a marker-named file under a production root must live under a
  `DebugSupport/` directory or be entirely `#if DEBUG`-gated, unless the
  file is listed in ALLOWED_FILES with a reason;
- a marker-named declaration (`func`, `var`, `let`, `struct`, `enum`,
  `class`, `actor`, `typealias`) outside `#if DEBUG` is a violation unless
  the declaration is listed in ALLOWED_DECLARATIONS with a reason;
- `@_spi(Testing)` declarations outside `#if DEBUG` are test-only API
  surface and are flagged outright.

Allowlist entries exist for load-bearing production API that happens to
carry a marker word; each entry names the consumer that requires it.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RULE = "debug-boundary"

SCAN_ROOTS = ("Apps", "Modules", "Packages")

"""Marker words that mean development-only code. Diagnostic, Probe, Trace
and Evidence are deliberately absent: in this codebase they are domain
vocabulary for production features (media probing, user-visible playback
diagnostics, the evidence pipeline feeding UnmetCapability warnings), so
matching them would flag production code rather than debug code."""
MARKER = re.compile(r"debug|harness|automation|testhook|fixture", re.IGNORECASE)

FILE_MARKER = MARKER

DECLARATION = re.compile(
    r"\b(?:func|var|let|struct|enum|class|actor|typealias)\s+"
    r"`?([A-Za-z_][A-Za-z0-9_]*)`?"
)
SPI_TESTING = re.compile(r"@_spi\(Testing\)")

"""Marker-named files that legitimately ship in Release, keyed by
repository-relative path with the consumer that requires them. An
allowlisted file still gets its declarations scanned — the entry only
excuses the file's own name and location."""
ALLOWED_FILES = {
    "Modules/Playback/Session/DebugProbeJournal.swift":
        "DebugProbeRetention stays ungated for the shipped record signature; "
        "the journal itself is #if DEBUG gated inside this file",
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDebugRecorder.swift":
        "inert in Release; the controller instantiates it only when "
        "debugRecorderMode is .enabled, which Release forces to .disabled",
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDebugSnapshot+Codable.swift":
        "Codable for the load-bearing debugSnapshot() return type",
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDebugging.swift":
        "model types backing debugStore and debugSnapshot(), both written "
        "by production event paths",
}

"""Ungated marker-named declarations that are load-bearing production API.
Keyed by repository-relative path; each entry is (name, reason)."""
ALLOWED_DECLARATIONS = {
    "Modules/MediaSource/MediaByteStream.swift": {
        "MediaSourceDebugTrace":
            "call-site-facing shell; the sink body is #if DEBUG gated",
    },
    "Modules/Playback/PlaybackRuntime.swift": {
        "debugSnapshot":
            "read by presentationDidAttach and control-wait paths",
    },
    "Modules/Playback/Scenes/ImmersiveSpaceView.swift": {
        "debugSnapshot":
            "read by the surface-attach confirmation path",
    },
    "Modules/Playback/Session/PlaybackMediaSessionDriver.swift": {
        "debugSnapshot":
            "driver protocol + implementation consumed by production",
    },
    "Modules/Playback/Session/RendererTransferCoordinator.swift": {
        "debugSnapshot":
            "read by renderer-transfer confirmation paths",
        "preparedDebugSnapshot":
            "read by renderer-transfer confirmation paths",
    },
    "Modules/Playback/Session/DebugProbeJournal.swift": {
        "DebugProbeRetention":
            "parameter type of the shipped probe record signature",
    },
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackCoreController.swift": {
        "PlaybackDebugRecorderMode":
            "init parameter type; Release forces the value to .disabled",
        "debugRecorder":
            "nil in Release because the mode is forced disabled",
        "debugRecorderMode":
            "kept on the stable init signature; forced .disabled in Release",
    },
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDebugRecorder.swift": {
        "PlaybackDebugRecorder":
            "internal type; never instantiated when the mode is disabled",
    },
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDebugging.swift": {
        "PlaybackDebugEvent":
            "event model written by production paths for debugSnapshot()",
        "MediaSessionDebugSummary":
            "summary model returned by debugSnapshot()",
        "PlaybackDebugSnapshotV1":
            "snapshot type returned by debugSnapshot()",
        "PlaybackDiagnosticsStore":
            "debugStore; production writes it so debugSnapshot() is correct",
    },
    "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDebugSnapshot+Codable.swift": {
        "PlaybackDebugSnapshotV1CodingKey":
            "Codable keys for the snapshot type",
    },
    "Packages/PlaybackCore/Sources/PlaybackCore/SampleBufferPlaybackSession.swift": {
        "debugStore":
            "written by production event paths; read via debugSnapshot()",
    },
    "Packages/PlaybackCore/Sources/PlaybackCore/"
    "SampleBufferPlaybackSession+Bindings.swift": {
        "debugSnapshot":
            "binding surface for the production-read snapshot",
    },
}


def production_swift_files() -> list[Path]:
    files: list[Path] = []
    for root_name in SCAN_ROOTS:
        root = REPOSITORY_ROOT / root_name
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.swift")):
            parts = path.relative_to(REPOSITORY_ROOT).parts
            if ".build" in parts or "Tests" in parts:
                continue
            if "Sources" not in parts and parts[0] == "Packages":
                continue
            files.append(path)
    return files


def whole_file_gated(lines: list[str]) -> bool:
    body = [
        line.strip()
        for line in lines
        if line.strip() and not line.strip().startswith("//")
    ]
    return bool(body) and body[0] == "#if DEBUG" and body[-1] == "#endif"


def audit_file(path: Path) -> list[str]:
    relative = path.relative_to(REPOSITORY_ROOT)
    lines = path.read_text(encoding="utf-8").splitlines()
    in_debug_support = "DebugSupport" in relative.parts

    if whole_file_gated(lines):
        return []

    failures: list[str] = []
    if FILE_MARKER.search(path.stem) and not in_debug_support:
        reason = ALLOWED_FILES.get(str(relative))
        if reason is None:
            failures.append(
                f"{relative}: error: [{RULE}] marker-named file compiles "
                "into Release; move it under DebugSupport/, wrap it in "
                "#if DEBUG, or record the shipping consumer in "
                "verify_debug_boundary.py"
            )

    scopes: list[str] = []
    allowed = ALLOWED_DECLARATIONS.get(str(relative), {})
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            condition = stripped[3:].strip()
            if condition == "DEBUG":
                scopes.append("debug")
            elif condition == "!DEBUG":
                scopes.append("inverted")
            else:
                scopes.append("release")
            continue
        if stripped.startswith("#elseif"):
            if scopes:
                condition = stripped[7:].strip()
                if "DEBUG" in condition and "!DEBUG" not in condition:
                    scopes[-1] = "debug" if scopes[-1] != "debug" else "release"
                else:
                    scopes[-1] = "release"
            continue
        if stripped == "#else":
            if scopes:
                top = scopes[-1]
                scopes[-1] = (
                    "release" if top == "debug"
                    else "debug" if top == "inverted"
                    else "release"
                )
            continue
        if stripped == "#endif":
            if not scopes:
                failures.append(
                    f"{relative}:{number}: error: [{RULE}] #endif without #if"
                )
            else:
                scopes.pop()
            continue
        if "debug" in scopes or in_debug_support:
            continue
        if SPI_TESTING.search(line):
            failures.append(
                f"{relative}:{number}: error: [{RULE}] @_spi(Testing) "
                "declaration compiles into Release; gate it behind #if DEBUG"
            )
            continue
        match = DECLARATION.search(line)
        if match and MARKER.search(match.group(1)):
            name = match.group(1)
            if name not in allowed:
                failures.append(
                    f"{relative}:{number}: error: [{RULE}] marker-named "
                    f"declaration `{name}` compiles into Release; gate it "
                    "behind #if DEBUG, move it to DebugSupport/, or record "
                    "the shipping consumer in verify_debug_boundary.py"
                )
    if scopes:
        failures.append(
            f"{relative}: error: [{RULE}] unclosed #if scope(s): "
            f"{len(scopes)} still open at end of file"
        )
    return failures


def main() -> int:
    failures: list[str] = []
    for path in production_swift_files():
        failures.extend(audit_file(path))
    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        print(f"{len(failures)} debug-boundary violation(s)", file=sys.stderr)
        return 1
    print(
        "debug boundary clean: marker-named files and declarations stay "
        "behind #if DEBUG or DebugSupport/"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
