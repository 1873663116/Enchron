#!/usr/bin/env python3
"""Make the episode-switch Scenarios follow the content-family rule.

A panoramic episode selected while docked now leaves the dock and lands in
portal, and every episode switch driven inside a Scenario captures frames,
because the 2026-09-08 black screen with audio satisfied the accessibility
tree and the window control plane. The docked Scenario is rewritten to await
the portal landing and capture frames; two new main-window Scenarios switch
from a flat episode to a panoramic one and back.

Mutates `Config/regression/catalog-v2.json` in place: load, mutate, recompute
`contentDigest`, write back with sorted keys.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT = ROOT / "Config/regression/catalog-v2.json"

JOURNEY_ID = "journey:presentation-tour"
JOURNEY_SLUG = "presentation-tour"
FLAT_ITEM = "sdr-bframe-multiaudio-avsync-120s.mp4"
PANORAMIC_ITEM = "180_3D.mp4"

CONTRACT_BODY = (
    "Each ordered static case is an independent attempt. Evidence from "
    "another case, Scenario, lane, or attempt is inadmissible. Readiness "
    "records whether the approved Operation registry can execute the "
    "complete claim; prerequisite Preparation readiness is reported "
    "separately."
)


def item(catalog: dict[str, Any], collection: str, identifier: str) -> dict[str, Any]:
    return next(value for value in catalog[collection] if value["id"] == identifier)


def op_call(prefix: str, number: int, operation: str, arguments: dict[str, Any]) -> dict[str, Any]:
    return {
        "arguments": arguments,
        "callId": f"{prefix}:{number:02d}",
        "maxInvocations": 1,
        "operation": operation,
    }


def await_window(prefix: str, number: int, presentation: str) -> dict[str, Any]:
    return op_call(
        prefix, number, "operation:playback.await-window-state@1",
        {
            "controls": "either",
            "deadlineSeconds": 45,
            "lifecycle": "playing",
            "presentation": presentation,
        },
    )


def capture(prefix: str, number: int, context: str, after: int) -> dict[str, Any]:
    return op_call(
        prefix, number, "operation:evidence.capture-frames@1",
        {
            "context": context,
            "count": 3,
            "minimumIntervalMillis": 1000,
            "relatedResults": [f"result://{prefix}:{after:02d}/response"],
        },
    )


def select_episode(prefix: str, number: int, context: str, identifiers: list[str], label: str) -> dict[str, Any]:
    return op_call(
        prefix, number, "operation:accessibility.activate@2",
        {
            "context": context,
            "identifiers": identifiers,
            "labels": [label],
            "labelsAfterIdentifiers": True,
            "summonControls": True,
        },
    )


def control_plane_obligation(obligation_prefix: str, prefix: str, slug: str, index: int, call: int) -> dict[str, Any]:
    return {
        "artifactClass": "coverage",
        "caseKey": "default",
        "evidenceSchema": "window-control-plane@1",
        "evidenceType": "window.control-plane",
        "id": f"{obligation_prefix}:o{index:02d}:default",
        "oracle": "oracle:agent-structured-window-control-plane@1",
        "producedByCall": f"{prefix}:{call:02d}",
        "rubric": f"rubric:{JOURNEY_SLUG}.{slug}.o{index:02d}@{RUBRIC_VERSION[slug]}",
    }


def frames_obligation(obligation_prefix: str, prefix: str, slug: str, index: int, call: int) -> dict[str, Any]:
    return {
        "artifactClass": "coverage",
        "caseKey": "default",
        "evidenceSchema": "frame-sequence@2",
        "evidenceType": "visual.frames",
        "id": f"{obligation_prefix}:o{index:02d}:default",
        "oracle": "oracle:agent-visual@2",
        "producedByCall": f"{prefix}:{call:02d}",
        "rubric": f"rubric:{JOURNEY_SLUG}.{slug}.o{index:02d}@{RUBRIC_VERSION[slug]}",
    }


DOCKED_SLUG = "docked-episode-switch-settles-and-exits"
WINDOW_TO_PORTAL_SLUG = "window-episode-switch-lands-in-portal"
PORTAL_TO_WINDOW_SLUG = "portal-episode-switch-lands-in-window"
RUBRIC_VERSION = {DOCKED_SLUG: 2, WINDOW_TO_PORTAL_SLUG: 1, PORTAL_TO_WINDOW_SLUG: 1}


def landing_rubric(slug: str, index: int, *, call: int, selected: str, menu: str, context: str, landing: str, title: str) -> dict[str, Any]:
    version = RUBRIC_VERSION[slug]
    return {
        "criteria": [
            f"The window-control-plane snapshot produced by playback.await-window-state@1 (presentation={landing}, lifecycle=playing, controls=either, deadlineSeconds=45) at call {call:02d}, right after selecting {selected} from {menu} in context {context}, reports presentation={landing} and attached={landing}: the selected episode lands in the main-window cell of its own content family (docs/PLAYBACK_PRESENTATION_CONSTRAINTS.md, 换片时由内容族决定去向).",
            "fields.error equals none (MainView.swift:985, `error=\\(playbackRuntime.userVisibleIssue?.category.rawValue ?? \"none\")`) and lifecycle is playing, so the family change completed without a surfaced playback issue.",
        ],
        "filename": f"rubric-{JOURNEY_SLUG}-{slug}-o{index:02d}-{version}.md",
        "id": f"rubric:{JOURNEY_SLUG}.{slug}.o{index:02d}@{version}",
        "negativeControls": [
            "Controller success without the application-side window-control-plane delivery is not evidence of product behavior.",
            f"presentation or attached other than {landing}, a non-playing lifecycle, or a non-none fields.error fails the bound case; the 2026-09-08 escape stayed attached to the previous presentation with audio running.",
        ],
        "title": title,
    }


def frames_rubric(slug: str, index: int, *, call: int, awaited: int, context: str, regression: str, title: str) -> dict[str, Any]:
    version = RUBRIC_VERSION[slug]
    return {
        "criteria": [
            f"The producer requests exactly context {context}, count 3, minimumIntervalMillis 1000, and relatedResults naming call {awaited:02d}'s response, where call {awaited:02d} awaited the {context} window state right after the episode switch.",
            f"The producer returns exactly three indexed frames; every frame has a content-bound screenshot attachment, presentation is {context}, lifecycle is Playing, error is none, and adjacent capture times differ by at least 1000 ms.",
            f"No frame's screenshot is blank, pure-colour, or undecodable, and at least one frame's screenshotDigest differs from frame 0's; the regression this closes is {regression}, so uniform blankness across all three frames fails the claim regardless of the reported lifecycle.",
        ],
        "filename": f"rubric-{JOURNEY_SLUG}-{slug}-o{index:02d}-{version}.md",
        "id": f"rubric:{JOURNEY_SLUG}.{slug}.o{index:02d}@{version}",
        "negativeControls": [
            "A capture taken before the episode-menu activation, fewer than three frames, or a sub-1000 ms interval is Indeterminate, not Satisfied.",
            "A blank, pure-colour or undecodable screenshot at any index, three identical screenshots, a non-Playing lifecycle, or a non-none error fails the bound case.",
        ],
        "title": title,
    }


def rewrite_docked_scenario(catalog: dict[str, Any]) -> list[dict[str, Any]]:
    slug = DOCKED_SLUG
    scenario = item(catalog, "scenarios", f"scenario:{JOURNEY_SLUG}:{slug}")
    prefix = f"call:{JOURNEY_SLUG}:{slug}"
    obligation_prefix = f"obligation:{JOURNEY_SLUG}:{slug}"
    menu = "PlayerPanel-menu-more → PlayerPanel-menu-episodes"

    kept = scenario["operations"][:7]
    assert kept[5]["operation"] == "operation:accessibility.activate@2"
    assert kept[5]["arguments"]["labels"] == [PANORAMIC_ITEM]
    assert kept[6]["operation"] == "operation:harness.assert-channels@2"
    scenario["operations"] = kept + [
        await_window(prefix, 8, "portal"),
        capture(prefix, 9, "portal", after=8),
    ]
    scenario["obligations"] = [
        control_plane_obligation(obligation_prefix, prefix, slug, 1, 8),
        frames_obligation(obligation_prefix, prefix, slug, 2, 9),
    ]
    scenario["title"] = "Docked 内切换到全景剧集时退出 Dock 落到 portal"

    old_rubric_ids = {f"rubric:{JOURNEY_SLUG}.{slug}.o01@1", f"rubric:{JOURNEY_SLUG}.{slug}.o02@1"}
    catalog["rubrics"] = [rubric for rubric in catalog["rubrics"] if rubric["id"] not in old_rubric_ids]
    return [
        landing_rubric(
            slug, 1, call=8, selected=PANORAMIC_ITEM, menu=menu, context="docked", landing="portal",
            title="Docked Episode Switch Lands In Portal",
        ),
        frames_rubric(
            slug, 2, call=9, awaited=8, context="portal",
            regression="a black screen with audio after selecting a panoramic episode while docked",
            title="Docked Episode Switch Shows Pixels In Portal",
        ),
    ]


def switch_scenario(
    slug: str,
    *,
    title: str,
    opened: str,
    opened_landing: str,
    selected: str,
    select_context: str,
    landing: str,
    landing_title: str,
    frames_title: str,
    regression: str,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    scenario_id = f"scenario:{JOURNEY_SLUG}:{slug}"
    prefix = f"call:{JOURNEY_SLUG}:{slug}"
    obligation_prefix = f"obligation:{JOURNEY_SLUG}:{slug}"
    identifiers = ["PlayerUI-TopAction-more", "PlayerUI-menu-episodes"]
    menu = "PlayerUI-TopAction-more → PlayerUI-menu-episodes"

    operations = [
        op_call(prefix, 1, "operation:app.relaunch@1", {}),
        op_call(prefix, 2, "operation:navigation.select-tab@1", {"tab": "files"}),
        op_call(
            prefix, 3, "operation:media.open@2",
            {
                "deadlineSeconds": 45,
                "expectedLanding": "either-main-window",
                "identifier": f"MediaLibrary-grid-video-{opened}",
            },
        ),
        await_window(prefix, 4, opened_landing),
        select_episode(prefix, 5, select_context, identifiers, selected),
        op_call(prefix, 6, "operation:harness.assert-channels@2", {}),
        await_window(prefix, 7, landing),
        capture(prefix, 8, landing, after=7),
    ]
    obligations = [
        control_plane_obligation(obligation_prefix, prefix, slug, 1, 7),
        frames_obligation(obligation_prefix, prefix, slug, 2, 8),
    ]
    scenario = {
        "applicability": {
            "factEquals": {"fact": "fact:runtime.catalog-scope-included", "value": True}
        },
        "blockers": [],
        "contract": CONTRACT_BODY,
        "estimatedCostMillis": 200000,
        "id": scenario_id,
        "journey": JOURNEY_ID,
        "lane": "device",
        "mainGateFor": [],
        "obligations": obligations,
        "operations": operations,
        "prerequisites": [
            {"key": "presentation-fixtures-ready", "schema": "fixture-set.presentation-tour@2"}
        ],
        "promiseRefs": ["promise:mode-transitions:c02"],
        "readiness": "ready",
        "staticCases": ["default"],
        "success": {
            "all": [{"observation": obligation["id"]} for obligation in obligations]
        },
        "title": title,
    }
    rubrics = [
        landing_rubric(
            slug, 1, call=7, selected=selected, menu=menu, context=select_context, landing=landing,
            title=landing_title,
        ),
        frames_rubric(slug, 2, call=8, awaited=7, context=landing, regression=regression, title=frames_title),
    ]
    return scenario, rubrics


def build_window_to_portal_scenario() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return switch_scenario(
        WINDOW_TO_PORTAL_SLUG,
        title="窗口内切换到全景剧集时翻到 portal",
        opened=FLAT_ITEM,
        opened_landing="window",
        selected=PANORAMIC_ITEM,
        select_context="window",
        landing="portal",
        landing_title="Window Episode Switch To A Panoramic Episode Lands In Portal",
        frames_title="Window To Portal Episode Switch Shows Pixels",
        regression="a stale flat surface after switching to a panoramic episode from the window",
    )


def build_portal_to_window_scenario() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return switch_scenario(
        PORTAL_TO_WINDOW_SLUG,
        title="portal 内切换到平面剧集时翻回 window",
        opened=PANORAMIC_ITEM,
        opened_landing="portal",
        selected=FLAT_ITEM,
        select_context="portal",
        landing="window",
        landing_title="Portal Episode Switch To A Flat Episode Lands In Window",
        frames_title="Portal To Window Episode Switch Shows Pixels",
        regression="a stale panoramic surface after switching to a flat episode from portal",
    )


def main() -> None:
    catalog = json.loads(BLUEPRINT.read_text(encoding="utf-8"))
    rubric_count_before = len(catalog["rubrics"])

    new_rubrics = rewrite_docked_scenario(catalog)
    new_scenarios: list[dict[str, Any]] = []
    for builder in (build_window_to_portal_scenario, build_portal_to_window_scenario):
        scenario, rubrics = builder()
        assert not any(existing["id"] == scenario["id"] for existing in catalog["scenarios"]), scenario["id"]
        new_scenarios.append(scenario)
        new_rubrics.extend(rubrics)

    catalog["scenarios"].extend(new_scenarios)
    catalog["rubrics"].extend(new_rubrics)
    item(catalog, "journeys", JOURNEY_ID)["scenarioRefs"].extend(scenario["id"] for scenario in new_scenarios)

    counts = catalog["expectedCounts"]
    counts["scenarios"] += len(new_scenarios)
    counts["rubrics"] += len(catalog["rubrics"]) - rubric_count_before
    counts["staticCases"] += sum(len(scenario["staticCases"]) for scenario in new_scenarios)

    payload = dict(catalog)
    payload.pop("contentDigest", None)
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    catalog["contentDigest"] = "sha256:" + hashlib.sha256(canonical).hexdigest()
    BLUEPRINT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"rewrote 1 scenario, added {len(new_scenarios)} scenarios, rubrics {rubric_count_before} -> {len(catalog['rubrics'])}")


if __name__ == "__main__":
    main()
