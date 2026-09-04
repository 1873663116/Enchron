from __future__ import annotations

import os
import shutil
import signal
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from harness.budgets import Budget
from harness.failures import InstrumentFault
from harness.waits import wait_for

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SEGMENT_DIRECTORY = "enchron-segments"
SEGMENT_CODEC = "h264"
SEGMENT_SUFFIX = ".mp4"
IDENTIFIER_SEPARATOR = ":"
FILENAME_SEPARATOR = "--"
START_BUDGET = Budget(
    30.0,
    "simctl creates the output file as soon as the recorder is running",
)
STOP_TIMEOUT_SECONDS = 120.0
STOP_SIGNAL = signal.SIGINT

ACTIVE_SEGMENTS: dict[str, "Segment"] = {}


class RecordingError(RuntimeError):
    pass


@dataclass(frozen=True)
class Segment:
    udid: str
    node: str
    attempt: int
    scenario: str
    path: Path
    process: subprocess.Popen


def temporary_root() -> Path:
    root = Path(os.environ.get("TMPDIR") or tempfile.gettempdir()).resolve()
    if root == REPOSITORY_ROOT or REPOSITORY_ROOT in root.parents:
        raise RecordingError(
            f"simctl refuses any output path inside the checkout, and TMPDIR is "
            f"{root}; segment recording needs a TMPDIR outside {REPOSITORY_ROOT}"
        )
    return root


def segment_root(udid: str) -> Path:
    return temporary_root() / SEGMENT_DIRECTORY / udid


def segment_filename(node: str, attempt: int) -> str:
    encoded = node.replace(IDENTIFIER_SEPARATOR, FILENAME_SEPARATOR)
    return f"{encoded}-{attempt}{SEGMENT_SUFFIX}"


def recorder_command(udid: str, path: Path) -> list[str]:
    return [
        "xcrun",
        "simctl",
        "io",
        udid,
        "recordVideo",
        "--codec",
        SEGMENT_CODEC,
        str(path),
    ]


def start_segment(udid: str, node: str, attempt: int, scenario: str) -> Segment:
    if attempt < 1:
        raise RecordingError(f"attempts are numbered from one, not {attempt}")
    running = ACTIVE_SEGMENTS.get(udid)
    if running is not None:
        raise RecordingError(
            f"{udid} {_recorder_state(running)} {running.node} attempt "
            f"{running.attempt} for {running.scenario}; one segment covers one "
            f"Scenario, so stop that one before starting {node} attempt {attempt}"
        )
    root = segment_root(udid)
    root.mkdir(parents=True, exist_ok=True)
    path = root / segment_filename(node, attempt)
    _clear(path)
    process = subprocess.Popen(
        recorder_command(udid, path),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    segment = Segment(udid, node, attempt, scenario, path, process)
    await_recorder(segment)
    ACTIVE_SEGMENTS[udid] = segment
    return segment


def _recorder_state(segment: Segment) -> str:
    code = segment.process.poll()
    if code is None:
        return "is still recording"
    return f"left a recorder that exited {code} without being stopped on"


def _clear(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        raise RecordingError(
            f"{path} is a directory, so no segment can be recorded there"
        )
    if os.path.lexists(path):
        path.unlink(missing_ok=True)


def await_recorder(segment: Segment) -> None:
    def probe() -> dict[str, object] | None:
        if segment.process.poll() is not None:
            raise RecordingError(
                f"simctl refused to record {segment.udid} into {segment.path}: "
                f"{_drain(segment).strip()}"
            )
        if segment.path.exists():
            return {"segment": str(segment.path)}
        return None

    def observe() -> list[object]:
        return [{"segment": str(segment.path), "exists": segment.path.exists()}]

    try:
        wait_for(f"segment {segment.path.name}", probe, START_BUDGET, observe)
    except InstrumentFault as expiry:
        segment.process.kill()
        raise RecordingError(
            f"the recorder for {segment.node} attempt {segment.attempt} produced no "
            f"file at {segment.path} within {START_BUDGET.seconds:.0f}s and was "
            f"killed: {_drain(segment).strip()}"
        ) from expiry
    except BaseException:
        if segment.process.poll() is None:
            segment.process.kill()
            _drain(segment)
        raise


def _drain(segment: Segment) -> str:
    _, noise = segment.process.communicate()
    return noise or ""


def stop_segment(segment: Segment, destination: Path) -> Path:
    if ACTIVE_SEGMENTS.get(segment.udid) is not segment:
        raise RecordingError(
            f"the segment for {segment.node} attempt {segment.attempt} is not the "
            f"one {segment.udid} is recording; it was already stopped"
        )
    process = segment.process
    if process.poll() is None:
        process.send_signal(STOP_SIGNAL)
    try:
        _, noise = process.communicate(timeout=STOP_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        ACTIVE_SEGMENTS.pop(segment.udid)
        raise RecordingError(
            f"the recorder for {segment.node} attempt {segment.attempt} ignored "
            f"{STOP_SIGNAL.name} for {STOP_TIMEOUT_SECONDS:.0f}s and was killed; "
            f"{segment.path} holds whatever it had flushed"
        )
    ACTIVE_SEGMENTS.pop(segment.udid)
    if process.returncode != 0:
        raise RecordingError(
            f"the recorder for {segment.node} attempt {segment.attempt} exited "
            f"{process.returncode} and {segment.path} was left where it lies: "
            f"{(noise or '').strip()}"
        )
    if not segment.path.is_file() or segment.path.stat().st_size == 0:
        raise RecordingError(
            f"the recorder for {segment.node} attempt {segment.attempt} exited "
            f"cleanly and left no bytes at {segment.path}"
        )
    try:
        destination.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise RecordingError(
            f"{destination} takes no segment, and {segment.path} still holds this "
            f"one: {error}"
        ) from error
    landed = destination / segment.path.name
    if landed.exists():
        raise RecordingError(
            f"{landed} already holds a segment; filing {segment.path} over it would "
            "replace evidence that is already recorded"
        )
    shutil.move(str(segment.path), str(landed))
    return landed
