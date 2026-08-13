#!/usr/bin/env python3

"""Ask a whole media set whether each title opens, and survive the ones that don't.

playback_mode_matrix already knows how to open one clip from a clean library
and judge where it landed, and it re-establishes its session per cell. What
it cannot do is survive a title that wedges the app: the wedge outlives the
cell, the next cell's ensure-session spends its full ten minutes on it, and
every remaining title is measuring the wreckage instead of the player.

So this drives the matrix one clip per process, caps each clip's wall clock,
and kills the resident runner between clips. That kill is the recovery that
was measured to work: with the stale runner gone, a session comes back in
about twenty-five seconds. A title that wedges costs its cap and nothing
more, and it is recorded as a wedge rather than smeared over its successors.

Clips run in the order given, so put a diverse subset first and the long
tail after; --deadline-minutes stops on a clean boundary when the device is
needed for something else.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MATRIX = REPOSITORY_ROOT / "Scripts/verification/playback_mode_matrix.py"
RUNNER_PATTERN = "test-without-building.*InteractiveDeviceSession"
WEDGED = "WEDGED"


def kill_resident_runner() -> None:
    subprocess.run(["pkill", "-f", RUNNER_PATTERN], check=False)
    time.sleep(4)


def run_one(clip: str, media_root: Path, evidence: Path, cap: float) -> dict[str, object]:
    cell = evidence / "cells" / clip.replace("/", "_")
    command = [
        sys.executable, str(MATRIX),
        "--clean", "--reps", "1", "--paths", "clean-open",
        "--media-root", str(media_root),
        "--evidence-dir", str(cell),
        "--clips", clip,
    ]
    started = time.monotonic()
    try:
        subprocess.run(
            command, cwd=REPOSITORY_ROOT, capture_output=True, text=True, timeout=cap
        )
    except subprocess.TimeoutExpired:
        return {"clip": clip, "verdict": WEDGED, "elapsed": round(time.monotonic() - started, 1)}
    results = cell / "results.jsonl"
    if not results.is_file():
        return {"clip": clip, "verdict": "NO_RESULT", "elapsed": round(time.monotonic() - started, 1)}
    record = json.loads(results.read_text().splitlines()[-1])
    step = (record.get("steps") or [{}])[0]
    visual = step.get("visual") or {}
    return {
        "clip": clip,
        "verdict": record.get("verdict"),
        "landed": step.get("landed"),
        "visual": visual.get("verdict"),
        "yavg": visual.get("yavg"),
        "ssim": visual.get("ssim"),
        "control_plane": step.get("control_plane"),
        "elapsed": round(time.monotonic() - started, 1),
        "evidence": str(cell),
    }


def main(arguments: argparse.Namespace) -> int:
    evidence = Path(arguments.evidence_dir)
    evidence.mkdir(parents=True, exist_ok=True)
    results_path = evidence / "results.jsonl"
    done = set()
    if results_path.is_file():
        done = {json.loads(line)["clip"] for line in results_path.read_text().splitlines() if line}

    clips = [c.strip() for c in Path(arguments.clips_file).read_text().splitlines() if c.strip()]
    clips = [c for c in clips if c not in done]
    deadline = time.monotonic() + arguments.deadline_minutes * 60

    counts: dict[str, int] = {}
    # A runner left behind by whatever ran last competes with the first
    # cell's own, and that cell's runner then never starts its test at all.
    kill_resident_runner()
    previous_was_clean = True
    for index, clip in enumerate(clips, start=1):
        if time.monotonic() > deadline:
            print(f"deadline reached with {len(clips) - index + 1} clips unrun", flush=True)
            break
        # Only after a bad cell. Killing before every clip forces a cold
        # ensure-session, which costs 25s healthy but has been measured at
        # 240s while recovering, and that alone can exceed the cap.
        if not previous_was_clean:
            kill_resident_runner()
        record = run_one(clip, Path(arguments.media_root), evidence, arguments.cap_seconds)
        previous_was_clean = record["verdict"] in ("PASS", "WRONG_STATE")
        counts[str(record["verdict"])] = counts.get(str(record["verdict"]), 0) + 1
        with results_path.open("a") as stream:
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(
            f"[{index}/{len(clips)}] {str(record['verdict']):<12}"
            f" {str(record.get('landed')):<16} visual={str(record.get('visual')):<10}"
            f" {record['elapsed']:>6}s  {Path(clip).name}",
            flush=True,
        )

    print("\n" + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())), flush=True)
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips-file", required=True)
    parser.add_argument("--media-root", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--cap-seconds", type=float, default=240.0)
    parser.add_argument("--deadline-minutes", type=float, default=120.0)
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(main(parse_arguments()))
