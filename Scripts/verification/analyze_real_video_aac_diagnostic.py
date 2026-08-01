#!/usr/bin/env python3
"""Validate retained real-video AAC state, PlaybackCore events, and raw capture facts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


ATTACHMENTS = {
    "preRateState": re.compile(r"^real-video-aac-00-pre-rate-state_\d+_.*\.txt$"),
    "preRateCore": re.compile(r"^real-video-aac-00-pre-rate-core_\d+_.*\.txt$"),
    "tailState": re.compile(r"^real-video-aac-00-tail-state_\d+_.*\.txt$"),
    "tailCore": re.compile(r"^real-video-aac-00-tail-core_\d+_.*\.txt$"),
    "checkpointA": re.compile(r"^real-video-aac-01-a-state_\d+_.*\.txt$"),
    "checkpointB": re.compile(r"^real-video-aac-02-b-state_\d+_.*\.txt$"),
    "coreA": re.compile(r"^real-video-aac-01-core_\d+_.*\.txt$"),
    "coreB": re.compile(r"^real-video-aac-02-core_\d+_.*\.txt$"),
}
OBSERVATION_TASK_PHASES = (
    "delayedTask.enter",
    "delayedTask.sleepReturned",
    "delayedTask.beforeStateRead",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_state(value: str) -> dict[str, str]:
    return dict(
        item.split("=", 1) for item in value.strip().split(";") if "=" in item
    )


def state_bool(state: dict[str, str], key: str) -> bool | None:
    value = state.get(key)
    if value == "true":
        return True
    if value == "false":
        return False
    return None


def state_float(state: dict[str, str], key: str) -> float | None:
    try:
        return float(state[key])
    except (KeyError, TypeError, ValueError):
        return None


def state_int(state: dict[str, str], key: str) -> int | None:
    try:
        return int(state[key])
    except (KeyError, TypeError, ValueError):
        return None


def playback_activation_sequence(events: list[object]) -> list[dict[str, object]]:
    indexed = [
        (index, event)
        for index, event in enumerate(events)
        if isinstance(event, dict)
        and isinstance(event.get("kind"), str)
        and event["kind"].startswith("playbackActivation.")
    ]
    return [
        event for _, event in sorted(
            indexed,
            key=lambda item: (
                item[1].get("sequenceNumber")
                if isinstance(item[1].get("sequenceNumber"), int)
                else float("inf"),
                item[0],
            ),
        )
    ]


def playback_activation_timeline(events: list[object]) -> list[dict[str, object]]:
    fields = (
        "phase", "delayMs", "activationSequence", "streamEpoch", "audioStreamEpoch",
        "delaysRateChangeUntilHasSufficientMediaData", "requestedRate",
        "synchronizerRate", "directTimebaseRate", "effectiveTimebaseRate",
        "directTimebaseTimeSeconds", "synchronizerCurrentTimeSeconds",
        "directSourceType", "directSourceTimeSeconds", "ultimateSourceTimeSeconds",
        "videoStatus", "videoHasSufficientMedia", "videoReadyForMoreMedia",
        "videoRequiresFlush", "videoAcceptedMinPTSSeconds",
        "videoAcceptedMaxPTSSeconds", "videoAcceptedMinDTSSeconds",
        "videoAcceptedMaxDTSSeconds", "videoAcceptedMaxEndSeconds",
        "videoAcceptedCount", "audioStatus", "audioHasSufficientMedia",
        "audioReadyForMoreMedia", "audioAcceptedMinPTSSeconds",
        "audioAcceptedMaxEndSeconds", "audioAcceptedCount",
    )
    timeline = []
    for event in playback_activation_sequence(events):
        details = event.get("details")
        if not isinstance(details, dict):
            details = {}
        timeline.append({
            "sequenceNumber": event.get("sequenceNumber"),
            **{field: details.get(field) for field in fields},
        })
    return timeline


def delivery_stage_timeline(events: list[object]) -> list[dict[str, object]]:
    timeline = []
    for event in events:
        if not isinstance(event, dict):
            continue
        kind = event.get("kind")
        if not isinstance(kind, str) or not kind.startswith("playbackDelivery.stage."):
            continue
        components = kind.split(".", 3)
        if len(components) != 4:
            continue
        details = event.get("details")
        if not isinstance(details, dict):
            details = {}
        timeline.append({
            "sequenceNumber": event.get("sequenceNumber"),
            "kind": kind,
            "lane": components[2],
            "stage": components[3],
            "streamEpoch": details.get("streamEpoch"),
            "sampleOrdinal": details.get("sampleOrdinal"),
            "presentationTimeSeconds": details.get("presentationTimeSeconds"),
            "decodeTimeSeconds": details.get("decodeTimeSeconds"),
            "outcome": details.get("outcome"),
        })
    return sorted(
        timeline,
        key=lambda event: (
            event["sequenceNumber"]
            if isinstance(event["sequenceNumber"], int)
            else float("inf")
        ),
    )


def observation_task_phase_report(events: list[object]) -> dict[str, object]:
    markers = []
    for event in playback_activation_sequence(events):
        if event.get("kind") != "playbackActivation.stageMarker":
            continue
        details = event.get("details")
        if not isinstance(details, dict):
            continue
        markers.append({
            "sequenceNumber": event.get("sequenceNumber"),
            "activationSequence": details.get("activationSequence"),
            "delayMs": details.get("delayMs"),
            "phase": details.get("phase"),
            "streamEpoch": details.get("streamEpoch"),
            "audioStreamEpoch": details.get("audioStreamEpoch"),
        })
    by_delay = {}
    for delay in (10, 50, 100, 500, 2_000):
        phases = [
            marker["phase"] for marker in markers
            if str(marker["delayMs"]) == str(delay)
        ]
        by_delay[str(delay)] = {
            "phases": phases,
            "missingPhases": [
                phase for phase in OBSERVATION_TASK_PHASES if phase not in phases
            ],
        }
    return {"markers": markers, "byDelay": by_delay}


def load_attachments(
    xcresult: Path,
    observer_mode: str = "enabled",
) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="enchron-real-aac-") as directory:
        exported = Path(directory)
        subprocess.run([
            "xcrun", "xcresulttool", "export", "attachments", "--path",
            str(xcresult), "--output-path", str(exported),
        ], check=True, stdout=subprocess.DEVNULL)
        manifest = json.loads((exported / "manifest.json").read_text())
        found: dict[str, list[str]] = {key: [] for key in ATTACHMENTS}
        for test in manifest:
            for attachment in test.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName", "")
                for key, pattern in ATTACHMENTS.items():
                    if pattern.fullmatch(name):
                        found[key].append(
                            (exported / attachment["exportedFileName"]).read_text()
                        )
        required = ["preRateState", "tailState"]
        if observer_mode == "enabled":
            required.extend(("preRateCore", "tailCore"))
        for key in required:
            values = found[key]
            if len(values) != 1:
                raise ValueError(f"Expected exactly one {key} attachment, found {len(values)}")
        for key in set(ATTACHMENTS) - set(required):
            if len(found[key]) > 1:
                raise ValueError(f"Expected at most one {key} attachment, found {len(found[key])}")
        return {
            "preRateState": parse_state(found["preRateState"][0]),
            "preRateCore": json.loads(found["preRateCore"][0]) if found["preRateCore"] else None,
            "tailState": parse_state(found["tailState"][0]),
            "tailCore": json.loads(found["tailCore"][0]) if found["tailCore"] else None,
            "checkpointA": parse_state(found["checkpointA"][0]) if found["checkpointA"] else None,
            "checkpointB": parse_state(found["checkpointB"][0]) if found["checkpointB"] else None,
            "coreA": json.loads(found["coreA"][0]) if found["coreA"] else None,
            "coreB": json.loads(found["coreB"][0]) if found["coreB"] else None,
        }


def validate_disabled_observer(evidence: dict[str, object]) -> dict[str, object]:
    pre_rate_state = evidence["preRateState"]
    tail_state = evidence["tailState"]
    if not isinstance(pre_rate_state, dict) or not isinstance(tail_state, dict):
        raise ValueError("Recorder-disabled state evidence is malformed")

    failures = []
    try:
        actual_rate_gate_passed = float(tail_state["actualRate"]) > 0.5
    except (KeyError, ValueError, TypeError):
        actual_rate_gate_passed = False
    if not actual_rate_gate_passed:
        failures.append("tail actualRate did not exceed 0.5")

    first = evidence.get("checkpointA")
    second = evidence.get("checkpointB")
    continuous_checkpoints_captured = isinstance(first, dict) and isinstance(second, dict)
    if not continuous_checkpoints_captured:
        failures.append("actual-rate gate prevented continuous A/B checkpoints")
        first = first if isinstance(first, dict) else {}
        second = second if isinstance(second, dict) else {}
    else:
        if first.get("session") != second.get("session"):
            failures.append("checkpoint session changed")
        for key in (
            "position", "videoSamples", "rendererInputs", "audioSamples",
            "audioRendererSamples",
        ):
            try:
                if float(second[key]) <= float(first[key]):
                    failures.append(f"{key} did not increase")
            except (KeyError, ValueError, TypeError):
                failures.append(f"{key} is missing or malformed")
        for key in ("actualRate", "targetRate"):
            try:
                if float(second[key]) <= 0:
                    failures.append(f"{key} is not active")
            except (KeyError, ValueError, TypeError):
                failures.append(f"{key} is missing or malformed")
        if second.get("audioRendererStatus") != "rendering":
            failures.append("audio renderer is not rendering")
        if second.get("audioRendererError") != "none":
            failures.append("audio renderer reports an error")

    outcome = "passed" if not failures else "failed"
    return {
        "observerMode": "disabled",
        "outcome": outcome,
        "controlOutcome": {
            "outcome": outcome,
            "actualRateGatePassed": actual_rate_gate_passed,
            "continuousCheckpointsCaptured": continuous_checkpoints_captured,
        },
        "failures": failures,
        "checkpoints": {"first": first, "second": second},
        "preRate": {"state": pre_rate_state},
        "tail": {"state": tail_state},
    }


def validate_sufficient_reapply(evidence: dict[str, object]) -> dict[str, object]:
    pre_rate_state = evidence["preRateState"]
    tail_state = evidence["tailState"]
    if not isinstance(pre_rate_state, dict) or not isinstance(tail_state, dict):
        raise ValueError("Sufficient-rate-reapply state evidence is malformed")

    reapply_keys = (
        "reapplyActivationSequence",
        "reapplyAnchorValue",
        "reapplyAnchorTimescale",
        "reapplyAnchorEpoch",
        "reapplyAnchorFlags",
        "reapplyRequestedRate",
        "reapplyAudioRequired",
        "reapplyVideoSufficient",
        "reapplyAudioSufficient",
        "reapplyDirectRate",
        "reapplyEffectiveRate",
        "reapplyAttemptCount",
        "reapplyClaimCount",
        "reapplyOutcome",
    )
    reapply_snapshot = {key: tail_state.get(key) for key in reapply_keys}
    failures = []
    pre_actual_rate = state_float(pre_rate_state, "actualRate")
    if pre_actual_rate is None or abs(pre_actual_rate) > 0.01:
        failures.append("pre-reapply actualRate was not zero")

    video_sufficient = state_bool(tail_state, "reapplyVideoSufficient")
    audio_required = state_bool(tail_state, "reapplyAudioRequired")
    audio_sufficient = state_bool(tail_state, "reapplyAudioSufficient")
    if video_sufficient is False:
        failures.append("video never became sufficient before verification ended")
        return {
            "observerMode": "disabled",
            "experimentMode": "sufficient-then-reapply",
            "outcome": "inconclusive",
            "classification": "video_never_sufficient",
            "causalConclusion": "not_evaluated",
            "failures": failures,
            "controlOutcome": {
                "outcome": "inconclusive",
                "preReapplyActualRateWasZero": pre_actual_rate == 0,
                "doubleRendererSufficiencyEstablished": False,
                "hypothesisRejected": False,
            },
            "preRate": {"state": pre_rate_state},
            "tail": {"state": tail_state},
            "reapplySnapshot": reapply_snapshot,
            "checkpoints": {
                "first": evidence.get("checkpointA"),
                "second": evidence.get("checkpointB"),
            },
        }
    if video_sufficient is not True:
        failures.append("reapply video sufficiency evidence is missing or malformed")
    if audio_required is True and audio_sufficient is not True:
        failures.append("audio never became sufficient before verification ended")
        return {
            "observerMode": "disabled",
            "experimentMode": "sufficient-then-reapply",
            "outcome": "inconclusive",
            "classification": "audio_never_sufficient",
            "causalConclusion": "not_evaluated",
            "failures": failures,
            "controlOutcome": {
                "outcome": "inconclusive",
                "preReapplyActualRateWasZero": pre_actual_rate == 0,
                "doubleRendererSufficiencyEstablished": False,
                "hypothesisRejected": False,
            },
            "preRate": {"state": pre_rate_state},
            "tail": {"state": tail_state},
            "reapplySnapshot": reapply_snapshot,
            "checkpoints": {
                "first": evidence.get("checkpointA"),
                "second": evidence.get("checkpointB"),
            },
        }

    integer_keys = (
        "reapplyActivationSequence",
        "reapplyAnchorValue",
        "reapplyAnchorTimescale",
        "reapplyAnchorEpoch",
        "reapplyAnchorFlags",
    )
    for key in integer_keys:
        if state_int(tail_state, key) is None:
            failures.append(f"{key} is missing or malformed")
    if (state_int(tail_state, "reapplyActivationSequence") or 0) <= 0:
        failures.append("reapply activation sequence is not positive")
    if (state_int(tail_state, "reapplyAnchorTimescale") or 0) <= 0:
        failures.append("reapply anchor timescale is not positive")
    requested_rate = state_float(tail_state, "reapplyRequestedRate")
    if requested_rate is None or requested_rate <= 0:
        failures.append("reapply requested rate is not positive")
    for key in ("reapplyDirectRate", "reapplyEffectiveRate"):
        value = state_float(tail_state, key)
        if value is None or abs(value) > 0.01:
            failures.append(f"{key} was not zero before reapply")
    if state_int(tail_state, "reapplyAttemptCount") != 1:
        failures.append("reapply attempt count was not exactly one")
    if state_int(tail_state, "reapplyClaimCount") != 1:
        failures.append("reapply claim count was not exactly one")
    if tail_state.get("reapplyOutcome") != "reapplied":
        failures.append("reapply outcome was not reapplied")
    setup_failure_count = len(failures)

    actual_rate = state_float(tail_state, "actualRate")
    effective_rate = state_float(tail_state, "effectiveRate")
    rate_activated = (
        actual_rate is not None
        and effective_rate is not None
        and actual_rate > 0.5
        and effective_rate > 0.5
    )
    if not rate_activated:
        failures.append("reapply did not activate both direct and effective rates")

    first = evidence.get("checkpointA")
    second = evidence.get("checkpointB")
    continuous_checkpoints_captured = isinstance(first, dict) and isinstance(second, dict)
    if not continuous_checkpoints_captured:
        failures.append("post-reapply A/B checkpoints were not captured")
        first = first if isinstance(first, dict) else {}
        second = second if isinstance(second, dict) else {}
    else:
        if first.get("session") != second.get("session"):
            failures.append("checkpoint session changed")
        for key in (
            "position", "videoSamples", "rendererInputs", "audioSamples",
            "audioRendererSamples",
        ):
            first_value = state_float(first, key)
            second_value = state_float(second, key)
            if first_value is None or second_value is None:
                failures.append(f"{key} is missing or malformed")
            elif second_value <= first_value:
                failures.append(f"{key} did not increase")

    preconditions_established = (
        setup_failure_count == 0
        and video_sufficient is True
        and (audio_required is not True or audio_sufficient is True)
    )
    if not preconditions_established:
        classification = "preconditions_not_established"
        causal_conclusion = "not_evaluated"
    elif not rate_activated:
        classification = "reapply_did_not_activate_rate"
        causal_conclusion = "hypothesis_rejected"
    elif failures:
        classification = "reapply_did_not_restore_continuity"
        causal_conclusion = "hypothesis_rejected"
    else:
        classification = "reapply_restored_continuous_playback"
        causal_conclusion = "hypothesis_supported"
    outcome = "passed" if not failures else "failed"
    return {
        "observerMode": "disabled",
        "experimentMode": "sufficient-then-reapply",
        "outcome": outcome,
        "classification": classification,
        "causalConclusion": causal_conclusion,
        "failures": failures,
        "controlOutcome": {
            "outcome": outcome,
            "preReapplyActualRateWasZero": pre_actual_rate == 0,
            "doubleRendererSufficiencyEstablished": (
                video_sufficient is True
                and (audio_required is not True or audio_sufficient is True)
            ),
            "attemptCount": state_int(tail_state, "reapplyAttemptCount"),
            "claimCount": state_int(tail_state, "reapplyClaimCount"),
            "rateActivated": rate_activated,
            "continuousCheckpointsCaptured": continuous_checkpoints_captured,
            "hypothesisRejected": causal_conclusion == "hypothesis_rejected",
        },
        "preRate": {"state": pre_rate_state},
        "tail": {"state": tail_state},
        "reapplySnapshot": reapply_snapshot,
        "checkpoints": {"first": first, "second": second},
    }


def validate(
    evidence: dict[str, object],
    observer_mode: str = "enabled",
    experiment_mode: str = "baseline",
) -> dict[str, object]:
    if experiment_mode == "sufficient-reapply":
        if observer_mode != "disabled":
            raise ValueError("Sufficient-rate-reapply requires observer mode disabled")
        return validate_sufficient_reapply(evidence)
    if experiment_mode != "baseline":
        raise ValueError(f"Unsupported experiment mode: {experiment_mode}")
    if observer_mode == "disabled":
        return validate_disabled_observer(evidence)
    if observer_mode != "enabled":
        raise ValueError(f"Unsupported observer mode: {observer_mode}")

    pre_rate_state = evidence["preRateState"]
    pre_rate_core = evidence["preRateCore"]
    tail_state = evidence["tailState"]
    tail_core = evidence["tailCore"]
    if not isinstance(pre_rate_state, dict) or not isinstance(pre_rate_core, dict):
        raise ValueError("Pre-rate diagnostic evidence is malformed")
    if not isinstance(tail_state, dict) or not isinstance(tail_core, dict):
        raise ValueError("Tail diagnostic evidence is malformed")
    pre_rate_events = pre_rate_core.get("events")
    if not isinstance(pre_rate_events, list):
        raise ValueError("Pre-rate PlaybackCore events are malformed")
    pre_rate_kinds = {event.get("kind") for event in pre_rate_events if isinstance(event, dict)}
    activation_sequence = playback_activation_sequence(pre_rate_events)
    tail_events = tail_core.get("events")
    if not isinstance(tail_events, list):
        raise ValueError("Tail PlaybackCore events are malformed")
    tail_activation_sequence = playback_activation_sequence(tail_events)
    tail_timeline = playback_activation_timeline(tail_events)
    delivery_timeline = delivery_stage_timeline(tail_events)
    last_delivery_stages = {
        lane: next(
            (event for event in reversed(delivery_timeline) if event["lane"] == lane),
            None,
        )
        for lane in ("video", "audio")
    }
    task_phase_report = observation_task_phase_report(tail_events)
    first = evidence.get("checkpointA")
    second = evidence.get("checkpointB")
    failures = []
    activation_phases = [
        event.get("details", {}).get("phase")
        for event in activation_sequence
        if isinstance(event.get("details"), dict)
    ]
    for phase in ("call.before", "call.returned"):
        if phase not in activation_phases:
            failures.append(f"pre-rate observation is missing {phase}")
    scheduled_delays = {
        int(details["delayMs"])
        for event in tail_activation_sequence
        if isinstance((details := event.get("details")), dict)
        and details.get("phase") == "scheduledSample"
        and str(details.get("delayMs", "")).isdigit()
    }
    required_scheduled_delays = {10, 50, 100, 500, 2_000}
    missing_scheduled_delays = sorted(required_scheduled_delays - scheduled_delays)
    if missing_scheduled_delays:
        failures.append(
            "tail observation is missing scheduled delays: "
            + ", ".join(str(delay) for delay in missing_scheduled_delays)
        )
    for lane, stage in last_delivery_stages.items():
        if stage is None:
            failures.append(f"tail evidence is missing {lane} delivery stage markers")
    if not isinstance(first, dict) or not isinstance(second, dict):
        failures.append("actual-rate gate prevented continuous A/B checkpoints")
        first = first if isinstance(first, dict) else {}
        second = second if isinstance(second, dict) else {}
    if first.get("session") != second.get("session"):
        failures.append("checkpoint session changed")
    for key in ("position", "videoSamples", "rendererInputs", "audioSamples", "audioRendererSamples"):
        try:
            if float(second[key]) <= float(first[key]):
                failures.append(f"{key} did not increase")
        except (KeyError, ValueError, TypeError):
            failures.append(f"{key} is missing or malformed")
    for key in ("actualRate", "targetRate"):
        try:
            if float(second[key]) <= 0:
                failures.append(f"{key} is not active")
        except (KeyError, ValueError, TypeError):
            failures.append(f"{key} is missing or malformed")
    if second.get("audioRendererStatus") != "rendering":
        failures.append("audio renderer is not rendering")
    if second.get("audioRendererError") != "none":
        failures.append("audio renderer reports an error")

    core = evidence.get("coreB")
    if not isinstance(core, dict):
        core = tail_core
    snapshot = core.get("snapshot")
    events = core.get("events")
    if not isinstance(snapshot, dict) or not isinstance(events, list):
        raise ValueError("PlaybackCore diagnostic evidence is malformed")
    first_enqueue = next(
        (event for event in events if event.get("kind") == "audioRenderer.firstEnqueue"),
        None,
    )
    if not isinstance(first_enqueue, dict) or not isinstance(first_enqueue.get("details"), dict):
        raise ValueError("Missing audioRenderer.firstEnqueue event")
    required_details = {
        "asbd.sampleRate", "asbd.formatID", "asbd.formatFlags",
        "asbd.bytesPerPacket", "asbd.framesPerPacket", "asbd.bytesPerFrame",
        "asbd.channelsPerFrame", "asbd.bitsPerChannel", "channelLayoutSize",
        "magicCookieSize", "magicCookieHash", "ffmpeg.cookieSource",
        "ffmpeg.payloadByteCount", "ffmpeg.packetPTS", "ffmpeg.packetDTS",
        "ffmpeg.packetDuration", "ffmpeg.timeBaseNumerator",
        "ffmpeg.timeBaseDenominator", "presentationTime.value",
        "presentationTime.timescale", "decodeTime.value", "decodeTime.timescale",
        "duration.value", "duration.timescale",
    }
    missing = sorted(required_details - first_enqueue["details"].keys())
    if missing:
        raise ValueError(f"First AAC enqueue is missing: {', '.join(missing)}")
    kinds = {event.get("kind") for event in events}
    for required in (
        "audioRenderer.prerollCompleted",
        "audioRenderer.rateActivated",
        "audioRenderer.statusChanged",
    ):
        if evidence.get("coreB") is not None and required not in kinds:
            failures.append(f"missing {required} event")
    outcome = "passed" if not failures else "failed"
    return {
        "observerMode": "enabled",
        "outcome": outcome,
        "controlOutcome": {"outcome": outcome},
        "failures": failures,
        "checkpoints": {"first": first, "second": second},
        "preRate": {
            "state": pre_rate_state,
            "snapshot": pre_rate_core.get("snapshot"),
            "events": pre_rate_events,
            "eventKinds": sorted(kind for kind in pre_rate_kinds if isinstance(kind, str)),
            "hasPrerollCompleted": "audioRenderer.prerollCompleted" in pre_rate_kinds,
            "hasRateActivated": "audioRenderer.rateActivated" in pre_rate_kinds,
            "playbackActivationPhases": activation_phases,
            "playbackActivationSequence": activation_sequence,
        },
        "tail": {
            "state": tail_state,
            "snapshot": tail_core.get("snapshot"),
            "events": tail_events,
            "missingScheduledDelays": missing_scheduled_delays,
            "playbackActivationSequence": tail_activation_sequence,
            "playbackActivationTimeline": tail_timeline,
            "observationTaskPhases": task_phase_report,
            "deliveryStageTimeline": delivery_timeline,
            "lastDeliveryStages": last_delivery_stages,
        },
        "snapshot": snapshot,
        "firstAudioEnqueue": first_enqueue,
        "audioRendererEvents": events,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xcresult", type=Path, required=True)
    parser.add_argument("--stereo-wav", type=Path)
    parser.add_argument("--channel-1-wav", type=Path)
    parser.add_argument("--channel-2-wav", type=Path)
    parser.add_argument("--channel-selection", choices=("channel-1",), default="channel-1")
    parser.add_argument(
        "--observer-mode",
        choices=("enabled", "disabled"),
        required=True,
    )
    parser.add_argument(
        "--experiment-mode",
        choices=("baseline", "sufficient-reapply"),
        default="baseline",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    for path in (args.stereo_wav, args.channel_1_wav, args.channel_2_wav):
        if path is not None and not path.is_file():
            raise ValueError(f"Missing retained capture: {path}")
    result = validate(
        load_attachments(args.xcresult, observer_mode=args.observer_mode),
        observer_mode=args.observer_mode,
        experiment_mode=args.experiment_mode,
    )
    captures = {
        name: {"path": str(path), "sha256": sha256(path)}
        for name, path in (
            ("stereo", args.stereo_wav),
            ("channel1", args.channel_1_wav),
            ("channel2", args.channel_2_wav),
        )
        if path is not None
    }
    if captures:
        result["physicalAudioCapture"] = {
            "interpretation": "optional physical-output fact; not a causal verdict",
            "predeclaredChannel": args.channel_selection,
            **captures,
        }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["outcome"] == "passed" else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"real video AAC diagnostic error: {error}")
        raise SystemExit(2)
