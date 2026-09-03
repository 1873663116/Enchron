#!/usr/bin/env python3

"""Generate the reachability matrix's segment plan from the inventory.

A segment plan says which proof contexts each run drives, which lane drives
it, which scenarios it runs, and which cells it decides. Hand-writing it rots:
the last one committed covered 78 of the 221 cells the inventory now derives
and named five operations that have since been renamed, so the matrix could
not be driven to completion at all. The inventory is generated from product
source on every run, so the plan that partitions it should be generated too.

The lane follows the scenarios. Opening media with a synthetic tap starves the
simulator's app main thread, so every scenario whose code reaches such a tap
(`reachability_matrix.SCENARIO_LANES`, derived from the harness source) runs
on the device lane; the browsing surface splits into a simulator segment for
the rest and a device segment for the openers. Player presentations always
need the device.

Two modes, because only half the plan can be derived without driving anything:

    probe   One segment per proof context and lane, running every scenario
            mapped to it, declaring every cell the inventory derives for it
            that the lane can drive. Its purpose is to record what each
            scenario actually drives.

    final   Reads the probe's segment results and emits a plan whose decisions
            are the cells that were driven, each assigned to exactly one
            segment. Cells no scenario reached are reported, not silently
            dropped: a cell with no segment is a hole in the baseline.

The scenario-to-context map below is a hypothesis taken from the scenario names
and the last committed plan. The probe settles it: a scenario mapped to the
wrong context drives nothing, and `report` names it.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/verification"))

from harness import lane_partition  # noqa: E402
import reachability_matrix as matrix  # noqa: E402

INVENTORY = REPOSITORY_ROOT / "Config/reachability_operation_inventory.json"

CONTEXT_PREFIXES = (
    ("docked", "docked"),
    ("panorama", "panorama"),
    ("portal", "portal"),
    ("player-panel-portal", "portal"),
    ("window", "window"),
)
"""Longest prefix wins; anything unmatched belongs to the browsing surface."""

BROWSER_CONTEXT = "main-window-browser"
BROWSER_SEGMENT = "probe-main-window-browser"
BROWSER_PLAYBACK_SEGMENT = "probe-main-window-browser-playback"
DOCKED_SEGMENT = "probe-docked"
DOCKED_RESET_SEGMENT = "probe-docked-reset-media-information"
DOCKED_RESET_SCENARIO = "docked-reset-media-information"
DOCKED_RESET_OPERATIONS = {
    "accessibility:PlayerPanel-button-settings",
    "accessibility:PlayerPanel-DockedPlacement-reset",
    "accessibility:PlayerPanel-media-information",
    "accessibility:PlayerPanel-media-information-close",
}


def scenario_context(scenario: str) -> str:
    for prefix, context in sorted(CONTEXT_PREFIXES, key=lambda p: -len(p[0])):
        if scenario == prefix or scenario.startswith(prefix + "-"):
            return context
    return BROWSER_CONTEXT


def inventory_operations() -> dict[str, dict]:
    document = json.loads(INVENTORY.read_text(encoding="utf-8"))
    return {str(operation["id"]): operation for operation in document["operations"]}


def inventory_cells() -> dict[str, set[str]]:
    cells: dict[str, set[str]] = {}
    for identifier, operation in inventory_operations().items():
        for context in matrix.product_proof_contexts(operation):
            cells.setdefault(str(context), set()).add(identifier)
    return cells


def scenarios_by_context() -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {}
    for scenario in sorted(matrix.SEGMENT_SCENARIO_NAMES):
        grouped.setdefault(scenario_context(scenario), []).append(scenario)
    return grouped


def segment(
    identifier: str,
    context: str,
    scenarios: list[str],
    operations: list[str],
    steps: int = 100,
) -> dict:
    return {
        "id": identifier,
        "context": context,
        "lane": matrix.segment_lane(context, scenarios),
        "expectedMaximumSteps": steps,
        "scenarios": scenarios,
        "decisions": [
            {"context": context, "operation": operation}
            for operation in operations
        ],
    }


def browser_segments(
    scenarios: list[str], operations: list[str], by_id: dict[str, dict]
) -> list[dict]:
    browse = [
        name for name in scenarios
        if matrix.SCENARIO_LANES[name] == lane_partition.SIMULATOR
    ]
    playback = [
        name for name in scenarios
        if matrix.SCENARIO_LANES[name] == lane_partition.DEVICE
    ]
    browse_operations = [
        operation for operation in operations
        if not lane_partition.opens_playback(by_id[operation])
    ]
    segments = []
    if browse and browse_operations:
        segments.append(
            segment(BROWSER_SEGMENT, BROWSER_CONTEXT, browse, browse_operations)
        )
    if playback:
        segments.append(
            segment(BROWSER_PLAYBACK_SEGMENT, BROWSER_CONTEXT, playback, operations)
        )
    return segments


def docked_segments(scenarios: list[str], operations: list[str]) -> list[dict]:
    main_operations = [op for op in operations if op not in DOCKED_RESET_OPERATIONS]
    reset_operations = [op for op in operations if op in DOCKED_RESET_OPERATIONS]
    main_scenarios = [name for name in scenarios if name != DOCKED_RESET_SCENARIO]
    segments = []
    if main_operations and main_scenarios:
        segments.append(
            segment(DOCKED_SEGMENT, "docked", main_scenarios, main_operations)
        )
    if reset_operations and DOCKED_RESET_SCENARIO in scenarios:
        segments.append(
            segment(
                DOCKED_RESET_SEGMENT,
                "docked",
                [DOCKED_RESET_SCENARIO],
                reset_operations,
            )
        )
    return segments


def probe_plan() -> dict:
    by_id = inventory_operations()
    cells = inventory_cells()
    grouped = scenarios_by_context()
    segments: list[dict] = []
    for context, scenarios in sorted(grouped.items()):
        operations = sorted(cells.get(context, ()))
        if not operations or not scenarios:
            continue
        if context == "docked":
            segments.extend(docked_segments(scenarios, operations))
        elif context == BROWSER_CONTEXT:
            segments.extend(browser_segments(scenarios, operations, by_id))
        else:
            segments.append(segment(f"probe-{context}", context, scenarios, operations))
    return {"segments": segments}


def probe_results(results: list[Path]) -> dict[str, dict]:
    probed: dict[str, dict] = {}
    for path in results:
        document = json.loads(path.read_text(encoding="utf-8"))
        name = str(document.get("segment") or path.stem)
        planned = document["segmentPlan"]
        probed[name] = {
            "context": str(planned["context"]),
            "scenarios": [str(value) for value in planned["scenarios"]],
            "driven": {
                (str(cell["context"]), str(cell["operation"]))
                for cell in document.get("drivenCells", [])
                if isinstance(cell, dict)
            },
        }
    return probed


def final_plan(results: list[Path], steps: int) -> tuple[dict, list[tuple[str, str]]]:
    cells = inventory_cells()
    wanted = {(context, operation)
              for context, operations in cells.items()
              for operation in operations}
    claimed: set[tuple[str, str]] = set()
    segments = []
    for name, probed in sorted(probe_results(results).items()):
        decisions = sorted((probed["driven"] & wanted) - claimed)
        if not decisions:
            continue
        claimed.update(decisions)
        context = probed["context"]
        entry = segment(
            name.removeprefix("probe-") + "-driven",
            context,
            probed["scenarios"],
            [],
            steps,
        )
        entry["decisions"] = [
            {"context": cell_context, "operation": operation}
            for cell_context, operation in decisions
        ]
        segments.append(entry)
    return {"segments": segments}, sorted(wanted - claimed)


def validate(plan: dict) -> list[str]:
    return matrix.validate_segment_plan(
        plan,
        operation_contexts={
            identifier: {
                str(context) for context in matrix.product_proof_contexts(operation)
            }
            for identifier, operation in inventory_operations().items()
        },
        scenario_names=matrix.SEGMENT_SCENARIO_NAMES,
        scenario_lanes=matrix.SCENARIO_LANES,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("probe", "final", "report"), required=True)
    parser.add_argument("--results", nargs="*", type=Path, default=[])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-maximum-steps", type=int, default=100)
    arguments = parser.parse_args()

    if arguments.mode == "probe":
        plan, uncovered = probe_plan(), []
    else:
        if not arguments.results:
            print("--results is required outside probe mode", file=sys.stderr)
            return 2
        plan, uncovered = final_plan(arguments.results, arguments.expected_maximum_steps)

    errors = validate(plan)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    summary = {
        "mode": arguments.mode,
        "segments": len(plan["segments"]),
        "lanes": {
            str(entry["id"]): str(entry["lane"]) for entry in plan["segments"]
        },
        "decisions": sum(len(entry["decisions"]) for entry in plan["segments"]),
        "inventoryCells": sum(len(operations) for operations in inventory_cells().values()),
        "uncovered": [
            {"context": context, "operation": operation}
            for context, operation in uncovered
        ],
    }
    if arguments.mode == "report":
        print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    if arguments.output:
        arguments.output.write_text(
            json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
