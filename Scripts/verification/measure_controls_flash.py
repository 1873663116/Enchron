#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, TypeVar

import enchron_target
from harness import (
    Budget,
    BudgetProvider,
    ControllerClient,
    FaultRecord,
    Halt,
    InstrumentFault,
    LocalToolRunner,
    ProductFailure,
    RecoveryPolicy,
    wait_for,
)

APP_BUNDLE_ID = "com.xiongzhipeng.Enchron"
PROBE_REMOTE_PATH = "Documents/surface-tap-probe.log"
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"
EXTRACTOR = REPOSITORY_ROOT / "Scripts/verification/extract_visionpro_ui_recording.py"
PROBE_TIMESTAMP = re.compile(r"^(\S+)\s+(.*)$")
PANORAMA_SETTLE_PATTERN = "presentation portal -> panorama"
PACING_POLL_SLACK_SECONDS = 5.0

Outcome = TypeVar("Outcome")


class ProductHalt(Exception):
    def __init__(self, action: str, failure: ProductFailure) -> None:
        self.action = action
        self.failure = failure
        super().__init__(f"{action} failed with product failure {failure.kind}")


@dataclass
class Instruments:
    device: str
    core_device: str
    developer_dir: str
    lane: str
    budgets: BudgetProvider
    controller: ControllerClient
    tools: LocalToolRunner
    policy: RecoveryPolicy
    history: list[FaultRecord] = field(default_factory=list)

    def record_wait_sample(self, label: str, seconds: float, censored: bool) -> None:
        self.budgets.record_sample(self.lane, label, seconds, censored)

    def tool_env(self) -> dict[str, str]:
        return {**os.environ, "DEVELOPER_DIR": self.developer_dir}


def recovered(
    instruments: Instruments, location: str, action: Callable[[], Outcome]
) -> Outcome:
    while True:
        instruments.policy.record_action()
        try:
            return action()
        except InstrumentFault as fault:
            instruments.history.append(
                FaultRecord(
                    location=location,
                    kind=fault.kind,
                    censored=fault.kind in ("transport-timeout", "wait-expired"),
                )
            )
            decision = instruments.policy.on_fault(fault, instruments.history)
            if isinstance(decision, Halt):
                fault.evidence["halt"] = {
                    "reason": decision.reason,
                    "faultReport": decision.report,
                }
                raise


def invoke(
    instruments: Instruments, action: str, verb: str, *arguments: str
) -> dict[str, object]:
    response = recovered(
        instruments,
        f"{action}:{verb}",
        lambda: instruments.controller.invoke(verb, list(arguments)),
    )
    if response.failure is not None:
        raise ProductHalt(action, response.failure)
    return response.document


def invoke_stop(instruments: Instruments) -> dict[str, object]:
    response = recovered(
        instruments,
        "teardown:stop",
        lambda: instruments.controller.invoke("stop"),
    )
    return response.document


def reset_probe_log(instruments: Instruments) -> None:
    def attempt() -> None:
        completed = instruments.tools.call(
            "probe-copy",
            lambda budget: enchron_target.truncate_in_container(
                target=instruments.device,
                bundle_id=APP_BUNDLE_ID,
                source=PROBE_REMOTE_PATH,
                developer_dir=instruments.developer_dir,
                core_device_identifier=instruments.core_device,
                budget_seconds=budget.seconds,
            ),
        )
        if completed.returncode != 0:
            raise InstrumentFault(
                "probe-copy-failed",
                {
                    "operation": "reset",
                    "stderr": (completed.stderr or completed.stdout)[-2_000:],
                    "diagnosis": (
                        "the probe log could not be emptied before the run; a "
                        "grown log left by a previous run makes container "
                        "copies fail and contaminates event attribution"
                    ),
                },
            )

    recovered(instruments, "probe-reset", attempt)


