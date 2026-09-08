"""Close the main window the way the wearer does and prove playback stopped.

The window bar's close button is outside the app's accessibility tree, so the
runner cannot tap it. The DEBUG verb ``closeMainWindow`` destroys the foreground
Window scene through ``requestSceneSessionDestruction``, which raises the same
``UIScene.didDisconnectNotification`` the wearer's close does. Once the window is
gone the app has no foreground scene, so the test channel drops and the verdict
is read from the probe journal copied out of the container.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import playback_mode_matrix as matrix
from harness import Budget, InstrumentFault, wait_for

CLOSE_MARKERS = (
    "testcmd closeMainWindow",
    "mainWindowScene disconnected trigger=wearer",
    "mainWindowScene closedByWearer stoppingPlayback",
)
DEFAULT_ITEM = "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"


def wearer_close_verdict(delta: list[str]) -> dict[str, object]:
    positions: dict[str, int | None] = {}
    search_from = 0
    ordered = True
    for marker in CLOSE_MARKERS:
        index = next((i for i in range(search_from, len(delta)) if marker in delta[i]), None)
        if index is None:
            ordered = ordered and all(marker not in line for line in delta)
            positions[marker] = None
            continue
        positions[marker] = index
        search_from = index + 1
    missing = [marker for marker in CLOSE_MARKERS if positions[marker] is None]
    passed = not missing and ordered
    return {"passed": passed, "missing": missing, "ordered": ordered, "positions": positions}


def run(*, item: str, evidence_directory: Path, settle_seconds: float) -> dict[str, object]:
    instruments = matrix._get_instruments()
    client = matrix._controller_client(instruments, evidence_directory)
    matrix._invoke_controller(instruments, client, "wearer-close:ensure-session", "ensure-session", "--no-screenshot")
    opened = matrix._invoke_controller(instruments, client, "wearer-close:tap", "tap", "--identifier", item, "--no-screenshot")
    if opened.get("success") is not True:
        return {"passed": False, "stage": "open", "response": opened}
    landing = matrix.wait_for_presentation(output_directory=evidence_directory, expected=matrix.PANORAMIC_WINDOW, target_started_at=0.0)
    if landing.get("verdict") != matrix.PASS:
        return {"passed": False, "stage": "landing", "response": landing}
    matrix.hold(instruments, "wearer-close:settle", settle_seconds)
    before = matrix._copy_probe_lines_harness(instruments, evidence_directory, "wearer-close:probe-before")
    cursor = matrix.probe_cursor(before)
    closed = matrix.app_command_harness(instruments, client, "closeMainWindow")
    if closed.get("ok") is not True and closed.get("success") is not True:
        return {"passed": False, "stage": "close", "response": closed}
    latest: dict[str, object] = {"delta": [], "verdict": wearer_close_verdict([]), "cursorError": None}

    def probe() -> dict[str, object] | None:
        after = matrix._copy_probe_lines_harness(instruments, evidence_directory, "wearer-close:probe-after")
        delta, _, cursor_error = matrix.probe_lines_since(after, cursor)
        latest.update({"delta": delta, "verdict": wearer_close_verdict(delta), "cursorError": cursor_error})
        return latest if latest["verdict"]["passed"] else None

    try:
        wait_for("wearer-close", probe, Budget(seconds=settle_seconds + 10.0, provenance="wearer close settle " + str(settle_seconds) + "s + 10s slack"), observe=lambda: [dict(latest["verdict"])], record=instruments.record_wait_sample)
    except InstrumentFault as fault:
        if fault.kind != "wait-expired":
            raise
    delta = list(latest["delta"])
    (evidence_directory / "wearer-close-probe.log").write_text("\n".join(delta) + ("\n" if delta else ""), encoding="utf-8")
    verdict = dict(latest["verdict"])
    verdict["stage"] = "verdict"
    verdict["cursorError"] = latest["cursorError"]
    verdict["item"] = item
    return verdict


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--item", default=DEFAULT_ITEM)
    parser.add_argument("--evidence-dir", type=Path, default=None)
    parser.add_argument("--settle-seconds", type=float, default=5.0)
    arguments = parser.parse_args()
    evidence_directory = (arguments.evidence_dir or matrix.default_evidence_directory() / "wearer-close").expanduser().resolve()
    evidence_directory.mkdir(parents=True, exist_ok=True)
    try:
        result = run(item=arguments.item, evidence_directory=evidence_directory, settle_seconds=arguments.settle_seconds)
    except InstrumentFault as fault:
        result = {"passed": False, "stage": "instrument", "kind": fault.kind, "evidence": fault.evidence}
    (evidence_directory / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
