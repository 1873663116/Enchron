#!/usr/bin/env python3
"""Measure whether summoning the playback controls blacks out the wearer's
field. Records a session, toggles the controls twice through the app command
channel (the same path a pinch takes), recovers the screen recording, and
reports the per-frame luma trough around each toggle."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

DEVICE = "00008142-001871A11491401C"
CORE_DEVICE = "59E3D57A-0288-53DC-9A7D-B657B6939558"
BUNDLE = "com.xiongzhipeng.XrPlayer"
DEVELOPER_DIR = "/Volumes/Cortisol/Applications/Xcode-beta3.app/Contents/Developer"
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"
EXTRACTOR = REPOSITORY_ROOT / "Scripts/verification/extract_visionpro_ui_recording.py"


def controller(output_directory: Path, *arguments: str) -> dict[str, object]:
    completed = subprocess.run(
        [
            sys.executable, str(CONTROLLER),
            "--device", DEVICE,
            "--developer-dir", DEVELOPER_DIR,
            "--output-directory", str(output_directory),
            *arguments,
        ],
        capture_output=True, text=True, timeout=900,
    )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {"success": False, "error": (completed.stderr or completed.stdout)[-400:]}


def luma_timeline(video: Path) -> list[tuple[float, float]]:
    completed = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-i", str(video),
            "-vf", "signalstats,metadata=mode=print",
            "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    samples: list[tuple[float, float]] = []
    seconds: float | None = None
    for line in completed.stderr.splitlines():
        timestamp = re.search(r"pts_time:([0-9.]+)", line)
        if timestamp:
            seconds = float(timestamp.group(1))
        elif "signalstats.YAVG=" in line and seconds is not None:
            samples.append((seconds, float(line.rsplit("=", 1)[1])))
    return samples


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--clip", default="180_3D_loop10.mp4")
    parser.add_argument("--black-yavg", type=float, default=18.0)
    parser.add_argument("--toggles", type=int, default=4)
    arguments = parser.parse_args()

    evidence = arguments.evidence_dir.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=True)

    controller(evidence, "halt")
    session = controller(evidence, "ensure-session")
    if session.get("stage") != "ready":
        print(f"session not ready: {session}", file=sys.stderr)
        return 1

    opened = controller(
        evidence, "tap", "--identifier",
        f"MediaLibrary-grid-video-{arguments.clip}", "--no-screenshot",
    )
    if opened.get("success") is not True:
        print(f"could not open {arguments.clip}: {opened}", file=sys.stderr)
        return 1
    time.sleep(12)

    # Four toggles so the second summon, the one that can reuse a retained
    # scene identity, is measured separately from the first.
    marks: list[float] = []
    started = time.monotonic()
    for _ in range(arguments.toggles):
        marks.append(round(time.monotonic() - started, 2))
        controller(evidence, "app-command", "--verb", "toggleControls",
                   "--timeout-seconds", "20")
        time.sleep(8)

    controller(evidence, "stop")
    time.sleep(8)

    bundles = sorted(evidence.glob("*.xcresult"))
    if not bundles:
        print("no result bundle recovered", file=sys.stderr)
        return 1
    frames = evidence / "frames"
    subprocess.run(
        [sys.executable, str(EXTRACTOR), str(bundles[-1]), str(frames)],
        capture_output=True, text=True, env={"DEVELOPER_DIR": DEVELOPER_DIR,
                                             "PATH": "/usr/bin:/bin:/opt/homebrew/bin"},
    )
    recordings = sorted(frames.rglob("screen-recording.mp4"))
    if not recordings:
        print("no screen recording inside the bundle", file=sys.stderr)
        return 1

    samples = luma_timeline(recordings[-1])
    if not samples:
        print("ffmpeg produced no luma samples", file=sys.stderr)
        return 1
    darkest = min(samples, key=lambda sample: sample[1])
    black = [sample for sample in samples if sample[1] < arguments.black_yavg]
    spans: list[dict[str, float]] = []
    for seconds, yavg in black:
        if spans and seconds - spans[-1]["endSeconds"] <= 0.5:
            spans[-1]["endSeconds"] = seconds
            spans[-1]["frames"] += 1
            spans[-1]["minYAVG"] = min(spans[-1]["minYAVG"], yavg)
        else:
            spans.append({
                "startSeconds": round(seconds, 2),
                "endSeconds": seconds,
                "frames": 1,
                "minYAVG": yavg,
            })
    for span in spans:
        span["endSeconds"] = round(span["endSeconds"], 2)
        span["durationSeconds"] = round(
            span["endSeconds"] - span["startSeconds"], 2
        )
        span["minYAVG"] = round(span["minYAVG"], 3)
    # The recording opens on an unrendered field; only spans after it count.
    blackouts = [span for span in spans if span["startSeconds"] > 1.0]
    report = {
        "recording": str(recordings[-1]),
        "frameCount": len(samples),
        "minYAVG": darkest[1],
        "minYAVGAtSeconds": darkest[0],
        "blackoutCount": len(blackouts),
        "blackouts": blackouts,
        "toggleMarksSeconds": marks,
    }
    (evidence / "flash-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if not blackouts else 2


if __name__ == "__main__":
    raise SystemExit(main())
