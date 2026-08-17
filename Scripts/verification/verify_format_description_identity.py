#!/usr/bin/env python3
"""Compare PlaybackCore format descriptions with FFmpeg-normalized declarations."""

from __future__ import annotations

import argparse
import concurrent.futures
from collections import Counter
import json
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
DEFAULT_MEDIA_ROOT = REPO.parent / "TestMedia"
PLAYBACK_CORE = REPO / "Packages" / "PlaybackCore"
DEFAULT_BASELINE = REPO / "Config" / "format_description_identity_baseline.json"
VIDEO_SUFFIXES = {
    ".av1", ".avi", ".h265", ".hevc", ".ivf", ".m2ts", ".m3u8",
    ".m4v", ".mkv", ".mov", ".mp4", ".mxf", ".ts", ".webm", ".y4m",
}
FIELDS = (
    "codec", "color_primaries", "transfer", "matrix", "full_range",
    "atoms", "mastering", "light_level",
)

PRIMARIES = {
    "bt709": "ITU_R_709_2",
    "bt2020": "ITU_R_2020",
    "smpte432": "P3_D65",
}
TRANSFERS = {
    "bt709": "ITU_R_709_2",
    "smpte2084": "SMPTE_ST_2084_PQ",
    "arib-std-b67": "ITU_R_2100_HLG",
}
MATRICES = {
    "bt709": "ITU_R_709_2",
    "bt2020nc": "ITU_R_2020",
    "bt2020c": "ITU_R_2020",
    "ipt-c2": "IPT_C2",
}
CODECS = {
    "h264": "avc1",
    "hevc": "hvc1",
    "av1": "av01",
    "mpeg4": "mp4v",
}
CONFIGURATION_ATOMS = {
    "h264": {"avcC"},
    "hevc": {"hvcC"},
    "av1": {"av1C"},
}


class UnknownDolbyVisionShape(ValueError):
    pass


@dataclass(frozen=True)
class Declaration:
    path: Path
    stream: dict
    dovi: dict | None

    @property
    def is_dolby_vision(self) -> bool:
        return self.dovi is not None

    def complete_dovi_fields(self) -> str:
        if self.dovi is None:
            return "dovi=absent"
        keys = (
            "dv_version_major", "dv_version_minor", "dv_profile", "dv_level",
            "rpu_present_flag", "el_present_flag", "bl_present_flag",
            "dv_bl_signal_compatibility_id", "dv_md_compression",
        )
        return " ".join(f"{key}={self.dovi.get(key)!r}" for key in keys)


@dataclass(frozen=True)
class Difference:
    field: str
    expected: str
    actual: str

    def describe(self) -> str:
        return f"{self.field}: expected={self.expected!r} actual={self.actual!r}"


@dataclass(frozen=True)
class Exemption:
    identifier: str
    declaration: dict[str, object]
    field: str
    expected: str
    actual: str
    count: int
    reason: str

    def matches(self, declaration: Declaration, difference: Difference) -> bool:
        return (
            difference.field == self.field
            and difference.expected == self.expected
            and difference.actual == self.actual
            and all(
                declaration.stream.get(key) == value
                for key, value in self.declaration.items()
            )
        )


@dataclass(frozen=True)
class CapabilityBoundary:
    identifier: str
    declaration: dict[str, object]
    error_contains: str
    count: int
    reason: str

    def matches(self, declaration: Declaration, error: str) -> bool:
        return self.error_contains in error and all(
            declaration.stream.get(key) == value
            for key, value in self.declaration.items()
        )


@dataclass(frozen=True)
class Baseline:
    exemptions: tuple[Exemption, ...]
    capability_boundaries: tuple[CapabilityBoundary, ...]

    @property
    def expected_counts(self) -> dict[str, int]:
        return {
            rule.identifier: rule.count
            for rule in (*self.exemptions, *self.capability_boundaries)
        }


@dataclass(frozen=True)
class Result:
    label: str
    is_dolby_vision: bool
    kind: str
    details: tuple[str, ...] = ()
    baseline_ids: tuple[str, ...] = ()


def require_rule_common(entry: object, category: str) -> tuple[
    str, dict[str, object], int, str
]:
    if not isinstance(entry, dict):
        raise ValueError(f"every {category} entry must be an object")
    identifier = entry.get("id")
    declaration = entry.get("declaration")
    count = entry.get("count")
    reason = entry.get("reason")
    if not isinstance(identifier, str) or not identifier:
        raise ValueError(f"every {category} entry needs a non-empty id")
    if not isinstance(declaration, dict) or not declaration:
        raise ValueError(f"{identifier} needs a non-empty declaration shape")
    if not all(isinstance(key, str) and key for key in declaration):
        raise ValueError(f"{identifier} has an invalid declaration key")
    if not isinstance(count, int) or isinstance(count, bool) or count <= 0:
        raise ValueError(f"{identifier} needs a positive count")
    if not isinstance(reason, str) or not reason:
        raise ValueError(f"{identifier} needs a non-empty reason")
    return identifier, declaration, count, reason


