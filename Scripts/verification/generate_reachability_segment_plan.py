#!/usr/bin/env python3

"""Generate the reachability matrix's segment plan from the inventory.

A segment plan says which proof contexts each run drives, which scenarios it
runs, and which cells it decides. Hand-writing it rots: the last one committed
covered 78 of the 221 cells the inventory now derives and named five operations
that have since been renamed, so the matrix could not be driven to completion at
all. The inventory is generated from product source on every run, so the plan
that partitions it should be generated too.

Two modes, because only half the plan can be derived without driving anything:

    probe   One segment per proof context, running every scenario mapped to that
            context, declaring every cell the inventory derives for it. Its
            purpose is to record what each scenario actually drives.

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


def scenario_context(scenario: str) -> str:
    for prefix, context in sorted(CONTEXT_PREFIXES, key=lambda p: -len(p[0])):
        if scenario == prefix or scenario.startswith(prefix + "-"):
            return context
    return BROWSER_CONTEXT


def inventory_cells() -> dict[str, set[str]]:
    document = json.loads(INVENTORY.read_text(encoding="utf-8"))
    cells: dict[str, set[str]] = {}
    for operation in document["operations"]:
        for context in matrix.product_proof_contexts(operation):
            cells.setdefault(str(context), set()).add(str(operation["id"]))
    return cells


def scenarios_by_context() -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {}
    for scenario in sorted(matrix.SEGMENT_SCENARIO_NAMES):
        grouped.setdefault(scenario_context(scenario), []).append(scenario)
    return grouped


def probe_plan() -> dict:
    cells = inventory_cells()
    grouped = scenarios_by_context()
    fault_ops = {
        "accessibility:PlayerPanel-button-settings",
        "accessibility:PlayerPanel-DockedPlacement-reset",
        "accessibility:PlayerPanel-media-information",
        "accessibility:PlayerPanel-media-information-close",
    }
    segments = []
    for context, scenarios in sorted(grouped.items()):
        operations = sorted(cells.get(context, ()))
        if not operations or not scenarios:
            continue
        if context == "docked":
            main_ops = [op for op in operations if op not in fault_ops]
            fault_decisions = [op for op in operations if op in fault_ops]
            docked_scenarios = [s for s in scenarios if s != "docked-reset-media-information"]
            fault_scenarios = ["docked-reset-media-information"]
            if main_ops and docked_scenarios:
                segments.append({
                    "id": "probe-docked",
                    "context": context,
                    "expectedMaximumSteps": 100,
                    "scenarios": docked_scenarios,
                    "decisions": [
                        {"context": context, "operation": operation}
                        for operation in main_ops
                    ],
                })
            if fault_decisions and fault_scenarios:
                segments.append({
                    "id": "probe-docked-reset-media-information",
                    "context": context,
                    "expectedMaximumSteps": 100,
                    "scenarios": fault_scenarios,
                    "decisions": [
                        {"context": context, "operation": operation}
                        for operation in fault_decisions
                    ],
                })
            continue
        segments.append({
            "id": f"probe-{context}",
            "context": context,
            "expectedMaximumSteps": 100,
            "scenarios": scenarios,
            "decisions": [
                {"context": context, "operation": operation}
                for operation in operations
            ],
        })
    ordered = []
    for seg in segments:
        if seg["id"] == "probe-docked-reset-media-information":
            continue
        ordered.append(seg)
        if seg["id"] == "probe-docked":
            for cand in segments:
                if cand["id"] == "probe-docked-reset-media-information":
                    ordered.append(cand)
    return {"segments": ordered}


def driven_by_segment(results: list[Path]) -> dict[str, set[tuple[str, str]]]:
    driven: dict[str, set[tuple[str, str]]] = {}
    for path in results:
        document = json.loads(path.read_text(encoding="utf-8"))
        name = str(document.get("segment") or path.stem)
        driven[name] = {
            (str(cell["context"]), str(cell["operation"]))
            for cell in document.get("drivenCells", [])
            if isinstance(cell, dict)
        }
    return driven


def final_plan(results: list[Path], steps: int) -> tuple[dict, list[tuple[str, str]]]:
    cells = inventory_cells()
    wanted = {(context, operation)
              for context, operations in cells.items()
              for operation in operations}
    driven = driven_by_segment(results)
    claimed: set[tuple[str, str]] = set()
    segments = []
    for name, keys in sorted(driven.items()):
        context = name.removeprefix("probe-")
        decisions = sorted((keys & wanted) - claimed)
        if not decisions:
            continue
        claimed.update(decisions)
        segments.append({
            "id": name.removeprefix("probe-") + "-driven",
            "context": context,
            "expectedMaximumSteps": steps,
            "scenarios": scenarios_by_context().get(context, []),
            "decisions": [
                {"context": cell_context, "operation": operation}
                for cell_context, operation in decisions
            ],
        })
    return {"segments": segments}, sorted(wanted - claimed)


def validate(plan: dict) -> list[str]:
    document = json.loads(INVENTORY.read_text(encoding="utf-8"))
    return matrix.validate_segment_plan(
        plan,
        operation_contexts={
            str(operation["id"]): {
                str(context) for context in matrix.product_proof_contexts(operation)
            }
            for operation in document["operations"]
        },
        scenario_names=matrix.SEGMENT_SCENARIO_NAMES,
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
        "decisions": sum(len(segment["decisions"]) for segment in plan["segments"]),
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
