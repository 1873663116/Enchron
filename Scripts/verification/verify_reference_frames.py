#!/usr/bin/env python3
"""Guard accepted reference frames: mint them from wearer acceptance, verify against them forever.

A reference frame is a device screenshot of a paused, wearer-accepted picture.
The wearer judges a dynamic-range family once; the frame captured at that
moment becomes the machine's standard. Every later capture of the same clip at
the same position must stay within the reference's thresholds, so a color
drift like the Profile 5 cast fails on the first commit that introduces it
instead of waiting for a human.

Two metrics decide: the largest shift among the Y/U/V plane averages (a global
color or brightness drift moves U/V or Y far beyond session noise) and SSIM
against the reference (confirms it is the same frame at all). Thresholds are
not invented; they are minted from measured session-to-session variance.

mint  --name <ref> --family <F> --source <desc> --position <s> \
      --captures a.png b.png [...] [--margin 3.0] [--registry DIR]

    Captures MUST come from at least two separate opens of the clip paused at
    the same position, so their spread contains real session-to-session
    variance. Byte-identical captures are refused: they measure nothing.
    The first capture becomes the reference frame; thresholds are the measured
    spread times --margin, recorded in the registry entry for audit.

verify --name <ref> --capture <png> [--registry DIR]

    Judges one fresh capture against the named reference.

Registry lives in TestMedia/References (registry.json + frames/), the
workspace home for calibration fixtures. Override with --registry or
ENCHRON_REFERENCE_ROOT.

Exit codes: 0 within thresholds, 1 drifted beyond thresholds, 2 the check
could not run (missing registry or frame, capture shape mismatch, 1x1
capture-failure screenshot, refused mint).
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY = REPOSITORY_ROOT.parent / "TestMedia" / "References"
# Mirrors playback_mode_matrix's frozen-frame gate; used only when measured
# SSIM spread is zero while the captures still differ.
FALLBACK_SSIM_FLOOR = 0.995

SIGNALSTATS = re.compile(r"lavfi\.signalstats\.([YUV]AVG)=([0-9.]+)")
SSIM_ALL = re.compile(r"All:([0-9.]+)")


class CheckCannotRun(Exception):
    pass


def run(command: list[str]) -> str:
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        raise CheckCannotRun(f"{command[0]} failed: {completed.stderr.strip()[:200]}")
    return completed.stdout + completed.stderr


def image_size(path: Path) -> tuple[int, int]:
    out = run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path),
    ])
    width, height = out.strip().split(",")
    return int(width), int(height)


def checked_capture(path: Path) -> Path:
    if not path.is_file():
        raise CheckCannotRun(f"capture not found: {path}")
    size = image_size(path)
    if size == (1, 1):
        raise CheckCannotRun(f"{path} is 1x1: capture failure, not a frame")
    return path


def plane_averages(path: Path) -> dict[str, float]:
    out = run([
        "ffmpeg", "-hide_banner", "-i", str(path),
        "-vf", "signalstats,metadata=print:file=-", "-f", "null", "-",
    ])
    averages = {name: float(value) for name, value in SIGNALSTATS.findall(out)}
    if set(averages) != {"YAVG", "UAVG", "VAVG"}:
        raise CheckCannotRun(f"signalstats gave no plane averages for {path}")
    return averages


def ssim(a: Path, b: Path) -> float:
    out = run([
        "ffmpeg", "-hide_banner", "-i", str(a), "-i", str(b),
        "-lavfi", "ssim", "-f", "null", "-",
    ])
    match = SSIM_ALL.search(out)
    if not match:
        raise CheckCannotRun(f"ssim produced no verdict for {a} vs {b}")
    return float(match.group(1))


def plane_delta(a: dict[str, float], b: dict[str, float]) -> float:
    return max(abs(a[name] - b[name]) for name in ("YAVG", "UAVG", "VAVG"))


def load_registry(root: Path) -> dict:
    index = root / "registry.json"
    if not index.is_file():
        return {}
    return json.loads(index.read_text(encoding="utf-8"))


def save_registry(root: Path, registry: dict) -> None:
    (root / "registry.json").write_text(
        json.dumps(registry, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def mint(arguments) -> int:
    captures = [checked_capture(Path(p)) for p in arguments.captures]
    if len(captures) < 2:
        raise CheckCannotRun("mint needs at least two captures from separate opens")
    sizes = {image_size(p) for p in captures}
    if len(sizes) > 1:
        raise CheckCannotRun(f"captures disagree on size: {sorted(sizes)}")
    digests = {hashlib.sha256(p.read_bytes()).hexdigest() for p in captures}
    if len(digests) == 1:
        raise CheckCannotRun(
            "captures are byte-identical; they measure no session-to-session "
            "variance. Capture across two separate opens of the clip."
        )

    reference = captures[0]
    reference_planes = plane_averages(reference)
    spread = max(plane_delta(reference_planes, plane_averages(p)) for p in captures[1:])
    ssim_min = min(ssim(reference, p) for p in captures[1:])
    if spread == 0:
        raise CheckCannotRun(
            "measured plane spread is zero; captures do not sample real variance"
        )
    threshold = arguments.margin * spread
    floor = 1 - arguments.margin * (1 - ssim_min) if ssim_min < 1 else FALLBACK_SSIM_FLOOR

    root = arguments.registry
    frames = root / "frames"
    frames.mkdir(parents=True, exist_ok=True)
    frame_path = frames / f"{arguments.name}.png"
    frame_path.write_bytes(reference.read_bytes())

    registry = load_registry(root)
    registry[arguments.name] = {
        "family": arguments.family,
        "source": arguments.source,
        "positionSeconds": arguments.position,
        "frame": f"frames/{arguments.name}.png",
        "acceptedAt": date.today().isoformat(),
        "planeAverages": reference_planes,
        "measured": {"planeSpread": spread, "ssimMin": ssim_min,
                     "captureCount": len(captures)},
        "margin": arguments.margin,
        "thresholds": {"planeDelta": round(threshold, 4), "ssimFloor": round(floor, 6)},
    }
    save_registry(root, registry)
    print(
        f"minted {arguments.name}: spread {spread:.4f} -> planeDelta<={threshold:.4f}, "
        f"ssim {ssim_min:.6f} -> floor {floor:.6f}"
    )
    return 0


def verify(arguments) -> int:
    registry = load_registry(arguments.registry)
    entry = registry.get(arguments.name)
    if entry is None:
        raise CheckCannotRun(f"no reference named {arguments.name!r} in {arguments.registry}")
    reference = arguments.registry / entry["frame"]
    if not reference.is_file():
        raise CheckCannotRun(f"reference frame missing: {reference}")
    candidate = checked_capture(Path(arguments.capture))
    if image_size(candidate) != image_size(reference):
        raise CheckCannotRun(
            f"size mismatch: {candidate} is {image_size(candidate)}, "
            f"reference is {image_size(reference)}"
        )

    delta = plane_delta(plane_averages(candidate), plane_averages(reference))
    similarity = ssim(candidate, reference)
    limits = entry["thresholds"]
    drifted = delta > limits["planeDelta"] or similarity < limits["ssimFloor"]

    print(
        f"{arguments.name}: planeDelta {delta:.4f} (limit {limits['planeDelta']}), "
        f"ssim {similarity:.6f} (floor {limits['ssimFloor']})"
    )
    if drifted:
        print("  drifted beyond the accepted reference")
        return 1
    print("  within the accepted reference")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--registry", type=Path,
        default=Path(os.environ.get("ENCHRON_REFERENCE_ROOT", DEFAULT_REGISTRY)),
    )
    commands = parser.add_subparsers(dest="command", required=True)

    minter = commands.add_parser("mint")
    minter.add_argument("--name", required=True)
    minter.add_argument("--family", required=True)
    minter.add_argument("--source", required=True)
    minter.add_argument("--position", type=float, required=True)
    minter.add_argument("--captures", nargs="+", required=True)
    minter.add_argument("--margin", type=float, default=3.0)

    verifier = commands.add_parser("verify")
    verifier.add_argument("--name", required=True)
    verifier.add_argument("--capture", required=True)

    arguments = parser.parse_args()
    try:
        return mint(arguments) if arguments.command == "mint" else verify(arguments)
    except CheckCannotRun as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