def load_baseline(path: Path) -> Baseline:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("version") != 1:
        raise ValueError("expected baseline version 1")
    raw_exemptions = payload.get("knownExemptions")
    raw_boundaries = payload.get("knownCapabilityBoundaries")
    if not isinstance(raw_exemptions, list):
        raise ValueError("knownExemptions must be a list")
    if not isinstance(raw_boundaries, list):
        raise ValueError("knownCapabilityBoundaries must be a list")

    exemptions: list[Exemption] = []
    boundaries: list[CapabilityBoundary] = []
    identifiers: set[str] = set()
    for entry in raw_exemptions:
        identifier, declaration, count, reason = require_rule_common(
            entry, "exemption"
        )
        field = entry.get("field")
        expected = entry.get("expected")
        actual = entry.get("actual")
        if field not in FIELDS:
            raise ValueError(f"{identifier} has an unknown field")
        if not isinstance(expected, str) or not isinstance(actual, str):
            raise ValueError(f"{identifier} needs expected and actual strings")
        exemptions.append(Exemption(
            identifier, declaration, field, expected, actual, count, reason
        ))
        identifiers.add(identifier)
    for entry in raw_boundaries:
        identifier, declaration, count, reason = require_rule_common(
            entry, "capability boundary"
        )
        error_contains = entry.get("errorContains")
        if not isinstance(error_contains, str) or not error_contains:
            raise ValueError(f"{identifier} needs a non-empty errorContains")
        boundaries.append(CapabilityBoundary(
            identifier, declaration, error_contains, count, reason
        ))
        if identifier in identifiers:
            raise ValueError(f"baseline id {identifier!r} is duplicated")
        identifiers.add(identifier)
    if len(identifiers) != len(exemptions) + len(boundaries):
        raise ValueError("knownExemptions contains duplicate ids")
    return Baseline(tuple(exemptions), tuple(boundaries))


def run(command: list[str], timeout: int = 300) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def build_probe() -> Path:
    built = subprocess.run(
        ["swift", "build", "--package-path", str(PLAYBACK_CORE),
         "--product", "PlaybackCoreRemoteMediaProbe"],
        cwd=REPO,
        check=False,
    )
    if built.returncode != 0:
        raise RuntimeError("PlaybackCoreRemoteMediaProbe build failed")
    bin_path = subprocess.run(
        ["swift", "build", "--package-path", str(PLAYBACK_CORE),
         "--show-bin-path"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    probe = Path(bin_path) / "PlaybackCoreRemoteMediaProbe"
    if not probe.is_file():
        raise RuntimeError(f"probe binary is missing: {probe}")
    return probe


def ffmpeg_declaration(path: Path, timeout: int) -> Declaration | None:
    completed = run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_streams", "-of", "json", str(path),
    ], timeout)
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "ffprobe failed")
    streams = json.loads(completed.stdout or "{}").get("streams") or []
    if not streams:
        return None
    stream = streams[0]
    dovi = next(
        (
            item for item in stream.get("side_data_list") or []
            if "dv_profile" in item
        ),
        None,
    )
    return Declaration(path=path, stream=stream, dovi=dovi)


def dovi_shape(declaration: Declaration) -> str:
    dovi = declaration.dovi
    if dovi is None:
        return "absent"
    codec = declaration.stream.get("codec_name")
    if codec is None and dovi.get("dv_profile") == 10:
        codec = "av1"
    profile = dovi.get("dv_profile")
    compatibility = dovi.get("dv_bl_signal_compatibility_id")
    rpu = dovi.get("rpu_present_flag")
    enhancement = dovi.get("el_present_flag")
    base = dovi.get("bl_present_flag")
    if rpu != 1 or base != 1:
        raise UnknownDolbyVisionShape(declaration.complete_dovi_fields())
    if codec == "hevc" and enhancement == 1:
        if profile == 7 and compatibility != 0:
            return "hevc-dual-layer"
        raise UnknownDolbyVisionShape(declaration.complete_dovi_fields())
    if codec == "hevc" and enhancement == 0:
        return "hevc-native" if compatibility == 0 else "hevc-compatible"
    if codec == "av1" and profile == 10 and enhancement == 0:
        return "av1"
    raise UnknownDolbyVisionShape(
        f"codec={codec!r} {declaration.complete_dovi_fields()}"
    )


