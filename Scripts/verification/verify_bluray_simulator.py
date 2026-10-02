#!/usr/bin/env python3
"""Drive one reviewed Blu-ray Scenario through the compiled Operation gateway.

No direct UI controller calls occur here. This tool checks raw Operation results;
the Regression Oracle, verdict and merge receipt remain separate review steps.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
if str(ROOT / "Scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "Scripts"))

from Scripts.regression.core.contracts import BoundLane
from Scripts.regression.core.plan import ScenarioAttemptNode
from Scripts.regression.core.runtime import open_run
from Scripts.regression.runctl import compile_execution_plan
from Scripts.regression.tools.pixel_heuristics import all_black
from Scripts.regression.tools.raster import decode_png
from Scripts.verification.prepare_bluray_supplement import CASES
from Scripts.verification.verify_bluray_corpus import parse_mpls


CORPUS = ROOT.parent / "TestMedia/Samples/DiscImages"
CASES_BY_SCENARIO = {f"scenario:bluray-disc:{case[0]}": case for case in CASES}


class BluRayE2EError(ValueError):
    pass


def _rendered_duration(seconds: float) -> str:
    total = int(seconds + 0.5)
    if total < 60:
        return f"{total} sec"
    minutes = total // 60
    return f"{minutes // 60} hr {minutes % 60} min" if minutes >= 60 else f"{minutes} min"


def _oracle(case: tuple, corpus: Path) -> tuple[int, dict[int, str]]:
    slug, _, _, _, playlist, expected_count, _ = case
    release, folder = (
        ("AVS-HD-709", "HDMV-2d") if slug.startswith("avs")
        else ("DolbyVision-Profile7-FEL", "FEL_test_for_AVS")
    )
    playlists = corpus / release / folder / "BDMV/PLAYLIST"
    authored = sorted(playlists.glob("*.mpls"))
    if len(authored) != expected_count:
        raise BluRayE2EError("authored playlist count differs from the registered corpus")
    ids = [playlist] + ([43] if slug.startswith("avs") else [])
    durations = {
        identifier: _rendered_duration(
            parse_mpls(playlists / f"{identifier:05d}.mpls")["duration90k"] / 90_000
        ) for identifier in ids
    }
    return len(authored), durations


def _result(document: dict) -> dict:
    if document.get("error"):
        raise BluRayE2EError(str(document["error"]))
    blocks = document.get("content")
    if not isinstance(blocks, list) or not blocks or blocks[0].get("type") != "text":
        raise BluRayE2EError("Operation gateway returned no typed text result")
    result = json.loads(blocks[0]["text"])
    if result.get("refused") or result.get("succeeded") is not True:
        raise BluRayE2EError(f"Operation failed or was refused: {result}")
    return result


def _matched_label(fields: dict) -> str:
    matched = fields.get("matchedElement")
    if not isinstance(matched, dict):
        raise BluRayE2EError("Accessibility result has no matched element")
    return " ".join(
        value for value in (matched.get("label"), matched.get("value"))
        if isinstance(value, str)
    )


def _screenshot(frame: dict) -> bytes:
    record = frame.get("record")
    if not isinstance(record, dict):
        raise BluRayE2EError("Frame has no controller record")
    candidate = next((record.get(key) for key in (
        "localScreenshotPath", "screenshotPath", "screenshot"
    ) if isinstance(record.get(key), str)), None)
    if candidate is None:
        raise BluRayE2EError("Frame has no screenshot path")
    path = Path(candidate)
    if path.is_symlink() or not path.is_file():
        raise BluRayE2EError("Frame screenshot is missing or a symlink")
    return path.read_bytes()


def verify_transcript(transcript: dict, corpus: Path = CORPUS) -> dict:
    scenario = transcript.get("scenario")
    case = CASES_BY_SCENARIO.get(scenario)
    if case is None:
        raise BluRayE2EError("Transcript scenario is not a registered Blu-ray case")
    _, _, _, _, selected_id, _, _ = case
    count, durations = _oracle(case, corpus)
    outcomes = transcript.get("outcomes")
    if not isinstance(outcomes, list):
        raise BluRayE2EError("Transcript has no Operation outcomes")
    counts: list[str] = []
    title_labels: dict[int, list[str]] = {identifier: [] for identifier in durations}
    selections: list[str] = []
    captured: list[dict] = []
    real_tap_ids: list[str] = []
    for outcome in outcomes:
        if outcome.get("succeeded") is not True or outcome.get("refused"):
            raise BluRayE2EError("Transcript contains a failed or refused Operation")
        operation = outcome.get("operation")
        fields = outcome.get("fields")
        if not isinstance(fields, dict):
            raise BluRayE2EError("Operation has no fields")
        if operation == "operation:accessibility.activate@2":
            real_tap_ids.extend(outcome.get("arguments", {}).get("identifiers", []))
        elif operation == "operation:media.open@2":
            real_tap_ids.append(outcome.get("arguments", {}).get("identifier", ""))
        elif operation == "operation:accessibility.inspect@2":
            identifier = fields.get("requestedIdentifier")
            label = _matched_label(fields)
            if identifier == "FileBrowsing-FilesScreen-itemCount":
                counts.append(label)
            for title_id in durations:
                if identifier == f"FileBrowsing-grid-bluray-playlist-{title_id}":
                    title_labels[title_id].append(label)
        elif operation == "operation:diagnostics.playback-state@1":
            state = fields.get("fields")
            if not isinstance(state, dict):
                raise BluRayE2EError("Playback diagnostic has no state fields")
            selections.append(str(state.get("bluRayPlaylistID")))
        elif operation == "operation:evidence.capture-frames@1":
            captured.extend(fields.get("frames", []))
    expected_count_reads = 2 if case[3].endswith(".iso") is False else 1
    if len(counts) < expected_count_reads or any(f"{count} items" not in item for item in counts):
        raise BluRayE2EError(f"Title count mismatch: expected {count} twice for BDMV parent/self, got {counts}")
    for title_id, duration in durations.items():
        labels = title_labels[title_id]
        required_reads = expected_count_reads if title_id == selected_id else 1
        if len(labels) < required_reads or any(
            f"Playlist ID {title_id}" not in label or f"Duration {duration}" not in label
            for label in labels
        ):
            raise BluRayE2EError(f"Title {title_id} label or authored duration mismatch: {labels}")
    selected_card = f"FileBrowsing-grid-bluray-playlist-{selected_id}"
    if selected_card not in real_tap_ids:
        raise BluRayE2EError("The selected title card was not tapped through the product")
    if selections != [str(selected_id)]:
        raise BluRayE2EError(f"Playback selected a different playlist: {selections}")
    if len(captured) != 3:
        raise BluRayE2EError("Three playback screenshots are required")
    image_hashes: set[str] = set()
    dimensions: list[list[int]] = []
    positions: list[float] = []
    for frame in captured:
        image = _screenshot(frame)
        raster = decode_png(image)
        if raster.degenerate or all_black(image) is not None:
            raise BluRayE2EError("Screenshot is 1x1 or all black")
        state = frame.get("playbackState", {}).get("fields", {})
        if str(state.get("bluRayPlaylistID")) != str(selected_id):
            raise BluRayE2EError("Screenshot belongs to another playlist")
        if state.get("displayedPixel") != "true" or int(state.get("videoSamples", "0")) < 1:
            raise BluRayE2EError("Screenshot has no decoded and displayed video sample")
        positions.append(float(state.get("position", "0")))
        dimensions.append([raster.width, raster.height])
        image_hashes.add(hashlib.sha256(image).hexdigest())
    if positions[-1] <= positions[0]:
        raise BluRayE2EError("Playback position did not advance across screenshots")
    if case[0].startswith("avs") and len(image_hashes) < 2:
        raise BluRayE2EError("AVS short H.264 title has no changing captured frame")
    return {
        "scenario": scenario,
        "playlistID": selected_id,
        "authoredTitleCount": count,
        "authoredRenderedDurations": durations,
        "screenshotDimensions": dimensions,
        "screenshotDigestCount": len(image_hashes),
        "scope": "same-attempt mechanical E2E evidence; no Regression verdict or merge receipt",
    }


def _run(arguments: argparse.Namespace) -> dict:
    scenario = arguments.scenario
    if scenario not in CASES_BY_SCENARIO:
        raise BluRayE2EError("Unknown supplemental Blu-ray Scenario")
    plan, _ = compile_execution_plan(
        ROOT, arguments.execution_input, arguments.catalog_root,
        arguments.policy, arguments.reviews_root, arguments.blueprint,
        requested_lane=BoundLane.SIMULATOR,
    )
    node = next((item for item in plan.nodes if isinstance(item, ScenarioAttemptNode)
                 and str(item.scenario_id) == scenario
                 and BoundLane.SIMULATOR in item.lane_candidates), None)
    if node is None:
        raise BluRayE2EError("Reviewed plan has no requested simulator Scenario")
    main = open_run(plan, arguments.run_directory)
    try:
        calls = main._call_sequence(node, BoundLane.SIMULATOR, main.view)
    finally:
        main.close()
    transcript = {"schema": "enchron.bluray.simulator-e2e/v1", "scenario": scenario, "outcomes": []}
    arguments.transcript.parent.mkdir(parents=True, exist_ok=True)
    try:
        for call in calls:
            command = [
                sys.executable, str(ROOT / "Scripts/regression/tools/server.py"),
                "--once", "op", "--repository-root", str(ROOT),
                "--execution-input", str(arguments.execution_input),
                "--catalog-root", str(arguments.catalog_root),
                "--policy", str(arguments.policy),
                "--reviews-root", str(arguments.reviews_root),
                "--blueprint", str(arguments.blueprint),
                "--run-directory", str(arguments.run_directory),
                "--node", str(node.id), "--call", str(call.call_id),
                "--lane", "simulator", "--requested-lane", "simulator",
                "--target", arguments.target, "--sidekick", "sidekick:bluray-simulator",
            ]
            completed = subprocess.run(command, capture_output=True, text=True, check=False)
            document = json.loads(completed.stdout)
            result = _result(document)
            transcript["outcomes"].append({
                **result, "operation": str(call.operation),
                "arguments": json.loads(call.arguments_bytes),
            })
            arguments.transcript.write_text(json.dumps(transcript, indent=2, sort_keys=True) + "\n")
            if completed.returncode != 0:
                raise BluRayE2EError(completed.stderr.strip() or "Operation gateway failed")
    finally:
        arguments.transcript.write_text(json.dumps(transcript, indent=2, sort_keys=True) + "\n")
    return verify_transcript(transcript, arguments.corpus)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", required=True, choices=sorted(CASES_BY_SCENARIO))
    parser.add_argument("--corpus", type=Path, default=CORPUS)
    parser.add_argument("--transcript", type=Path, required=True)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--execution-input", type=Path)
    parser.add_argument("--catalog-root", type=Path)
    parser.add_argument("--blueprint", type=Path)
    parser.add_argument("--policy", type=Path, default=ROOT / "Regression/review-policy.md")
    parser.add_argument("--reviews-root", type=Path)
    parser.add_argument("--run-directory", type=Path)
    parser.add_argument("--target")
    arguments = parser.parse_args()
    try:
        if arguments.run:
            if any(value is None for value in (
                arguments.execution_input, arguments.catalog_root, arguments.blueprint,
                arguments.reviews_root, arguments.run_directory, arguments.target,
            )):
                raise BluRayE2EError("--run requires reviewed Catalog, frozen input, run directory and simulator target")
            report = _run(arguments)
        else:
            report = verify_transcript(json.loads(arguments.transcript.read_text()), arguments.corpus)
    except (BluRayE2EError, OSError, KeyError, ValueError) as error:
        parser.exit(1, f"Blu-ray simulator verification failed: {error}\n")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
