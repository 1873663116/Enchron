#!/usr/bin/env python3

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Callable, Iterable


@dataclass(frozen=True)
class RecordingSource:
    path: Path
    origin: str
    started_at: float | None
    metadata: dict[str, object]


@dataclass(frozen=True)
class FramePoint:
    seconds: float
    reasons: tuple[str, ...]


def walk_attachment_records(value: object) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    if isinstance(value, dict):
        if "exportedFileName" in value or "suggestedHumanReadableName" in value:
            records.append(value)
        for child in value.values():
            records.extend(walk_attachment_records(child))
    elif isinstance(value, list):
        for child in value:
            records.extend(walk_attachment_records(child))
    return records


MOVIE_CONTAINER_FORMATS = frozenset(
    {"mov", "mp4", "m4a", "3gp", "3g2", "mj2", "matroska", "webm"}
)


def probe_video(path: Path) -> dict[str, object] | None:
    completed = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration,size,format_name"
            ":stream=codec_name,codec_type,width,height,avg_frame_rate",
            "-of",
            "json",
            str(path),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        return None
    try:
        payload = json.loads(completed.stdout)
        video_stream = next(
            stream
            for stream in payload.get("streams", [])
            if stream.get("codec_type") == "video"
        )
        duration = float(payload["format"]["duration"])
        formats = set(str(payload["format"]["format_name"]).split(","))
    except (KeyError, StopIteration, TypeError, ValueError, json.JSONDecodeError):
        return None
    # The Staging scan below offers every pending file to this probe, and ffmpeg
    # demuxes plain text as an ANSI art video with a plausible duration and frame
    # rate. A staged xcresult holds the runner's stdout beside its attachments, so
    # without a container check the app's own log is recovered as the recording.
    if not formats & MOVIE_CONTAINER_FORMATS:
        return None
    return {
        "duration": duration,
        "bytes": int(payload["format"].get("size", path.stat().st_size)),
        "codec": video_stream.get("codec_name"),
        "container": payload["format"]["format_name"],
        "width": int(video_stream.get("width", 0)),
        "height": int(video_stream.get("height", 0)),
        "averageFrameRate": video_stream.get("avg_frame_rate"),
    }


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_recording_sources(
    result_bundle: Path,
    attachment_export_root: Path,
    attachment_records: Iterable[dict[str, object]],
    probe_video: Callable[[Path], dict[str, object] | None] = probe_video,
) -> list[RecordingSource]:
    records = list(attachment_records)
    recording_records = [
        record
        for record in records
        if str(record.get("suggestedHumanReadableName", "")).startswith(
            "Screen Recording"
        )
    ]
    sources: list[RecordingSource] = []
    seen_digests: set[str] = set()

    for record in recording_records:
        exported_name = record.get("exportedFileName")
        if not isinstance(exported_name, str):
            continue
        path = attachment_export_root / exported_name
        if not path.is_file():
            continue
        metadata = probe_video(path)
        if metadata is None:
            continue
        digest = file_digest(path)
        seen_digests.add(digest)
        timestamp = record.get("timestamp")
        sources.append(
            RecordingSource(
                path=path,
                origin="xcresult attachment",
                started_at=float(timestamp) if isinstance(timestamp, (int, float)) else None,
                metadata=metadata,
            )
        )

    pending_started_at: float | None = None
    if not sources and len(recording_records) == 1:
        timestamp = recording_records[0].get("timestamp")
        if isinstance(timestamp, (int, float)):
            pending_started_at = float(timestamp)

    staging_root = result_bundle / "Staging"
    if staging_root.is_dir():
        for path in sorted(item for item in staging_root.rglob("*") if item.is_file()):
            metadata = probe_video(path)
            if metadata is None:
                continue
            digest = file_digest(path)
            if digest in seen_digests:
                continue
            seen_digests.add(digest)
            sources.append(
                RecordingSource(
                    path=path,
                    origin="xcresult pending attachment",
                    started_at=pending_started_at,
                    metadata=metadata,
                )
            )

    return sources


SYSTEM_ATTACHMENT_PREFIXES = (
    "Screen Recording",
    "UI Snapshot",
    "Synthesized Event",
    "Debug description",
    "App UI hierarchy",
)


def plan_frame_points(
    duration: float,
    recording_started_at: float | None,
    attachment_records: Iterable[dict[str, object]],
    fixed_interval: float = 5.0,
    scene_change_times: Iterable[float] = (),
) -> list[FramePoint]:
    if duration <= 0:
        return []
    planned: dict[float, set[str]] = {}

    def add(seconds: float, reason: str) -> None:
        if seconds < 0 or seconds >= duration:
            return
        rounded = round(seconds, 3)
        planned.setdefault(rounded, set()).add(reason)

    add(min(0.5, duration / 2), "recording start")
    if duration > 1:
        add(duration - 0.5, "recording end")

    if fixed_interval > 0:
        seconds = fixed_interval
        while seconds < duration:
            add(seconds, "fixed interval")
            seconds += fixed_interval

    if recording_started_at is not None:
        for record in attachment_records:
            name = str(record.get("suggestedHumanReadableName", ""))
            timestamp = record.get("timestamp")
            if not isinstance(timestamp, (int, float)):
                continue
            relative_seconds = float(timestamp) - recording_started_at
            if name.startswith("Synthesized Event"):
                add(relative_seconds - 0.25, "before XCUITest interaction")
                add(relative_seconds, "XCUITest interaction")
                add(relative_seconds + 0.5, "after XCUITest interaction")
                add(relative_seconds + 1.5, "settled after XCUITest interaction")
            elif name and not name.startswith(SYSTEM_ATTACHMENT_PREFIXES):
                add(relative_seconds, f"test checkpoint: {name}")

    for seconds in scene_change_times:
        add(seconds, "large visual change")

    return [
        FramePoint(seconds=seconds, reasons=tuple(sorted(reasons)))
        for seconds, reasons in sorted(planned.items())
    ]