def expected_facts(declaration: Declaration) -> dict[str, str]:
    stream = declaration.stream
    codec_name = stream.get("codec_name")
    shape = dovi_shape(declaration)
    if codec_name is None and shape == "av1":
        codec_name = "av1"
    codec = CODECS.get(codec_name, stream.get("codec_tag_string") or "none")
    atoms = set(CONFIGURATION_ATOMS.get(codec_name, set()))

    if shape == "hevc-native":
        codec = "dvh1"
        atoms.add("dvcC")
    elif shape == "hevc-compatible":
        atoms.add("dvvC")
    elif shape == "av1":
        atoms.add("dvvC")

    primaries = PRIMARIES.get(stream.get("color_primaries"), "none")
    transfer = TRANSFERS.get(stream.get("color_transfer"), "none")
    matrix = MATRICES.get(stream.get("color_space"), "none")
    color_range = stream.get("color_range")
    full_range = "1" if color_range == "pc" else "0" if color_range == "tv" else "none"

    dovi = declaration.dovi
    if dovi is not None:
        profile = dovi["dv_profile"]
        compatibility = dovi["dv_bl_signal_compatibility_id"]
        if profile == 5:
            primaries = "ITU_R_2020"
            transfer = "SMPTE_ST_2084_PQ"
            matrix = "none"
            full_range = "1"
        else:
            if primaries == "none" and compatibility in (0, 1, 4):
                primaries = "ITU_R_2020"
            if transfer == "none" and compatibility in (0, 1):
                transfer = "SMPTE_ST_2084_PQ"
            if transfer == "none" and compatibility == 4:
                transfer = "ITU_R_2100_HLG"
            if matrix == "none" and compatibility in (1, 4):
                matrix = "ITU_R_2020"
            if full_range == "none" and compatibility == 0:
                full_range = "1"
            if full_range == "none" and compatibility in (1, 4):
                full_range = "0"

    side_types = {
        item.get("side_data_type") for item in stream.get("side_data_list") or []
    }
    return {
        "codec": codec,
        "color_primaries": primaries,
        "transfer": transfer,
        "matrix": matrix,
        "full_range": full_range,
        "atoms": "+".join(sorted(atoms)) if atoms else "none",
        "mastering": "1" if "Mastering display metadata" in side_types else "0",
        "light_level": "1" if "Content light level metadata" in side_types else "0",
    }


