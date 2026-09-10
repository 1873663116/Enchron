#!/usr/bin/env python3

"""Asserts the measured facts that the Dolby Vision handling in
PlaybackFFmpegBridge.c reads as given.

That code makes three decisions from the source and re-derives none of them at
runtime.

Whether to declare a track as Dolby Vision to VideoToolbox.
`has_usable_dovi_configuration` reads the decoded stream's configuration record
and refuses it when `el_present_flag` is set, because a dual-layer source
delivers only its base layer through one decoder input, and a decoder told the
track is Profile 7 has no path for it and refuses the whole track.

Which record describes the stream being decoded. `detect_dolby_vision` scans
every video stream to word the dynamic range line, and believes a record found on
some other stream only when `bl_present_flag` is clear: a pure enhancement layer
cannot stand alone, so it belongs to the decoded stream, while a stream carrying
its own base layer is an unrelated title whose profile is not a fact about this
one.

Which field becomes the digit after the profile in that line. It is
`dv_bl_signal_compatibility_id`, the dynamic range the base layer is also readable
as, and not `dv_level`, which counts resolution and bitrate tiers. The two fields
are equal on both Profile 7.6 fixtures and on the single-layer declaration control,
which is why three device rounds of green results said nothing about this rule and
why separate fixtures are measured for it.

A remux of a fixture, or an FFmpeg build that reports a stream layout
differently, moves the ground under that decision without changing a line of C
and without any symptom the code can raise.

The measurement runs through `dolby_vision_premise_probe.c`, linked against the
same vendored FFmpeg the bridge links, so the stream selection and the side data
lookup are the ones production performs rather than a command line ffprobe's
approximation of them.

The probe exits non-zero only when it cannot read the file: 2 on a usage error,
3 when `avformat_open_input` or `avformat_find_stream_info` fails. A file that
violates a premise still prints its report and exits zero, because which premise
applies to which fixture is decided here and not there. A probe changed to exit
non-zero on a violated premise would turn every real premise failure into
`measure`'s "could not read" abort, which names the wrong cause and stops the
run before the remaining fixtures are measured.

The probe prints the whole video stream record, which is wider than the premises
below read: the index, the codec, the sample entry tag, the dimensions, which
stream decodes, the configuration record and the declaration verdict. A failing
premise is then read against the file it was measured on. The sample entry tag
is in the record for the same reason: `codec_type` branches on the configuration
record and reads no tag, so the tag is printed to be seen not deciding anything.

Two controls run first, because every premise about the Profile 7.6 fixtures
asserts that something is refused, and a mirror that refuses everything would
satisfy all of them while measuring nothing. A single-layer file proves the
declaration condition can still return true. A constructed container carrying an
unrelated Dolby Vision track proves the scan's rule about other streams is
reached at all, since no file in the sample tree is shaped that way. Three more
fixtures follow, chosen only because their level and cross compatibility disagree,
so the naming rule is measured by files that can tell the two apart.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

from enchron_artifact_paths import scratch_directory

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROBE_SOURCE = (
    Path(__file__).resolve().parents[1] / "verification/dolby_vision_premise_probe.c"
)
VENDORED_FFMPEG = (
    REPOSITORY_ROOT
    / "Packages/PlaybackCore/Vendor/FFmpeg/PlaybackFFmpeg.xcframework/macos-arm64"
)
SAMPLE_ROOT = Path(
    "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/Samples/DynamicRange/DolbyVision"
)
MATROSKA = SAMPLE_ROOT / "Profile7.6/FEL_test_for_AVS.mkv"
MP4 = SAMPLE_ROOT / "Profile7.6/FEL_test_for_AVS.mp4"
SINGLE_LAYER = (
    SAMPLE_ROOT / "HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
)

FIXTURES_WHERE_LEVEL_AND_CROSS_ID_DISAGREE = (
    (
        SAMPLE_ROOT / "HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        1,
        4,
        "Dolby Vision Profile 8.4",
        "Dolby Vision Profile 8.1",
    ),
    (
        SAMPLE_ROOT / "Profile8.1/OfficialDolby/P81_GlassBlowing2_1920x1080-59.94fps_fmp4.mp4",
        5,
        1,
        "Dolby Vision Profile 8.1",
        "Dolby Vision Profile 8.5",
    ),
    (
        SAMPLE_ROOT / "HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
        1,
        0,
        "Dolby Vision Profile 5",
        "Dolby Vision Profile 5.1",
    ),
)

LINK_FLAGS = [
    "-lc++",
    "-liconv",
    "-lz",
    "-lbz2",
    "-llzma",
    "-framework", "AudioToolbox",
    "-framework", "VideoToolbox",
    "-framework", "CoreMedia",
    "-framework", "CoreVideo",
    "-framework", "CoreFoundation",
    "-framework", "CoreText",
    "-framework", "CoreGraphics",
    "-framework", "Security",
]


def build_probe(source: Path, quiet: bool) -> Path:
    if not VENDORED_FFMPEG.is_dir():
        raise SystemExit(
            f"the vendored FFmpeg macOS slice is missing: {VENDORED_FFMPEG}\n"
            "Without it this check would have to measure through some other FFmpeg "
            "than the one the bridge links, which is the confusion it exists to prevent."
        )
    clang = shutil.which("clang")
    if clang is None:
        raise SystemExit("clang is not on PATH; the premise probe cannot be built.")
    library = VENDORED_FFMPEG / "libPlaybackFFmpeg.a"
    source_path_fingerprint = hashlib.sha256(
        str(source.resolve()).encode()
    ).hexdigest()[:12]
    binary = (
        scratch_directory("dolby-vision-premise-probe")
        / f"dolby_vision_premise_probe-{source_path_fingerprint}"
    )
    newest_input = max(source.stat().st_mtime, library.stat().st_mtime)
    if binary.exists() and binary.stat().st_mtime >= newest_input:
        return binary
    command = [
        clang,
        "-O1",
        "-Wall",
        "-I", str(VENDORED_FFMPEG / "Headers"),
        str(source),
        str(library),
        *LINK_FLAGS,
        "-o", str(binary),
    ]
    completed = subprocess.run(command, check=False, text=True, capture_output=True)
    if completed.returncode != 0:
        raise SystemExit(
            f"the premise probe did not build:\n{completed.stderr or completed.stdout}"
        )
    if not quiet:
        print(f"built the premise probe against {library}")
    return binary


def measure(binary: Path, media: Path) -> dict[str, object]:
    if not media.is_file():
        raise SystemExit(f"the fixture this check reads is missing: {media}")
    completed = subprocess.run(
        [str(binary), str(media)], check=False, text=True, capture_output=True
    )
    if completed.returncode != 0:
        raise SystemExit(
            f"the premise probe could not read {media}:\n{completed.stderr.strip()}"
        )
    return json.loads(completed.stdout)


def build_unrelated_track_fixture(plain: Path, dolby_vision: Path) -> Path:
    """A container whose decoded stream is one title and whose second video stream
    is a different one carrying its own base layer. Nothing in the sample tree is
    shaped this way, so the rule that refuses such a record has no natural fixture
    and this is muxed at run time from two real samples.

    Matroska, because this FFmpeg's mp4 muxer drops the configuration record on
    remux for every sample entry tried, which would leave nothing to refuse."""
    path = scratch_directory("dolby-vision-premise-probe") / "unrelated-dolby-vision-track.mkv"
    completed = subprocess.run(
        [
            "ffmpeg", "-y", "-v", "error",
            "-i", str(plain),
            "-i", str(dolby_vision),
            "-map", "0:v:0",
            "-map", "1:v:0",
            "-t", "3",
            "-c", "copy",
            "-disposition:v:0", "default",
            "-disposition:v:1", "0",
            str(path),
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0 or not path.is_file():
        raise SystemExit(
            f"could not construct the unrelated track fixture:\n{completed.stderr}"
        )
    return path


def video_stream(measurement: dict[str, object], index: int) -> dict[str, object] | None:
    for stream in measurement["videoStreams"]:
        if stream["index"] == index:
            return stream
    return None


def decoded_stream(measurement: dict[str, object]) -> dict[str, object] | None:
    return video_stream(measurement, measurement["decodedStreamIndex"])


class Premises:
    """Each entry names the fact, the value read now, the value the C code was
    written against, and the decision in that code which stops being true when
    they differ."""

    def __init__(self) -> None:
        self.failures: list[str] = []
        self.checked = 0

    def require(self, *, fact: str, measured: object, expected: object, consequence: str) -> None:
        self.checked += 1
        if measured == expected:
            print(f"  ok   {fact}: {measured!r}")
            return
        self.failures.append(
            f"{fact}\n"
            f"       measured {measured!r}, the code was written against {expected!r}\n"
            f"       {consequence}"
        )
        print(f"  FAIL {fact}: measured {measured!r}, expected {expected!r}")


def check_control(premises: Premises, measurement: dict[str, object]) -> None:
    """Without this, a mirror of the declaration condition that always answered
    "not declarable" would satisfy every premise below while measuring nothing."""
    print(f"\ncontrol, single layer {Path(measurement['path']).name}")
    stream = decoded_stream(measurement)
    premises.require(
        fact="a single layer record on the decoded stream is declarable",
        measured=(
            stream is not None
            and stream["dolbyVision"] is not None
            and stream["dolbyVision"]["elPresent"] is False
            and measurement["decodedStreamDeclaresDolbyVision"]
        ),
        expected=True,
        consequence=(
            "This file is what the declaration condition exists to let through: one layer, "
            "no enhancement stream, a profile VideoToolbox decodes. If it is refused, the "
            "condition is broken in the permissive direction's opposite and every premise "
            "below is passing because nothing is ever declarable, not because the Profile "
            "7.6 fixtures are shaped as expected."
        ),
    )


def check_unrelated_track(premises: Premises, measurement: dict[str, object]) -> None:
    """The rule this exercises has no fixture in the sample tree, so without a
    constructed one it would be a branch nothing ever reaches."""
    print("\ncontrol, an unrelated Dolby Vision track, constructed")
    foreign = [
        stream
        for stream in measurement["videoStreams"]
        if not stream["isDecodedStream"] and stream["dolbyVision"] is not None
    ]
    premises.require(
        fact="the constructed container carries a base layer record off the decoded stream",
        measured=len(foreign) == 1 and foreign[0]["dolbyVision"]["blPresent"] is True,
        expected=True,
        consequence=(
            "The mux has to survive for this leg to test anything. If the muxer stopped "
            "preserving the configuration record, the leg below would be asserting that an "
            "absent record is refused, which proves nothing, and the rule would be untested "
            "rather than covered."
        ),
    )
    premises.require(
        fact="that record is refused, so no profile is published",
        measured=measurement["detected"]["recordStreamIndex"],
        expected=-1,
        consequence=(
            "detect_dolby_vision believes a record from a stream it is not decoding only "
            "when bl_present_flag is clear. A stream carrying its own base layer is a "
            "different title, and accepting it would word this title's dynamic range line "
            "from that one's profile."
        ),
    )


def check_naming(
    premises: Premises,
    measurements: list[tuple[dict[str, object], int, int, str, str]],
) -> None:
    """Pins the fixtures that can tell the two candidate fields apart. Neither
    Profile 7.6 file can: both carry level 6 and cross compatibility 6, so a name
    built from either reads Profile 7.6 and a regression in which field is read
    leaves them green. The single-layer declaration control carries 1 and 1 and is
    no better. These three disagree."""
    print("\nnaming, files where the level and the cross compatibility differ")
    for measurement, level, cross, published, misread in measurements:
        stream = decoded_stream(measurement)
        record = stream["dolbyVision"] if stream is not None else None
        premises.require(
            fact=f"{Path(measurement['path']).name[:38]} reads level {level}, cross {cross}",
            measured=(
                record["level"] if record else None,
                record["blCompatibilityId"] if record else None,
                measurement["detected"]["crossCompatibilityID"],
            ),
            expected=(level, cross, cross),
            consequence=(
                f"This file is published as {published}. Its level and its cross "
                f"compatibility differ, so it is one of the few that can show which one "
                f"the name is built from: reading the level would produce {misread}. If "
                "the two ever agree here, this fixture stops separating the rules and "
                "the only files left measuring the naming rule are ones that cannot."
            ),
        )


def check_matroska(premises: Premises, measurement: dict[str, object]) -> None:
    print(f"\nMatroska {measurement['path']}")
    stream = decoded_stream(measurement)
    detected = measurement["detected"]
    record = stream["dolbyVision"] if stream is not None else None

    premises.require(
        fact="the decoded stream carries a configuration record",
        measured=record is not None,
        expected=True,
        consequence=(
            "This is the only fixture whose decoded stream carries a record, so it is the "
            "only one that puts has_usable_dovi_configuration under load at all. If the "
            "record moves off the decoded stream, nothing here exercises the condition "
            "that keeps a dual-layer source from being declared."
        ),
    )
    if record is not None:
        premises.require(
            fact="el_present_flag is set on that record",
            measured=record["elPresent"],
            expected=True,
            consequence=(
                "This flag is the single thing standing between this file and a black "
                "screen. has_usable_dovi_configuration refuses the record only because it "
                "is set. Reading 0 here would let add_dovi_configuration_atom attach a "
                "Profile 7 descriptor, and VideoToolbox, having no path for Profile 7, "
                "refuses the whole track: 0 frames displayed out of every sample accepted."
            ),
        )
        premises.require(
            fact="the record reads Profile 7, cross compatibility 6",
            measured=(detected["profile"], detected["crossCompatibilityID"]),
            expected=(7, 6),
            consequence=(
                "The dynamic range line is worded from these two values, and they are the "
                "whole name: Profile 7.6. The level is not read and is not asserted, "
                "because nothing consumes it."
            ),
        )
    premises.require(
        fact="the decoded stream is not declared as Dolby Vision",
        measured=measurement["decodedStreamDeclaresDolbyVision"],
        expected=False,
        consequence=(
            "This is the decision itself, and the value that reaches VideoToolbox. True "
            "here is the black screen, whatever combination of record and flag produced it."
        ),
    )
    premises.require(
        fact="the label still has a record to read, on the decoded stream",
        measured=detected["recordStreamIndex"],
        expected=0,
        consequence=(
            "detect_dolby_vision scans every video stream to word the dynamic range line. "
            "Losing the record entirely does not black the picture out, but it silently "
            "takes the Profile 7.6 fallback wording away, which is the state this file was "
            "in before it was said at all."
        ),
    )


def check_mp4(premises: Premises, measurement: dict[str, object]) -> None:
    print(f"\nmp4 {measurement['path']}")
    detected = measurement["detected"]
    base = video_stream(measurement, 0)
    enhancement = video_stream(measurement, 1)

    premises.require(
        fact="the mp4 carries two video streams",
        measured=len(measurement["videoStreams"]),
        expected=2,
        consequence=(
            "This layout is what keeps the configuration record off the stream that gets "
            "decoded, and it is the whole reason detect_dolby_vision scans every video "
            "stream rather than the decoded one."
        ),
    )
    premises.require(
        fact="the decoded stream is the base layer, index 0",
        measured=measurement["decodedStreamIndex"],
        expected=0,
        consequence=(
            "av_find_best_stream picks this by disposition. If it ever picked the "
            "enhancement track, the reader would feed the decoder a track carrying no base "
            "layer, and the declaration condition would be reading the wrong stream's record."
        ),
    )
    premises.require(
        fact="the decoded stream carries no configuration record",
        measured=base is not None and base["dolbyVision"] is None,
        expected=True,
        consequence=(
            "This is why this container never went black. has_usable_dovi_configuration "
            "reads the decoded stream, finds nothing, declares nothing, and the base layer "
            "decodes as plain HDR10. A remux that moved the record onto stream 0 would put "
            "this file under the same condition the Matroska is under, and it would then "
            "depend entirely on el_present_flag reading 1."
        ),
    )
    premises.require(
        fact="the decoded stream is not declared as Dolby Vision",
        measured=measurement["decodedStreamDeclaresDolbyVision"],
        expected=False,
        consequence=(
            "The decision itself for this file, reached for a different reason than the "
            "Matroska's: there is no record to refuse rather than a record refused."
        ),
    )
    premises.require(
        fact="the record sits on stream 1 and reads Profile 7, cross compatibility 6",
        measured=(
            detected["recordStreamIndex"],
            detected["profile"],
            detected["crossCompatibilityID"],
        ),
        expected=(1, 7, 6),
        consequence=(
            "This is the only place the mp4 states its profile, and the dynamic range line "
            "is worded from it. Reading the decoded stream alone reports a plain HDR10 "
            "track and the claim disappears."
        ),
    )
    if enhancement is not None and enhancement["dolbyVision"] is not None:
        premises.require(
            fact="el_present_flag is set on stream 1's record",
            measured=enhancement["dolbyVision"]["elPresent"],
            expected=True,
            consequence=(
                "The line reads a fallback because of this flag. Clear, and the label would "
                "claim a Dolby Vision picture the wearer is not being shown."
            ),
        )
        premises.require(
            fact="bl_present_flag is clear on stream 1's record",
            measured=enhancement["dolbyVision"]["blPresent"],
            expected=False,
            consequence=(
                "This is the sole reason the mp4 and the m2ts find their record at all. "
                "detect_dolby_vision believes a record on a stream it is not decoding only "
                "when this flag is clear, because a pure enhancement layer cannot stand "
                "alone and so belongs to the decoded stream. The failure runs the other way "
                "from the Matroska's: reading 1 here would make this record look like an "
                "unrelated title, the scan would skip it, and both files would silently drop "
                "to a plain HDR10 line while still playing perfectly."
            ),
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matroska", type=Path, default=MATROSKA)
    parser.add_argument("--mp4", type=Path, default=MP4)
    parser.add_argument(
        "--single-layer",
        type=Path,
        default=SINGLE_LAYER,
        help="A single-layer Dolby Vision file, used only to prove the declaration "
        "condition can still answer yes.",
    )
    parser.add_argument("--probe-source", type=Path, default=PROBE_SOURCE)
    parser.add_argument(
        "--json",
        type=Path,
        default=None,
        help="Write the raw measurement of every fixture here.",
    )
    arguments = parser.parse_args()

    binary = build_probe(arguments.probe_source, quiet=False)
    control = measure(binary, arguments.single_layer)
    unrelated = measure(
        binary, build_unrelated_track_fixture(arguments.mp4, arguments.single_layer)
    )
    matroska = measure(binary, arguments.matroska)
    mp4 = measure(binary, arguments.mp4)
    naming = [
        (measure(binary, path), level, cross, published, misread)
        for path, level, cross, published, misread in FIXTURES_WHERE_LEVEL_AND_CROSS_ID_DISAGREE
    ]
    print(f"measured through libavformat {matroska['libavformatVersion']}")

    if arguments.json is not None:
        arguments.json.parent.mkdir(parents=True, exist_ok=True)
        arguments.json.write_text(
            json.dumps(
                {
                    "control": control,
                    "unrelatedTrack": unrelated,
                    "matroska": matroska,
                    "mp4": mp4,
                    "naming": [entry[0] for entry in naming],
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    premises = Premises()
    check_control(premises, control)
    check_unrelated_track(premises, unrelated)
    check_naming(premises, naming)
    check_matroska(premises, matroska)
    check_mp4(premises, mp4)

    print(f"\n{premises.checked - len(premises.failures)} of {premises.checked} premises hold")
    for failure in premises.failures:
        print(f"FAIL   {failure}", file=sys.stderr)
    raise SystemExit(1 if premises.failures else 0)


if __name__ == "__main__":
    main()
