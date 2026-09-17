#!/usr/bin/env python3
"""Migrate the regression blueprint to the ended-state Play Next contract.

Automatic end-of-media continuation is gone: playback now stays in the ended
lifecycle and the primary transport button morphs into Replay or Play Next per
the End of Playback setting. The Play Next tap launches the resolved next item
with origin .automaticContinuation, preserving the stored-position bypass of
Ask Every Time.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT = ROOT / "Config/regression/catalog-v2.json"
SCENARIO_ID = "scenario:local-media-lifecycle:automatic-play-next-resume-policy"
RUBRIC_ID = "rubric:local-media-lifecycle.automatic-play-next-resume-policy.o01@1"
PROMISE_ID = "promise:playback-queue:c01"
CALL_PREFIX = "call:local-media-lifecycle:automatic-play-next-resume-policy"


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
    for number in range(len(scenario["operations"]), position - 1, -1):
        scenario.update(
            replace_strings(dict(scenario), f"{CALL_PREFIX}:{number:02d}", f"{CALL_PREFIX}:{number + 1:02d}")
        )
    scenario["operations"].insert(
        position - 1,
        {
            "arguments": arguments,
            "callId": f"{CALL_PREFIX}:{position:02d}",
            "maxInvocations": 1,
            "operation": operation,
        },
    )


def main() -> None:
    catalog = json.loads(BLUEPRINT.read_text(encoding="utf-8"))
    expected_counts = dict(catalog["expectedCounts"])
    obligation_count = sum(len(value["obligations"]) for value in catalog["scenarios"])

    promise = item(catalog, "promises", PROMISE_ID)
    promise["title"] = "Ended Play Next resume policy"
    promise["statement"] = (
        "The ended-state Play Next affordance continues from the stored position "
        "according to the queue action without an Ask Every Time resume prompt; "
        "reaching end of media never launches the next item by itself."
    )

    scenario = item(catalog, "scenarios", SCENARIO_ID)
    scenario["title"] = "Ended Play Next resume policy"
    if len(scenario["operations"]) == 26:
        insert_call(
            scenario,
            25,
            "operation:playback.await-window-state@1",
            {
                "controls": "shown",
                "deadlineSeconds": 45,
                "lifecycle": "ended",
                "presentation": "window",
            },
        )
        insert_call(
            scenario,
            26,
            "operation:accessibility.activate@2",
            {
                "context": "window",
                "identifiers": ["PlayerPanel-button-play"],
                "summonControls": True,
            },
        )
    assert len(scenario["operations"]) == 28
    scenario["obligations"][0]["producedByCall"] = f"{CALL_PREFIX}:28"

    rubric = item(catalog, "rubrics", RUBRIC_ID)
    rubric["title"] = "Ended Play Next resume policy"
    rubric["criteria"] = [
        "The terminal playback probe has mediaName=viewing-storage-16m01s.mp4, "
        "position at least 20 seconds, at least 300 seconds remaining, and session "
        "different from relatedResults[0], which is the first-item "
        "diagnostics.playback-state@1 session captured before the ended Play Next "
        "tap. That fixture runs 961.0 s -- generated-viewing-storage-h264-16m01s-v1 "
        "in Tests/Fixtures/fixture-registry.json -- so it is above "
        "ViewingStatePolicy.minimumContentDurationSeconds of 900 and its exit "
        "actually retains a resumable status for the reopen and the ended "
        "continuation to find; the 30-second item that ends naturally is below "
        "that constant and correctly retains nothing.",
        "The terminal playback probe has resumePromptPresentations=1, "
        "automaticResumeBypasses=1, and pendingResumePrompt=false: the one direct "
        "reopen presented Ask Every Time, while the ended Play Next continuation "
        "resumed without a second prompt. Both counters increment only on the "
        "seconds > 0 arms of requestPlayback, which the 961-second fixture's "
        "saved position supplies.",
    ]
    rubric["negativeControls"] = [
        "A missing direct-open prompt, a resume prompt on the ended Play Next "
        "path, a terminal position below the saved range, session equal to "
        "relatedResults[0], or a mediaName other than viewing-storage-16m01s.mp4 "
        "violates HC-013. The next item playing without the intervening "
        "await-window-state@1 ended observation and the PlayerPanel-button-play "
        "activation means the product still advances by itself and fails the claim.",
    ]

    # Stale references to the removed .stop default in two rubric criteria.
    catalog = replace_strings(
        catalog,
        "under the default endBehavior .stop a correct product",
        "under the default endBehavior, which now ends playback and waits for the "
        "ended-state transport affordance instead of auto-repeating, a correct product",
    )
    catalog = replace_strings(
        catalog,
        "With the default endBehavior .stop a correct product",
        "With the default endBehavior, which now ends playback and waits for the "
        "ended-state transport affordance instead of auto-repeating, a correct product",
    )

    # copyDocuments pins catalog-root payloads by digest; viewing-state.md was
    # updated for the new coordinator line numbers and the manual continuation.
    for document in catalog["copyDocuments"]:
        if document["path"] in {"promises/viewing-state.md", "semantic-authority.json"}:
            payload_bytes = (ROOT / "Config/regression/catalog-root" / document["path"]).read_bytes()
            document["digest"] = "sha256:" + hashlib.sha256(payload_bytes).hexdigest()

    assert catalog["expectedCounts"] == expected_counts
    assert sum(len(value["obligations"]) for value in catalog["scenarios"]) == obligation_count
    payload = dict(catalog)
    payload.pop("contentDigest", None)
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    catalog["contentDigest"] = "sha256:" + hashlib.sha256(canonical).hexdigest()
    BLUEPRINT.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