def copy_probe_lines(
    instruments: Instruments, evidence_dir: Path, location: str
) -> list[str]:
    def attempt() -> list[str]:
        with tempfile.NamedTemporaryFile(
            prefix="enchron-controls-probe-",
            suffix=".log",
            delete=False,
        ) as handle:
            destination = Path(handle.name)
        destination.unlink(missing_ok=True)
        completed = instruments.tools.call(
            "probe-copy",
            lambda budget: enchron_target.copy_from_container(
                target=instruments.device,
                bundle_id=APP_BUNDLE_ID,
                source=PROBE_REMOTE_PATH,
                destination=destination,
                developer_dir=instruments.developer_dir,
                core_device_identifier=instruments.core_device,
                budget_seconds=budget.seconds,
            ),
        )
        if completed.returncode != 0 or not destination.is_file():
            destination.unlink(missing_ok=True)
            raise InstrumentFault(
                "probe-copy-failed",
                {
                    "operation": "read",
                    "stderr": (completed.stderr or completed.stdout)[-2_000:],
                    "diagnosis": (
                        "the probe log did not come back from the app "
                        "container; without it no event can be correlated "
                        "with the recording"
                    ),
                },
            )
        lines = destination.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines()
        destination.unlink(missing_ok=True)
        (evidence_dir / "surface-tap-probe.log").write_text(
            "\n".join(lines) + "\n",
            encoding="utf-8",
        )
        return lines

    return recovered(instruments, location, attempt)


def wait_for_panorama_settle(
    instruments: Instruments, evidence_dir: Path, after: datetime
) -> list[str]:
    latest: list[str] = []

    def probe() -> dict[str, object] | None:
        lines = copy_probe_lines(
            instruments, evidence_dir, "panorama-settle:probe-copy"
        )
        latest[:] = lines
        if any(
            PANORAMA_SETTLE_PATTERN in message
            for _, message in probe_events(lines, after=after)
        ):
            return {"pattern": PANORAMA_SETTLE_PATTERN, "lineCount": len(lines)}
        return None

    def observe() -> list[object]:
        return [message for _, message in probe_events(latest, after=after)][-20:]

    wait_for(
        "panorama-settle",
        probe,
        instruments.budgets.budget(instruments.lane, "panorama-settle"),
        observe,
        record=instruments.record_wait_sample,
    )
    return list(latest)


def hold(instruments: Instruments, label: str, seconds: float) -> None:
    if seconds <= 0:
        return
    started = datetime.now(timezone.utc)

    def probe() -> dict[str, object] | None:
        elapsed = (datetime.now(timezone.utc) - started).total_seconds()
        if elapsed >= seconds:
            return {"heldSeconds": round(elapsed, 3)}
        return None

    wait_for(
        label,
        probe,
        Budget(
            seconds=seconds + PACING_POLL_SLACK_SECONDS,
            provenance=(
                f"pacing hold {seconds:g}s from --toggle-interval-seconds "
                f"+ {PACING_POLL_SLACK_SECONDS:g}s poll slack"
            ),
        ),
        observe=lambda: [],
        record=instruments.record_wait_sample,
    )


def wait_for_result_bundle(
    instruments: Instruments, evidence_dir: Path
) -> list[Path]:
    found: list[Path] = []

    def probe() -> dict[str, object] | None:
        bundles = sorted(
            evidence_dir.glob("*.xcresult"),
            key=lambda path: path.stat().st_mtime,
        )
        if not bundles:
            return None
        summary = instruments.tools.run(
            "xcresult-summary",
            [
                "xcrun",
                "xcresulttool",
                "get",
                "test-results",
                "summary",
                "--path",
                str(bundles[-1]),
            ],
            env=instruments.tool_env(),
        )
        if summary.returncode != 0:
            return None
        found[:] = bundles
        return {"bundle": str(bundles[-1]), "bundleCount": len(bundles)}

    def observe() -> list[object]:
        return [str(path) for path in sorted(evidence_dir.glob("*.xcresult"))]

    wait_for(
        "result-bundle",
        probe,
        instruments.budgets.budget(instruments.lane, "result-bundle"),
        observe,
        record=instruments.record_wait_sample,
    )
    return list(found)


