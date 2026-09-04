#!/usr/bin/env python3

"""Prove every title in a media set opens and shows moving pixels.

playback_mode_matrix answers "does this clip survive every presentation
path", and pays for one automation session per cell to do it. This answers
the wider, shallower question: of a whole media set, which titles play at
all. One session covers the entire sweep, so a hundred titles cost about the
same setup as one matrix cell, while the clean-state preamble, the settle
judgment, and the two-screenshot luma and SSIM gate are the matrix's,
imported rather than restated.

A title passes only when the product's own settle judgment lands it in a
presentation and the pixels then read as neither black nor frozen.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

from playback_mode_matrix import (
    DEFAULT_EVIDENCE_ROOT,
    DRIVE_ERROR,
    PASSING_VERDICTS,
    apply_visual_gate,
    clean_state_preamble,
    controller,
    controller_summary,
    copy_probe_lines,
    safe_component,
    wait_for_clean_open,
)


def open_and_judge(
    *,
    name: str,
    title_directory: Path,
    controller_directory: Path,
) -> dict[str, object]:
    title_directory.mkdir(parents=True, exist_ok=True)
    before, _ = copy_probe_lines(title_directory)
    probe_offset = len(before) if before is not None else 0

    started_at = time.monotonic()
    tap = controller(
        controller_directory,
        "tap",
        "--identifier",
        f"MediaLibrary-grid-video-{name}",
        "--no-screenshot",
    )
    if tap.get("success") is not True:
        return {
            "verdict": DRIVE_ERROR,
            "phase": "open",
            "controller": controller_summary(tap),
        }

    result, delta = wait_for_clean_open(
        cell_directory=title_directory,
        controller_directory=controller_directory,
        target_started_at=started_at,
        probe_offset=probe_offset,
    )
    if result.get("verdict") in PASSING_VERDICTS:
        apply_visual_gate(result, controller_directory)
    (title_directory / "probe.log").write_text("\n".join(delta), encoding="utf-8")
    return result


def leave_immersive(landed: object, controller_directory: Path) -> None:
    """An immersive landing empties the main window, and the next clean
    preamble has to reach the library again.

    Only these two presentations. Trying the exit from anywhere else costs a
    thirty-second existence wait on a control that is not there and records
    an XCUITest failure, whose triage pass then slows every command that
    follows. The next clip's relaunch is what recovers an unknown state."""
    if landed not in ("panorama", "docked"):
        return
    controller(
        controller_directory,
        "tapSequence",
        "--identifiers",
        "PlayerPanel-button-exit-spatial",
        "--no-screenshot",
    )


def run_sweep(arguments: argparse.Namespace) -> int:
    evidence = Path(arguments.evidence_dir)
    controller_directory = evidence / "session"
    controller_directory.mkdir(parents=True, exist_ok=True)
    results_path = evidence / "results.jsonl"

    session = controller(controller_directory, "ensure-session")
    if session.get("stage") != "ready":
        print(json.dumps({"stage": "ensure-session", **controller_summary(session)}))
        return 1
    print(f"session {session.get('sessionID')} ready in {session.get('elapsedSeconds')}s")

    clips = [line.strip() for line in Path(arguments.clips_file).read_text().splitlines()]
    clips = [clip for clip in clips if clip and not clip.startswith("#")]
    if arguments.skip:
        clips = clips[arguments.skip:]
    if arguments.limit:
        clips = clips[: arguments.limit]

    media_root = Path(arguments.media_root)
    passed = failed = 0
    for index, clip in enumerate(clips, start=1):
        name = Path(clip).name
        record: dict[str, object] = {
            "index": index,
            "clip": clip,
            "name": name,
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        failure = clean_state_preamble(
            clip=clip,
            media_root=media_root,
            controller_directory=controller_directory,
        )
        if failure is not None:
            record.update({"verdict": DRIVE_ERROR, **failure})
        else:
            title_directory = evidence / "titles" / f"{index:03d}-{safe_component(name)}"
            record.update(
                open_and_judge(
                    name=name,
                    title_directory=title_directory,
                    controller_directory=controller_directory,
                )
            )
            leave_immersive(record.get("landed"), controller_directory)

        verdict = record.get("verdict")
        if verdict in PASSING_VERDICTS:
            passed += 1
        else:
            failed += 1
        with results_path.open("a") as stream:
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
        visual = record.get("visual")
        visual_verdict = visual.get("verdict") if isinstance(visual, dict) else "-"
        print(
            f"[{index}/{len(clips)}] {str(verdict):<14} {str(record.get('landed')):<16}"
            f" visual={str(visual_verdict):<12} {name}",
            flush=True,
        )

    print(f"\n{passed} passed, {failed} not passed, results in {results_path}")
    return 0 if failed == 0 else 2


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips-file", required=True)
    parser.add_argument("--media-root", required=True)
    parser.add_argument(
        "--evidence-dir", default=str(DEFAULT_EVIDENCE_ROOT / "source-sweep")
    )
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--skip", type=int, default=0)
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run_sweep(parse_arguments()))
