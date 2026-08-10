#!/usr/bin/env python3
"""Measure whether opening a window scene blacks out the wearer's field.
Records a session, drives the requested presentation, toggles a window through
the app command channel (the same path a pinch takes), recovers the screen
recording, and reports the per-frame luma trough around each toggle.

The report carries the probe lines the app wrote during the run, so the
presentation the blackouts were measured in is part of the evidence rather
than an assumption about what tapping a library item does."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from playback_mode_matrix import copy_probe_lines  # noqa: E402

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


def immersive_now(evidence: Path) -> bool:
    lines, _ = copy_probe_lines(evidence)
    for line in reversed(lines or []):
        if " immersiveSpaceDisappeared " in line:
            return False
        if " immersiveSpaceAppeared " in line:
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--clip", default="180_3D_loop10.mp4")
    parser.add_argument("--black-yavg", type=float, default=18.0)
    parser.add_argument("--toggles", type=int, default=4)
    parser.add_argument("--verb", default="toggleControls")
    parser.add_argument(
        "--enter-panorama",
        action="store_true",
        help="Apply the native 180 format so the toggles are measured inside "
             "progressive immersion instead of the flat window.",
    )
    arguments = parser.parse_args()

    evidence = arguments.evidence_dir.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=True)

    controller(evidence, "halt")
    session = controller(evidence, "ensure-session")
    if session.get("stage") != "ready":
        print(f"session not ready: {session}", file=sys.stderr)
        return 1

    # A prior run can leave the app restored into a presentation, where the
    # library grid the measurement starts from does not exist.
    controller(evidence, "relaunch")
    time.sleep(6)

    opened = controller(
        evidence, "tap", "--identifier",
        f"MediaLibrary-grid-video-{arguments.clip}", "--no-screenshot",
    )
    if opened.get("success") is not True:
        print(f"could not open {arguments.clip}: {opened}", file=sys.stderr)
        return 1
    time.sleep(12)

    if arguments.enter_panorama:
        entered = controller(
            evidence, "tapSequence", "--identifiers",
            "PlayerUI-window-playback-surface",
            "PlayerUI-TopAction-videoFormat",
            "PlayerUI-VideoFormat-Projection-180°",
            "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side",
            "PlayerUI-VideoFormat-apply",
            "--no-screenshot",
        )
        if entered.get("success") is not True:
            print(f"could not enter panorama: {entered}", file=sys.stderr)
            return 1
        time.sleep(20)

    if not immersive_now(evidence):
        print(
            "the app is not in an immersive presentation; the toggles would "
            "measure the flat window instead",
            file=sys.stderr,
        )
        return 1

    marks: list[float] = []
    started = time.monotonic()
    for _ in range(arguments.toggles):
        marks.append(round(time.monotonic() - started, 2))
        controller(evidence, "app-command", "--verb", arguments.verb,
                   "--timeout-seconds", "20")
        time.sleep(8)

    probe_lines, probe_error = copy_probe_lines(evidence)
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
        "verb": arguments.verb,
        "enteredPanorama": arguments.enter_panorama,
        "probeError": probe_error,
        "probeLines": probe_lines or [],
    }
    (evidence / "flash-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if not blackouts else 2


if __name__ == "__main__":
    raise SystemExit(main())
