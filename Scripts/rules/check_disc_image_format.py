#!/usr/bin/env python3

"""Checks that a Blu-ray disc image opens as the stream it holds.

A disc image begins with filesystem descriptors rather than media, and FFmpeg
scores those as an MPEG program stream. The bridge therefore names the demuxer
for a UDF image instead of probing it. Two things have to stay true for that to
keep working: the image must still be recognisable as UDF, and naming the
demuxer must still recover the streams the disc holds. Neither is a property of
our code, so neither is covered by a unit test.

The control matters as much as the premise. Naming a demuxer for files that are
not disc images would break every other source, so the check requires the two
non-disc fixtures to open identically whether the helper runs or not.

Two negative controls build the probe in a state that is known to fail, so the
check is seen failing rather than trusted to.

  --reads-nothing   build the probe with the sniff removed, so every image is
                    probed, which is the state before the fix.
  --without-resync  build the probe with the sniff in place but the resync
                    limit left at the demuxer default, which is the state that
                    identified the streams and then delivered no packet from
                    them.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

from enchron_artifact_paths import scratch_directory

REPOSITORY = Path(__file__).resolve().parents[2]
VENDOR = (
    REPOSITORY
    / "Packages/PlaybackCore/Vendor/FFmpeg/PlaybackFFmpeg.xcframework/macos-arm64"
)
MEDIA = Path(
    "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
    "/Samples/DynamicRange/DolbyVision/Profile7.6"
)
DISC_IMAGE = MEDIA / "FEL_test_for_AVS.iso"
NOT_DISC_IMAGES = (MEDIA / "FEL_test_for_AVS.m2ts", MEDIA / "FEL_test_for_AVS.mp4")

LINK_FLAGS = [
    "-lc++", "-liconv", "-lz", "-lbz2", "-llzma",
    "-framework", "AudioToolbox",
    "-framework", "VideoToolbox",
    "-framework", "CoreMedia",
    "-framework", "CoreVideo",
    "-framework", "CoreFoundation",
    "-framework", "CoreText",
    "-framework", "CoreGraphics",
    "-framework", "Security",
]

def build_probe(reads_nothing: bool, without_resync: bool = False) -> Path:
    clang = shutil.which("clang")
    if clang is None:
        raise SystemExit("clang is not on PATH; the disc image probe cannot be built.")
    source = REPOSITORY / "Scripts/verification/disc_image_probe.c"
    name = "probe"
    if reads_nothing:
        name = "probe_reads_nothing"
    elif without_resync:
        name = "probe_without_resync"
    binary = scratch_directory("disc-image-check") / name
    command = [
        clang, "-o", str(binary), str(source),
        "-I", str(VENDOR / "Headers"), str(VENDOR / "libPlaybackFFmpeg.a"),
        *LINK_FLAGS,
    ]
    if reads_nothing:
        command.insert(1, "-DPROBE_READS_NOTHING")
    if without_resync:
        command.insert(1, "-DPROBE_WITHOUT_RESYNC")
    subprocess.run([str(part) for part in command], check=True)
    return binary

def measure(binary: Path, media: Path) -> dict[str, dict[str, str]]:
    completed = subprocess.run(
        [str(binary), str(media)], capture_output=True, text=True, check=True
    )
    readings: dict[str, dict[str, str]] = {}
    for line in completed.stdout.splitlines():
        label, _, rest = line.partition(" ")
        readings[label] = dict(re.findall(r"(\w+)=([^\s]+)", rest))
    return readings

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reads-nothing", action="store_true")
    parser.add_argument("--without-resync", action="store_true")
    arguments = parser.parse_args()

    for media in (DISC_IMAGE, *NOT_DISC_IMAGES):
        if not media.exists():
            raise SystemExit(f"fixture is missing, so nothing would be measured: {media}")

    binary = build_probe(arguments.reads_nothing, arguments.without_resync)
    failures = 0

    def expect(fact: str, measured: object, expected: object, because: str) -> None:
        nonlocal failures
        if measured == expected:
            print(f"  ok   {fact}: {measured}")
        else:
            failures += 1
            print(f"  FAIL {fact}: measured {measured}, expected {expected}")
            print(f"       {because}")

    print(f"\ndisc image {DISC_IMAGE.name}")
    disc = measure(binary, DISC_IMAGE)
    expect(
        "probing alone reads it as a program stream",
        disc["probed"]["format"],
        "mpeg",
        "If probing ever identifies this correctly the helper is redundant, which is"
        " worth knowing; the fix exists only because the probe is wrong here.",
    )
    expect(
        "probing alone finds one of the two video streams",
        disc["probed"]["videoStreams"],
        "1",
        "The disc holds a base layer and an enhancement layer. Recovering one means"
        " the second is lost along with any claim it carries.",
    )
    expect(
        "naming the demuxer opens it as MPEG-TS",
        disc["opened"]["format"],
        "mpegts",
        "Blu-ray keeps its video in MPEG-TS. If this stops holding, the image is not"
        " a Blu-ray image and naming that demuxer is the wrong answer for it.",
    )
    expect(
        "naming the demuxer recovers both video streams",
        (disc["opened"]["videoStreams"], disc["opened"]["width"], disc["opened"]["height"]),
        ("2", "3840", "2160"),
        "This is the whole point of the fix, and it must match what the sibling"
        " .m2ts reports, since they carry the same stream.",
    )
    expect(
        "and packets actually arrive from the stream it recovered",
        disc["opened"]["videoPackets"],
        "20",
        "Identifying a stream and delivering packets from it are separate things."
        " Naming the demuxer alone did the first and not the second: the payload sits"
        " behind the disc's filesystem metadata and the demuxer stopped hunting for"
        " its first sync byte after 64 KB, so the device reported duration 0 with"
        " nothing produced while this check, which did not read packets, passed.",
    )

    for media in NOT_DISC_IMAGES:
        print(f"\ncontrol, not a disc image {media.name}")
        readings = measure(binary, media)
        expect(
            "opens the same whether the helper runs or not",
            readings["opened"],
            readings["probed"],
            "The helper must claim only disc images. Naming a demuxer for anything"
            " else would substitute our guess for a probe that was already right.",
        )

    total = 5 + len(NOT_DISC_IMAGES)
    print(f"\n{total - failures} of {total} premises hold")
    return 1 if failures else 0

if __name__ == "__main__":
    sys.exit(main())