def extract_recording(
    instruments: Instruments, bundle: Path, frames: Path
) -> None:
    completed = instruments.tools.run(
        "recording-extraction",
        [sys.executable, str(EXTRACTOR), str(bundle), str(frames)],
        env=instruments.tool_env(),
    )
    if completed.returncode != 0:
        raise InstrumentFault(
            "recording-extraction-failed",
            {
                "bundle": str(bundle),
                "exitCode": completed.returncode,
                "stderr": (completed.stderr or completed.stdout)[-2_000:],
                "diagnosis": (
                    "the recording extractor could not read the result "
                    "bundle, so no frames exist to analyze"
                ),
            },
        )


def luma_timeline(
    instruments: Instruments, video: Path
) -> list[tuple[float, float]]:
    completed = instruments.tools.run(
        "luma-analysis",
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            str(video),
            "-vf",
            "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-",
            "-f",
            "null",
            "-",
        ],
        env=instruments.tool_env(),
    )
    samples: list[tuple[float, float]] = []
    seconds: float | None = None
    for line in (completed.stdout + "\n" + completed.stderr).splitlines():
        timestamp = re.search(r"pts_time:([0-9.]+)", line)
        if timestamp is not None:
            seconds = float(timestamp.group(1))
            continue
        if "lavfi.signalstats.YAVG=" in line and seconds is not None:
            samples.append((seconds, float(line.rsplit("=", 1)[1])))
    if completed.returncode != 0:
        raise InstrumentFault(
            "luma-analysis-failed",
            {
                "video": str(video),
                "exitCode": completed.returncode,
                "stderr": completed.stderr[-2_000:],
                "diagnosis": "ffmpeg could not decode the recording",
            },
        )
    if not samples:
        raise InstrumentFault(
            "luma-analysis-failed",
            {
                "video": str(video),
                "diagnosis": "ffmpeg produced no luma samples",
            },
        )
    return samples


def probe_events(
    lines: list[str],
    *,
    after: datetime,
) -> list[tuple[datetime, str]]:
    events: list[tuple[datetime, str]] = []
    for line in lines:
        match = PROBE_TIMESTAMP.match(line)
        if match is None:
            continue
        try:
            timestamp = datetime.fromisoformat(
                match.group(1).replace("Z", "+00:00")
            )
        except ValueError:
            continue
        if timestamp >= after:
            events.append((timestamp, match.group(2)))
    return events


def black_spans(
    samples: list[tuple[float, float]],
    threshold: float,
) -> list[dict[str, float | int]]:
    frame_intervals = [
        current[0] - previous[0]
        for previous, current in zip(samples, samples[1:])
        if current[0] > previous[0]
    ]
    contiguous_gap = statistics.median(frame_intervals) * 1.5
    spans: list[dict[str, float | int]] = []
    for seconds, yavg in samples:
        if yavg >= threshold:
            continue
        if spans and seconds - float(spans[-1]["endSeconds"]) <= contiguous_gap:
            spans[-1]["endSeconds"] = seconds
            spans[-1]["frames"] = int(spans[-1]["frames"]) + 1
            spans[-1]["minYAVG"] = min(float(spans[-1]["minYAVG"]), yavg)
        else:
            spans.append(
                {
                    "startSeconds": seconds,
                    "endSeconds": seconds,
                    "frames": 1,
                    "minYAVG": yavg,
                }
            )
    for span in spans:
        span["startSeconds"] = round(float(span["startSeconds"]), 3)
        span["endSeconds"] = round(float(span["endSeconds"]), 3)
        span["durationSeconds"] = round(
            float(span["endSeconds"]) - float(span["startSeconds"]),
            3,
        )
        span["minYAVG"] = round(float(span["minYAVG"]), 3)
    return spans


def event_seconds(
    events: list[tuple[datetime, str]],
    *,
    recording_started_at: float,
    contains: str,
) -> list[float]:
    return [
        round(timestamp.timestamp() - recording_started_at, 3)
        for timestamp, message in events
        if contains in message
    ]


