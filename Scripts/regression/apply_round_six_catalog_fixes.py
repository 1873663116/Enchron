#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT = ROOT / "Config/regression/catalog-v2.json"


def item(catalog: dict[str, Any], collection: str, identifier: str) -> dict[str, Any]:
    return next(value for value in catalog[collection] if value["id"] == identifier)


def replace_strings(value: Any, old: str, new: str) -> Any:
    if isinstance(value, str):
        return value.replace(old, new)
    if isinstance(value, list):
        return [replace_strings(entry, old, new) for entry in value]
    if isinstance(value, dict):
        return {key: replace_strings(entry, old, new) for key, entry in value.items()}
    return value


def insert_call(scenario: dict[str, Any], position: int, operation: str, arguments: dict[str, Any]) -> None:
    prefix = scenario["operations"][0]["callId"].rsplit(":", 1)[0]
    for number in range(len(scenario["operations"]), position - 1, -1):
        scenario.update(replace_strings(dict(scenario), f"{prefix}:{number:02d}", f"{prefix}:{number + 1:02d}"))
    scenario["operations"].insert(
        position - 1,
        {
            "arguments": arguments,
            "callId": f"{prefix}:{position:02d}",
            "maxInvocations": 1,
            "operation": operation,
        },
    )


def remove_calls(scenario: dict[str, Any], numbers: set[int]) -> None:
    prefix = scenario["operations"][0]["callId"].rsplit(":", 1)[0]
    scenario["operations"] = [
        call for call in scenario["operations"]
        if int(call["callId"].rsplit(":", 1)[1]) not in numbers
    ]
    mapping = {
        old: new
        for new, old in enumerate(
            [number for number in range(1, max(numbers | {len(scenario["operations"])}) + len(numbers) + 1) if number not in numbers],
            1,
        )
    }
    for old, new in sorted(mapping.items()):
        if old != new:
            scenario.update(replace_strings(dict(scenario), f"{prefix}:{old:02d}", f"{prefix}:{new:02d}"))


def rewrite_case_rubric(catalog: dict[str, Any], identifier: str, criteria: list[str], negative: list[str]) -> None:
    rubric = item(catalog, "rubrics", identifier)
    rubric["criteria"] = criteria
    rubric["negativeControls"] = negative


