#!/usr/bin/env python3
"""Independent Blu-ray corpus parsing and catalog comparison primitives.

The parser reads authored MPLS bytes and never obtains expected timelines from
libbluray. The host-side probe/build runner lives in Scripts/build.
"""

from __future__ import annotations

import hashlib
from pathlib import Path


DEFAULT_CORPUS = Path(
    "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/Samples/DiscImages"
)
GOLDEN = {
    "AVS-HD-709": {
        "folder": "HDMV-2d",
        "iso_sha256": "7f1de39604ce3894ff085fcd145d035786d265435944e2fd4333e92c99ac59db",
        "playlist_count": 110,
        "stream_count": 253,
        "mpls_sha256": {
            2: "0914f916dc075196bee2836960aa704dea7928c6afd4a418a29c8e86cb5d8f8c",
            43: "d9d6fe75b2465f7c5bc59c513c12b77a7c9a7c2d4f00a23b1687697edd82b28c",
            99: "f76d336882f4d11ccbcb1d2f6522178012a3eacc1d21eef062abbe324faa2b51",
        },
        "duration90k": {2: 324_324_000, 43: 135_003_620, 99: 2_702_700},
        "clip_ids": {
            43: [f"{number:05d}" for number in range(86, 91)],
            99: [f"{number:05d}" for number in range(202, 232)],
        },
    },
    "DolbyVision-Profile7-FEL": {
        "folder": "FEL_test_for_AVS",
        "iso_sha256": "b3e788d13eb5933fddc80f903eb013cbc58a27f2b28a87bc63647a492a642ca9",
        "playlist_count": 1,
        "stream_count": 1,
        "mpls_sha256": {
            0: "344f47eba8ee5a6f3e717f823e7c034065b9ede7889aee60d69b583bc1ae128e",
        },
        "duration90k": {0: 10_792_030},
        "clip_ids": {0: ["00000"]},
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def be16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "big")


def be32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "big")


def parse_mpls(path: Path) -> dict:
    """Read the MPLS PlayList section: fixed header and PlayItem IN/OUT ticks.

    MPLS stores clip IN/OUT in 45 kHz units. Product timestamps use 90 kHz.
    The parser deliberately does not use libbluray, CLPI, or product types.
    """
    data = path.read_bytes()
    if len(data) < 48 or data[:4] != b"MPLS":
        raise ValueError(f"Invalid MPLS header: {path}")
    start = be32(data, 8)
    if start + 10 > len(data):
        raise ValueError(f"Truncated PlayList section: {path}")
    section_length = be32(data, start)
    section_end = start + 4 + section_length
    if section_end > len(data):
        raise ValueError(f"PlayList section exceeds file: {path}")
    item_count = be16(data, start + 6)
    position = start + 10
    clips = []
    timeline90k = 0
    for _ in range(item_count):
        if position + 2 > section_end:
            raise ValueError(f"Truncated PlayItem: {path}")
        item_length = be16(data, position)
        item = position + 2
        if item_length < 20 or item + item_length > section_end:
            raise ValueError(f"Invalid PlayItem length: {path}")
        clip_id = data[item : item + 5].decode("ascii")
        if data[item + 5 : item + 9] != b"M2TS" or not clip_id.isdecimal():
            raise ValueError(f"Unsupported PlayItem reference: {path}")
        in45k = be32(data, item + 12)
        out45k = be32(data, item + 16)
        if out45k <= in45k:
            raise ValueError(f"Invalid PlayItem time range: {path}")
        clips.append({
            "clipID": clip_id,
            "startTime90k": timeline90k,
            "inTime90k": in45k * 2,
            "outTime90k": out45k * 2,
        })
        timeline90k += (out45k - in45k) * 2
        position = item + item_length
    return {"duration90k": timeline90k, "clips": clips}


def assert_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def verify_catalog(probed: dict, bdmv: Path, golden: dict, label: str) -> dict:
    assert_equal(probed.get("schema"), "enchron.bluray.probe/v1", f"{label} schema")
    titles = probed["titles"]
    expected_ids = list(range(golden["playlist_count"]))
    assert_equal([title["playlistID"] for title in titles], expected_ids,
                 f"{label} playlist IDs")
    playlists = bdmv / "PLAYLIST"
    streams = bdmv / "STREAM"
    assert_equal(len(list(playlists.glob("*.mpls"))), golden["playlist_count"],
                 f"{label} MPLS count")
    assert_equal(len(list(streams.glob("*.m2ts"))), golden["stream_count"],
                 f"{label} M2TS count")
    unsupported: dict[str, set[int]] = {}
    for title in titles:
        playlist_id = title["playlistID"]
        parsed = parse_mpls(playlists / f"{playlist_id:05d}.mpls")
        assert_equal(title["duration90k"], parsed["duration90k"],
                     f"{label} playlist {playlist_id} duration")
        observed = [{key: clip[key] for key in ("clipID", "startTime90k",
                    "inTime90k", "outTime90k")} for clip in title["clips"]]
        assert_equal(observed, parsed["clips"],
                     f"{label} playlist {playlist_id} PlayItems")
        for clip in title["clips"]:
            for stream in clip["streams"]:
                if stream["kind"] == "video" and stream["codingType"] not in (0x1B, 0x24):
                    codec = {0x01: "MPEG-1", 0x02: "MPEG-2", 0xEA: "VC-1"}.get(
                        stream["codingType"], f"0x{stream['codingType']:02x}"
                    )
                    unsupported.setdefault(codec, set()).add(playlist_id)
    for playlist_id, expected in golden["duration90k"].items():
        assert_equal(titles[playlist_id]["duration90k"], expected,
                     f"{label} golden duration {playlist_id}")
    for playlist_id, expected in golden["clip_ids"].items():
        title = titles[playlist_id]
        assert_equal([clip["clipID"] for clip in title["clips"]], expected,
                     f"{label} golden clips {playlist_id}")
        byte_position = 0
        physical_limit = 0
        for clip in title["clips"]:
            assert_equal(clip["byteStart"], byte_position,
                         f"{label} playlist {playlist_id} byte start")
            physical_limit += (streams / f"{clip['clipID']}.m2ts").stat().st_size
            if not (byte_position < clip["byteEnd"] <= physical_limit
                    and clip["byteEnd"] % 192 == 0):
                raise AssertionError(
                    f"{label} playlist {playlist_id} byte range exceeds authored M2TS bounds"
                )
            byte_position = clip["byteEnd"]
    for playlist_id, expected in golden["mpls_sha256"].items():
        assert_equal(sha256(playlists / f"{playlist_id:05d}.mpls"), expected,
                     f"{label} MPLS SHA-256 {playlist_id}")
    return {
        "playlistCount": len(titles),
        "streamFileCount": golden["stream_count"],
        "unsupportedVideoCodecs": {
            codec: sorted(ids) for codec, ids in sorted(unsupported.items())
        },
    }
