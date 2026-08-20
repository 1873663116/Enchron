#!/usr/bin/env python3

from pathlib import Path
import os
import re
import sys


REPOSITORY = Path(
    os.environ.get(
        "ENCHRON_FORMAT_CHECK_ROOT",
        Path(__file__).resolve().parents[2],
    )
)
BRIDGE = Path(
    "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c"
)
HEADER = Path(
    "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/include/PlaybackFFmpegBridge.h"
)
PLAYBACK_CORE = Path("Packages/PlaybackCore/Sources/PlaybackCore")
OWNER = "PBFFmpegVideoFormatDescriptionCreate"
LOW_LEVEL_CONSTRUCTOR = re.compile(
    r"\bCMVideoFormatDescriptionCreate(?:From[A-Za-z0-9]+)?\s*\("
)


def read(relative_path: Path) -> str:
    path = REPOSITORY / relative_path
    if not path.is_file():
        raise RuntimeError(f"required source file is missing: {relative_path}")
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(f"cannot read {relative_path}: {error}") from error


def function_region(source: str, marker: str) -> str:
    start = source.find(marker)
    if start < 0:
        raise RuntimeError(f"required function is missing: {marker}")
    following = re.search(r"\n    private static func ", source[start + len(marker):])
    if not following:
        raise RuntimeError(f"cannot find the end of function: {marker}")
    return source[start:start + len(marker) + following.start()]


def require(condition: bool, message: str, violations: list[str]) -> None:
    if not condition:
        violations.append(message)


def main() -> int:
    bridge = read(BRIDGE)
    header = read(HEADER)
    swift_sources = sorted((REPOSITORY / PLAYBACK_CORE).glob("*.swift"))
    if not swift_sources:
        raise RuntimeError(f"no Swift sources found under {PLAYBACK_CORE}")
    sources = {path.relative_to(REPOSITORY): path.read_text(encoding="utf-8")
               for path in swift_sources}
    sources[BRIDGE] = bridge

    violations: list[str] = []
    low_level_owners = [
        path for path, source in sources.items()
        if LOW_LEVEL_CONSTRUCTOR.search(source)
    ]
    require(
        low_level_owners == [BRIDGE],
        "CMVideoFormatDescription constructors must have exactly one production "
        f"owner, {BRIDGE}; found {', '.join(map(str, low_level_owners)) or 'none'}",
        violations,
    )
    require(
        len(re.findall(rf"\bOSStatus\s+{OWNER}\s*\(", bridge)) == 1,
        f"{OWNER} must have exactly one implementation",
        violations,
    )
    require(
        len(re.findall(rf"\bOSStatus\s+{OWNER}\s*\(", header)) == 1,
        f"{OWNER} must have exactly one exported declaration",
        violations,
    )
    require(
        "PBFFmpegReaderCopyCompressedFormatDescription" not in bridge
        and "PBFFmpegReaderCopyCompressedFormatDescription" not in header,
        "the legacy reader-specific construction entry must not return",
        violations,
    )
    swift_direct_constructors = [
        str(path) for path, source in sources.items()
        if path.suffix == ".swift" and LOW_LEVEL_CONSTRUCTOR.search(source)
    ]
    require(
        not swift_direct_constructors,
        "Swift must construct video format descriptions only through the bridge owner: "
        + ", ".join(swift_direct_constructors),
        violations,
    )
    swift_owner_calls = sum(
        len(re.findall(rf"\b{OWNER}\s*\(", source))
        for path, source in sources.items()
        if path.suffix == ".swift"
    )
    require(
        swift_owner_calls >= 3,
        "reader, source-preservation, and presentation-override paths must all "
        f"use {OWNER}; found {swift_owner_calls} Swift calls",
        violations,
    )

    normalization_mentions = re.findall(r"\bnormalize_mov_codec_ids\s*\(", bridge)
    require(
        len(normalization_mentions) == 2,
        "normalize_mov_codec_ids must have one definition and exactly one call; "
        f"found {len(normalization_mentions)} total mentions",
        violations,
    )
    require(
        "normalize_mov_apac_codec_id" not in bridge
        and "normalize_mov_dolby_vision_av1_codec_id" not in bridge,
        "legacy MOV codec normalizers must not return",
        violations,
    )

    provider = read(PLAYBACK_CORE / "VideoSampleProvider.swift")
    gate = function_region(provider, "private static func shouldConsultAVFoundation(")
    forbidden_gate_inputs = (
        "pathExtension",
        "containerFormat",
        '.contains("mov")',
        '.contains("mp4")',
        '["mov", "mp4", "m4v"]',
    )
    for forbidden in forbidden_gate_inputs:
        require(
            forbidden not in gate,
            f"AVFoundation format gate must not infer source facts from {forbidden}",
            violations,
        )
    require(
        "sourceInformation?.containerSupportsSourceFormatDescription" in gate,
        "AVFoundation format gate must consume MediaSourceInformation's "
        "bridge-reported container fact",
        violations,
    )

    if violations:
        for violation in violations:
            print(f"format-description structure violation: {violation}", file=sys.stderr)
        return 1
    print("format-description structure check passed")
    print(f"  constructor owner: {BRIDGE}")
    print(f"  construction entry: {OWNER}")
    print("  MOV codec normalization call sites: 1")
    print("  AVFoundation gate uses explicit bridge facts")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(
            "format-description structure check could not run: "
            f"{type(error).__name__}: {error}",
            file=sys.stderr,
        )
        sys.exit(2)
