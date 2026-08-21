#!/usr/bin/env python3

"""Walk the presentation graph at random and see whether anything wedges.

playback_mode_matrix runs fixed paths, which is what you want when you are
asking whether a named transition still works. It cannot answer the other
question: whether some order nobody wrote down leaves playback stuck. This
walks the same action graph in a seeded random order for as long as you ask,
and every hop is judged by the matrix's own settle and pixel gates, so a hop
passes only when the product reports a steady presentation and the screen
then shows moving, non-black content.

The seed is printed and recorded. A walk that finds something is replayable.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import random
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

from presentation_model import (  # noqa: E402
    CONTENT_FAMILY,
    FLAT,
    PANORAMIC,
    lands_in_main_window,
)
from playback_mode_matrix import (  # noqa: E402
    APPLY_360_MONO,
    APPLY_FLAT_MONO,
    APPLY_NATIVE_180,
    DEFAULT_EVIDENCE_ROOT,
    DRIVE_ERROR,
    OPEN_CLIP,
    PASSING_VERDICTS,
    STEREO_LABELS,
    Step,
    apply_visual_gate,
    clean_state_preamble,
    controller,
    controller_summary,
    copy_probe_lines,
    run_step,
    safe_component,
    wait_for_clean_open,
)


SURFACE = "PlayerUI-window-playback-surface"
# The window column is live in window and portal, so its chrome has to be
# summoned before the format menu will accept a tap. In an immersive
# presentation the window is already empty and the surface tap has nothing
# to hit.
CHROME_HOSTS = ("window", "portal")

# Projection only changes in the main window column, so the immersive cells
# offer nothing but the way out. apply-flat from panorama was a diagonal.
LEGAL_MOVES: dict[str, tuple[str, ...]] = {
    "window": ("apply-flat", "apply-180", "apply-360", "enter-docked"),
    "portal": ("apply-flat", "apply-180", "apply-360", "enter-panorama"),
    "panorama": ("exit-spatial",),
    "docked": ("exit-spatial",),
}


def build_step(move: str, presentation: str, clip: str) -> Step:
    prefix = (SURFACE,) if presentation in CHROME_HOSTS else ()
    stereo = STEREO_LABELS.get(clip, "Side-by-Side")
    if move == "apply-flat":
        return Step("apply-flat", (*prefix, *APPLY_FLAT_MONO), lands_in_main_window(FLAT))
    if move == "apply-180":
        actions = tuple(
            action.replace("{stereo_label}", stereo) for action in APPLY_NATIVE_180
        )
        return Step("apply-180", (*prefix, *actions), lands_in_main_window(PANORAMIC))
    if move == "apply-360":
        return Step("apply-360", (*prefix, *APPLY_360_MONO), lands_in_main_window(PANORAMIC))
    if move == "enter-docked":
        return Step(
            "enter-docked",
            (*prefix, "PlayerUI-TopAction-dock", "PlayerUI-DockMenu-skybox"),
            "docked",
        )
    if move == "enter-panorama":
        return Step(
            "enter-panorama", ("summon:PlayerUI-TopAction-resumePanorama",), "panorama"
        )
    if move == "exit-spatial":
        target = lands_in_main_window(CONTENT_FAMILY[presentation])
        return Step("exit-spatial", ("summon:PlayerPanel-button-exit-spatial",), target)
    raise ValueError(f"unknown move {move}")


def open_clip(
    *, clip: str, cell_directory: Path, controller_directory: Path
) -> tuple[dict[str, object], int]:
    before, _ = copy_probe_lines(cell_directory)
    offset = len(before) if before is not None else 0
    started_at = time.monotonic()
    tap = controller(
        controller_directory,
        "tap",
        "--identifier",
        f"MediaLibrary-grid-video-{Path(clip).name}",
        "--no-screenshot",
    )
    if tap.get("success") is not True:
        return {
            "verdict": DRIVE_ERROR,
            "phase": "open",
            "controller": controller_summary(tap),
        }, offset
    result, delta = wait_for_clean_open(
        cell_directory=cell_directory,
        controller_directory=controller_directory,
        target_started_at=started_at,
        probe_offset=offset,
    )
    if result.get("verdict") in PASSING_VERDICTS:
        apply_visual_gate(result, controller_directory)
    result["name"] = "open"
    return result, offset + len(delta)


def walk_clip(
    *,
    clip: str,
    hops: int,
    rng: random.Random,
    media_root: Path,
    evidence: Path,
    controller_directory: Path,
    results_path: Path,
) -> bool:
    cell_directory = evidence / "walks" / safe_component(Path(clip).name)
    cell_directory.mkdir(parents=True, exist_ok=True)

    failure = clean_state_preamble(
        clip=clip, media_root=media_root, controller_directory=controller_directory
    )
    if failure is not None:
        record = {"clip": clip, "hop": 0, "verdict": DRIVE_ERROR, **failure}
        append(results_path, record)
        print(f"  preamble failed: {failure}", flush=True)
        return False

    result, offset = open_clip(
        clip=clip,
        cell_directory=cell_directory,
        controller_directory=controller_directory,
    )
    presentation = result.get("landed")
    append(results_path, {"clip": clip, "hop": 0, "move": "open", **result})
    print(
        f"  hop 0 open -> {presentation} {result.get('verdict')}",
        flush=True,
    )
    if result.get("verdict") not in PASSING_VERDICTS or presentation not in LEGAL_MOVES:
        return False

    for hop in range(1, hops + 1):
        move = rng.choice(LEGAL_MOVES[presentation])
        step = build_step(move, presentation, Path(clip).name)
        step_result, offset = run_step(
            step=step,
            step_index=hop,
            clip=Path(clip).name,
            cell_directory=cell_directory,
            controller_directory=controller_directory,
            probe_offset=offset,
        )
        verdict = step_result.get("verdict")
        visual = step_result.get("visual")
        visual_verdict = visual.get("verdict") if isinstance(visual, dict) else "-"
        append(
            results_path,
            {"clip": clip, "hop": hop, "move": move, "from": presentation, **step_result},
        )
        print(
            f"  hop {hop} {presentation} --{move}--> {step.expect_presentation}"
            f" {verdict} visual={visual_verdict}",
            flush=True,
        )
        if verdict not in PASSING_VERDICTS:
            return False
        presentation = step.expect_presentation
    return True


def append(results_path: Path, record: dict[str, object]) -> None:
    with results_path.open("a") as stream:
        stream.write(json.dumps(record, ensure_ascii=False, default=str) + "\n")


def run(arguments: argparse.Namespace) -> int:
    evidence = Path(arguments.evidence_dir)
    controller_directory = evidence / "session"
    controller_directory.mkdir(parents=True, exist_ok=True)
    results_path = evidence / "results.jsonl"

    session = controller(controller_directory, "ensure-session")
    if session.get("stage") != "ready":
        print(json.dumps({"stage": "ensure-session", **controller_summary(session)}))
        return 1
    print(f"session {session.get('sessionID')} ready, seed {arguments.seed}")

    rng = random.Random(arguments.seed)
    survived = 0
    for clip in arguments.clips:
        print(f"{clip}", flush=True)
        if walk_clip(
            clip=clip,
            hops=arguments.hops,
            rng=rng,
            media_root=Path(arguments.media_root),
            evidence=evidence,
            controller_directory=controller_directory,
            results_path=results_path,
        ):
            survived += 1

    total = len(arguments.clips)
    print(f"\n{survived}/{total} clips survived {arguments.hops} hops, seed {arguments.seed}")
    return 0 if survived == total else 2


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips", nargs="+", required=True)
    parser.add_argument("--media-root", required=True)
    parser.add_argument("--hops", type=int, default=12)
    parser.add_argument("--seed", type=int, default=20260814)
    parser.add_argument(
        "--evidence-dir", default=str(DEFAULT_EVIDENCE_ROOT / "transition-stress")
    )
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run(parse_arguments()))
