#!/usr/bin/env python3
"""Build a segmented reachability regression plan from accepted device evidence."""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASELINE = ROOT / "Config/reachability_matrix_baseline.json"
CURRENT_SCENARIO_CATALOG = Path(__file__).resolve().with_name(
    "reachability_matrix.py"
)


@dataclass(frozen=True, order=True)
class CellKey:
    context: str
    operation: str


@dataclass(frozen=True)
class Route:
    context: str
    scenarios: tuple[str, ...]
    expected_maximum_steps: int
    source_segment: str
    source_result: Path


def segment_result_is_qualified(document: dict[str, Any]) -> bool:
    session_id = document.get("sessionID")
    health = document.get("channelHealth")
    before = health.get("before", {}) if isinstance(health, dict) else {}
    after = health.get("after", {}) if isinstance(health, dict) else {}
    continuity = document.get("channelContinuity")
    probe = document.get("probeJournal")
    return (
        document.get("status") == "complete"
        and isinstance(session_id, str)
        and bool(session_id)
        and before.get("passed") is True
        and after.get("passed") is True
        and before.get("sessionID") == session_id
        and after.get("sessionID") == session_id
        and (
            not isinstance(continuity, dict)
            or continuity.get("passed") is True
        )
        and (not isinstance(probe, dict) or probe.get("passed") is True)
    )


def route_from_result(path: Path, document: dict[str, Any]) -> Route | None:
    plan = document.get("segmentPlan")
    if not isinstance(plan, dict):
        return None
    scenarios = plan.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        return None
    context = str(plan.get("context", ""))
    source_segment = str(document.get("segment", plan.get("id", "")))
    expected_steps = plan.get("expectedMaximumSteps", 100)
    if not context or not source_segment or not isinstance(expected_steps, int):
        return None
    return Route(
        context=context,
        scenarios=tuple(str(value) for value in scenarios),
        expected_maximum_steps=min(100, max(1, expected_steps)),
        source_segment=source_segment,
        source_result=path.resolve(),
    )


def cell_keys(values: object) -> set[CellKey]:
    if not isinstance(values, list):
        return set()
    return {
        CellKey(str(value.get("context", "")), str(value.get("operation", "")))
        for value in values
        if isinstance(value, dict)
        and value.get("context")
        and value.get("operation")
    }


def collect_routes(
    result_paths: Iterable[Path],
) -> tuple[dict[CellKey, set[Route]], dict[CellKey, set[Route]]]:
    driven_routes: dict[CellKey, set[Route]] = defaultdict(set)
    planned_routes: dict[CellKey, set[Route]] = defaultdict(set)
    for path in sorted(set(result_paths)):
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(document, dict) or not segment_result_is_qualified(document):
            continue
        route = route_from_result(path, document)
        if route is None:
            continue
        for key in cell_keys(document.get("drivenCells")):
            driven_routes[key].add(route)
        plan = document.get("segmentPlan", {})
        for key in cell_keys(plan.get("decisions")):
            planned_routes[key].add(route)
    return driven_routes, planned_routes


def choose_route(key: CellKey, routes: set[Route]) -> Route:
    return min(
        routes,
        key=lambda route: (
            route.context != key.context,
            len(route.scenarios),
            route.scenarios,
            route.source_segment,
            str(route.source_result),
        ),
    )


def current_route_for_unmapped_cell(key: CellKey) -> Route | None:
    scenario: str | None = None
    if key == CellKey(
        "docked", "negative:immersive-resident-window"
    ):
        scenario = "docked-resident-window"
    elif key.context == "main-window-browser" and key.operation in {
        "accessibility:PlayerUI-resumeDecision-primary",
        "accessibility:PlayerUI-resumeDecision-secondary",
    }:
        scenario = "resume-decision"
    elif key.context == "portal" and key.operation in {
        "accessibility:PlayerUI-loadFailure-primary",
        "accessibility:PlayerUI-loadFailure-secondary",
        "accessibility:PlayerUI-playbackIssue-confirm",
        "accessibility:PlayerUI-unmetCapability-dismiss",
    }:
        scenario = "portal-issues-round11"
    elif key.context == "portal":
        scenario = "portal"
    elif key.context == "window" and key.operation.startswith(
        "accessibility:EnvironmentCard-"
    ):
        scenario = "window-environment-round11"
    elif key.context == "window" and key.operation in {
        "accessibility:PlayerUI-loadFailure-primary",
        "accessibility:PlayerUI-loadFailure-secondary",
    }:
        scenario = "playback-failures"
    elif key.context == "window":
        scenario = "window-playback"
    if scenario is None:
        return None
    return Route(
        context=key.context,
        scenarios=(scenario,),
        expected_maximum_steps=100,
        source_segment="current-scenario-catalog",
        source_result=CURRENT_SCENARIO_CATALOG,
    )