def main() -> None:
    catalog = json.loads(BLUEPRINT.read_text(encoding="utf-8"))
    expected_counts = dict(catalog["expectedCounts"])
    obligation_count = sum(len(value["obligations"]) for value in catalog["scenarios"])

    storage = item(catalog, "operations", "operation:storage.clear@1")
    storage["invalidatesTags"] = [tag for tag in storage["invalidatesTags"] if tag not in {"library.contents", "settings.state"}]

    buffered = item(catalog, "scenarios", "scenario:network-resilience:buffered-reconnect-has-no-indicator")
    if len(buffered["operations"]) == 21:
        remove_calls(buffered, {21})
    buffered["obligations"][0]["producedByCall"] = "call:network-resilience:buffered-reconnect-has-no-indicator:10"
    buffered["obligations"][1]["producedByCall"] = "call:network-resilience:buffered-reconnect-has-no-indicator:20"
    buffered["operations"][-1]["arguments"].pop("relatedFrameManifests", None)
    rewrite_case_rubric(
        catalog,
        "rubric:network-resilience.buffered-reconnect-has-no-indicator.o01@1",
        [
            "For caseKey paired-control, the bound artifact is the three-frame healthy control sequence for the registered WebDAV card after its exact activation receipt is restored; the frames remain Playing with increasing positions and expose no loading or issue surface.",
            "For caseKey buffer-absorbed-interruption, the bound artifact is the three-frame fault sequence for the same registered WebDAV card; its exact receipt is restored, its host trace contains ordered successful Range 206, injected 503, and recovered 206 responses, and the frames remain Playing with buffer ahead greater than zero, increasing positions, and no loading or issue surface.",
        ],
        ["A mismatched case, unrestored recipe, missing ordered host responses for the fault case, fewer than three product snapshots, a visible loading or issue indicator, zero buffer-ahead, or a non-increasing position fails the bound case."],
    )

    certificate = item(catalog, "scenarios", "scenario:network-resilience:certificate-change-stops-without-trust")
    certificate["operations"][-1]["arguments"]["cursorToken"] = "result://call:network-resilience:certificate-change-stops-without-trust:06/cursorToken"

    audio = item(catalog, "scenarios", "scenario:audio-only-playback:secondary-menu-pins-audio-controls")
    if len(audio["operations"]) == 15:
        remove_calls(audio, {15})
    audio["operations"][-1]["arguments"]["cursorToken"] = "result://call:audio-only-playback:secondary-menu-pins-audio-controls:12/cursorToken"
    audio["obligations"][0]["producedByCall"] = "call:audio-only-playback:secondary-menu-pins-audio-controls:07"
    audio["obligations"][1]["producedByCall"] = "call:audio-only-playback:secondary-menu-pins-audio-controls:14"
    rewrite_case_rubric(
        catalog,
        "rubric:audio-only-playback.secondary-menu-pins-audio-controls.o01@1",
        [
            "For caseKey audio-menu, the bound trace contains one surface to More to Audio transaction that exposes a real enabled secondary menu and keeps playback controls visible through the 9000 ms probe.",
            "For caseKey speed-menu, the bound trace contains one surface to More to Playback Speed transaction that exposes a real enabled secondary menu and keeps playback controls visible through the 9000 ms probe.",
            "The bound trace keeps lifecycle Playing and shows no subtitle, video-format, Dock, or Panorama actions in the audio-only control set.",
        ],
        ["A trace for the other case, omitted More step, split nested-menu route, controls hidden before 9000 ms, or any video-only action fails the bound case."],
    )

    dolby = item(catalog, "scenarios", "scenario:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch")
    if len(dolby["operations"]) == 22:
        remove_calls(dolby, {21, 22})
    dolby["operations"][-1]["arguments"].pop("relatedFrameManifests", None)
    for obligation, call in zip(dolby["obligations"], (6, 12, 20)):
        obligation["producedByCall"] = f"call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:{call:02d}"
    rewrite_case_rubric(
        catalog,
        "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1",
        [
            "For caseKey profile-8-hdr10, the bound artifact follows one surface to videoFormat to HDRFallback to apply transaction, preserves source tuple (8,1,false) and source format atoms, and shows the reviewed HDR10/PQ renderer branch.",
            "For caseKey profile-8-hlg, the bound artifact follows one surface to videoFormat to HDRFallback to apply transaction, preserves source tuple (8,4,false) and source format atoms, and shows the reviewed HLG/B67 renderer branch.",
            "For caseKey profile-5-no-fallback, the bound artifact preserves source tuple (5,0,false), records no fallback mutation after the absence check and cancel transaction, and retains source and renderer Dolby Vision atom facts.",
            "The bound artifact contains exactly one three-frame Playing sequence at 1000 ms minimum intervals with stable session and revision, increasing position, distinct content attachments, non-none pixel formats, and no issue or whole-frame cast.",
        ],
        ["A mismatched case, changed source tuple or format atoms, an unreviewed renderer transfer, fallback offered for Profile 5, fewer than three valid frames, repeated attachments, or non-advancing playback fails the bound case."],
    )

    subtitle = item(catalog, "scenarios", "scenario:local-media-lifecycle:subtitle-switch-and-off")
    subtitle["operations"][-1]["arguments"].pop("relatedFrameManifests", None)
    rewrite_case_rubric(
        catalog,
        "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1",
        [
            "For caseKey embedded-text, the bound frames show the generated SubRip cue containing Enchron 字幕验证 after selecting ffmpeg.subtitle.3.",
            "For caseKey embedded-bitmap, the bound frames show the generated DVB bitmap cue titled Enchron generated bitmap proof with its top-safe-area color bars after selecting ffmpeg.subtitle.5.",
            "For caseKey off, the bound frames contain no subtitle pixels after selecting Off and only Off is selected; for caseKey restore, the bound frames again show Enchron 字幕验证 after selecting ffmpeg.subtitle.3.",
        ],
        ["A mismatched case reference, retained subtitle pixels in the Off case, missing expected cue, fewer than three changing valid frames, or blank, pure-color, or repeated attachments fails the bound case."],
    )

    webdav = item(catalog, "scenarios", "scenario:webdav-source-lifecycle:webdav-add-source")
    webdav["operations"][-1]["arguments"]["relatedResults"] = [
        "result://call:webdav-source-lifecycle:webdav-add-source:05/interaction",
        "result://call:webdav-source-lifecycle:webdav-add-source:10/interaction",
    ]

    remote_index = item(catalog, "scenarios", "scenario:viewing-state-and-storage:remote-index-reused-on-second-open")
    if len(remote_index["operations"]) == 16:
        insert_call(remote_index, 12, "operation:accessibility.activate@2", {"context": "main-window-browser", "labels": ["Enchron Regression WebDAV"]})

    for scenario_id in (
        "scenario:emby-server-lifecycle:emby-resume-entry-semantics",
        "scenario:emby-server-lifecycle:episode-resume-and-start-actions",
    ):
        scenario = item(catalog, "scenarios", scenario_id)
        if len(scenario["operations"]) == 9:
            insert_call(scenario, 3, "operation:accessibility.activate@2", {"context": "window", "labels": ["Enchron Regression Library", "Enchron Regression Series", "Enchron Regression Episode"]})
            back_index = next(index for index, call in enumerate(scenario["operations"]) if call["operation"] == "operation:accessibility.activate@2" and call["arguments"].get("identifiers") == ["PlayerUI-InfoBar-button-back"])
            insert_call(scenario, back_index + 2, "operation:accessibility.activate@2", {"context": "window", "labels": ["Enchron Regression Episode"]})

    projection = item(catalog, "scenarios", "scenario:projection-and-stereo:apple-immersive-projection")
    if len(projection["operations"]) == 8:
        remove_calls(projection, {7})
    rewrite_case_rubric(
        catalog,
        "rubric:projection-and-stereo.apple-immersive-projection.o01@1",
        [
            "The media is opened without a later format.apply or seek, presentation.enter-panorama requests deadlineSeconds 45, and the bound producer requests exactly context panorama, count 3, and minimumIntervalMillis 1000.",
            "The producer returns exactly three indexed frames; every playbackState is available, presentationObservation is expected and observed panorama, each record has a content-bound screenshot attachment, and adjacent capture times differ by at least 1000 ms.",
            "In every frame playbackState.fields reports source format provenance, Apple Immersive content and projection signals, multiview stereo, MV-HEVC, hvc1 with hvcC and lhvC configuration, and multiview renderer input.",
            "Across all frames session and stream epoch are stable, lifecycle is Playing, presentation is panorama, the immersive geometry is stereo progressive with displayed pixels, no error is active, and screenshots contain nonblank changing Beach imagery.",
        ],
        ["A user format override or seek, short capture interval, non-Apple projection signal, packed stereo, missing lhvC or multiview facts, mono geometry, changed session or epoch, zero displayed pixels, an active issue, or blank, identical, pure-color, or undecodable screenshots fails or makes the claim indeterminate according to the missing evidence."],
    )

    audio_matrix = item(catalog, "scenarios", "scenario:format-coverage:audio-delivery-codec-matrix")
    if not audio_matrix["operations"]:
        audio_matrix["operations"] = [
            {
                "arguments": {},
                "callId": f"call:format-coverage:audio-delivery-codec-matrix:{number:02d}",
                "maxInvocations": 1,
                "operation": "operation:app.relaunch@1",
            }
            for number in range(1, 46)
        ]
    audio_matrix.update(replace_strings(dict(audio_matrix), ":opus", ":vorbis"))
    audio_matrix["staticCases"] = ["vorbis" if case == "opus" else case for case in audio_matrix["staticCases"]]
    if len(audio_matrix["operations"]) == 46:
        remove_calls(audio_matrix, {26})
    for old, new in (("mp2", "dts"), ("mp3", "truehd")):
        audio_matrix.update(replace_strings(dict(audio_matrix), f":{old}", f":{new}"))
        audio_matrix["staticCases"] = [new if case == old else case for case in audio_matrix["staticCases"]]
        for obligation in audio_matrix["obligations"]:
            if obligation["caseKey"] == old:
                obligation["caseKey"] = new
    prefix = "call:format-coverage:audio-delivery-codec-matrix"
    restored = (
        (17, "operation:media.open@2", {"deadlineSeconds": 45, "expectedLanding": "window", "identifier": "MediaLibrary-grid-video-dts_es.dts"}),
        (18, "operation:playback.await-window-state@1", {"controls": "either", "deadlineSeconds": 45, "lifecycle": "playing", "presentation": "window"}),
        (19, "operation:playback.wait-position@2", {"deadlineSeconds": 45, "minimumPositionMillis": 500, "minimumRemainingMillis": 500}),
        (20, "operation:diagnostics.playback-state@1", {}),
        (21, "operation:app.relaunch@1", {}),
        (22, "operation:navigation.select-tab@1", {"tab": "files"}),
        (23, "operation:media.open@2", {"deadlineSeconds": 45, "expectedLanding": "window", "identifier": "MediaLibrary-grid-video-atmos.thd"}),
        (24, "operation:playback.await-window-state@1", {"controls": "either", "deadlineSeconds": 45, "lifecycle": "ended", "presentation": "window"}),
        (25, "operation:diagnostics.playback-state@1", {}),
    )
    for number, operation, arguments in restored:
        audio_matrix["operations"][number - 1] = {"arguments": arguments, "callId": f"{prefix}:{number:02d}", "maxInvocations": 1, "operation": operation}
    next(obligation for obligation in audio_matrix["obligations"] if obligation["caseKey"] == "dts")["producedByCall"] = f"{prefix}:20"
    next(obligation for obligation in audio_matrix["obligations"] if obligation["caseKey"] == "truehd")["producedByCall"] = f"{prefix}:25"
    classification = item(catalog, "scenarios", "scenario:format-coverage:signalled-media-classification")
    classification["operations"][2]["arguments"]["expectedLanding"] = "window"
    classification["operations"][3]["arguments"]["presentation"] = "window"
    classification["operations"][4]["arguments"]["context"] = "window"

    external_subtitles = item(catalog, "scenarios", "scenario:local-media-lifecycle:external-subtitle-source-matrix")
    external_subtitles["prerequisites"] = [
        {"key": "local-aggregate-staged", "schema": "fixture-set.local-aggregate-staged@2"},
        {"key": "local-directory-subtitle-source-ready", "schema": "media-source.local-directory-sidecars@1"}
    ]
    rewrite_case_rubric(
        catalog,
        "rubric:local-media-lifecycle.external-subtitle-source-matrix.o01@1",
        [
            "For the bound caseKey, the independent attempt opens its real media identity and invokes playback.select-subtitle with host playerPanel, the matching sourceKind, and deadlineSeconds within 1 through 90. Local and WebDAV sidecars use the registered sdr-bframe-aggregate-30s.zh-CN.srt label; the Emby case discovers the sole external track from the verified seed receipt.",
            "The bound Operation discovers only real external.subtitle menu items, selects the unique source-kind and label match, returns the complete selection and identity observations, preserves session, media, source identity, and content revision, and the following three-frame producer shows the reviewed external cue rather than an embedded subtitle.",
        ],
        ["A mismatched source case, Catalog-authored dynamic track ID, direct state injection, missing authenticated source, ambiguous discovery result, identity or revision change, missing external cue, embedded cue, fewer than three changing frames, or source-kind mismatch fails the bound case."],
    )

    failure_matrix = item(catalog, "scenarios", "scenario:network-resilience:playback-failure-category-matrix")
    prefix = "call:network-resilience:playback-failure-category-matrix"
    for terminal, start in ((13, 1), (26, 14), (39, 27), (52, 40)):
        failure_matrix["operations"][terminal - 1]["arguments"]["relatedResults"] = [
            f"result://{prefix}:{start + 5:02d}/activationReceipt",
            f"result://{prefix}:{start + 6:02d}/matchedElement",
            f"result://{prefix}:{start + 7:02d}/fields",
            f"result://{prefix}:{start + 8:02d}/restorationReceipt",
            f"result://{prefix}:{start + 9:02d}/interaction",
            f"result://{prefix}:{start + 10:02d}/playbackObservation",
            f"result://{prefix}:{start + 11:02d}/fields",
        ]

    recoverable = item(catalog, "scenarios", "scenario:network-resilience:recoverable-read-resumes-from-checkpoint")
    recoverable["operations"][10]["arguments"]["relatedResults"] = [
        "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/binding",
        "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:09/expectationObservation",
    ]

    artwork = item(catalog, "scenarios", "scenario:emby-server-lifecycle:artwork-by-image-tag")
    if len(artwork["operations"]) == 3:
        insert_call(artwork, 3, "operation:accessibility.activate@2", {"context": "window", "labels": ["Enchron Regression Library", "Enchron Regression Series"]})

    season_navigation = item(catalog, "scenarios", "scenario:emby-server-lifecycle:series-season-episode-navigation")
    if len(season_navigation["operations"]) == 7:
        prefix = "call:emby-server-lifecycle:series-season-episode-navigation"
        season_navigation["operations"] = [
            season_navigation["operations"][0],
            season_navigation["operations"][1],
            season_navigation["operations"][2],
            season_navigation["operations"][3],
            season_navigation["operations"][4],
            {"arguments": {"context": "window", "identifier": "Emby-Evidence"}, "callId": f"{prefix}:06", "maxInvocations": 1, "operation": "operation:accessibility.inspect@2"},
            {"arguments": {"context": "window", "labels": ["Season 2"]}, "callId": f"{prefix}:07", "maxInvocations": 1, "operation": "operation:accessibility.activate@2"},
            {"arguments": {"context": "window", "identifier": "Emby-Evidence"}, "callId": f"{prefix}:08", "maxInvocations": 1, "operation": "operation:accessibility.inspect@2"},
            {"arguments": {"context": "window", "labels": ["Enchron Regression Episode 2"]}, "callId": f"{prefix}:09", "maxInvocations": 1, "operation": "operation:accessibility.activate@2"},
            {"arguments": {"context": "window", "identifier": "Emby-Evidence", "relatedResults": [f"result://{prefix}:06/response", f"result://{prefix}:08/response"]}, "callId": f"{prefix}:10", "maxInvocations": 1, "operation": "operation:accessibility.inspect@2"},
        ]
        season_navigation["obligations"][0]["producedByCall"] = f"{prefix}:10"

    for scenario in catalog["scenarios"]:
        for call in scenario["operations"]:
            if call["operation"] == "operation:input.device-hub-pinch@2":
                call["arguments"].setdefault("targetDomain", "canvas")

    assert catalog["expectedCounts"] == expected_counts
    assert sum(len(value["obligations"]) for value in catalog["scenarios"]) == obligation_count == 149
    payload = dict(catalog)
    payload.pop("contentDigest", None)
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    catalog["contentDigest"] = "sha256:" + hashlib.sha256(canonical).hexdigest()
    BLUEPRINT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
