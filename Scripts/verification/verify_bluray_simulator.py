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
from Scripts.regression.tools import server as regression_server
from Scripts.regression.tools.pixel_heuristics import all_black
from Scripts.regression.tools.raster import decode_png
from Scripts.verification.prepare_bluray_supplement import CASES, BluRayCase
from Scripts.verification.verify_bluray_corpus import parse_mpls


CORPUS = ROOT.parent / "TestMedia/Samples/DiscImages"
CASES_BY_SCENARIO = {f"scenario:bluray-disc:{case.slug}": case for case in CASES}


class BluRayE2EError(ValueError):
    pass


def _rendered_duration(seconds: float) -> str:
    total = int(seconds + 0.5)
    if total < 60:
        return f"{total} sec"
    minutes = total // 60
    return f"{minutes // 60} hr {minutes % 60} min" if minutes >= 60 else f"{minutes} min"


def _oracle(case: BluRayCase, corpus: Path) -> tuple[int, dict[int, str]]:
    playlists = corpus / case.corpus_release / case.corpus_folder / "BDMV/PLAYLIST"
    authored = sorted(playlists.glob("*.mpls"))
    if len(authored) != case.authored_playlist_count:
        raise BluRayE2EError("authored playlist count differs from the registered corpus")
    ids = [case.selected_playlist] + [item[0] for item in case.companion_titles]
    durations = {
        identifier: _rendered_duration(
            parse_mpls(playlists / f"{identifier:05d}.mpls")["duration90k"] / 90_000
        ) for identifier in ids
    }
    return len(authored), durations


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
    selected_id = case.selected_playlist
    count, durations = _oracle(case, corpus)
    outcomes = transcript.get("outcomes")
    if not isinstance(outcomes, list):
        raise BluRayE2EError("Transcript has no Operation outcomes")
    counts: list[str] = []
    title_labels: dict[int, list[str]] = {identifier: [] for identifier in durations}
    selections: list[str] = []
    captured: list[dict] = []
    real_tap_ids: list[str] = []
    group_labels: dict[str, list[str]] = {kind: [] for kind, _ in case.group_counts}
    inspect_positions: dict[str, list[int]] = {}
    tap_positions: dict[str, list[int]] = {}
    selection_positions: list[int] = []
    frame_outcome_positions: list[int] = []
    for outcome_index, outcome in enumerate(outcomes):
        if outcome.get("succeeded") is not True or outcome.get("refused"):
            raise BluRayE2EError("Transcript contains a failed or refused Operation")
        operation = outcome.get("operation")
        fields = outcome.get("fields")
        if not isinstance(fields, dict):
            raise BluRayE2EError("Operation has no fields")
        if operation == "operation:accessibility.activate@2":
            for identifier in outcome.get("arguments", {}).get("identifiers", []):
                real_tap_ids.append(identifier)
                tap_positions.setdefault(identifier, []).append(outcome_index)
        elif operation == "operation:media.open@2":
            identifier = outcome.get("arguments", {}).get("identifier", "")
            if "grid-bluray-playlist" in identifier:
                raise BluRayE2EError("Old playlist card identifier cannot select projected content")
            real_tap_ids.append(identifier)
            tap_positions.setdefault(identifier, []).append(outcome_index)
        elif operation == "operation:accessibility.inspect@2":
            identifier = fields.get("requestedIdentifier")
            if isinstance(identifier, str) and "grid-bluray-playlist" in identifier:
                raise BluRayE2EError("Old playlist card identifier cannot prove projected content")
            label = _matched_label(fields)
            if "Playlist ID" in label:
                raise BluRayE2EError("Content label exposes a visible Playlist ID")
            if isinstance(identifier, str):
                inspect_positions.setdefault(identifier, []).append(outcome_index)
            if identifier == "FileBrowsing-FilesScreen-itemCount":
                counts.append(label)
            for kind in group_labels:
                if identifier == f"FileBrowsing-grid-bluray-group-{kind}":
                    group_labels[kind].append(label)
            for title_id in durations:
                if identifier == f"FileBrowsing-grid-bluray-content-{title_id}":
                    title_labels[title_id].append(label)
        elif operation == "operation:diagnostics.playback-state@1":
            state = fields.get("fields")
            if not isinstance(state, dict):
                raise BluRayE2EError("Playback diagnostic has no state fields")
            selections.append(str(state.get("bluRayPlaylistID")))
            selection_positions.append(outcome_index)
        elif operation == "operation:evidence.capture-frames@1":
            captured.extend(fields.get("frames", []))
            frame_outcome_positions.append(outcome_index)
    expected_counts = [case.root_item_count]
    if case.is_directory:
        expected_counts.append(case.root_item_count)
    if case.selected_group:
        expected_counts.append(dict(case.group_counts)[case.selected_group])
    if len(counts) != len(expected_counts) or any(
        f"{expected} items" not in observed
        for expected, observed in zip(expected_counts, counts)
    ):
        raise BluRayE2EError(
            f"Projected content count mismatch: expected {expected_counts}, got {counts}"
        )

    expected_group_reads = 2 if case.is_directory else 1
    for kind, expected_count in case.group_counts:
        labels = group_labels[kind]
        display_name = {
            "videos": "Videos",
            "sequences": "Sequences",
            "stillImages": "Still images",
            "additional": "Additional content",
        }[kind]
        if len(labels) != expected_group_reads or any(
            display_name not in label or f"{expected_count} items" not in label
            for label in labels
        ):
            raise BluRayE2EError(f"Projected {kind} group mismatch: {labels}")

    expected_titles = {
        case.selected_playlist: (case.selected_duration, case.selected_name),
        **{identifier: (duration, name)
           for identifier, duration, name in case.companion_titles},
    }
    for title_id, duration in durations.items():
        labels = title_labels[title_id]
        expected_duration, expected_name = expected_titles[title_id]
        if duration != expected_duration:
            raise BluRayE2EError(f"Authored duration oracle changed for content {title_id}")
        if len(labels) != 1 or any(
            expected_name not in label or f"Duration {duration}" not in label
            or "Playlist" in label for label in labels
        ):
            raise BluRayE2EError(f"Content {title_id} label or authored duration mismatch: {labels}")

    selected_card = f"FileBrowsing-grid-bluray-content-{selected_id}"
    if selected_card not in real_tap_ids:
        raise BluRayE2EError("The selected content card was not tapped through the product")
    selected_inspection = inspect_positions.get(selected_card, [])
    selected_tap = tap_positions.get(selected_card, [])
    if len(selected_inspection) != 1 or len(selected_tap) != 1 or selected_inspection[0] >= selected_tap[0]:
        raise BluRayE2EError("The selected content card was not inspected before playback")
    if case.selected_group:
        group_card = f"FileBrowsing-grid-bluray-group-{case.selected_group}"
        group_taps = tap_positions.get(group_card, [])
        if len(group_taps) != 1 or selected_inspection[0] < group_taps[0]:
            raise BluRayE2EError("Content was inspected before its content group was opened")
        count_positions = inspect_positions.get("FileBrowsing-FilesScreen-itemCount", [])
        if not count_positions or not group_taps[0] < count_positions[-1] < selected_inspection[0]:
            raise BluRayE2EError("Opened content group count was not verified before selection")
        for kind, _ in case.group_counts:
            group_id = f"FileBrowsing-grid-bluray-group-{kind}"
            positions = inspect_positions.get(group_id, [])
            if len(positions) != expected_group_reads or any(
                position > group_taps[0] for position in positions
            ):
                raise BluRayE2EError("Root content groups were not verified before selection")
    if case.is_directory:
        required = {"FileBrowsing-grid-bluray-browseFiles", "FileBrowsing-grid-folder-BDMV"}
        if not required.issubset(real_tap_ids):
            raise BluRayE2EError("BDMV parent/self traversal was not performed")
    if selections != [str(selected_id)]:
        raise BluRayE2EError(f"Playback selected a different playlist: {selections}")
    if len(selection_positions) != 1 or len(frame_outcome_positions) != 1 or not (
        selected_tap[0] < selection_positions[0] < frame_outcome_positions[0]
    ):
        raise BluRayE2EError("Playback diagnostics and screenshots are not from the selected attempt")
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
    if case.slug.startswith("avs") and len(image_hashes) < 2:
        raise BluRayE2EError("AVS short H.264 title has no changing captured frame")
    return {
        "scenario": scenario,
        "playlistID": selected_id,
        "authoredTitleCount": count,
        "authoredRenderedDurations": durations,
        "rootItemCounts": expected_counts,
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
            tool_result = regression_server.call_tool("op", {
                "repositoryRoot": str(ROOT),
                "executionInput": str(arguments.execution_input),
                "catalogRoot": str(arguments.catalog_root),
                "policy": str(arguments.policy),
                "reviewsRoot": str(arguments.reviews_root),
                "blueprint": str(arguments.blueprint),
                "runDirectory": str(arguments.run_directory),
                "node": str(node.id),
                "call": str(call.call_id),
                "lane": "simulator",
                "requestedLane": "simulator",
                "target": arguments.target,
                "sidekick": "sidekick:bluray-simulator",
            })
            result = dict(tool_result.json)
            if result.get("refused") or result.get("succeeded") is not True:
                raise BluRayE2EError(f"Operation failed or was refused: {result}")
            transcript["outcomes"].append({
                **result, "operation": str(call.operation),
                "arguments": json.loads(call.arguments_bytes),
            })
            arguments.transcript.write_text(json.dumps(transcript, indent=2, sort_keys=True) + "\n")
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
