#!/usr/bin/env python3
"""Resolve the journey content conditions that a human eye keeps getting wrong.

Two verdicts in the 2026-08-26 round were wrong because the probe was wrong,
not because the condition was missing. J03 was recorded blocked on
`pgrep -x smbd` finding nothing, but macOS launches smbd on demand, so an idle
share looks identical to a disabled one; the honest probe is a mount. J08 was
recorded voided after a sweep that never descended into the vendored FFmpeg
FATE corpus, where both an audio-only sample and a cover-art sample were
sitting the whole time. Both checks now run here, deterministically, and the
exit status is the verdict.

Credentials come from the repository .env and are never printed or placed on a
command line that another process could read.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE_ROOT = REPOSITORY_ROOT.parent
TEST_MEDIA = WORKSPACE_ROOT / "TestMedia"
ENVIRONMENT_FILE = REPOSITORY_ROOT / ".env"
SHARE_NAME = "TestMedia"
AGGREGATE_STEM = "sdr-bframe-aggregate-30s"
AUDIO_SUFFIXES = (
    ".aac", ".ac3", ".aob", ".ape", ".caf", ".dts", ".eac3", ".flac", ".m4a",
    ".mka", ".mp3", ".oga", ".ogg", ".opus", ".thd", ".wav", ".wv",
)


def read_environment() -> dict[str, str]:
    values: dict[str, str] = {}
    if not ENVIRONMENT_FILE.exists():
        return values
    for line in ENVIRONMENT_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip("'\"")
    return values


def host_address() -> str:
    for interface in ("en0", "en1"):
        result = subprocess.run(
            ["ipconfig", "getifaddr", interface], capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    return "127.0.0.1"


def check_smb() -> dict[str, object]:
    environment = read_environment()
    user = environment.get("SMB_USER", "")
    password = environment.get("SMB_PASSWORD", "")
    address = host_address()
    if not user or not password:
        return {
            "check": "smb",
            "ready": False,
            "reason": "SMB_USER or SMB_PASSWORD missing from .env",
            "address": address,
        }
    listening = (
        subprocess.run(
            ["nc", "-z", "-G", "2", address, "445"], capture_output=True
        ).returncode
        == 0
    )
    if not listening:
        return {
            "check": "smb",
            "ready": False,
            "reason": f"nothing listening on {address}:445; enable File Sharing in System Settings",
            "address": address,
        }
    mount_point = Path(tempfile.mkdtemp(prefix="journey-smb-"))
    try:
        mounted = subprocess.run(
            [
                "mount_smbfs",
                f"//{user}:{password}@{address}/{SHARE_NAME}",
                str(mount_point),
            ],
            capture_output=True,
            text=True,
        )
        if mounted.returncode != 0:
            return {
                "check": "smb",
                "ready": False,
                "reason": f"mount rejected: {mounted.stderr.strip()}",
                "address": address,
            }
        try:
            found = sorted(
                str(path.relative_to(mount_point))
                for path in mount_point.rglob(f"{AGGREGATE_STEM}.*")
            )
            return {
                "check": "smb",
                "ready": bool(found),
                "reason": "" if found else f"{AGGREGATE_STEM}.* not present on the share",
                "address": address,
                "share": SHARE_NAME,
                "aggregate": found,
            }
        finally:
            subprocess.run(["umount", str(mount_point)], capture_output=True)
    finally:
        shutil.rmtree(mount_point, ignore_errors=True)


def probe_streams(path: Path) -> list[dict[str, object]]:
    result = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "stream=codec_type,codec_name,disposition",
            "-of", "json", str(path),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    return json.loads(result.stdout or "{}").get("streams", [])


def classify(path: Path) -> str | None:
    streams = probe_streams(path)
    if not streams:
        return None
    kinds = [stream.get("codec_type") for stream in streams]
    if "audio" not in kinds:
        return None
    pictures = [
        stream
        for stream in streams
        if stream.get("codec_type") == "video"
        and (
            stream.get("disposition", {}).get("attached_pic")
            or stream.get("codec_name") in {"png", "mjpeg", "bmp"}
        )
    ]
    videos = [stream for stream in streams if stream.get("codec_type") == "video"]
    if not videos:
        return "audio-only"
    if len(videos) == len(pictures):
        return "audio-with-cover"
    return None


def check_audio_fixtures() -> dict[str, object]:
    if shutil.which("ffprobe") is None:
        return {"check": "audio-fixtures", "ready": False, "reason": "ffprobe not installed"}
    if not TEST_MEDIA.exists():
        return {"check": "audio-fixtures", "ready": False, "reason": f"{TEST_MEDIA} missing"}
    plain: list[str] = []
    cover: list[str] = []
    for path in sorted(TEST_MEDIA.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in AUDIO_SUFFIXES:
            continue
        kind = classify(path)
        relative = str(path.relative_to(TEST_MEDIA))
        if kind == "audio-only":
            plain.append(relative)
        elif kind == "audio-with-cover":
            cover.append(relative)
    missing = []
    if not plain:
        missing.append("no audio-only sample")
    if not cover:
        missing.append("no audio sample carrying cover art")
    return {
        "check": "audio-fixtures",
        "ready": not missing,
        "reason": "; ".join(missing),
        "audio_only": plain,
        "audio_with_cover": cover,
    }


CHECKS = {"smb": check_smb, "audio-fixtures": check_audio_fixtures}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", choices=[*CHECKS, []], default=list(CHECKS))
    arguments = parser.parse_args(argv)
    selected = arguments.names or list(CHECKS)
    results = [CHECKS[name]() for name in selected]
    print(json.dumps({"checks": results}, indent=2, sort_keys=True))
    return 0 if all(result["ready"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