def probe_field(message: str, name: str) -> str | None:
    match = re.search(rf"(?:^| ){re.escape(name)}=([^ ]+)", message)
    return match.group(1) if match is not None else None


def topology_ownership_outcome(
    events: list[tuple[datetime, str]],
) -> dict[str, object]:
    write_ids: list[str] = []
    verification_by_write_id: dict[str, list[bool]] = {}
    for _, message in events:
        if "spatialVideoTopology reconciled" in message:
            if write_id := probe_field(message, "writeID"):
                write_ids.append(write_id)
        elif "spatialVideoTopology ownershipVerified" in message:
            write_id = probe_field(message, "writeID")
            chain_active = probe_field(message, "ancestorChainActive")
            if write_id is not None and chain_active in {"true", "false"}:
                verification_by_write_id.setdefault(write_id, []).append(
                    chain_active == "true"
                )

    failed_write_ids = sorted(
        write_id
        for write_id, observations in verification_by_write_id.items()
        if False in observations
    )
    unverified_write_ids = sorted(
        write_id
        for write_id in write_ids
        if True not in verification_by_write_id.get(write_id, [])
    )
    return {
        "writeIDs": write_ids,
        "verifiedActiveWriteIDs": sorted(
            write_id
            for write_id, observations in verification_by_write_id.items()
            if True in observations
        ),
        "failedWriteIDs": failed_write_ids,
        "unverifiedWriteIDs": unverified_write_ids,
    }


def spans_for_events(
    spans: list[dict[str, float | int]],
    marks: list[float],
) -> list[dict[str, float | int]]:
    return [
        span
        for span in spans
        if any(
            mark <= float(span["endSeconds"])
            and float(span["startSeconds"]) < mark + 1
            for mark in marks
        )
    ]


def spans_during_phases(
    spans: list[dict[str, float | int]],
    starts: list[float],
    ends: list[float],
    recording_end: float,
) -> list[dict[str, float | int]]:
    phases = [
        (
            start,
            next((end for end in ends if end > start), recording_end),
        )
        for start in starts
    ]
    return [
        span
        for span in spans
        if any(
            start <= float(span["endSeconds"])
            and float(span["startSeconds"]) < end
            for start, end in phases
        )
    ]