def current_route_for_additional_cell(key: CellKey) -> Route | None:
    scenarios = {
        CellKey(
            "docked", "accessibility:PlayerPanel-media-information-close"
        ): "docked-content-round11",
        CellKey(
            "docked", "accessibility:PlayerPanel-menu-audio"
        ): "docked-content-round11",
        CellKey(
            "docked", "accessibility:PlayerPanel-menu-episodes"
        ): "docked-content-round11",
        CellKey(
            "docked", "accessibility:PlayerPanel-button-exit-spatial"
        ): "docked-exit-command-round11",
        CellKey(
            "docked", "accessibility:PlayerPanel-DockedPlacement-back"
        ): "docked-reset-media-information",
        CellKey(
            "docked", "accessibility:PlayerPanel-precision-timeline-back"
        ): "docked-transport-issues",
        CellKey(
            "panorama", "accessibility:PlayerPanel-precision-timeline-back"
        ): "panorama",
    }
    scenario = scenarios.get(key)
    if scenario is None:
        return None
    return Route(
        context=key.context,
        scenarios=(scenario,),
        expected_maximum_steps=100,
        source_segment="current-additional-cell-route",
        source_result=CURRENT_SCENARIO_CATALOG,
    )


def slug(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return cleaned or "segment"


def build_plan(
    *,
    baseline: dict[str, Any],
    driven_routes: dict[CellKey, set[Route]],
    planned_routes: dict[CellKey, set[Route]],
    additional_cells: set[CellKey],
) -> dict[str, Any]:
    required = {
        CellKey(str(cell["context"]), str(cell["operation"]))
        for cell in baseline.get("cells", [])
        if isinstance(cell, dict) and cell.get("verdict") == "reachable"
    }
    required.update(additional_cells)

    selected: dict[CellKey, Route] = {}
    missing: list[CellKey] = []
    for key in sorted(required):
        current_additional = (
            current_route_for_additional_cell(key)
            if key in additional_cells else None
        )
        routes = {current_additional} if current_additional is not None else set()
        if not routes:
            routes = driven_routes.get(key, set())
        if not routes and key in additional_cells:
            routes = planned_routes.get(key, set())
        if not routes:
            current_route = current_route_for_unmapped_cell(key)
            if current_route is not None:
                routes = {current_route}
        if not routes:
            missing.append(key)
            continue
        selected[key] = choose_route(key, routes)
    if missing:
        detail = "\n".join(
            f"{key.context}\t{key.operation}" for key in missing
        )
        raise ValueError(f"No qualified historical route for:\n{detail}")

    grouped: dict[tuple[str, tuple[str, ...]], list[CellKey]] = defaultdict(list)
    route_metadata: dict[tuple[str, tuple[str, ...]], list[Route]] = defaultdict(list)
    for key, route in selected.items():
        group = (route.context, route.scenarios)
        grouped[group].append(key)
        route_metadata[group].append(route)

    segments: list[dict[str, Any]] = []
    for index, group in enumerate(sorted(grouped), start=1):
        context, scenarios = group
        routes = route_metadata[group]
        segments.append({
            "id": f"regression-{index:02d}-{slug(context)}-{slug('-'.join(scenarios))}",
            "context": context,
            "expectedMaximumSteps": max(
                route.expected_maximum_steps for route in routes
            ),
            "scenarios": list(scenarios),
            "decisions": [
                {"context": key.context, "operation": key.operation}
                for key in sorted(grouped[group])
            ],
            "historicalSources": sorted({
                str(route.source_result) for route in routes
            }),
        })

    return {
        "schemaVersion": 2,
        "delivery": "reachability-regression",
        "requiredReachableBaselineCells": sum(
            cell.get("verdict") == "reachable"
            for cell in baseline.get("cells", [])
            if isinstance(cell, dict)
        ),
        "additionalCells": [
            {"context": key.context, "operation": key.operation}
            for key in sorted(additional_cells)
        ],
        "segments": segments,
    }


def parse_cell(value: str) -> CellKey:
    context, separator, operation = value.partition(":")
    if not separator or not context or not operation:
        raise argparse.ArgumentTypeError(
            "cells must use CONTEXT:OPERATION"
        )
    return CellKey(context, operation)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument(
        "--evidence-root",
        type=Path,
        action="append",
        required=True,
        help="Recursively scan this directory for qualified results.json files.",
    )
    parser.add_argument(
        "--additional-cell",
        type=parse_cell,
        action="append",
        default=[],
        help="Also schedule a known-defect cell as CONTEXT:OPERATION.",
    )
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    result_paths = [
        path
        for root in arguments.evidence_root
        for path in root.rglob("results.json")
    ]
    driven_routes, planned_routes = collect_routes(result_paths)
    baseline = json.loads(arguments.baseline.read_text(encoding="utf-8"))
    plan = build_plan(
        baseline=baseline,
        driven_routes=driven_routes,
        planned_routes=planned_routes,
        additional_cells=set(arguments.additional_cell),
    )
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "output": str(arguments.output.resolve()),
        "segmentCount": len(plan["segments"]),
        "decisionCount": sum(
            len(segment["decisions"]) for segment in plan["segments"]
        ),
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
