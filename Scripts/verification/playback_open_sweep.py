#!/usr/bin/env python3

"""Ask a whole media set whether each title opens, on one session, without ever
re-establishing it.

The expensive and fragile part of a per-clip sweep turned out not to be the
playing: relaunch, reset, push, import and tap were measured at thirteen
seconds together on a healthy session. It was re-establishing the session
per clip. Each ensure-session spawns a runner, and when one lands while
another is still resident the two contend for the device, neither serves
reliably, and the cell reports a settle timeout the player never caused.

So this establishes one session and keeps it. Per clip it runs the same
sequence by hand and judges from the control plane, which is a two second
round trip. The device probe file is read only when the control plane has
been unreadable for several polls, which is what an immersive landing looks
like; putting that container copy at the top of every poll is what made
earlier sweeps spend a whole settle deadline on a single iteration.

A title passes only when the product reports a steady presentation with its
video visible and the screen then shows moving, non-black content.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

from playback_mode_matrix import (  # noqa: E402
    BUNDLE,
    CORE_DEVICE,
    DEVELOPER_DIR,
    WINDOWED_STEADY_LIFECYCLES,
    app_command,
    capture_visual_evidence,
    controller,
    controller_summary,
    copy_probe_lines,
    format_facts,
    last_settlement_settled,
    read_control_plane,
    safe_component,
)


SETTLE_DEADLINE_SECONDS = 45.0
# An immersive landing empties the window, so the control plane goes missing.
# Only then is the probe file worth its container copy.
MISSING_PLANE_POLLS_BEFORE_PROBE = 4


def push_clip(media_path: Path) -> str | None:
    completed = subprocess.run(
        [
            "xcrun", "devicectl", "device", "copy", "to",
            "--device", CORE_DEVICE,
            "--domain-type", "appDataContainer",
            "--domain-identifier", BUNDLE,
            "--source", str(media_path),
            "--destination", f"Documents/TestMediaInbox/{media_path.name}",
        ],
        capture_output=True, text=True, timeout=900,
        env={"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin"},
    )
    if completed.returncode != 0:
        return (completed.stderr or completed.stdout).strip()[-300:]
    return None


def prepare_library(clip: str, media_root: Path, session: Path) -> dict[str, object] | None:
    media_path = media_root / clip
    if not media_path.is_file():
        return {"phase": "media", "message": f"No such media: {media_path}"}
    relaunch = controller(session, "relaunch", "--no-screenshot")
    if relaunch.get("success") is not True:
        return {"phase": "relaunch", "controller": controller_summary(relaunch)}
    reset = app_command(session, "resetState")
    if reset.get("ok") is not True:
        return {"phase": "reset", "controller": controller_summary(reset)}
    if (error := push_clip(media_path)) is not None:
        return {"phase": "push", "message": error}
    imported = app_command(session, "importMedia", f"file={media_path.name}")
    if imported.get("ok") is not True:
        return {"phase": "import", "controller": controller_summary(imported)}
    return None


def judge_open(name: str, cell: Path, session: Path) -> dict[str, object]:
    cell.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    tap = controller(
        session, "tap", "--identifier", f"MediaLibrary-grid-video-{name}", "--no-screenshot"
    )
    if tap.get("success") is not True:
        return {"verdict": "DRIVE_ERROR", "phase": "tap", "controller": controller_summary(tap)}

    missing_plane = 0
    invisible_steady = 0
    latest: dict[str, str] | None = None
    while time.monotonic() - started < SETTLE_DEADLINE_SECONDS:
        plane, _ = read_control_plane(session)
        if plane is None:
            missing_plane += 1
            if missing_plane >= MISSING_PLANE_POLLS_BEFORE_PROBE:
                lines, _ = copy_probe_lines(cell)
                if lines is not None and last_settlement_settled(lines) is True:
                    return {
                        "verdict": "PASS",
                        "landed": "immersive",
                        "seconds": round(time.monotonic() - started, 1),
                    }
            continue
        missing_plane = 0
        latest = plane
        lifecycle = (plane.get("lifecycle") or "").lower()
        if lifecycle.startswith("failed"):
            return {
                "verdict": "FAILED",
                "landed": "failed",
                "message": plane.get("lifecycle"),
                "control_plane": format_facts(plane),
            }
        if plane.get("transition") != "none":
            continue
        # Window and portal are the two presentations that keep the control
        # plane readable, and portal is where a signalled panoramic source
        # lands before anyone asks for panorama. Accepting only window timed
        # out every spatial clip in the set.
        presentation = plane.get("presentation")
        if presentation in ("window", "portal") and lifecycle in WINDOWED_STEADY_LIFECYCLES:
            if plane.get("videoVisible") == "true":
                return {
                    "verdict": "PASS",
                    "landed": presentation,
                    "seconds": round(time.monotonic() - started, 1),
                    "control_plane": format_facts(plane),
                }
            invisible_steady += 1
            if invisible_steady >= 5:
                # A clip that already ended without ever being seen visible
                # may simply be shorter than one poll: the FATE ProRes
                # vectors run 70ms. That is unjudged, not a failure. A clip
                # sitting at ready or playing with nothing on screen is.
                ended_before_seen = lifecycle == "ended"
                return {
                    "verdict": "TOO_SHORT" if ended_before_seen else "NO_PICTURE",
                    "landed": "window-invisible",
                    "control_plane": format_facts(plane),
                }
    return {
        "verdict": "STALL",
        "landed": None,
        "seconds": round(time.monotonic() - started, 1),
        "control_plane": format_facts(latest),
    }


def main(arguments: argparse.Namespace) -> int:
    evidence = Path(arguments.evidence_dir)
    session = evidence / "session"
    session.mkdir(parents=True, exist_ok=True)
    results_path = evidence / "results.jsonl"
    done = set()
    if results_path.is_file():
        done = {json.loads(l)["clip"] for l in results_path.read_text().splitlines() if l}

    subprocess.run(["pkill", "-f", "test-without-building.*InteractiveDeviceSession"], check=False)
    time.sleep(5)
    ready = controller(session, "ensure-session")
    if ready.get("stage") != "ready":
        print(json.dumps(controller_summary(ready)))
        return 1
    print(f"session {ready.get('sessionID')} ready in {ready.get('elapsedSeconds')}s", flush=True)

    clips = [c.strip() for c in Path(arguments.clips_file).read_text().splitlines() if c.strip()]
    clips = [c for c in clips if c not in done]
    deadline = time.monotonic() + arguments.deadline_minutes * 60
    counts: dict[str, int] = {}

    for index, clip in enumerate(clips, start=1):
        if time.monotonic() > deadline:
            print(f"deadline reached, {len(clips) - index + 1} clips unrun", flush=True)
            break
        name = Path(clip).name
        cell = evidence / "titles" / f"{index:03d}-{safe_component(name)}"
        record: dict[str, object] = {"clip": clip, "name": name}
        failure = prepare_library(clip, Path(arguments.media_root), session)
        if failure is not None:
            record.update({"verdict": "DRIVE_ERROR", **failure})
        else:
            record.update(judge_open(name, cell, session))
            if record.get("verdict") == "PASS":
                visual = capture_visual_evidence(
                    controller_directory=session,
                    lifecycle=(record.get("control_plane") or {}).get("lifecycle"),
                )
                record["visual"] = visual
                if visual.get("verdict") in ("black", "frozen"):
                    record["verdict"] = "BAD_PIXELS"
        counts[str(record["verdict"])] = counts.get(str(record["verdict"]), 0) + 1
        with results_path.open("a") as stream:
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
        visual = record.get("visual")
        print(
            f"[{index}/{len(clips)}] {str(record['verdict']):<12}"
            f" {str(record.get('landed')):<18}"
            f" visual={str(visual.get('verdict') if isinstance(visual, dict) else '-'):<10} {name}",
            flush=True,
        )

    print("\n" + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())), flush=True)
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips-file", required=True)
    parser.add_argument("--media-root", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--deadline-minutes", type=float, default=60.0)
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(main(parse_arguments()))