def report_instrument_fault(
    evidence_dir: Path,
    instruments: Instruments,
    fault: InstrumentFault,
    phase_durations: dict[str, float],
) -> int:
    report = {
        "instrumentFault": {
            "kind": fault.kind,
            "evidence": fault.evidence,
            "budget": fault.budget.provenance if fault.budget else None,
        },
        "faultReport": instruments.policy.fault_report(),
        "phaseDurationsSeconds": phase_durations,
    }
    (evidence_dir / "instrument-fault.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, indent=2, sort_keys=True), file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Record physical Vision Pro control toggles and report "
            "correlated black frames."
        )
    )
    parser.add_argument("--device", required=True)
    parser.add_argument("--execution-input", type=Path, required=True)
    parser.add_argument("--developer-dir", default=None)
    parser.add_argument(
        "--output-directory",
        "--evidence-dir",
        dest="output_directory",
        type=Path,
        required=True,
    )
    parser.add_argument("--clip-label", default="180_3D")
    parser.add_argument("--toggles", type=int, default=4)
    parser.add_argument("--toggle-interval-seconds", type=float, default=8)
    parser.add_argument("--black-yavg", type=float, default=18)
    parser.add_argument("--fail-fast", action="store_true")
    arguments = parser.parse_args()

    developer_dir = (
        arguments.developer_dir or enchron_target.developer_directory()
    )
    evidence = arguments.output_directory.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    lane = "simulator" if enchron_target.is_simulator(arguments.device) else "device"
    budgets = BudgetProvider()
    instruments = Instruments(
        device=arguments.device,
        core_device=enchron_target.core_device(),
        developer_dir=developer_dir,
        lane=lane,
        budgets=budgets,
        controller=ControllerClient(
            lane,
            command_prefix=[
                sys.executable,
                str(CONTROLLER),
                "--device",
                arguments.device,
                "--developer-dir",
                developer_dir,
                "--execution-input",
                str(arguments.execution_input),
                "--output-directory",
                str(evidence),
            ],
            budgets=budgets,
        ),
        tools=LocalToolRunner(lane, budgets=budgets),
        policy=RecoveryPolicy(),
    )

    run_started_at = datetime.now().astimezone()
    run_error: str | None = None
    probe_lines: list[str] | None = None
    probe_error: str | None = None
    stop_result: dict[str, object] | None = None
    session_started = False
    fault_in_flight: InstrumentFault | None = None
    phase_durations: dict[str, float] = {}
    phase_started_at = datetime.now(timezone.utc)

    def mark_phase(phase: str) -> None:
        nonlocal phase_started_at
        now = datetime.now(timezone.utc)
        phase_durations[phase] = round(
            (now - phase_started_at).total_seconds(), 3
        )
        phase_started_at = now

    try:
        reset_probe_log(instruments)
        mark_phase("probeReset")
        ready = invoke(instruments, "ensure session", "ensure-session")
        session_started = ready.get("stage") == "ready"
        if not session_started:
            raise InstrumentFault(
                "session-lost",
                {
                    "document": ready,
                    "diagnosis": (
                        "ensure-session succeeded without reaching stage=ready"
                    ),
                },
            )
        mark_phase("ensureSession")
        invoke(
            instruments,
            f"open {arguments.clip_label}",
            "tap",
            "--label",
            arguments.clip_label,
            "--no-screenshot",
        )
        mark_phase("openMedia")
        invoke(
            instruments,
            "show controls for Panorama entry",
            "app-command",
            "--verb",
            "toggleControls",
            "--arg",
            "visible=true",
            "--no-screenshot",
        )
        invoke(
            instruments,
            "enter Panorama",
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-resumePanorama",
            "--no-screenshot",
        )
        mark_phase("enterPanorama")
        probe_lines = wait_for_panorama_settle(
            instruments, evidence, run_started_at
        )
        mark_phase("panoramaSettleWait")
        for _ in range(arguments.toggles):
            invoke(
                instruments,
                "toggle controls",
                "app-command",
                "--verb",
                "toggleControls",
                "--no-screenshot",
            )
            hold(
                instruments,
                "toggle-interval",
                arguments.toggle_interval_seconds,
            )
        probe_lines = copy_probe_lines(
            instruments, evidence, "post-toggle:probe-copy"
        )
        visible_events = [
            message
            for _, message in probe_events(probe_lines, after=run_started_at)
            if "immersiveControlsAttachment visible=" in message
        ]
        if visible_events and "visible=false" in visible_events[-1]:
            invoke(
                instruments,
                "show controls for Panorama exit",
                "app-command",
                "--verb",
                "toggleControls",
                "--no-screenshot",
            )
        mark_phase("controlToggles")
        invoke(
            instruments,
            "exit spatial playback",
            "tapSequence",
            "--identifiers",
            "PlayerPanel-button-exit-spatial",
            "--no-screenshot",
        )
        mark_phase("exitSequence")
    except ProductHalt as halt:
        run_error = f"{halt.action} failed: " + json.dumps(
            {"kind": halt.failure.kind, "evidence": halt.failure.evidence},
            ensure_ascii=False,
        )
        mark_phase("failedPhase")
    except InstrumentFault as fault:
        fault_in_flight = fault
        mark_phase("failedPhase")

    try:
        probe_lines = copy_probe_lines(
            instruments, evidence, "teardown:probe-copy"
        )
    except InstrumentFault as fault:
        fault_in_flight = fault_in_flight or fault
    if session_started:
        try:
            stop_result = invoke_stop(instruments)
        except InstrumentFault as fault:
            fault_in_flight = fault_in_flight or fault
    mark_phase("teardown")

    if fault_in_flight is not None:
        return report_instrument_fault(
            evidence, instruments, fault_in_flight, phase_durations
        )

    if arguments.fail_fast and run_error is not None:
        report = {
            "runError": run_error,
            "probeError": probe_error,
            "stopResult": stop_result,
            "phaseDurationsSeconds": phase_durations,
            "failFast": True,
        }
        (evidence / "flash-report.json").write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1

    try:
        bundles = wait_for_result_bundle(instruments, evidence)
        mark_phase("resultBundleWait")
        frames = evidence / "frames"
        extract_recording(instruments, bundles[-1], frames)
        mark_phase("recordingExtraction")
        index = json.loads(
            (frames / "recording-index.json").read_text(encoding="utf-8")
        )
        recording = index["recordings"][-1]
        video = frames / recording["video"]
        samples = luma_timeline(instruments, video)
        mark_phase("lumaAnalysis")
    except InstrumentFault as fault:
        return report_instrument_fault(
            evidence, instruments, fault, phase_durations
        )

    spans = black_spans(samples, arguments.black_yavg)
    events = probe_events(probe_lines or [], after=run_started_at)
    recording_started_at = float(recording["startedAt"])
    all_toggle_marks = event_seconds(
        events,
        recording_started_at=recording_started_at,
        contains="testcmd toggleControls begin",
    )
    toggle_marks = all_toggle_marks[: arguments.toggles]
    exit_preparation_toggle_marks = all_toggle_marks[arguments.toggles :]
    control_phase_end = (
        exit_preparation_toggle_marks[0]
        if exit_preparation_toggle_marks
        else samples[-1][0]
    )
    visibility_marks = [
        mark
        for mark in event_seconds(
            events,
            recording_started_at=recording_started_at,
            contains="immersiveControlsAttachment visible=",
        )
        if toggle_marks
        and toggle_marks[0] <= mark < control_phase_end
    ]
    entry_marks = event_seconds(
        events,
        recording_started_at=recording_started_at,
        contains="immersiveSpaceAppeared",
    )
    if not entry_marks:
        entry_marks = event_seconds(
            events,
            recording_started_at=recording_started_at,
            contains=PANORAMA_SETTLE_PATTERN,
        )
    toggle_blackouts = spans_for_events(spans, toggle_marks)
    visibility_blackouts = spans_for_events(spans, visibility_marks)
    entry_blackouts = spans_during_phases(
        spans,
        entry_marks,
        toggle_marks,
        samples[-1][0],
    )
    topology_ownership = topology_ownership_outcome(events)
    report = {
        "recording": str(video),
        "recordingStartedAt": recording_started_at,
        "frameCount": len(samples),
        "blackYAVGThreshold": arguments.black_yavg,
        "blackouts": spans,
        "toggleMarksSeconds": toggle_marks,
        "toggleBlackouts": toggle_blackouts,
        "controlVisibilityMarksSeconds": visibility_marks,
        "controlVisibilityBlackouts": visibility_blackouts,
        "exitPreparationToggleMarksSeconds": exit_preparation_toggle_marks,
        "panoramaEntryMarksSeconds": entry_marks,
        "panoramaEntryBlackouts": entry_blackouts,
        "topologyOwnership": topology_ownership,
        "runError": run_error,
        "probeError": probe_error,
        "stopResult": stop_result,
        "phaseDurationsSeconds": phase_durations,
    }
    (evidence / "flash-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    if (
        run_error is not None
        or probe_error is not None
        or len(toggle_marks) != arguments.toggles
        or not entry_marks
        or stop_result is None
        or stop_result.get("success") is not True
        or not topology_ownership["writeIDs"]
        or bool(topology_ownership["failedWriteIDs"])
        or bool(topology_ownership["unverifiedWriteIDs"])
    ):
        return 1
    return 0 if not toggle_blackouts and not visibility_blackouts else 2


if __name__ == "__main__":
    raise SystemExit(main())