def detect_scene_changes(path: Path, threshold: float) -> list[float]:
    completed = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            str(path),
            "-vf",
            f"select='gt(scene,{threshold})',showinfo",
            "-an",
            "-f",
            "null",
            "-",
        ],
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        return []
    return [float(value) for value in re.findall(r"pts_time:([0-9.]+)", completed.stderr)]


def link_or_copy(source: Path, destination: Path) -> None:
    try:
        destination.hardlink_to(source)
    except OSError:
        shutil.copy2(source, destination)


def extract_frame(video: Path, seconds: float, destination: Path) -> None:
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            f"{seconds:.3f}",
            "-i",
            str(video),
            # The xcresult screen recording is anamorphic: 2732x2048 pixels
            # carrying a 16:9 view with no aspect metadata, so square-pixel
            # viewers stretch it vertically. Normalize to the same 16:9
            # geometry the XCUIScreen screenshot channel delivers.
            "-vf",
            "scale=iw:iw*9/16",
            "-frames:v",
            "1",
            "-y",
            str(destination),
        ],
        check=True,
    )


def create_contact_sheet(frame_directory: Path, frame_count: int, output: Path) -> None:
    if frame_count == 0:
        return
    columns = min(4, frame_count)
    rows = math.ceil(frame_count / columns)
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-framerate",
            "1",
            "-pattern_type",
            "glob",
            "-i",
            str(frame_directory / "*.png"),
            "-vf",
            f"scale=683:-1,tile={columns}x{rows}:padding=2:margin=2",
            "-frames:v",
            "1",
            "-y",
            str(output),
        ],
        check=True,
    )


def export_attachments(result_bundle: Path, output_root: Path) -> tuple[Path, list[dict[str, object]]]:
    export_root = output_root / "xcresult-attachments"
    export_root.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            [
                "xcrun",
                "xcresulttool",
                "export",
                "attachments",
                "--path",
                str(result_bundle),
                "--output-path",
                str(export_root),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        # An unsealed bundle (halt before finalization leaves no Info.plist)
        # cannot be read by xcresulttool; the Staging scan below still
        # recovers its pending recording files.
        print(
            f"xcresulttool export failed; continuing with Staging recovery: "
            f"{(error.stdout or '').strip()[-200:]}",
            file=sys.stderr,
        )
        return export_root, []
    manifest_path = export_root / "manifest.json"
    if not manifest_path.is_file():
        return export_root, []
    records = walk_attachment_records(json.loads(manifest_path.read_text()))
    manifest_path.unlink()
    return export_root, records


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Recover physical Vision Pro UI-test recordings from an xcresult and "
            "extract frames aligned to interactions, checkpoints, fixed intervals, "
            "and large visual changes."
        )
    )
    parser.add_argument("result_bundle", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fixed-interval", type=float, default=5.0)
    parser.add_argument("--scene-threshold", type=float, default=0.35)
    arguments = parser.parse_args()

    result_bundle = arguments.result_bundle.resolve()
    output_root = arguments.output.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    export_root, attachment_records = export_attachments(result_bundle, output_root)
    sources = find_recording_sources(
        result_bundle,
        export_root,
        attachment_records,
    )

    recordings: list[dict[str, object]] = []
    for index, source in enumerate(sources, start=1):
        recording_root = output_root / f"recording-{index:02d}"
        frame_root = recording_root / "frames"
        frame_root.mkdir(parents=True, exist_ok=True)
        video_path = recording_root / "screen-recording.mp4"
        link_or_copy(source.path, video_path)

        duration = float(source.metadata["duration"])
        scene_changes = detect_scene_changes(video_path, arguments.scene_threshold)
        points = plan_frame_points(
            duration=duration,
            recording_started_at=source.started_at,
            attachment_records=attachment_records,
            fixed_interval=arguments.fixed_interval,
            scene_change_times=scene_changes,
        )
        frames: list[dict[str, object]] = []
        for frame_index, point in enumerate(points, start=1):
            frame_name = f"frame-{frame_index:03d}-{point.seconds:08.3f}s.png"
            extract_frame(video_path, point.seconds, frame_root / frame_name)
            frames.append(
                {
                    "seconds": point.seconds,
                    "reasons": list(point.reasons),
                    "file": f"frames/{frame_name}",
                }
            )

        contact_sheet = recording_root / "contact-sheet.png"
        create_contact_sheet(frame_root, len(frames), contact_sheet)
        recordings.append(
            {
                "origin": source.origin,
                "startedAt": source.started_at,
                "video": str(video_path.relative_to(output_root)),
                "sha256": file_digest(video_path),
                "metadata": source.metadata,
                "contactSheet": str(contact_sheet.relative_to(output_root)),
                "frames": frames,
            }
        )

    shutil.rmtree(export_root, ignore_errors=True)

    report = {
        "schemaVersion": 1,
        "resultBundle": str(result_bundle),
        "recordingCount": len(recordings),
        "recordings": recordings,
    }
    report_path = output_root / "recording-index.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"recordings={len(recordings)}")
    print(f"index={report_path}")
    if not recordings:
        raise SystemExit(66)


if __name__ == "__main__":
    main()
