#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


DEFAULT_CATALOG = Path("Config/regression/catalog-v2.json")
EXPECTED_COUNTS = {
    "journeys": 14,
    "operations": 35,
    "oracles": 11,
    "preparations": 18,
    "promises": 65,
    "rubrics": 67,
    "scenarios": 65,
    "staticCases": 115,
}


def by_id(values: list[dict[str, Any]], identifier: str) -> dict[str, Any]:
    matches = [value for value in values if value["id"] == identifier]
    if len(matches) != 1:
        raise ValueError(f"expected one {identifier}, found {len(matches)}")
    return matches[0]


def call(scenario: dict[str, Any], suffix: str) -> dict[str, Any]:
    identifier = f"call:{scenario['id'].removeprefix('scenario:')}:{suffix}"
    matches = [value for value in scenario["operations"] if value["callId"] == identifier]
    if len(matches) != 1:
        raise ValueError(f"expected one {identifier}, found {len(matches)}")
    return matches[0]


def operation(scenario: dict[str, Any], suffix: str, operation_id: str, arguments: dict[str, Any]) -> dict[str, Any]:
    return {
        "arguments": arguments,
        "callId": f"call:{scenario['id'].removeprefix('scenario:')}:{suffix}",
        "maxInvocations": 1,
        "operation": operation_id,
    }


def bind(
    obligation: dict[str, Any],
    call_id: str,
    evidence_type: str,
    evidence_schema: str,
    oracle: str,
) -> None:
    obligation["producedByCall"] = call_id
    obligation["evidenceType"] = evidence_type
    obligation["evidenceSchema"] = evidence_schema
    obligation["oracle"] = oracle


