#!/usr/bin/env python3
"""Add three Catalog v2 Scenarios closing this week's device escapes:

* selecting an episode while docked must relaunch onto a settled docked
  surface and exit cleanly (no stale screen entity, no exit failure);
* selecting an episode while in panorama must settle onto real pixels
  (not a black screen) and exit cleanly;
* opening an HLG file and entering docked must not retire the audio
  renderer.

Each new Scenario also inserts one `operation:harness.assert-channels@2`
call right after the presentation-switch settlement noise, so a probe
journal that overflowed or compacted during exactly that window fails the
attempt (see the companion fix in `regression_operation_adapter.py`).

This script mutates `Config/regression/catalog-v2.json` in place, matching
the existing `apply_round_four_catalog_fixes.py` / `apply_round_six_...`
convention: load, mutate the Python structure, recompute `contentDigest`,
write back with sorted keys.
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
AUDIO_JOURNEY_ID = "journey:dynamic-range-interpretation"
AUDIO_JOURNEY_SLUG = "dynamic-range-interpretation"


def item(catalog: dict[str, Any], collection: str, identifier: str) -> dict[str, Any]:
    return next(value for value in catalog[collection] if value["id"] == identifier)


def op_call(prefix: str, number: int, operation: str, arguments: dict[str, Any]) -> dict[str, Any]:
    return {
        "arguments": arguments,
        "callId": f"{prefix}:{number:02d}",
        "maxInvocations": 1,
        "operation": operation,
    }


CONTRACT_BODY = (
    "Each ordered static case is an independent attempt. Evidence from "
    "another case, Scenario, lane, or attempt is inadmissible. Readiness "
    "records whether the approved Operation registry can execute the "
    "complete claim; prerequisite Preparation readiness is reported "
    "separately."
)


def build_docked_episode_switch_scenario() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    slug = "docked-episode-switch-settles-and-exits"
    scenario_id = f"scenario:{JOURNEY_SLUG}:{slug}"
    prefix = f"call:{JOURNEY_SLUG}:{slug}"
    obligation_prefix = f"obligation:{JOURNEY_SLUG}:{slug}"

    operations = [
        op_call(prefix, 1, "operation:app.relaunch@1", {}),
        op_call(prefix, 2, "operation:navigation.select-tab@1", {"tab": "files"}),
        op_call(
            prefix, 3, "operation:media.open@2",
            {
                "deadlineSeconds": 45,
                "expectedLanding": "window",
                "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4",
            },
        ),
        op_call(
            prefix, 4, "operation:playback.await-window-state@1",
            {
                "controls": "either",
                "deadlineSeconds": 45,
                "lifecycle": "playing",
                "presentation": "window",
            },
        ),
        op_call(
            prefix, 5, "operation:presentation.enter-docked-default@1",
            {"deadlineSeconds": 30, "summonControls": True},
        ),
        op_call(
            prefix, 6, "operation:accessibility.activate@2",
            {
                "context": "docked",
                "identifiers": ["PlayerPanel-menu-more", "PlayerPanel-menu-episodes"],
                "labels": ["180_3D.mp4"],
                "labelsAfterIdentifiers": True,
                "summonControls": True,
            },
        ),
        op_call(prefix, 7, "operation:harness.assert-channels@2", {}),
        op_call(
            prefix, 8, "operation:accessibility.inspect@2",
            {
                "context": "docked",
                "identifier": "PlayerUI-spatial-state",
                "requireMatchedElement": True,
                "summonControls": True,
                "deadlineSeconds": 30,
            },
        ),
        op_call(
            prefix, 9, "operation:presentation.exit-spatial@1",
            {"deadlineSeconds": 30, "from": "docked"},
        ),
    ]

    obligations = [
        {
            "artifactClass": "coverage",
            "caseKey": "default",
            "evidenceSchema": "accessibility-tree@1",
            "evidenceType": "accessibility.tree",
            "id": f"{obligation_prefix}:o01:default",
            "oracle": "oracle:agent-structured-accessibility-tree@1",
            "producedByCall": f"{prefix}:08",
            "rubric": f"rubric:{JOURNEY_SLUG}.{slug}.o01@1",
        },
        {
            "artifactClass": "coverage",
            "caseKey": "default",
            "evidenceSchema": "window-control-plane@1",
            "evidenceType": "window.control-plane",
            "id": f"{obligation_prefix}:o02:default",
            "oracle": "oracle:agent-structured-window-control-plane@1",
            "producedByCall": f"{prefix}:09",
            "rubric": f"rubric:{JOURNEY_SLUG}.{slug}.o02@1",
        },
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
        "promiseRefs": ["promise:mode-transitions:c05"],
        "readiness": "ready",
        "staticCases": ["default"],
        "success": {
            "all": [
                {"observation": f"{obligation_prefix}:o01:default"},
                {"observation": f"{obligation_prefix}:o02:default"},
            ]
        },
        "title": "Docked 内切换剧集后重新落地并安全退出",
    }

    rubrics = [
        {
            "criteria": [
                "The bound PlayerUI-spatial-state accessibility tree, read with context docked, requireMatchedElement true, summonControls true and deadlineSeconds 30 right after selecting 180_3D.mp4 from PlayerPanel-menu-more → PlayerPanel-menu-episodes (labelsAfterIdentifiers true), reports spatialState.fields.attached=docked with a rendererConsumer and playbackEntity present, proving the shell re-settled rather than staying pinned to the pre-switch surface.",
                "spatialState.fields.mediaName (or the equivalent media identity field carried by PlayerUI-spatial-state) names 180_3D.mp4, not sdr-bframe-multiaudio-avsync-120s.mp4, so the observation is bound to the entity produced by the in-place switch and cannot be satisfied by a stale pre-switch snapshot.",
            ],
            "filename": f"rubric-{JOURNEY_SLUG}-{slug}-o01-1.md",
            "id": f"rubric:{JOURNEY_SLUG}.{slug}.o01@1",
            "negativeControls": [
                "A missing PlayerUI-spatial-state matchedElement, requireMatchedElement false, or a read taken before the episode-menu activation is Indeterminate, not Satisfied.",
                "attached other than docked, an absent rendererConsumer/playbackEntity, or a mediaName still naming the original file (evidence of the reported in-place relaunch onto the released screen entity) fails the bound case.",
            ],
            "title": "Docked Episode Switch Settles Again",
        },
        {
            "criteria": [
                "The window-control-plane snapshot produced by presentation.exit-spatial@1 (from=docked, deadlineSeconds=30) reports presentation=window, attached=window, and the same session identity the docked-resident probe observed, per MainView.swift:927 (`session=`) and MainView.swift:926 (`lifecycle=`).",
                "fields.error equals none (MainView.swift:985, `error=\\(playbackRuntime.userVisibleIssue?.category.rawValue ?? \"none\")`), so the exit that used to fail with rendererReleaseUnavailable now completes without a surfaced playback issue.",
            ],
            "filename": f"rubric-{JOURNEY_SLUG}-{slug}-o02-1.md",
            "id": f"rubric:{JOURNEY_SLUG}.{slug}.o02@1",
            "negativeControls": [
                "Controller success without the application-side window-control-plane delivery is not evidence of product behavior.",
                "attached other than window, a changed session, or a non-none fields.error (including a rendererReleaseUnavailable-class failure) fails the bound case.",
            ],
            "title": "Docked Episode Switch Exits Without A Playback Issue",
        },
    ]
    return scenario, rubrics


def build_panorama_episode_switch_scenario() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    slug = "panorama-episode-switch-settles-with-pixels"
    scenario_id = f"scenario:{JOURNEY_SLUG}:{slug}"
    prefix = f"call:{JOURNEY_SLUG}:{slug}"
    obligation_prefix = f"obligation:{JOURNEY_SLUG}:{slug}"

    operations = [
        op_call(prefix, 1, "operation:app.relaunch@1", {}),
        op_call(prefix, 2, "operation:navigation.select-tab@1", {"tab": "files"}),
        op_call(
            prefix, 3, "operation:media.open@2",
            {
                "deadlineSeconds": 45,
                "expectedLanding": "window",
                "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4",
            },
        ),
        op_call(
            prefix, 4, "operation:playback.await-window-state@1",
            {
                "controls": "either",
                "deadlineSeconds": 45,
                "lifecycle": "playing",
                "presentation": "window",
            },
        ),
        op_call(
            prefix, 5, "operation:format.apply@2",
            {
                "deadlineSeconds": 30,
                "projection": "equirectangular180",
                "stereoLayout": "mono",
                "summonControls": True,
            },
        ),
        op_call(
            prefix, 6, "operation:presentation.enter-panorama@1",
            {"deadlineSeconds": 30, "summonControls": True},
        ),
        op_call(
            prefix, 7, "operation:accessibility.activate@2",
            {
                "context": "panorama",
                "identifiers": ["PlayerPanel-menu-more", "PlayerPanel-menu-episodes"],
                "labels": ["360.mp4"],
                "labelsAfterIdentifiers": True,
                "summonControls": True,
            },
        ),
        op_call(prefix, 8, "operation:harness.assert-channels@2", {}),
        op_call(
            prefix, 9, "operation:accessibility.inspect@2",
            {
                "context": "panorama",
                "identifier": "PlayerUI-spatial-state",
                "requireMatchedElement": True,
                "summonControls": True,
                "deadlineSeconds": 30,
            },
        ),
        op_call(
            prefix, 10, "operation:evidence.capture-frames@1",
            {
                "context": "panorama",
                "count": 3,
                "minimumIntervalMillis": 1000,
                "relatedResults": [
                    f"result://{prefix}:09/matchedElement",
                    f"result://{prefix}:09/response",
                ],
            },
        ),
        op_call(
            prefix, 11, "operation:presentation.exit-spatial@1",
            {"deadlineSeconds": 30, "from": "panorama"},
        ),
    ]

    obligations = [
        {
            "artifactClass": "coverage",
            "caseKey": "default",
            "evidenceSchema": "frame-sequence@2",
            "evidenceType": "visual.frames",
            "id": f"{obligation_prefix}:o01:default",
            "oracle": "oracle:agent-visual@2",
            "producedByCall": f"{prefix}:10",
            "rubric": f"rubric:{JOURNEY_SLUG}.{slug}.o01@1",
        },
        {
            "artifactClass": "coverage",
            "caseKey": "default",
            "evidenceSchema": "window-control-plane@1",
            "evidenceType": "window.control-plane",
            "id": f"{obligation_prefix}:o02:default",
            "oracle": "oracle:agent-structured-window-control-plane@1",
            "producedByCall": f"{prefix}:11",
            "rubric": f"rubric:{JOURNEY_SLUG}.{slug}.o02@1",
        },
    ]

    scenario = {
        "applicability": {
            "factEquals": {"fact": "fact:runtime.catalog-scope-included", "value": True}
        },
        "blockers": [],
        "contract": CONTRACT_BODY,
        "estimatedCostMillis": 230000,
        "id": scenario_id,
        "journey": JOURNEY_ID,
        "lane": "device",
        "mainGateFor": [],
        "obligations": obligations,
        "operations": operations,
        "prerequisites": [
            {"key": "presentation-fixtures-ready", "schema": "fixture-set.presentation-tour@2"}
        ],
        "promiseRefs": ["promise:mode-transitions:c04"],
        "readiness": "ready",
        "staticCases": ["default"],
        "success": {
            "all": [
                {"observation": f"{obligation_prefix}:o01:default"},
                {"observation": f"{obligation_prefix}:o02:default"},
            ]
        },
        "title": "Panorama 内切换剧集后以像素证明落地",
    }

    rubrics = [
        {
            "criteria": [
                "The producer requests exactly context panorama, count 3, minimumIntervalMillis 1000, and relatedResults naming call 09's matchedElement and response in that order, where call 09 read PlayerUI-spatial-state in context panorama with requireMatchedElement true right after selecting 360.mp4 from PlayerPanel-menu-more → PlayerPanel-menu-episodes.",
                "The producer returns exactly three indexed frames; every frame has a content-bound screenshot attachment, presentation is panorama, lifecycle is Playing, error is none, and adjacent capture times differ by at least 1000 ms.",
                "No frame's screenshot is blank, pure-colour, or undecodable, and at least one frame's screenshotDigest differs from frame 0's — the exact regression this closes is a black screen after switching episodes while in panorama, so uniform blankness across all three frames fails the claim regardless of the reported lifecycle.",
            ],
            "filename": f"rubric-{JOURNEY_SLUG}-{slug}-o01-1.md",
            "id": f"rubric:{JOURNEY_SLUG}.{slug}.o01@1",
            "negativeControls": [
                "A missing PlayerUI-spatial-state matchedElement, a capture taken before the episode-menu activation, fewer than three frames, or a sub-1000 ms interval is Indeterminate, not Satisfied.",
                "A blank, pure-colour or undecodable screenshot at any index, three identical screenshots, a non-Playing lifecycle, or a non-none error fails the bound case.",
            ],
            "title": "Panorama Episode Switch Settles With Pixels",
        },
        {
            "criteria": [
                "The window-control-plane snapshot produced by presentation.exit-spatial@1 (from=panorama, deadlineSeconds=30) reports presentation=portal and attached=portal, matching the reviewed panorama-to-portal exit route (promise:mode-transitions:c04) rather than window.",
                "fields.error equals none (MainView.swift:985) and the session identity is unchanged from the panorama-resident probe, so the switched episode continues without a surfaced playback issue after exit.",
            ],
            "filename": f"rubric-{JOURNEY_SLUG}-{slug}-o02-1.md",
            "id": f"rubric:{JOURNEY_SLUG}.{slug}.o02@1",
            "negativeControls": [
                "Controller success without the application-side window-control-plane delivery is not evidence of product behavior.",
                "attached other than portal, a changed session, or a non-none fields.error fails the bound case.",
            ],
            "title": "Panorama Episode Switch Exits Without A Playback Issue",
        },
    ]
    return scenario, rubrics


def build_docked_hlg_audio_scenario() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    slug = "docked-hlg-audio-integrity"
    scenario_id = f"scenario:{AUDIO_JOURNEY_SLUG}:{slug}"
    prefix = f"call:{AUDIO_JOURNEY_SLUG}:{slug}"
    obligation_prefix = f"obligation:{AUDIO_JOURNEY_SLUG}:{slug}"

    operations = [
        op_call(prefix, 1, "operation:app.relaunch@1", {}),
        op_call(prefix, 2, "operation:navigation.select-tab@1", {"tab": "files"}),
        op_call(
            prefix, 3, "operation:media.open@2",
            {
                "deadlineSeconds": 45,
                "expectedLanding": "window",
                "identifier": "MediaLibrary-grid-video-hlg-hevc-10bit-avsync-10s.mp4",
            },
        ),
        op_call(
            prefix, 4, "operation:playback.await-window-state@1",
            {
                "controls": "either",
                "deadlineSeconds": 45,
                "lifecycle": "playing",
                "presentation": "window",
            },
        ),
        op_call(prefix, 5, "operation:diagnostics.playback-state@1", {}),
        op_call(
            prefix, 6, "operation:presentation.enter-docked-default@1",
            {"deadlineSeconds": 30, "summonControls": True},
        ),
        op_call(prefix, 7, "operation:harness.assert-channels@2", {}),
        op_call(
            prefix, 8, "operation:diagnostics.playback-state@1",
            {"relatedResults": [f"result://{prefix}:05/fields"]},
        ),
        op_call(
            prefix, 9, "operation:evidence.capture-audio@2",
            {
                "durationMillis": 5000,
                "expectedSession": f"result://{prefix}:05/session",
                "inputDevice": "Steinberg UR12",
                "wavPath": f"audio/{slug}-default.wav",
            },
        ),
    ]

    obligations = [
        {
            "artifactClass": "coverage",
            "caseKey": "default",
            "evidenceSchema": "playback-probe@1",
            "evidenceType": "playback.probe",
            "id": f"{obligation_prefix}:o01:default",
            "oracle": "oracle:agent-structured-playback-probe@1",
            "producedByCall": f"{prefix}:08",
            "rubric": f"rubric:{AUDIO_JOURNEY_SLUG}.{slug}.o01@1",
        },
        {
            "artifactClass": "coverage",
            "caseKey": "default",
            "evidenceSchema": "audio-measurement@2",
            "evidenceType": "audio.measurement",
            "id": f"{obligation_prefix}:o02:default",
            "oracle": "oracle:agent-audio@2",
            "producedByCall": f"{prefix}:09",
            "rubric": f"rubric:{AUDIO_JOURNEY_SLUG}.{slug}.o02@1",
        },
    ]

    scenario = {
        "applicability": {
            "factEquals": {"fact": "fact:runtime.catalog-scope-included", "value": True}
        },
        "blockers": [],
        "contract": CONTRACT_BODY,
        "estimatedCostMillis": 150000,
        "id": scenario_id,
        "journey": AUDIO_JOURNEY_ID,
        "lane": "device",
        "mainGateFor": [],
        "obligations": obligations,
        "operations": operations,
        "prerequisites": [
            {"key": "dynamic-range-corpus-ready", "schema": "fixture-set.dynamic-range@2"}
        ],
        "promiseRefs": ["promise:track-selection:c02"],
        "readiness": "ready",
        "staticCases": ["default"],
        "success": {
            "all": [
                {"observation": f"{obligation_prefix}:o01:default"},
                {"observation": f"{obligation_prefix}:o02:default"},
            ]
        },
        "title": "HLG 文件进入 Docked 后音频保持存活",
    }

    rubrics = [
        {
            "criteria": [
                "Call 08's fields.audioRendererError equals none (MainView.swift:974, `audioRendererError=\\(output.audioRendererError ?? \"none\")`), read from the docked-resident PlayerUI-playback-state snapshot taken right after presentation.enter-docked-default@1 and the harness.assert-channels@2 gate.",
                "Call 08's fields.audioRendererSamples (MainView.swift:969, `audioRendererSamples=\\(output.audioRendererSamples)`) is strictly greater than call 05's pre-docked baseline value referenced via relatedResults, and fields.hasAudio (MainView.swift:967) remains true — the exact regression this closes is audio going silent right after entering docked while the picture keeps playing.",
                "session (MainView.swift:927) and lifecycle (MainView.swift:926) are unchanged between call 05 and call 08, so the two readings are bound to the same playback attempt rather than a relaunch.",
            ],
            "filename": f"rubric-{AUDIO_JOURNEY_SLUG}-{slug}-o01-1.md",
            "id": f"rubric:{AUDIO_JOURNEY_SLUG}.{slug}.o01@1",
            "negativeControls": [
                "A missing PlayerUI-playback-state read, a changed session between call 05 and call 08, or an absent audioRendererSamples/audioRendererError field is Indeterminate, not Satisfied.",
                "A non-none audioRendererError, a non-advancing or unavailable audioRendererSamples count, or hasAudio false fails the bound case.",
            ],
            "title": "Docked HLG Audio Renderer Stays Healthy",
        },
        {
            "criteria": [
                "The five-second capture on Steinberg UR12, bound to call 05's session, is not silent and measurement.dominantPulseHz is close to 660 Hz, matching the HLG fixture's registered audio (Tests/Fixtures/fixture-registry.json, generated-hlg-hevc10-avsync-10s-v1: \"AAC LC 48 kHz stereo; 660 Hz 80 ms pulses aligned with a white video flash every second\").",
                "The capture is taken while docked and lifecycle remains Playing for its duration, proving the audible signal survives the docked entry rather than predating it.",
            ],
            "filename": f"rubric-{AUDIO_JOURNEY_SLUG}-{slug}-o02-1.md",
            "id": f"rubric:{AUDIO_JOURNEY_SLUG}.{slug}.o02@1",
            "negativeControls": [
                "An absent capture, measurement.silent true, rmsDbfs below the silence floor, or a missing measurement.dominantPulseHz is Indeterminate and never Satisfied.",
                "A dominantPulseHz far from 660 Hz, a mismatched session, or a non-Playing lifecycle during the capture violates the rubric.",
            ],
            "title": "Docked HLG Audio Is Audible",
        },
    ]
    return scenario, rubrics


def main() -> None:
    catalog = json.loads(BLUEPRINT.read_text(encoding="utf-8"))

    new_scenarios: list[dict[str, Any]] = []
    new_rubrics: list[dict[str, Any]] = []
    for builder in (
        build_docked_episode_switch_scenario,
        build_panorama_episode_switch_scenario,
        build_docked_hlg_audio_scenario,
    ):
        scenario, rubrics = builder()
        assert not any(existing["id"] == scenario["id"] for existing in catalog["scenarios"]), scenario["id"]
        new_scenarios.append(scenario)
        new_rubrics.extend(rubrics)

    catalog["scenarios"].extend(new_scenarios)
    catalog["rubrics"].extend(new_rubrics)

    presentation_journey = item(catalog, "journeys", JOURNEY_ID)
    presentation_journey["scenarioRefs"].extend(
        scenario["id"] for scenario in new_scenarios if scenario["journey"] == JOURNEY_ID
    )
    audio_journey = item(catalog, "journeys", AUDIO_JOURNEY_ID)
    audio_journey["scenarioRefs"].extend(
        scenario["id"] for scenario in new_scenarios if scenario["journey"] == AUDIO_JOURNEY_ID
    )

    counts = catalog["expectedCounts"]
    counts["scenarios"] += len(new_scenarios)
    counts["rubrics"] += len(new_rubrics)
    counts["staticCases"] += sum(len(scenario["staticCases"]) for scenario in new_scenarios)

    payload = dict(catalog)
    payload.pop("contentDigest", None)
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    catalog["contentDigest"] = "sha256:" + hashlib.sha256(canonical).hexdigest()
    BLUEPRINT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"added {len(new_scenarios)} scenarios and {len(new_rubrics)} rubrics")
    for scenario in new_scenarios:
        print(" -", scenario["id"])


if __name__ == "__main__":
    main()
