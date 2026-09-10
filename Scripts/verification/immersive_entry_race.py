#!/usr/bin/env python3

"""Ask for the immersive space the instant playback starts, and see who owns the surface.

The dock button is not reachable through the accessibility harness until the
player chrome becomes hittable, three to four seconds after a clip opens, which
is well past the window this exercises. The test channel's enterSpatial verb
issues the same presentation request the button does, so the entry can be asked
for while the technical session is still being prepared.

The failure this guards against is a claim recorded against the player window
after that window has been dismissed: the shared video entity is then minted
under the window presentation, the space adopts it, and settlement never
receives a pixel. Every iteration reads the probe journal between the
dismissal and the next push and fails on any renderer claim found there.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"
PROBE_RELATIVE_PATH = "Documents/surface-tap-probe.log"
BUNDLE = "com.xiongzhipeng.Enchron"
SEQUENCE = re.compile(r"probeSequence=(\d+)")


def controller(arguments: argparse.Namespace, *command: str) -> dict:
    completed = subprocess.run(
        [
            sys.executable,
            str(CONTROLLER),
            "--device",
            arguments.device,
            "--execution-input",
            arguments.execution_input,
            "--output-directory",
            str(Path(arguments.evidence_dir) / "session"),
            *command,
            "--no-screenshot",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        return json.loads(completed.stdout, strict=False)
    except json.JSONDecodeError:
        return {"success": False, "error": completed.stdout[-400:] or completed.stderr[-400:]}


def control_plane(arguments: argparse.Namespace, identifier: str) -> dict[str, str]:
    response = controller(arguments, "snapshot", "--identifier", identifier)
    matched = response.get("matchedElement") or {}
    value = matched.get("value") or ""
    return dict(field.split("=", 1) for field in value.split(";") if "=" in field)


def probe_lines(container: Path) -> list[str]:
    try:
        return (container / PROBE_RELATIVE_PATH).read_text(
            encoding="utf-8", errors="replace"
        ).splitlines()
    except OSError:
        return []


def app_container(device: str) -> Path:
    completed = subprocess.run(
        ["xcrun", "simctl", "get_app_container", device, BUNDLE, "data"],
        capture_output=True,
        text=True,
        check=False,
    )
    return Path(completed.stdout.strip())


def claims_while_the_player_window_is_down(lines: list[str]) -> list[str]:
    dismissed = False
    late: list[str] = []
    for line in lines:
        if "pushedWindow dismiss window=player" in line:
            dismissed = True
            continue
        if "pushedWindow push window=player" in line:
            dismissed = False
            continue
        if dismissed and "rendererOwnership.claim" in line and "target=window/" in line:
            late.append(line)
    return late


def wait_until_playing(arguments: argparse.Namespace) -> bool:
    for _ in range(15):
        if control_plane(arguments, "PlayerUI-window-control-plane").get("lifecycle") == "Playing":
            return True
        time.sleep(1)
    return False


def iteration(arguments: argparse.Namespace, container: Path, index: int) -> dict:
    controller(arguments, "tap", "--identifier", "PlayerUI-presentation-conversion-dismiss")
    controller(arguments, "app-command", "--verb", "exitSpatial")
    time.sleep(2)
    controller(arguments, "tap", "--identifier", "PlayerUI-InfoBar-button-back")
    time.sleep(2)
    controller(arguments, "tap", "--identifier", arguments.source_identifier)
    time.sleep(2)
    mark = len(probe_lines(container))
    controller(arguments, "tap", "--identifier", arguments.clip_identifier)
    controller(arguments, "tap", "--identifier", "PlayerUI-resumeDecision-primary")
    playing = wait_until_playing(arguments)
    entered = False
    for _ in range(8):
        if controller(arguments, "app-command", "--verb", "enterSpatial").get("success"):
            entered = True
            break
    time.sleep(arguments.settle_seconds)
    spatial = control_plane(arguments, "PlayerUI-spatial-state")
    controller(arguments, "app-command", "--verb", "exitSpatial")
    time.sleep(arguments.settle_seconds)
    window = control_plane(arguments, "PlayerUI-window-control-plane")
    delta = probe_lines(container)[mark:]
    late = claims_while_the_player_window_is_down(delta)
    conversion_failures = [line for line in delta if "conversionFailed" in line]
    return {
        "iteration": index,
        "reachedPlaying": playing,
        "entered": entered,
        "spatialPresentation": spatial.get("presentation"),
        "spatialTransition": spatial.get("transition"),
        "windowPresentation": window.get("presentation"),
        "windowResolution": window.get("lastExecutionResolution"),
        "lateWindowClaims": late,
        "conversionFailures": conversion_failures,
    }


def run(arguments: argparse.Namespace) -> int:
    evidence = Path(arguments.evidence_dir)
    evidence.mkdir(parents=True, exist_ok=True)
    session = controller(arguments, "ensure-session")
    if session.get("stage") != "ready":
        print(json.dumps({"stage": "ensure-session", "session": session}, ensure_ascii=False)[:600])
        return 1
    container = app_container(arguments.device)
    if not container.is_dir():
        print(f"no application container for {BUNDLE} on {arguments.device}")
        return 1
    records = []
    for index in range(1, arguments.iterations + 1):
        record = iteration(arguments, container, index)
        records.append(record)
        print(
            f"[{index}] entered={record['entered']}"
            f" playing={record['reachedPlaying']}"
            f" lateClaims={len(record['lateWindowClaims'])}"
            f" conversionFailures={len(record['conversionFailures'])}"
            f" spatial={record['spatialPresentation']}/{record['spatialTransition']}"
            f" window={record['windowPresentation']}",
            flush=True,
        )
    (evidence / "results.json").write_text(
        json.dumps(records, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    offenders = [r for r in records if r["lateWindowClaims"] or r["conversionFailures"]]
    print(f"{len(records) - len(offenders)}/{len(records)} entries kept the surface")
    return 0 if not offenders else 2


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--execution-input", required=True)
    parser.add_argument("--clip-identifier", required=True)
    parser.add_argument(
        "--source-identifier", default="FileBrowsing-SourcesSidebar-source-media-library"
    )
    parser.add_argument("--iterations", type=int, default=8)
    parser.add_argument("--settle-seconds", type=float, default=12.0)
    parser.add_argument(
        "--evidence-dir",
        default=str(REPOSITORY_ROOT / ".scratch/Verification/immersive-entry-race"),
    )
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run(parse_arguments()))
