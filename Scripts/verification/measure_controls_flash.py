#!/usr/bin/env python3
"""Record physical Vision Pro control toggles and report correlated black frames."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile
import time


APP_BUNDLE_ID = "com.xiongzhipeng.XrPlayer"
PROBE_REMOTE_PATH = "Documents/surface-tap-probe.log"
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"
EXTRACTOR = REPOSITORY_ROOT / "Scripts/verification/extract_visionpro_ui_recording.py"
PROBE_TIMESTAMP = re.compile(r"^(\S+)\s+(.*)$")


def active_developer_directory() -> str:
    completed = subprocess.run(
        ["xcode-select", "-p"],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


class RecordingSession:
    def __init__(
        self,
        *,
        device: str,
        developer_dir: str,
        execution_input: Path,
        output_directory: Path,
    ) -> None:
        self.device = device
        self.developer_dir = developer_dir
        self.execution_input = execution_input
        self.output_directory = output_directory
        self.started = False
        self.stopped = False

    def controller(self, *arguments: str) -> dict[str, object]:
        # CoreDevice error 7000 surfaces before the command file lands in the
        # app container, so the app never saw the command and one retry cannot
        # double-execute it.
        document = self.controller_once(*arguments)
        if (
            document.get("success") is False
            and "error 7000" in str(document.get("error", ""))
        ):
            time.sleep(3)
            document = self.controller_once(*arguments)
        return document

    def controller_once(self, *arguments: str) -> dict[str, object]:
        command = [
            sys.executable,
            str(CONTROLLER),
            "--device",
            self.device,
            "--developer-dir",
            self.developer_dir,
            "--execution-input",
            str(self.execution_input),
            "--output-directory",
            str(self.output_directory),
        ]
        command.extend(arguments)
        completed = subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            timeout=900,
        )
        try:
            document = json.loads(completed.stdout)
        except json.JSONDecodeError:
            document = {
                "success": False,
                "error": (completed.stderr or completed.stdout)[-2_000:],
            }
        if completed.returncode != 0 and document.get("success") is not False:
            document["success"] = False
            document["error"] = (completed.stderr or completed.stdout)[-2_000:]
        return document

    def ensure(self) -> dict[str, object]:
        result = self.controller("ensure-session")
        self.started = result.get("stage") == "ready"
        return result

    def stop(self) -> dict[str, object] | None:
        if self.started is False or self.stopped:
            return None
        self.stopped = True
        return self.controller("stop")


def reset_probe_log(
    *,
    device: str,
    developer_dir: str,
) -> str | None:
    # The app appends fat settlement lines at frame rate; container copies of a
    # grown file fail (CoreDevice 7000 / timeouts), so each run starts empty.
    with tempfile.NamedTemporaryFile(
        prefix="enchron-controls-probe-reset-",
        suffix=".log",
        delete=False,
    ) as handle:
        source = Path(handle.name)
    try:
        completed = subprocess.run(
            [
                "xcrun",
                "devicectl",
                "device",
                "copy",
                "to",
                "--device",
                device,
                "--domain-type",
                "appDataContainer",
                "--domain-identifier",
                APP_BUNDLE_ID,
                "--source",
                str(source),
                "--destination",
                PROBE_REMOTE_PATH,
            ],
            capture_output=True,
            text=True,
            env={**os.environ, "DEVELOPER_DIR": developer_dir},
            timeout=120,
        )
    finally:
        source.unlink(missing_ok=True)
    if completed.returncode != 0:
        return (completed.stderr or completed.stdout)[-2_000:]
    return None


def copy_probe_lines(
    *,
    device: str,
    developer_dir: str,
    output_directory: Path,
) -> tuple[list[str] | None, str | None]:
    for attempt in range(2):
        with tempfile.NamedTemporaryFile(
            prefix="enchron-controls-probe-",
            suffix=".log",
            delete=False,
        ) as handle:
            destination = Path(handle.name)
        destination.unlink(missing_ok=True)
        completed = subprocess.run(
            [
                "xcrun",
                "devicectl",
                "device",
                "copy",
                "from",
                "--device",
                device,
                "--domain-type",
                "appDataContainer",
                "--domain-identifier",
                APP_BUNDLE_ID,
                "--source",
                PROBE_REMOTE_PATH,
                "--destination",
                str(destination),
            ],
            capture_output=True,
            text=True,
            env={**os.environ, "DEVELOPER_DIR": developer_dir},
            timeout=120,
        )
        if completed.returncode == 0 and destination.is_file():
            lines = destination.read_text(
                encoding="utf-8", errors="replace"
            ).splitlines()
            (output_directory / "surface-tap-probe.log").write_text(
                "\n".join(lines) + "\n",
                encoding="utf-8",
            )
            destination.unlink(missing_ok=True)
            return lines, None
        destination.unlink(missing_ok=True)
        if attempt == 0:
            time.sleep(1.5)
    return None, (completed.stderr or completed.stdout)[-2_000:]


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


def wait_for_probe(
    *,
    device: str,
    developer_dir: str,
    output_directory: Path,
    after: datetime,
    pattern: str,
    timeout_seconds: float,
) -> list[str] | None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        lines, _ = copy_probe_lines(
            device=device,
            developer_dir=developer_dir,
            output_directory=output_directory,
        )
        if lines is not None and any(
            pattern in message
            for _, message in probe_events(lines, after=after)
        ):
            return lines
        time.sleep(1)
    return None


def luma_timeline(video: Path) -> list[tuple[float, float]]:
    completed = subprocess.run(
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
        capture_output=True,
        text=True,
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
        raise RuntimeError(completed.stderr[-2_000:])
    return samples


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
    # Probe timestamps have one-second precision. The original measured
    # control flashes lasted at most 0.43 seconds, so one timestamp bucket
    # covers the observed disturbance plus timestamp quantization.
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


def require_success(result: dict[str, object], action: str) -> None:
    if result.get("success") is not True:
        raise RuntimeError(f"{action} failed: {json.dumps(result, ensure_ascii=False)}")


def wait_for_result_bundle(
    output_directory: Path,
    *,
    developer_dir: str,
    timeout_seconds: float,
) -> list[Path]:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        bundles = sorted(
            output_directory.glob("*.xcresult"),
            key=lambda path: path.stat().st_mtime,
        )
        if bundles:
            completed = subprocess.run(
                [
                    "xcrun",
                    "xcresulttool",
                    "get",
                    "test-results",
                    "summary",
                    "--path",
                    str(bundles[-1]),
                ],
                capture_output=True,
                text=True,
                env={**os.environ, "DEVELOPER_DIR": developer_dir},
            )
            if completed.returncode == 0:
                return bundles
        time.sleep(1)
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--execution-input", type=Path, required=True)
    parser.add_argument("--developer-dir", default=active_developer_directory())
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
    parser.add_argument("--transition-timeout-seconds", type=float, default=20)
    parser.add_argument("--black-yavg", type=float, default=18)
    parser.add_argument("--fail-fast", action="store_true")
    arguments = parser.parse_args()

    evidence = arguments.output_directory.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    session = RecordingSession(
        device=arguments.device,
        developer_dir=arguments.developer_dir,
        execution_input=arguments.execution_input,
        output_directory=evidence,
    )
    run_started_at = datetime.now().astimezone()
    run_error: str | None = None
    probe_lines: list[str] | None = None
    probe_error: str | None = None
    stop_result: dict[str, object] | None = None
    phase_durations: dict[str, float] = {}
    phase_started_at = time.monotonic()

    def mark_phase(phase: str) -> None:
        nonlocal phase_started_at
        now = time.monotonic()
        phase_durations[phase] = round(now - phase_started_at, 3)
        phase_started_at = now

    try:
        reset_error = reset_probe_log(
            device=arguments.device,
            developer_dir=arguments.developer_dir,
        )
        if reset_error is not None:
            raise RuntimeError(f"probe log reset failed: {reset_error}")
        mark_phase("probeReset")
        ready = session.ensure()
        if ready.get("stage") != "ready":
            raise RuntimeError(
                f"session not ready: {json.dumps(ready, ensure_ascii=False)}"
            )
        mark_phase("ensureSession")
        require_success(
            session.controller(
                "tap",
                "--label",
                arguments.clip_label,
                "--no-screenshot",
            ),
            f"open {arguments.clip_label}",
        )
        mark_phase("openMedia")
        require_success(
            session.controller(
                "app-command",
                "--verb",
                "toggleControls",
                "--arg",
                "visible=true",
                "--no-screenshot",
            ),
            "show controls for Panorama entry",
        )
        require_success(
            session.controller(
                "tapSequence",
                "--identifiers",
                "PlayerUI-TopAction-resumePanorama",
                "--no-screenshot",
            ),
            "enter Panorama",
        )
        mark_phase("enterPanorama")
        probe_lines = wait_for_probe(
            device=arguments.device,
            developer_dir=arguments.developer_dir,
            output_directory=evidence,
            after=run_started_at,
            pattern="presentation portal -> panorama",
            timeout_seconds=arguments.transition_timeout_seconds,
        )
        if probe_lines is None:
            raise RuntimeError("Panorama did not settle before the transition timeout")
        mark_phase("panoramaSettleWait")
        for _ in range(arguments.toggles):
            require_success(
                session.controller(
                    "app-command",
                    "--verb",
                    "toggleControls",
                    "--no-screenshot",
                ),
                "toggle controls",
            )
            time.sleep(arguments.toggle_interval_seconds)
        latest_probe_lines, probe_error = copy_probe_lines(
            device=arguments.device,
            developer_dir=arguments.developer_dir,
            output_directory=evidence,
        )
        if latest_probe_lines is not None:
            probe_lines = latest_probe_lines
        if probe_lines is not None:
            visible_events = [
                message
                for _, message in probe_events(probe_lines, after=run_started_at)
                if "immersiveControlsAttachment visible=" in message
            ]
            if visible_events and "visible=false" in visible_events[-1]:
                require_success(
                    session.controller(
                        "app-command",
                        "--verb",
                        "toggleControls",
                        "--no-screenshot",
                    ),
                    "show controls for Panorama exit",
                )
        mark_phase("controlToggles")
        require_success(
            session.controller(
                "tapSequence",
                "--identifiers",
                "PlayerPanel-button-exit-spatial",
                "--no-screenshot",
            ),
            "exit spatial playback",
        )
        mark_phase("exitSequence")
    except Exception as error:
        run_error = str(error)
        mark_phase("failedPhase")
    finally:
        latest_probe_lines, latest_probe_error = copy_probe_lines(
            device=arguments.device,
            developer_dir=arguments.developer_dir,
            output_directory=evidence,
        )
        if latest_probe_lines is not None:
            probe_lines = latest_probe_lines
            probe_error = None
        elif probe_lines is None:
            probe_error = latest_probe_error
        stop_result = session.stop()
        mark_phase("teardown")

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

    bundles = wait_for_result_bundle(
        evidence,
        developer_dir=arguments.developer_dir,
        timeout_seconds=arguments.transition_timeout_seconds,
    )
    if not bundles:
        print(run_error or "no result bundle recovered", file=sys.stderr)
        return 1
    mark_phase("resultBundleWait")
    frames = evidence / "frames"
    completed = subprocess.run(
        [sys.executable, str(EXTRACTOR), str(bundles[-1]), str(frames)],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        env={**os.environ, "DEVELOPER_DIR": arguments.developer_dir},
    )
    if completed.returncode != 0:
        print(completed.stderr or completed.stdout, file=sys.stderr)
        return 1
    mark_phase("recordingExtraction")
    index = json.loads((frames / "recording-index.json").read_text(encoding="utf-8"))
    recording = index["recordings"][-1]
    video = frames / recording["video"]
    samples = luma_timeline(video)
    mark_phase("lumaAnalysis")
    if not samples:
        print("ffmpeg produced no luma samples", file=sys.stderr)
        return 1
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
            contains="presentation portal -> panorama",
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