def constructed_facts(probe: Path, path: Path, timeout: int) -> dict[str, str]:
    completed = run(
        [str(probe), "--stage", "format", "--url", str(path)],
        timeout,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "probe failed"
        raise RuntimeError(detail)
    line = completed.stdout.strip().splitlines()[-1]
    values = {}
    for token in shlex.split(line):
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        values[key] = value
    missing = [field for field in FIELDS if field not in values]
    if missing:
        raise RuntimeError(f"probe omitted fields {missing}: {line}")
    return values


def verify_one(
    probe: Path,
    root: Path,
    path: Path,
    timeout: int,
    baseline: Baseline,
) -> Result:
    declaration: Declaration | None = None
    label = str(path.relative_to(root)) if path.is_relative_to(root) else str(path)
    try:
        declaration = ffmpeg_declaration(path, timeout)
        if declaration is None:
            return Result(label, False, "no-video")
        expected = expected_facts(declaration)
        actual = constructed_facts(probe, path, timeout)
        differences = tuple(
            Difference(field, expected[field], actual[field])
            for field in FIELDS
            if expected[field] != actual[field]
        )
        if not differences:
            return Result(label, declaration.is_dolby_vision, "pass")

        details: list[str] = []
        baseline_ids: list[str] = []
        unresolved = False
        for difference in differences:
            matches = [
                rule for rule in baseline.exemptions
                if rule.matches(declaration, difference)
            ]
            if len(matches) == 1:
                rule = matches[0]
                details.append(
                    f"{difference.describe()} exemption={rule.identifier!r} "
                    f"reason={rule.reason}"
                )
                baseline_ids.append(rule.identifier)
            elif matches:
                unresolved = True
                details.append(
                    f"{difference.describe()} matches multiple exemptions: "
                    + ", ".join(rule.identifier for rule in matches)
                )
            else:
                unresolved = True
                details.append(difference.describe())
        return Result(
            label,
            declaration.is_dolby_vision,
            "mismatch" if unresolved else "exemption",
            tuple(details),
            tuple(baseline_ids),
        )
    except UnknownDolbyVisionShape as error:
        return Result(label, True, "unknown-dovi", (str(error),))
    except Exception as error:
        is_dolby_vision = declaration.is_dolby_vision if declaration else False
        if declaration:
            matches = [
                rule for rule in baseline.capability_boundaries
                if rule.matches(declaration, str(error))
            ]
            if len(matches) == 1:
                rule = matches[0]
                return Result(
                    label,
                    is_dolby_vision,
                    "capability-boundary",
                    (f"reason={rule.reason}", f"error={error}"),
                    (rule.identifier,),
                )
            if matches:
                return Result(
                    label,
                    is_dolby_vision,
                    "probe-failed",
                    (
                        f"matches multiple capability boundaries: "
                        + ", ".join(rule.identifier for rule in matches),
                        str(error),
                    ),
                )
        return Result(label, is_dolby_vision, "probe-failed", (str(error),))


def create_profile_five_remux(media_root: Path, output: Path, timeout: int) -> None:
    source = media_root / (
        "Samples/DynamicRange/DolbyVision/HD/"
        "Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
    )
    completed = run([
        "ffmpeg", "-y", "-v", "error", "-i", str(source),
        "-map", "0:v:0", "-c", "copy", "-tag:v", "hvc1", str(output),
    ], timeout)
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "Profile 5 remux failed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--media-root", type=Path, default=DEFAULT_MEDIA_ROOT)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument(
        "--baseline",
        type=Path,
        default=DEFAULT_BASELINE,
        help="known declaration-shape exemptions and capability boundaries",
    )
    parser.add_argument(
        "--skip-profile-five-remux",
        action="store_true",
        help="Do not add the generated MP4-to-Matroska Profile 5 invariance fixture.",
    )
    args = parser.parse_args()
    media_root = args.media_root.resolve()
    if not media_root.is_dir():
        parser.error(f"media root does not exist: {media_root}")
    try:
        baseline = load_baseline(args.baseline)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"FAIL baseline: {error}", file=sys.stderr)
        return 1
    probe = build_probe()
    files = sorted(
        path for path in media_root.rglob("*")
        if path.is_file() and path.suffix.lower() in VIDEO_SUFFIXES
    )

    with tempfile.TemporaryDirectory(prefix="enchron-profile5-remux-") as temp:
        if not args.skip_profile_five_remux:
            remux = Path(temp) / "profile5-hvc1.mkv"
            try:
                create_profile_five_remux(media_root, remux, args.timeout)
                files.append(remux)
            except Exception as error:
                print(f"FAIL <generated-profile5-remux>: {error}")
                return 1

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            results = list(pool.map(
                lambda path: verify_one(
                    probe, media_root, path, args.timeout, baseline
                ),
                files,
            ))

    counts: dict[str, int] = {}
    baseline_counts: Counter[str] = Counter()
    for result in results:
        counts[result.kind] = counts.get(result.kind, 0) + 1
        baseline_counts.update(result.baseline_ids)
        if result.kind == "pass":
            if result.is_dolby_vision:
                print(f"PASS Dolby Vision: {result.label}")
            continue
        if result.kind == "no-video":
            print(f"PASS no video declaration: {result.label}")
            continue
        if result.kind == "exemption":
            print(f"EXEMPT declared shape: {result.label}")
        elif result.kind == "capability-boundary":
            print(f"BOUNDARY known capability: {result.label}")
        else:
            print(f"FAIL {result.kind}: {result.label}")
        for detail in result.details:
            print(f"  {detail}")

    unclassified = [
        result for result in results
        if result.kind not in (
            "pass", "no-video", "exemption", "capability-boundary"
        )
    ]
    dovi_failures = [result for result in unclassified if result.is_dolby_vision]
    dovi_passes = sum(
        result.is_dolby_vision and result.kind == "pass" for result in results
    )
    baseline_drift: list[str] = []
    for identifier, expected_count in baseline.expected_counts.items():
        actual_count = baseline_counts[identifier]
        if actual_count != expected_count:
            baseline_drift.append(
                f"{identifier}: expected {expected_count}, observed {actual_count}"
            )
    unexpected_ids = sorted(set(baseline_counts) - set(baseline.expected_counts))
    baseline_drift.extend(f"unexpected baseline id: {item}" for item in unexpected_ids)
    if baseline_drift:
        print("FAIL baseline drift:")
        for detail in baseline_drift:
            print(f"  {detail}")
    print(
        "SUMMARY "
        f"files={len(results)} dolby_vision_pass={dovi_passes} "
        f"dolby_vision_fail={len(dovi_failures)} "
        f"unclassified={len(unclassified)} baseline_drift={len(baseline_drift)} "
        + " ".join(f"{key}={value}" for key, value in sorted(counts.items()))
    )
    return 1 if unclassified or baseline_drift else 0


if __name__ == "__main__":
    sys.exit(main())
