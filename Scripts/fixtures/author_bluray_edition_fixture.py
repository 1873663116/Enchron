#!/usr/bin/env python3
"""Author and verify the controlled Sintel Blu-ray edition fixture.

The fixture reuses the official Sintel transport stream without modifying it.
Three MPLS playlists select literal ranges from clip 00000: two overlapping
edits for version grouping and one short additional item. The output is not an
officially released edition of the film.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable


SCHEMA = "enchron.bluray.edition-fixture/v1"
DISC_NAME = "Sintel – Edition tests"
SOURCE_MD5 = "edef70074bc275190a016f9eaeb478dd"
SOURCE_ROOT = Path(
    "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/Samples/DiscImages/"
    "Sintel/Sintel-Bluray"
)
OUTPUT_ROOT = Path(
    "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/Samples/DiscImages/"
    "Sintel-Editions"
)
PLAYLISTS: dict[int, dict[str, object]] = {
    0: {
        "role": "version",
        "fixtureLabel": "Reference edit",
        "segmentsSeconds": [(600, 620), (640, 660), (680, 700)],
        "durationSeconds": 60,
    },
    1: {
        "role": "version",
        "fixtureLabel": "Alternate edit",
        "segmentsSeconds": [(600, 620), (630, 655), (680, 700), (720, 730)],
        "durationSeconds": 75,
    },
    2: {
        "role": "additional",
        "fixtureLabel": "Additional excerpt",
        "segmentsSeconds": [(760, 770)],
        "durationSeconds": 10,
    },
}


def be16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "big")


def be32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "big")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_mpls_bytes(data: bytes) -> dict[str, object]:
    if len(data) < 48 or data[:4] != b"MPLS":
        raise ValueError("invalid MPLS header")
    playlist_start = be32(data, 8)
    mark_start = be32(data, 12)
    if playlist_start < 40 or playlist_start + 10 > len(data):
        raise ValueError("invalid MPLS playlist offset")
    playlist_end = playlist_start + 4 + be32(data, playlist_start)
    if playlist_end > len(data) or mark_start != playlist_end:
        raise ValueError("invalid MPLS playlist section")
    item_count = be16(data, playlist_start + 6)
    position = playlist_start + 10
    clips: list[dict[str, object]] = []
    timeline90k = 0
    item_ranges45k: list[tuple[int, int]] = []
    for _ in range(item_count):
        if position + 2 > playlist_end:
            raise ValueError("truncated MPLS PlayItem")
        item_length = be16(data, position)
        item = position + 2
        if item_length < 20 or item + item_length > playlist_end:
            raise ValueError("invalid MPLS PlayItem length")
        clip_id = data[item : item + 5].decode("ascii")
        if data[item + 5 : item + 9] != b"M2TS" or not clip_id.isdecimal():
            raise ValueError("invalid MPLS clip reference")
        in45k = be32(data, item + 12)
        out45k = be32(data, item + 16)
        if out45k <= in45k:
            raise ValueError("invalid MPLS PlayItem time range")
        clips.append(
            {
                "clipID": clip_id,
                "startTime90k": timeline90k,
                "inTime90k": in45k * 2,
                "outTime90k": out45k * 2,
            }
        )
        item_ranges45k.append((in45k, out45k))
        timeline90k += (out45k - in45k) * 2
        position = item + item_length
    if position != playlist_end or mark_start + 6 > len(data):
        raise ValueError("invalid MPLS section boundary")
    mark_end = mark_start + 4 + be32(data, mark_start)
    mark_count = be16(data, mark_start + 4)
    if mark_end > len(data) or mark_start + 6 + mark_count * 14 > mark_end:
        raise ValueError("invalid MPLS mark section")
    for index in range(mark_count):
        mark = mark_start + 6 + index * 14
        if data[mark + 1] != 1:
            raise ValueError("fixture chapter mark is not an entry mark")
        item_ref = be16(data, mark + 2)
        timestamp = be32(data, mark + 4)
        if item_ref >= item_count:
            raise ValueError("fixture chapter references an unavailable PlayItem")
        item_in, item_out = item_ranges45k[item_ref]
        if not item_in <= timestamp < item_out:
            raise ValueError("fixture chapter lies outside its PlayItem")
    return {
        "duration90k": timeline90k,
        "chapterCount": mark_count,
        "clips": clips,
    }


def _single_playitem_template(data: bytes) -> tuple[bytes, bytes, int, int]:
    parsed = parse_mpls_bytes(data)
    clips = parsed["clips"]
    if len(clips) != 1 or clips[0]["clipID"] != "00000":
        raise ValueError("source MPLS must contain only physical clip 00000")
    playlist_start = be32(data, 8)
    item_position = playlist_start + 10
    item_length = be16(data, item_position)
    item = data[item_position + 2 : item_position + 2 + item_length]
    source_in = be32(item, 12)
    source_out = be32(item, 16)
    return data[:playlist_start], item, source_in, source_out


def author_playlist(template: bytes, segments_seconds: Iterable[tuple[int, int]]) -> bytes:
    prefix, source_item, source_in45k, source_out45k = _single_playitem_template(template)
    segments = list(segments_seconds)
    if not segments:
        raise ValueError("an authored playlist requires at least one segment")
    items = bytearray()
    marks = bytearray()
    previous_start = -1
    for index, (start_seconds, end_seconds) in enumerate(segments):
        if not isinstance(start_seconds, int) or not isinstance(end_seconds, int):
            raise ValueError("fixture segment boundaries must be whole seconds")
        start45k = start_seconds * 45_000
        end45k = end_seconds * 45_000
        if start45k < source_in45k or end45k > source_out45k or end45k <= start45k:
            raise ValueError("fixture segment lies outside the source PlayItem")
        if start45k <= previous_start:
            raise ValueError("fixture segments must remain in source order")
        previous_start = start45k
        item = bytearray(source_item)
        item[12:16] = struct.pack(">I", start45k)
        item[16:20] = struct.pack(">I", end45k)
        items += struct.pack(">H", len(item)) + item
        marks += b"\0\x01" + struct.pack(">HIHI", index, start45k, 0xFFFF, 0)

    playlist_payload = struct.pack(">HHH", 0, len(segments), 0) + items
    playlist_section = struct.pack(">I", len(playlist_payload)) + playlist_payload
    mark_payload = struct.pack(">H", len(segments)) + marks
    mark_section = struct.pack(">I", len(mark_payload)) + mark_payload
    result_prefix = bytearray(prefix)
    result_prefix[12:16] = struct.pack(">I", len(prefix) + len(playlist_section))
    result_prefix[16:20] = b"\0\0\0\0"
    authored = bytes(result_prefix) + playlist_section + mark_section
    parse_mpls_bytes(authored)
    return authored


def ordered_overlap_seconds(
    left: Iterable[tuple[int, int]], right: Iterable[tuple[int, int]]
) -> int:
    left_ranges = list(left)
    right_ranges = list(right)
    left_index = right_index = overlap = 0
    while left_index < len(left_ranges) and right_index < len(right_ranges):
        left_start, left_end = left_ranges[left_index]
        right_start, right_end = right_ranges[right_index]
        overlap += max(0, min(left_end, right_end) - max(left_start, right_start))
        if left_end <= right_end:
            left_index += 1
        else:
            right_index += 1
    return overlap


def retarget_movie_object(data: bytes, removed_playlist: int, replacement: int) -> tuple[bytes, int]:
    if len(data) < 50 or data[:4] != b"MOBJ":
        raise ValueError("invalid MovieObject header")
    payload_length = be32(data, 40)
    payload_end = 44 + payload_length
    if payload_end > len(data):
        raise ValueError("truncated MovieObject payload")
    object_count = be16(data, 48)
    position = 50
    result = bytearray(data)
    changed = 0
    for _ in range(object_count):
        if position + 4 > payload_end:
            raise ValueError("truncated MovieObject object")
        command_count = be16(data, position + 2)
        position += 4
        if position + command_count * 12 > payload_end:
            raise ValueError("truncated MovieObject commands")
        for _ in range(command_count):
            instruction = be32(data, position)
            operand_count = (instruction >> 29) & 0x7
            group = (instruction >> 27) & 0x3
            subgroup = (instruction >> 24) & 0x7
            immediate_first = (instruction >> 23) & 0x1
            branch_option = (instruction >> 16) & 0xF
            destination = be32(data, position + 4)
            if (
                operand_count >= 1
                and group == 0
                and subgroup == 2
                and immediate_first == 1
                and branch_option in (0, 1, 2)
                and destination == removed_playlist
            ):
                result[position + 4 : position + 8] = struct.pack(">I", replacement)
                changed += 1
            position += 12
    return bytes(result), changed


def validate_replaceable_output(output: Path) -> None:
    if not output.exists():
        return
    manifest = output / "SOURCE.json"
    try:
        schema = json.loads(manifest.read_text(encoding="utf-8"))["schema"]
    except (OSError, KeyError, TypeError, ValueError) as error:
        raise ValueError(f"existing output is not an authored Sintel editions fixture: {output}") from error
    if schema != SCHEMA:
        raise ValueError(f"existing output is not an authored Sintel editions fixture: {output}")


def build_manifest(
    authored_files: dict[str, bytes], control_files_sha256: str, iso_sha256: str
) -> dict[str, object]:
    return {
        "schema": SCHEMA,
        "title": DISC_NAME,
        "purpose": "Controlled Blu-ray fixture for edition grouping and additional-content tests",
        "officialReleaseVersions": False,
        "disclaimer": (
            "The authored playlists are test-only edits. They are not official Sintel release versions "
            "and must not be labeled as director, theatrical, extended, or other named editions."
        ),
        "source": {
            "title": "Sintel",
            "publisher": "Blender Foundation",
            "sourcePage": "https://durian.blender.org/news/sintel-blu-ray-iso-download/",
            "publisherMD5": SOURCE_MD5,
            "license": "Creative Commons Attribution 3.0",
            "licensePage": "https://durian.blender.org/sharing/",
            "attribution": "© copyright Blender Foundation | www.sintel.org",
            "physicalClip": "00000.m2ts",
            "sourcePlayItemSeconds": [600, 1488],
        },
        "playlists": [
            {
                "playlistID": playlist_id,
                "role": specification["role"],
                "fixtureLabel": specification["fixtureLabel"],
                "segmentsSeconds": [list(segment) for segment in specification["segmentsSeconds"]],
                "durationSeconds": specification["durationSeconds"],
            }
            for playlist_id, specification in PLAYLISTS.items()
        ],
        "relationship": {
            "versionPlaylistIDs": [0, 1],
            "orderedSharedSeconds": ordered_overlap_seconds(
                PLAYLISTS[0]["segmentsSeconds"], PLAYLISTS[1]["segmentsSeconds"]
            ),
            "additionalPlaylistIDs": [2],
        },
        "derived": {
            "controlFilesSHA256": control_files_sha256,
            "isoSHA256": iso_sha256,
            "files": {name: sha256_bytes(data) for name, data in sorted(authored_files.items())},
        },
        "reproduction": {
            "command": "python3 Scripts/fixtures/author_bluray_edition_fixture.py",
            "verification": (
                "python3 Scripts/fixtures/author_bluray_edition_fixture.py --verify-only "
                "--probe Packages/PlaybackCore/.build/out/Products/Debug/BluRayDiscProbe"
            ),
        },
    }


def metadata_xml() -> bytes:
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<disclib xmlns="urn:BDA:bdmv;disclib" xmlns:di="urn:BDA:bdmv;discinfo">\n'
        f"  <di:discinfo><di:title><di:name>{DISC_NAME}</di:name></di:title></di:discinfo>\n"
        "</disclib>\n"
    ).encode("utf-8")


def _link_or_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def _disc_tree_hash(authored_files: dict[str, bytes]) -> str:
    digest = hashlib.sha256()
    for name, data in sorted(authored_files.items()):
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(data).digest())
    return digest.hexdigest()


def _validate_source(source: Path) -> bytes:
    playlist = source / "BDMV/PLAYLIST/00000.mpls"
    stream = source / "BDMV/STREAM/00000.m2ts"
    clip_info = source / "BDMV/CLIPINF/00000.clpi"
    movie_object = source / "BDMV/MovieObject.bdmv"
    index = source / "BDMV/index.bdmv"
    for path in (playlist, stream, clip_info, movie_object, index):
        if not path.is_file():
            raise ValueError(f"official Sintel source is missing {path.relative_to(source)}")
    parsed = parse_mpls_bytes(playlist.read_bytes())
    expected = [{
        "clipID": "00000",
        "startTime90k": 0,
        "inTime90k": 600 * 90_000,
        "outTime90k": 1_488 * 90_000,
    }]
    if parsed["clips"] != expected:
        raise ValueError("official Sintel source playlist no longer has the expected clip range")
    return playlist.read_bytes()


def _matches_expected_fixture(source: Path, output: Path) -> bool:
    disc = output / "Sintel-Editions"
    try:
        template = _validate_source(source)
        for playlist_id, specification in PLAYLISTS.items():
            expected = author_playlist(template, specification["segmentsSeconds"])
            name = f"{playlist_id:05d}.mpls"
            if (disc / f"BDMV/PLAYLIST/{name}").read_bytes() != expected:
                return False
            if (disc / f"BDMV/BACKUP/PLAYLIST/{name}").read_bytes() != expected:
                return False
        expected_movie_object, changed = retarget_movie_object(
            (source / "BDMV/MovieObject.bdmv").read_bytes(), 1900, 0
        )
        if changed != 1:
            return False
        for relative in ("BDMV/MovieObject.bdmv", "BDMV/BACKUP/MovieObject.bdmv"):
            if (disc / relative).read_bytes() != expected_movie_object:
                return False
        expected_index = (source / "BDMV/index.bdmv").read_bytes()
        for relative in ("BDMV/index.bdmv", "BDMV/BACKUP/index.bdmv"):
            if (disc / relative).read_bytes() != expected_index:
                return False
        if (disc / "BDMV/META/DL/bdmt_eng.xml").read_bytes() != metadata_xml():
            return False
        return (
            (disc / "BDMV/STREAM/00000.m2ts").stat().st_size
            == (source / "BDMV/STREAM/00000.m2ts").stat().st_size
            and (disc / "BDMV/CLIPINF/00000.clpi").read_bytes()
            == (source / "BDMV/CLIPINF/00000.clpi").read_bytes()
        )
    except (OSError, ValueError):
        return False


def _author_disc(source: Path, disc: Path) -> dict[str, bytes]:
    template = _validate_source(source)
    authored: dict[str, bytes] = {}
    for playlist_id, specification in PLAYLISTS.items():
        name = f"{playlist_id:05d}.mpls"
        playlist = author_playlist(template, specification["segmentsSeconds"])
        authored[f"BDMV/PLAYLIST/{name}"] = playlist
        for relative in (f"BDMV/PLAYLIST/{name}", f"BDMV/BACKUP/PLAYLIST/{name}"):
            destination = disc / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(playlist)

    original_movie_object = (source / "BDMV/MovieObject.bdmv").read_bytes()
    movie_object, changed = retarget_movie_object(original_movie_object, 1900, 0)
    if changed != 1:
        raise ValueError(f"expected one immediate MovieObject reference to playlist 1900, found {changed}")
    authored["BDMV/MovieObject.bdmv"] = movie_object
    for relative in ("BDMV/MovieObject.bdmv", "BDMV/BACKUP/MovieObject.bdmv"):
        destination = disc / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(movie_object)

    index = (source / "BDMV/index.bdmv").read_bytes()
    authored["BDMV/index.bdmv"] = index
    for relative in ("BDMV/index.bdmv", "BDMV/BACKUP/index.bdmv"):
        destination = disc / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(index)

    metadata = metadata_xml()
    authored["BDMV/META/DL/bdmt_eng.xml"] = metadata
    metadata_path = disc / "BDMV/META/DL/bdmt_eng.xml"
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.write_bytes(metadata)

    _link_or_copy(source / "BDMV/STREAM/00000.m2ts", disc / "BDMV/STREAM/00000.m2ts")
    for relative in ("BDMV/CLIPINF/00000.clpi", "BDMV/BACKUP/CLIPINF/00000.clpi"):
        _link_or_copy(source / "BDMV/CLIPINF/00000.clpi", disc / relative)
    for relative in ("BDMV/AUXDATA", "BDMV/BDJO", "BDMV/JAR", "CERTIFICATE/BACKUP"):
        (disc / relative).mkdir(parents=True, exist_ok=True)
    return authored


def _create_iso(disc: Path, image: Path) -> None:
    command = [
        "hdiutil", "makehybrid", "-o", str(image), str(disc), "-udf",
        "-udf-version", "1.50", "-udf-volume-name", "SINTEL_EDITIONS",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode:
        raise RuntimeError(f"hdiutil makehybrid failed: {completed.stderr[-2000:]}")
    if not image.is_file():
        raise RuntimeError("hdiutil did not create the requested ISO")


def _probe(binary: Path, source: Path) -> dict[str, object]:
    completed = subprocess.run(
        [str(binary), "--json", str(source)], capture_output=True, text=True, check=False
    )
    if completed.returncode:
        raise RuntimeError(f"BluRayDiscProbe failed for {source}: {completed.stderr[-2000:]}")
    return json.loads(completed.stdout)


def verify_fixture(output: Path, probe: Path | None = None) -> dict[str, object]:
    manifest = json.loads((output / "SOURCE.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != SCHEMA:
        raise ValueError("fixture manifest schema is invalid")
    disc = output / "Sintel-Editions"
    image = output / "Sintel-Editions.iso"
    expected_ids = list(PLAYLISTS)
    parsed: dict[int, dict[str, object]] = {}
    for playlist_id, specification in PLAYLISTS.items():
        playlist = disc / f"BDMV/PLAYLIST/{playlist_id:05d}.mpls"
        value = parse_mpls_bytes(playlist.read_bytes())
        if value["duration90k"] != specification["durationSeconds"] * 90_000:
            raise ValueError(f"playlist {playlist_id} duration does not match its contract")
        if value["chapterCount"] != len(specification["segmentsSeconds"]):
            raise ValueError(f"playlist {playlist_id} chapter count does not match its PlayItems")
        expected_clips = []
        timeline90k = 0
        for start, end in specification["segmentsSeconds"]:
            expected_clips.append({
                "clipID": "00000",
                "startTime90k": timeline90k,
                "inTime90k": start * 90_000,
                "outTime90k": end * 90_000,
            })
            timeline90k += (end - start) * 90_000
        if value["clips"] != expected_clips:
            raise ValueError(f"playlist {playlist_id} clip ranges do not match its contract")
        parsed[playlist_id] = value
    actual_ids = sorted(int(path.stem) for path in (disc / "BDMV/PLAYLIST").glob("*.mpls"))
    if actual_ids != expected_ids:
        raise ValueError(f"fixture playlist IDs: expected {expected_ids}, got {actual_ids}")
    observed_control_files: dict[str, bytes] = {}
    for relative, expected_hash in manifest["derived"]["files"].items():
        data = (disc / relative).read_bytes()
        if sha256_bytes(data) != expected_hash:
            raise ValueError(f"fixture control file hash differs: {relative}")
        observed_control_files[relative] = data
    if _disc_tree_hash(observed_control_files) != manifest["derived"]["controlFilesSHA256"]:
        raise ValueError("fixture control-file aggregate hash differs")
    for playlist_id in PLAYLISTS:
        name = f"{playlist_id:05d}.mpls"
        if (disc / f"BDMV/PLAYLIST/{name}").read_bytes() != (
            disc / f"BDMV/BACKUP/PLAYLIST/{name}"
        ).read_bytes():
            raise ValueError(f"fixture backup playlist differs: {name}")
    for relative in ("MovieObject.bdmv", "index.bdmv"):
        if (disc / f"BDMV/{relative}").read_bytes() != (
            disc / f"BDMV/BACKUP/{relative}"
        ).read_bytes():
            raise ValueError(f"fixture backup differs: {relative}")
    _, removed_references = retarget_movie_object(
        (disc / "BDMV/MovieObject.bdmv").read_bytes(), 1900, 0
    )
    if removed_references:
        raise ValueError("fixture MovieObject still references removed playlist 1900")
    if (disc / "BDMV/META/DL/bdmt_eng.xml").read_bytes() != metadata_xml():
        raise ValueError("fixture disc metadata name differs")
    if sha256_file(image) != manifest["derived"]["isoSHA256"]:
        raise ValueError("fixture ISO hash does not match SOURCE.json")
    result: dict[str, object] = {
        "schema": SCHEMA,
        "verdict": "passed",
        "playlistDurations90k": {
            str(identifier): value["duration90k"] for identifier, value in parsed.items()
        },
        "isoSHA256": manifest["derived"]["isoSHA256"],
    }
    if probe:
        directory_catalog = _probe(probe, disc)
        iso_catalog = _probe(probe, image)
        if directory_catalog != iso_catalog:
            raise ValueError("directory and ISO catalogs differ")
        titles = directory_catalog.get("titles", [])
        if [title["playlistID"] for title in titles] != expected_ids:
            raise ValueError("product catalog does not expose exactly playlists 0, 1, and 2")
        for title in titles:
            playlist_id = title["playlistID"]
            expected = parsed[playlist_id]
            if title["duration90k"] != expected["duration90k"]:
                raise ValueError(f"product duration differs for playlist {playlist_id}")
            observed = [
                {key: clip[key] for key in ("clipID", "startTime90k", "inTime90k", "outTime90k")}
                for clip in title["clips"]
            ]
            if observed != expected["clips"]:
                raise ValueError(f"product PlayItems differ for playlist {playlist_id}")
            if not title["clips"] or not title["clips"][0]["streams"]:
                raise ValueError(f"product stream facts are missing for playlist {playlist_id}")
        result["productCatalog"] = directory_catalog
    return result


def author(source: Path, output: Path) -> dict[str, object]:
    validate_replaceable_output(output)
    if output.exists() and _matches_expected_fixture(source, output):
        return verify_fixture(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".sintel-editions-", dir=output.parent))
    replacement = temporary / output.name
    replacement.mkdir()
    try:
        disc = replacement / "Sintel-Editions"
        authored = _author_disc(source, disc)
        image = replacement / "Sintel-Editions.iso"
        _create_iso(disc, image)
        manifest = build_manifest(authored, _disc_tree_hash(authored), sha256_file(image))
        (replacement / "SOURCE.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        backup = temporary / "previous"
        if output.exists():
            output.rename(backup)
        try:
            replacement.rename(output)
        except OSError:
            if backup.exists() and not output.exists():
                backup.rename(output)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    finally:
        shutil.rmtree(temporary, ignore_errors=True)
    return verify_fixture(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE_ROOT)
    parser.add_argument("--output", type=Path, default=OUTPUT_ROOT)
    parser.add_argument("--probe", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    arguments = parser.parse_args()
    try:
        report = (
            verify_fixture(arguments.output, arguments.probe)
            if arguments.verify_only
            else author(arguments.source, arguments.output)
        )
        if arguments.probe and not arguments.verify_only:
            report = verify_fixture(arguments.output, arguments.probe)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(json.dumps({"schema": SCHEMA, "verdict": "failed", "error": str(error)}))
        return 1
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