def apply(document: dict[str, Any]) -> None:
    if document["expectedCounts"] != EXPECTED_COUNTS:
        raise ValueError("expectedCounts changed before the round-four migration")
    scenarios = document["scenarios"]
    rubrics = document["rubrics"]

    transition_disarm = by_id(
        document["operations"],
        "operation:transition-trace.disarm@1",
    )
    transition_disarm["role"] = "evidence"

    confirmed = by_id(scenarios, "scenario:library-management:confirmed-batch-deletion")
    call(confirmed, "12")["arguments"]["priorSnapshot"] = (
        "result://call:library-management:confirmed-batch-deletion:10/snapshot"
    )

    search = by_id(scenarios, "scenario:library-management:current-folder-search-counts")
    call(search, "08")["arguments"]["relatedResults"] = [
        "result://call:library-management:current-folder-search-counts:04/snapshot",
        "result://call:library-management:current-folder-search-counts:06/afterSnapshot",
    ]

    certificate = by_id(
        scenarios,
        "scenario:network-resilience:certificate-change-stops-without-trust",
    )
    certificate["operations"] = [
        *[value for value in certificate["operations"] if not value["callId"].endswith((":11", ":12"))],
        operation(
            certificate,
            "11",
            "operation:accessibility.activate@2",
            {
                "context": "window",
                "identifiers": ["PlayerUI-loadFailure-secondary"],
            },
        ),
        operation(
            certificate,
            "12",
            "operation:diagnostics.surface-probe@1",
            {
                "cursorToken": "result://call:network-resilience:certificate-change-stops-without-trust:10/cursorToken",
                "remoteExpectation": "certificate-change",
                "remoteReceiptID": "result://call:network-resilience:certificate-change-stops-without-trust:07/receiptID",
                "restoredGenerationToken": "result://call:network-resilience:certificate-change-stops-without-trust:09/restoredGenerationToken",
            },
        ),
    ]
    certificate["obligations"][0]["producedByCall"] = call(certificate, "12")["callId"]

    failures = by_id(scenarios, "scenario:network-resilience:playback-failure-category-matrix")
    failures["estimatedCostMillis"] = 760000
    for suffix in ("07", "20", "33", "46"):
        arguments = call(failures, suffix)["arguments"]
        arguments["requireMatchedElement"] = True
        arguments["deadlineSeconds"] = 45

    external = by_id(scenarios, "scenario:local-media-lifecycle:external-subtitle-source-matrix")
    for obligation, suffix in zip(external["obligations"], ("06", "14", "21"), strict=True):
        bind(
            obligation,
            call(external, suffix)["callId"],
            "visual.frames",
            "frame-sequence@2",
            "oracle:agent-visual@2",
        )

    subtitle = by_id(scenarios, "scenario:local-media-lifecycle:subtitle-switch-and-off")
    for obligation, suffix in zip(subtitle["obligations"], ("07", "09", "11", "13"), strict=True):
        obligation["producedByCall"] = call(subtitle, suffix)["callId"]
    subtitle["operations"] = [
        value for value in subtitle["operations"] if not value["callId"].endswith((":14", ":15", ":16"))
    ]
    subtitle_rubric = by_id(
        rubrics,
        "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1",
    )
    subtitle_rubric["criteria"] = [
        "Selecting ffmpeg.subtitle.3 displays the generated SubRip cue containing 'Enchron 字幕验证' and selecting ffmpeg.subtitle.5 displays the generated DVB bitmap cue titled 'Enchron generated bitmap proof' with its top-safe-area color bars.",
        "Selecting Off removes subtitle pixels and marks only Off selected; selecting ffmpeg.subtitle.3 again restores the generated SubRip cue containing 'Enchron 字幕验证'.",
    ]

    smb = by_id(scenarios, "scenario:smb-source-lifecycle:smb-browse-shares-and-directories")
    smb["operations"] = [
        operation(smb, "01", "operation:host.preflight@1", {"check": "smb-aggregate"}),
        operation(smb, "02", "operation:app.relaunch@1", {}),
        operation(smb, "03", "operation:navigation.select-tab@1", {"tab": "files"}),
        operation(
            smb,
            "04",
            "operation:diagnostics.browse-hierarchy@1",
            {
                "context": "main-window-browser",
                "pathComponents": ["TestMedia", "TestVectors", "Enchron", "PlaybackBehavior"],
                "sourceLabel": "Enchron Regression SMB",
                "sourceReceipt": "result://call:smb-source-lifecycle:smb-browse-shares-and-directories:01/report",
            },
        ),
    ]
    smb["obligations"][0]["producedByCall"] = call(smb, "04")["callId"]

    home = by_id(scenarios, "scenario:emby-server-lifecycle:home-poster-and-next-up")
    home["operations"] = [
        operation(home, "01", "operation:app.relaunch@1", {}),
        operation(home, "02", "operation:navigation.select-tab@1", {"tab": "emby"}),
        operation(home, "03", "operation:accessibility.inspect@2", {"context": "window", "identifier": "Emby-Evidence"}),
        operation(home, "04", "operation:accessibility.activate@2", {"context": "window", "labels": ["Enchron Regression Series"]}),
        operation(home, "05", "operation:accessibility.inspect@2", {"context": "window", "identifier": "Emby-Evidence"}),
        operation(home, "06", "operation:app.relaunch@1", {}),
        operation(home, "07", "operation:navigation.select-tab@1", {"tab": "emby"}),
        operation(home, "08", "operation:accessibility.activate@2", {"context": "window", "labels": ["Enchron Regression Episode"]}),
        operation(home, "09", "operation:accessibility.inspect@2", {"context": "window", "identifier": "Emby-Evidence"}),
    ]
    home["obligations"][0]["producedByCall"] = call(home, "09")["callId"]

    guidance = by_id(scenarios, "scenario:issue-surface-behavior:source-failure-guidance-matrix")
    for suffix, field in (("18", "unreachableAddress"), ("29", "missingPathAddress"), ("40", "httpAddress")):
        target = call(guidance, suffix)
        preflight_suffix = {"18": "12", "29": "23", "40": "34"}[suffix]
        target["arguments"].pop("textFile", None)
        target["arguments"].pop("textJSONKey", None)
        target["arguments"]["text"] = (
            f"result://call:issue-surface-behavior:source-failure-guidance-matrix:{preflight_suffix}/{field}"
        )

    audio = by_id(scenarios, "scenario:format-coverage:audio-delivery-codec-matrix")
    for suffix, stream_id in (("06", "2"), ("13", "3"), ("37", "1"), ("44", "8")):
        call(audio, suffix)["arguments"]["identifiers"] = [
            "PlayerUI-TopAction-more",
            "PlayerUI-menu-audio",
            f"PlayerUI-menu-audio-{stream_id}",
        ]

    classification = by_id(scenarios, "scenario:format-coverage:signalled-media-classification")
    call(classification, "08")["arguments"]["expectedLanding"] = "window"
    call(classification, "09")["arguments"]["presentation"] = "window"
    call(classification, "10")["arguments"]["context"] = "window"

    route = by_id(scenarios, "scenario:presentation-tour:format-application-route")
    for obligation, suffix in zip(route["obligations"], ("08", "16"), strict=True):
        obligation["producedByCall"] = call(route, suffix)["callId"]

    editor = by_id(scenarios, "scenario:presentation-tour:format-editor-hosts-window-and-portal")
    editor["obligations"][1]["producedByCall"] = call(editor, "16")["callId"]
    editor["operations"] = [value for value in editor["operations"] if not value["callId"].endswith(":17")]
    editor_rubric = by_id(
        rubrics,
        "rubric:presentation-tour.format-editor-hosts-window-and-portal.o01@1",
    )
    editor_rubric["criteria"] = [
        editor_rubric["criteria"][0],
        "The window case binds the editor hierarchy and registered values. The portal case binds the successful Playback surface and videoFormat activation responses, including the matched public elements that live outside the main-window hierarchy.",
    ]

    coexist = by_id(scenarios, "scenario:presentation-tour:portal-format-and-panorama-actions-coexist")
    coexist["operations"] = [
        *[value for value in coexist["operations"] if int(value["callId"].rsplit(":", 1)[1]) <= 5],
        operation(coexist, "06", "operation:accessibility.activate@2", {"context": "portal", "labels": ["Playback surface"]}),
        operation(coexist, "07", "operation:accessibility.activate@2", {"context": "portal", "identifiers": ["PlayerUI-TopAction-videoFormat"]}),
        operation(coexist, "08", "operation:accessibility.activate@2", {"context": "portal", "identifiers": ["PlayerUI-VideoFormat-cancel"]}),
        operation(coexist, "09", "operation:accessibility.activate@2", {"context": "portal", "labels": ["Playback surface"]}),
        operation(coexist, "10", "operation:accessibility.activate@2", {"context": "portal", "identifiers": ["PlayerUI-TopAction-resumePanorama"]}),
    ]
    coexist["obligations"][0]["producedByCall"] = call(coexist, "10")["callId"]

    timeout = by_id(scenarios, "scenario:presentation-tour:transition-timeout-rolls-back")
    timeout["obligations"][0]["producedByCall"] = call(timeout, "09")["callId"]

    if sum(len(value["obligations"]) for value in scenarios) != 149:
        raise ValueError("round-four migration changed the pinned obligation count")
    if document["expectedCounts"] != EXPECTED_COUNTS:
        raise ValueError("round-four migration changed expectedCounts")


def write(path: Path, document: dict[str, Any]) -> None:
    unsigned = dict(document)
    unsigned.pop("contentDigest", None)
    encoded = json.dumps(
        unsigned,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    document["contentDigest"] = "sha256:" + hashlib.sha256(encoded).hexdigest()
    path.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", nargs="?", type=Path, default=DEFAULT_CATALOG)
    arguments = parser.parse_args()
    document = json.loads(arguments.catalog.read_text(encoding="utf-8"))
    apply(document)
    write(arguments.catalog, document)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
