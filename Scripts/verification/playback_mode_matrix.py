#!/usr/bin/env python3

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time
from typing import NamedTuple, Sequence
import uuid


DEVICE = "00008142-001871A11491401C"
CORE_DEVICE = "59E3D57A-0288-53DC-9A7D-B657B6939558"
BUNDLE = "com.xiongzhipeng.XrPlayer"
DEVELOPER_DIR = "/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer"
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"
DEFAULT_EVIDENCE_ROOT = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/"
    "playback-mode-coverage-20260809"
)

CONTROL_PLANE_IDENTIFIER = "PlayerUI-window-control-plane"
PROBE_REMOTE_PATH = "Documents/surface-tap-probe.log"
CONTROLLER_TIMEOUT_SECONDS = 600.0
# A copy against a container whose app is not currently running hangs rather
# than failing, and one that catches the app mid-relaunch has been measured
# taking 70s before recovering. The bound is there to end the hang, so it has
# to sit above the slow-but-finite case or it converts recovery into a stall.
PROBE_COPY_TIMEOUT_SECONDS = 150.0
# This window must outlast the product's 31-second settlement deadline.
SETTLEMENT_TIMEOUT_SECONDS = 40.0
POLL_INTERVAL_SECONDS = 2.0
STALL_RECOVERY_SECONDS = 8.0

REGRESSION_BANNER = (
    "playback_mode_matrix is the regression instrument: it sweeps the "
    "clip x path x rep cell grid to surface cross-breakage after a batch of "
    "fixes. Each cell re-establishes its own automation session "
    "(ensure-session measured 25.7s, 2026-08-09); recorded full rounds take "
    "tens of minutes, and the failing moment inside a cell is not observable "
    "live. Per-cell verdicts stream to results.jsonl."
)

PASS = "PASS"
STALL_RECOVERED = "STALL_RECOVERED"
STALL_TIMEOUT = "STALL_TIMEOUT"
WRONG_STATE = "WRONG_STATE"
DRIVE_ERROR = "DRIVE_ERROR"
PASSING_VERDICTS = frozenset((PASS, STALL_RECOVERED))

DEFAULT_CLIPS = ("180_3D.mp4", "180_3D_TB.mp4")
STEREO_LABELS = {
    "180_3D.mp4": "Side-by-Side",
    "180_3D_TB.mp4": "Top-Bottom",
    # Ten-minute stream-copy loops of the sanctioned clips; the 60s originals
    # end mid-path on multi-step cycle paths. Generated under
    # TestEvidence/fixtures, selected via --media-root.
    "180_3D_loop10.mp4": "Side-by-Side",
    "180_3D_TB_loop10.mp4": "Top-Bottom",
}

FORMAT_FIELDS = (
    "presentation",
    "transition",
    "projection",
    "formatProvenance",
    "sourceContentKind",
    "effectiveContentIsPanoramic",
    "stereoLayout",
    "mvHEVC",
    "providerProjectionKind",
    "sampleProjectionKind",
    "rendererProjectionKind",
    "rendererViewPackingKind",
    "corePresentationPhase",
    "corePresentationComponentStatus",
    "windowComponentContentType",
    "videoVisible",
    "lifecycle",
    # A title that reports playing with nothing on screen fails in one of three
    # places, and only these tell them apart: the renderer rejected the format,
    # the renderer never accepted the samples the provider produced, or it
    # accepted them and never displayed one.
    "videoRendererStatus",
    "videoRendererError",
    "videoSamples",
    "rendererInputs",
    "displayedPixel",
    "bootstrapComplete",
    "providerCodecName",
    "providerCodecTag",
    "sampleMediaSubtype",
)


class Step(NamedTuple):
    name: str
    actions: tuple[str, ...]
    expect_presentation: str


OPEN_CLIP = ("MediaLibrary-grid-video-{clip}",)
APPLY_FLAT_MONO = (
    "PlayerUI-TopAction-videoFormat",
    "PlayerUI-VideoFormat-Projection-Flat",
    "PlayerUI-VideoFormat-Stereo Layout-Mono",
    "PlayerUI-VideoFormat-apply",
)
APPLY_NATIVE_180 = (
    "PlayerUI-TopAction-videoFormat",
    "PlayerUI-VideoFormat-Projection-180°",
    "PlayerUI-VideoFormat-Stereo Layout-{stereo_label}",
    "PlayerUI-VideoFormat-apply",
)
APPLY_360_MONO = (
    "PlayerUI-TopAction-videoFormat",
    "PlayerUI-VideoFormat-Projection-360°",
    "PlayerUI-VideoFormat-Stereo Layout-Mono",
    "PlayerUI-VideoFormat-apply",
)

PATHS: dict[str, tuple[Step, ...]] = {
    "open-default": (
        Step("open", OPEN_CLIP, "panorama"),
    ),
    "panorama-portal-cycle": (
        Step("open", OPEN_CLIP, "panorama"),
        Step(
            "exit-to-portal-1",
            ("PlayerPanel-button-exit-spatial",),
            "portal",
        ),
        Step(
            "enter-panorama-1",
            ("PlayerUI-TopAction-resumePanorama",),
            "panorama",
        ),
        Step(
            "exit-to-portal-2",
            ("PlayerPanel-button-exit-spatial",),
            "portal",
        ),
        Step(
            "enter-panorama-2",
            ("PlayerUI-TopAction-resumePanorama",),
            "panorama",
        ),
    ),
    "format-flat-roundtrip": (
        Step("open", OPEN_CLIP, "panorama"),
        Step("apply-flat-mono", APPLY_FLAT_MONO, "window"),
        Step("apply-native-180", APPLY_NATIVE_180, "panorama"),
    ),
    "dock-roundtrip": (
        Step("open", OPEN_CLIP, "panorama"),
        Step("apply-flat-mono", APPLY_FLAT_MONO, "window"),
        Step(
            "enter-docked",
            (
                "PlayerUI-TopAction-dock",
                "PlayerUI-DockMenu-skybox",
            ),
            "docked",
        ),
        Step(
            "exit-to-window",
            ("PlayerPanel-button-exit-spatial",),
            "window",
        ),
    ),
    "reopen-in-session": (
        Step("open", OPEN_CLIP, "panorama"),
        Step(
            "exit-to-portal",
            ("PlayerPanel-button-exit-spatial",),
            "portal",
        ),
        Step(
            "back-and-reopen",
            (
                "PlayerUI-InfoBar-button-back",
                "MediaLibrary-grid-video-{clip}",
            ),
            "panorama",
        ),
    ),
    "format-360": (
        Step("open", OPEN_CLIP, "panorama"),
        Step("apply-360-mono", APPLY_360_MONO, "panorama"),
    ),
    "clean-open": (
        Step("open", OPEN_CLIP, "any-steady"),
    ),
    "clean-spatial-cycle": (
        Step("open", OPEN_CLIP, "window"),
        Step(
            "apply-native-180",
            ("PlayerUI-window-playback-surface", *APPLY_NATIVE_180),
            "panorama",
        ),
        Step(
            "exit-to-portal-1",
            ("summon:PlayerPanel-button-exit-spatial",),
            "portal",
        ),
        Step(
            "enter-panorama-1",
            ("summon:PlayerUI-TopAction-resumePanorama",),
            "panorama",
        ),
        Step(
            "exit-to-portal-2",
            ("summon:PlayerPanel-button-exit-spatial",),
            "portal",
        ),
        Step(
            "enter-panorama-2",
            ("summon:PlayerUI-TopAction-resumePanorama",),
            "panorama",
        ),
    ),
    "clean-dock-cycle": (
        Step("open", OPEN_CLIP, "window"),
        Step(
            "enter-docked-1",
            (
                "PlayerUI-window-playback-surface",
                "PlayerUI-TopAction-dock",
                "PlayerUI-DockMenu-skybox",
            ),
            "docked",
        ),
        Step(
            "exit-to-window-1",
            ("summon:PlayerPanel-button-exit-spatial",),
            "window",
        ),
        Step(
            "enter-docked-2",
            (
                "PlayerUI-window-playback-surface",
                "PlayerUI-TopAction-dock",
                "PlayerUI-DockMenu-skybox",
            ),
            "docked",
        ),
        Step(
            "exit-to-window-2",
            ("summon:PlayerPanel-button-exit-spatial",),
            "window",
        ),
    ),
    "clean-360-cycle": (
        Step("open", OPEN_CLIP, "window"),
        Step(
            "apply-360-mono",
            ("PlayerUI-window-playback-surface", *APPLY_360_MONO),
            "panorama",
        ),
        Step(
            "exit-to-portal",
            ("summon:PlayerPanel-button-exit-spatial",),
            "portal",
        ),
        Step(
            "enter-panorama",
            ("summon:PlayerUI-TopAction-resumePanorama",),
            "panorama",
        ),
    ),
}


def controller(
    output_directory: Path,
    *arguments: str,
    timeout: float = CONTROLLER_TIMEOUT_SECONDS,
) -> dict[str, object]:
    command = [
        sys.executable,
        str(CONTROLLER),
        "--device",
        DEVICE,
        "--output-directory",
        str(output_directory),
        *arguments,
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"success": False, "error": str(error)}
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError:
        detail = (completed.stdout + completed.stderr)[-500:]
        return {
            "success": False,
            "error": "Controller did not return JSON.",
            "detail": detail,
            "returncode": completed.returncode,
        }
    if not isinstance(document, dict):
        return {
            "success": False,
            "error": "Controller returned a non-object JSON value.",
            "returncode": completed.returncode,
        }
    document["_returncode"] = completed.returncode
    return document


def controller_summary(document: dict[str, object]) -> dict[str, object]:
    summary = {
        key: document[key]
        for key in (
            "success",
            "stage",
            "message",
            "error",
            "detail",
            "appState",
            "sessionID",
            "_returncode",
        )
        if key in document
    }
    matched = document.get("matchedElement")
    if isinstance(matched, dict):
        summary["matchedElement"] = {
            key: matched[key]
            for key in ("identifier", "value", "isEnabled", "isHittable")
            if key in matched
        }
    return summary


def parse_control_plane(document: dict[str, object]) -> dict[str, str] | None:
    matched = document.get("matchedElement")
    if not isinstance(matched, dict):
        return None
    value = matched.get("value")
    if not isinstance(value, str) or not value:
        return None
    return dict(part.split("=", 1) for part in value.split(";") if "=" in part)


def read_control_plane(
    output_directory: Path,
    *,
    timeout: float = CONTROLLER_TIMEOUT_SECONDS,
) -> tuple[dict[str, str] | None, dict[str, object]]:
    document = controller(
        output_directory,
        "snapshot",
        "--identifier",
        CONTROL_PLANE_IDENTIFIER,
        "--no-screenshot",
        timeout=timeout,
    )
    return parse_control_plane(document), document


def copy_probe_lines(cell_directory: Path) -> tuple[list[str] | None, str | None]:
    # The probe copy races the app appending to the same file; one retry
    # keeps a passed step from being downgraded over a transient transfer.
    lines, error = copy_probe_lines_once(cell_directory)
    # A timeout means the container link is congested, and a second copy only
    # doubles the poll's cost while the caller's settle deadline runs down.
    if lines is None and "exceeded" not in (error or ""):
        time.sleep(1.5)
        lines, error = copy_probe_lines_once(cell_directory)
    return lines, error


def copy_probe_lines_once(
    cell_directory: Path,
) -> tuple[list[str] | None, str | None]:
    destination = cell_directory / f".probe-{uuid.uuid4()}.log"
    environment = {
        "DEVELOPER_DIR": DEVELOPER_DIR,
        "PATH": "/usr/bin:/bin",
    }
    try:
        completed = subprocess.run(
            [
                "xcrun",
                "devicectl",
                "device",
                "copy",
                "from",
                "--device",
                CORE_DEVICE,
                "--domain-type",
                "appDataContainer",
                "--domain-identifier",
                BUNDLE,
                "--source",
                PROBE_REMOTE_PATH,
                "--destination",
                str(destination),
            ],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
            # An app whose main thread is wedged also wedges the container
            # copy, and an unbounded wait here hangs the whole sweep instead
            # of recording the stall it is meant to observe.
            timeout=PROBE_COPY_TIMEOUT_SECONDS,
        )
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()
            return None, detail[-500:] or "Unable to copy the device probe."
        if not destination.is_file():
            return None, "devicectl reported success without a probe file."
        return destination.read_text(encoding="utf-8").splitlines(), None
    except subprocess.TimeoutExpired:
        return None, (
            f"Probe copy exceeded {PROBE_COPY_TIMEOUT_SECONDS:.0f}s; "
            "the app container is not answering."
        )
    except (OSError, UnicodeError) as error:
        return None, str(error)
    finally:
        destination.unlink(missing_ok=True)


def write_probe_excerpt(
    *,
    cell_directory: Path,
    step_index: int,
    step_name: str,
    offset: int,
) -> tuple[str, list[str], int, str | None]:
    excerpt_path = cell_directory / (
        f"step-{step_index:02d}-{safe_component(step_name)}-probe.log"
    )
    lines, error = copy_probe_lines(cell_directory)
    if lines is None:
        excerpt_path.write_text("", encoding="utf-8")
        return str(excerpt_path), [], offset, error
    if len(lines) < offset:
        excerpt_path.write_text("", encoding="utf-8")
        return (
            str(excerpt_path),
            [],
            len(lines),
            f"Probe line count moved backwards from {offset} to {len(lines)}.",
        )
    excerpt = lines[offset:]
    text = "\n".join(excerpt)
    excerpt_path.write_text(text + ("\n" if text else ""), encoding="utf-8")
    return str(excerpt_path), excerpt, len(lines), None


def safe_component(value: str) -> str:
    component = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-.")
    return component or "value"


def resolve_actions(step: Step, clip: str) -> tuple[str, ...]:
    values = {
        "clip": clip,
        "stereo_label": STEREO_LABELS.get(clip, "{stereo_label}"),
    }
    return tuple(action.format_map(values) for action in step.actions)


def format_facts(plane: dict[str, str] | None) -> dict[str, str | None] | None:
    if plane is None:
        return None
    return {field: plane.get(field) for field in FORMAT_FIELDS}


def observed_state(
    plane: dict[str, str],
    elapsed_seconds: float,
) -> dict[str, object]:
    return {
        "elapsed_seconds": round(elapsed_seconds, 3),
        "presentation": plane.get("presentation"),
        "transition": plane.get("transition"),
        "lifecycle": plane.get("lifecycle"),
        "projection": plane.get("projection"),
    }


def append_observed_state(
    observations: list[dict[str, object]],
    plane: dict[str, str],
    elapsed_seconds: float,
) -> None:
    state = observed_state(plane, elapsed_seconds)
    if observations:
        comparable_keys = ("presentation", "transition", "lifecycle", "projection")
        if all(observations[-1].get(key) == state.get(key) for key in comparable_keys):
            return
    observations.append(state)


FORMAT_CHANGE_FIELDS = ("projection", "stereoLayout", "formatProvenance")


def format_changed(
    baseline: dict[str, str] | None,
    plane: dict[str, str],
) -> bool:
    if baseline is None:
        return True
    return any(
        plane.get(field) != baseline.get(field)
        for field in FORMAT_CHANGE_FIELDS
    )


def wait_for_presentation(
    *,
    output_directory: Path,
    expected: str,
    target_started_at: float,
    baseline_plane: dict[str, str] | None = None,
) -> dict[str, object]:
    # A step whose expected presentation equals the state it starts from
    # (apply-360-mono: panorama to panorama) would pass vacuously on the first
    # poll; such a step only passes once a format field moved off the baseline.
    require_format_change = (
        baseline_plane is not None
        and baseline_plane.get("presentation") == expected
        and baseline_plane.get("transition") == "none"
    )
    deadline = target_started_at + SETTLEMENT_TIMEOUT_SECONDS
    next_poll_at = time.monotonic()
    latest_plane: dict[str, str] | None = None
    latest_controller: dict[str, object] | None = None
    observations: list[dict[str, object]] = []

    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        plane, document = read_control_plane(
            output_directory,
            timeout=max(0.1, min(CONTROLLER_TIMEOUT_SECONDS, remaining)),
        )
        latest_controller = document
        elapsed = time.monotonic() - target_started_at
        if plane is not None:
            latest_plane = plane
            append_observed_state(observations, plane, elapsed)
            if (
                plane.get("presentation") == expected
                and plane.get("transition") == "none"
                and (
                    not require_format_change
                    or format_changed(baseline_plane, plane)
                )
            ):
                return {
                    "verdict": PASS,
                    "time_to_target_seconds": round(elapsed, 3),
                    "actual_presentation": plane.get("presentation"),
                    "control_plane": format_facts(plane),
                    "observed_states": observations,
                }
        next_poll_at += POLL_INTERVAL_SECONDS
        sleep_seconds = min(next_poll_at - time.monotonic(), deadline - time.monotonic())
        if sleep_seconds > 0:
            time.sleep(sleep_seconds)

    elapsed = time.monotonic() - target_started_at
    common = {
        "elapsed_seconds": round(elapsed, 3),
        "actual_presentation": (
            latest_plane.get("presentation") if latest_plane is not None else None
        ),
        "control_plane": format_facts(latest_plane),
        "observed_states": observations,
    }
    if latest_plane is None:
        return {
            **common,
            "verdict": DRIVE_ERROR,
            "phase": "control-plane",
            "controller": controller_summary(latest_controller or {}),
        }
    if (
        latest_plane.get("transition") == "none"
        and latest_plane.get("presentation") != expected
    ):
        return {**common, "verdict": WRONG_STATE}
    return {**common, "verdict": STALL_TIMEOUT}


def parse_probe_timestamp(line: str) -> datetime | None:
    token = line.split(maxsplit=1)[0] if line else ""
    if not token:
        return None
    try:
        return datetime.fromisoformat(token.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_settlement_fields(line: str) -> dict[str, str] | None:
    marker = " settlement "
    if marker not in line:
        return None
    payload = line.split(marker, 1)[1]
    fields = dict(
        part.split("=", 1)
        for part in payload.split(",")
        if "=" in part
    )
    return fields or None


IMMERSIVE_PRESENTATIONS = frozenset(("panorama", "docked"))


def last_settlement_settled(lines: Sequence[str]) -> bool | None:
    settled: bool | None = None
    for line in lines:
        fields = parse_settlement_fields(line)
        if fields is not None and "settled" in fields:
            settled = fields["settled"] == "true"
    return settled


# Mirrors the isSettled conjunction in ImmersiveSpaceView, in the same order,
# so the first unmet conjunct names the blocker the wearer is actually stuck on.
SETTLEMENT_CONJUNCTS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("ready", ("ready",)),
    ("immersiveMode", ("immersiveMode",)),
    ("contentTypeOrOverride", ("contentTypeMatches", "overrideAdopted")),
    ("viewingMode", ("viewingMode",)),
    ("spatialMode", ("spatialMode",)),
    ("pixels", ("pixels",)),
)


def settlement_blocker(fields: dict[str, str]) -> str | None:
    for name, alternatives in SETTLEMENT_CONJUNCTS:
        if not any(fields.get(field) == "true" for field in alternatives):
            return name
    return None


def settlement_trace(lines: Sequence[str]) -> dict[str, object] | None:
    samples = [
        fields
        for fields in (parse_settlement_fields(line) for line in lines)
        if fields is not None and "settled" in fields
    ]
    if not samples:
        return None
    settled_flags = [fields["settled"] == "true" for fields in samples]
    terminal = samples[-1]
    return {
        "samples": len(samples),
        "settled_samples": sum(settled_flags),
        "reached_settled": any(settled_flags),
        "regressed_after_settled": any(
            settled_flags[index] and not settled_flags[index + 1]
            for index in range(len(settled_flags) - 1)
        ),
        "terminal_settled": settled_flags[-1],
        "terminal_blocker": settlement_blocker(terminal),
        "terminal_fields": {
            field: terminal.get(field)
            for field in (
                "ready",
                "immersiveMode",
                "contentTypeMatches",
                "overrideAdopted",
                "viewingMode",
                "spatialMode",
                "pixels",
                "gotImmersive",
                "gotViewing",
                "status",
                "provenance",
            )
        },
    }


def appeared_presentation(lines: Sequence[str]) -> str | None:
    presentation: str | None = None
    for line in lines:
        if " immersiveSpaceAppeared " not in line:
            continue
        fields = dict(
            part.split("=", 1)
            for part in line.split(" immersiveSpaceAppeared ", 1)[1].split()
            if "=" in part
        )
        # Mid-transition the probe still names the departing presentation;
        # the landing is the transition target.
        transition = fields.get("transition")
        if transition and transition != "none":
            presentation = transition
        else:
            presentation = fields.get("presentation", presentation)
    return presentation


def wait_for_immersive_settlement(
    *,
    cell_directory: Path,
    expected: str,
    target_started_at: float,
    probe_offset: int,
    controller_directory: Path,
) -> tuple[dict[str, object], list[str]]:
    # In a settled immersive presentation the main window is present but empty,
    # so the control-plane element leaves the accessibility hierarchy; the
    # device probe file is the only observation channel that stays truthful.
    deadline = target_started_at + SETTLEMENT_TIMEOUT_SECONDS
    delta: list[str] = []
    copy_error: str | None = None
    while time.monotonic() < deadline:
        lines, copy_error = copy_probe_lines(cell_directory)
        elapsed = time.monotonic() - target_started_at
        if lines is not None and len(lines) >= probe_offset:
            delta = lines[probe_offset:]
            if last_settlement_settled(delta) is True:
                appeared = appeared_presentation(delta)
                if appeared is not None and appeared != expected:
                    return (
                        {
                            "verdict": WRONG_STATE,
                            "actual_presentation": appeared,
                            "elapsed_seconds": round(elapsed, 3),
                        },
                        delta,
                    )
                return (
                    {
                        "verdict": PASS,
                        "time_to_target_seconds": round(elapsed, 3),
                        "actual_presentation": appeared or expected,
                    },
                    delta,
                )
        time.sleep(1)

    elapsed = time.monotonic() - target_started_at
    common = {"elapsed_seconds": round(elapsed, 3)}
    if copy_error is not None:
        return (
            {**common, "verdict": DRIVE_ERROR, "phase": "probe", "message": copy_error},
            delta,
        )
    if any(parse_settlement_fields(line) for line in delta):
        return ({**common, "verdict": STALL_TIMEOUT}, delta)
    # No spatial records at all: the tap most likely never opened an immersive
    # surface. A windowed control plane, when present, names where we landed.
    plane, _ = read_control_plane(controller_directory)
    if plane is not None:
        return (
            {
                **common,
                "verdict": WRONG_STATE,
                "actual_presentation": plane.get("presentation"),
                "control_plane": format_facts(plane),
            },
            delta,
        )
    return (
        {
            **common,
            "verdict": STALL_TIMEOUT,
            "message": "No spatial probe records and no windowed control plane.",
        },
        delta,
    )


def probe_shows_recovered_stall(lines: Sequence[str]) -> bool:
    none_since: datetime | None = None
    for line in lines:
        timestamp = parse_probe_timestamp(line)
        fields = parse_settlement_fields(line)
        if timestamp is None or fields is None:
            continue
        if fields.get("settled") == "true":
            if (
                none_since is not None
                and (timestamp - none_since).total_seconds() >= STALL_RECOVERY_SECONDS
            ):
                return True
            none_since = None
        elif fields.get("gotImmersive") == "none":
            if none_since is None:
                none_since = timestamp
        else:
            none_since = None
    return False


def drive_error_step(
    *,
    step: Step,
    actions: Sequence[str],
    phase: str,
    started_at: float,
    controller_document: dict[str, object] | None = None,
    message: str | None = None,
) -> dict[str, object]:
    result: dict[str, object] = {
        "name": step.name,
        "actions": list(actions),
        "expect_presentation": step.expect_presentation,
        "verdict": DRIVE_ERROR,
        "phase": phase,
        "elapsed_seconds": round(time.monotonic() - started_at, 3),
    }
    if controller_document is not None:
        result["controller"] = controller_summary(controller_document)
    if message is not None:
        result["message"] = message
    return result


def run_step(
    *,
    step: Step,
    step_index: int,
    clip: str,
    cell_directory: Path,
    controller_directory: Path,
    probe_offset: int,
) -> tuple[dict[str, object], int]:
    actions = resolve_actions(step, clip)
    step_started_at = time.monotonic()
    immersive_target = step.expect_presentation in IMMERSIVE_PRESENTATIONS
    baseline_plane = (
        None if immersive_target else read_control_plane(controller_directory)[0]
    )
    target_started_at: float | None = None
    result: dict[str, object] | None = None

    # Windowed chrome hides faster than consecutive controller round-trips,
    # so consecutive taps travel as one tapSequence command and land with
    # sub-second spacing inside the resident runner.
    segments: list[tuple[str, tuple[str, ...]]] = []
    for identifier in actions:
        if identifier.startswith("summon:") or identifier.startswith("app:"):
            segments.append(("scheme", (identifier,)))
        elif segments and segments[-1][0] == "taps":
            segments[-1] = ("taps", segments[-1][1] + (identifier,))
        else:
            segments.append(("taps", (identifier,)))

    for segment_index, (kind, payload) in enumerate(segments):
        if segment_index == len(segments) - 1:
            target_started_at = time.monotonic()
        if kind == "scheme":
            scheme_action = payload[0]
            if scheme_action.startswith("summon:"):
                document = summon_and_tap(
                    controller_directory, scheme_action[len("summon:"):]
                )
                if (
                    document.get("success") is not True
                    and document.get("ok") is not True
                ):
                    result = drive_error_step(
                        step=step,
                        actions=actions,
                        phase="summon-tap",
                        started_at=step_started_at,
                        controller_document=document,
                    )
                    result["failed_action"] = scheme_action
                    break
            else:
                document = app_command(
                    controller_directory, scheme_action[len("app:"):]
                )
                if document.get("ok") is not True:
                    result = drive_error_step(
                        step=step,
                        actions=actions,
                        phase="app-command",
                        started_at=step_started_at,
                        controller_document=document,
                    )
                    result["failed_action"] = scheme_action
                    break
            continue
        if len(payload) == 1:
            document = controller(
                controller_directory,
                "tap",
                "--identifier",
                payload[0],
                "--no-screenshot",
            )
        else:
            document = controller(
                controller_directory,
                "tapSequence",
                "--identifiers",
                *payload,
                "--no-screenshot",
            )
        if document.get("success") is not True:
            result = drive_error_step(
                step=step,
                actions=actions,
                phase="tap",
                started_at=step_started_at,
                controller_document=document,
            )
            result["failed_action"] = " -> ".join(payload)
            break

    if result is None:
        if target_started_at is None:
            result = drive_error_step(
                step=step,
                actions=actions,
                phase="path-data",
                started_at=step_started_at,
                message="Step has no target-triggering action.",
            )
        elif immersive_target:
            wait_result, delta = wait_for_immersive_settlement(
                cell_directory=cell_directory,
                expected=step.expect_presentation,
                target_started_at=target_started_at,
                probe_offset=probe_offset,
                controller_directory=controller_directory,
            )
            result = {
                "name": step.name,
                "actions": list(actions),
                "expect_presentation": step.expect_presentation,
                **wait_result,
            }
            excerpt_path = cell_directory / (
                f"step-{step_index:02d}-{safe_component(step.name)}-probe.log"
            )
            text = "\n".join(delta)
            excerpt_path.write_text(text + ("\n" if text else ""), encoding="utf-8")
            result["probe_excerpt"] = str(excerpt_path)
            result["stall_recovered"] = (
                result["verdict"] == PASS and probe_shows_recovered_stall(delta)
            )
            result["settlement_trace"] = settlement_trace(delta)
            apply_visual_gate(result, controller_directory)
            return result, probe_offset + len(delta)
        else:
            result = {
                "name": step.name,
                "actions": list(actions),
                "expect_presentation": step.expect_presentation,
                "baseline_control_plane": format_facts(baseline_plane),
                **wait_for_presentation(
                    output_directory=controller_directory,
                    expected=step.expect_presentation,
                    target_started_at=target_started_at,
                    baseline_plane=baseline_plane,
                ),
            }

    excerpt_path, excerpt, new_offset, probe_error = write_probe_excerpt(
        cell_directory=cell_directory,
        step_index=step_index,
        step_name=step.name,
        offset=probe_offset,
    )
    result["probe_excerpt"] = excerpt_path
    if probe_error is not None:
        # Only the immersive branch judges from the probe, and it returns
        # before this point. Here the control plane already proved the
        # presentation settled with its video visible, so a failed copy of a
        # corroborating log says the file service dropped a socket, not that
        # playback did anything wrong. The error stays on the record.
        result["probe_error"] = probe_error
    result["stall_recovered"] = (
        result["verdict"] == PASS and probe_shows_recovered_stall(excerpt)
    )
    result["settlement_trace"] = settlement_trace(excerpt)
    return result, new_offset


def control_signature(plane: dict[str, str] | None) -> tuple[str | None, str | None] | None:
    if plane is None:
        return None
    return plane.get("lifecycle"), plane.get("presentation")


def choose_wedge_clip(current_clip: str, selected_clips: Sequence[str]) -> str:
    for candidate in (*selected_clips, *DEFAULT_CLIPS):
        if candidate != current_clip and "hnvr" not in candidate.casefold():
            return candidate
    raise ValueError("No alternate allowed clip is available for the wedge check.")


def run_wedge_check(
    *,
    current_clip: str,
    selected_clips: Sequence[str],
    controller_directory: Path,
) -> tuple[str, dict[str, object]]:
    alternate_clip = choose_wedge_clip(current_clip, selected_clips)
    baseline_plane, baseline_document = read_control_plane(controller_directory)
    baseline_signature = control_signature(baseline_plane)
    identifier = f"MediaLibrary-grid-video-{alternate_clip}"
    target_started_at = time.monotonic()
    tap_document = controller(
        controller_directory,
        "tap",
        "--identifier",
        identifier,
        "--no-screenshot",
    )
    evidence: dict[str, object] = {
        "clip": alternate_clip,
        "identifier": identifier,
        "baseline": {
            "signature": baseline_signature,
            "control_plane": format_facts(baseline_plane),
            "controller": controller_summary(baseline_document),
        },
        "tap": controller_summary(tap_document),
        "observed_states": [],
    }
    if tap_document.get("success") is not True:
        return "blocked", evidence

    deadline = target_started_at + SETTLEMENT_TIMEOUT_SECONDS
    next_poll_at = time.monotonic()
    observations: list[dict[str, object]] = []
    latest_controller: dict[str, object] | None = None
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        plane, document = read_control_plane(
            controller_directory,
            timeout=max(0.1, min(CONTROLLER_TIMEOUT_SECONDS, remaining)),
        )
        latest_controller = document
        elapsed = time.monotonic() - target_started_at
        if plane is not None:
            append_observed_state(observations, plane, elapsed)
            if control_signature(plane) != baseline_signature:
                evidence["observed_states"] = observations
                evidence["changed_control_plane"] = format_facts(plane)
                return "opened", evidence
        next_poll_at += POLL_INTERVAL_SECONDS
        sleep_seconds = min(next_poll_at - time.monotonic(), deadline - time.monotonic())
        if sleep_seconds > 0:
            time.sleep(sleep_seconds)
    evidence["observed_states"] = observations
    evidence["last_controller"] = controller_summary(latest_controller or {})
    return "blocked", evidence


def app_command(
    controller_directory: Path,
    verb: str,
    *arguments: str,
) -> dict[str, object]:
    extra: list[str] = []
    for argument in arguments:
        extra.extend(("--arg", argument))
    document = controller(
        controller_directory, "app-command", "--verb", verb, *extra
    )
    # devicectl sometimes loses the race against the app's 0.5s poller while
    # writing command.json (CoreDeviceError 7000 naming that file). The
    # command never executed, so one retry is safe for every verb, including
    # mutating ones.
    if document.get("success") is not True and "test-command.json" in str(
        document.get("error", "")
    ):
        time.sleep(1.5)
        document = controller(
            controller_directory, "app-command", "--verb", verb, *extra
        )
    return document


def summon_and_tap(
    controller_directory: Path,
    identifier: str,
) -> dict[str, object]:
    """Tap a control that lives on auto-hiding chrome. Checking visibility in
    a separate round-trip loses the race, so the tap itself is the probe:
    when no element appears, toggle the controls and try again inside the
    runner's own existence wait."""
    document = controller(
        controller_directory,
        "tap",
        "--identifier",
        identifier,
        "--no-screenshot",
    )
    if document.get("success") is True:
        return document
    for _ in range(2):
        toggled = app_command(controller_directory, "toggleControls")
        if toggled.get("ok") is not True:
            return toggled
        document = controller(
            controller_directory,
            "tapSequence",
            "--identifiers",
            identifier,
            "--no-screenshot",
        )
        if document.get("success") is True:
            return document
    return document


def push_to_inbox(media_path: Path) -> str | None:
    environment = {"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin"}
    try:
        completed = subprocess.run(
            [
                "xcrun", "devicectl", "device", "copy", "to",
                "--device", CORE_DEVICE,
                "--domain-type", "appDataContainer",
                "--domain-identifier", BUNDLE,
                "--source", str(media_path),
                "--destination", f"Documents/TestMediaInbox/{media_path.name}",
            ],
            capture_output=True, text=True, env=environment, timeout=600,
        )
    except subprocess.TimeoutExpired:
        return f"Media push exceeded 600s for {media_path.name}."
    if completed.returncode != 0:
        return (completed.stderr or completed.stdout).strip()[-300:]
    return None


def clean_state_preamble(
    *,
    clip: str,
    media_root: Path,
    controller_directory: Path,
) -> dict[str, object] | None:
    """Returns a DRIVE_ERROR-shaped dict on failure, None on success. The
    library afterwards contains exactly the clip under test, so end-of-media
    auto-advance has nowhere to go and the banned file can never be reached."""
    media_path = media_root / clip
    if not media_path.is_file():
        return {"phase": "clean-media", "message": f"No such media: {media_path}"}
    # Relaunch before resetting: a dying instance saves its in-memory library
    # on termination, and that write landing after a reset resurrects the
    # references the reset deleted (observed as duplicate single-item
    # libraries). Terminating first removes the concurrent writer; the fresh
    # instance then clears both its defaults and its own in-memory state.
    # The runner's relaunch verb restarts only the app and consumes no
    # automation grant; ensure-session runs only as recovery.
    relaunch = controller(controller_directory, "relaunch", "--no-screenshot")
    if relaunch.get("success") is not True:
        relaunch = controller(
            controller_directory, "--developer-dir", DEVELOPER_DIR, "ensure-session"
        )
        if relaunch.get("stage") != "ready":
            return {"phase": "clean-relaunch", "controller": controller_summary(relaunch)}
    reset = app_command(controller_directory, "resetState")
    if reset.get("ok") is not True:
        session = controller(
            controller_directory, "--developer-dir", DEVELOPER_DIR, "ensure-session"
        )
        if session.get("stage") != "ready":
            return {"phase": "clean-session", "controller": controller_summary(session)}
        reset = app_command(controller_directory, "resetState")
        if reset.get("ok") is not True:
            return {"phase": "clean-reset", "controller": controller_summary(reset)}
    if (error := push_to_inbox(media_path)) is not None:
        return {"phase": "clean-push", "message": error}
    imported = app_command(
        controller_directory, "importMedia", f"file={media_path.name}"
    )
    if imported.get("ok") is not True:
        return {"phase": "clean-import", "controller": controller_summary(imported)}
    listing = app_command(controller_directory, "listLibrary")
    if listing.get("ok") is not True:
        return {"phase": "clean-list", "controller": controller_summary(listing)}
    names = listing.get("payload")
    if names != [media_path.name]:
        return {
            "phase": "clean-verify",
            "message": f"Library after clean import is {names}.",
        }
    return None


WINDOWED_STEADY_LIFECYCLES = frozenset(("playing", "ready", "paused", "ended"))

VISUAL_BLACK_YAVG = 18.0
VISUAL_BLACK_YMAX = 40.0
VISUAL_FROZEN_SSIM = 0.995


def ffmpeg_luma_stats(image_path: str) -> tuple[float, float] | None:
    completed = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-i", image_path,
            "-vf", "signalstats,metadata=mode=print",
            "-frames:v", "1", "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    yavg = ymax = None
    for line in completed.stderr.splitlines():
        if "signalstats.YAVG=" in line:
            yavg = float(line.rsplit("=", 1)[1])
        elif "signalstats.YMAX=" in line:
            ymax = float(line.rsplit("=", 1)[1])
    if yavg is None or ymax is None:
        return None
    return yavg, ymax


def ffmpeg_ssim(first_path: str, second_path: str) -> float | None:
    completed = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-i", first_path, "-i", second_path,
            "-filter_complex", "ssim", "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    match = re.search(r"All:([0-9.]+)", completed.stderr)
    return float(match.group(1)) if match else None


def capture_visual_evidence(
    *,
    controller_directory: Path,
    lifecycle: str | None,
) -> dict[str, object]:
    """Two screenshots 2.5s apart: luma statistics rule out a black frame and
    the inter-frame SSIM rules out a frozen renderer while playing. Raw
    numbers stay in the record so a human can re-judge borderline cells."""
    shots: list[str] = []
    for index in (1, 2):
        document = controller(controller_directory, "snapshot")
        path = document.get("localScreenshotPath")
        if isinstance(path, str):
            shots.append(path)
        if index == 1:
            time.sleep(2.5)
    evidence: dict[str, object] = {"screenshots": shots}
    if not shots:
        evidence["verdict"] = "unavailable"
        return evidence
    stats = ffmpeg_luma_stats(shots[0])
    if stats is not None:
        evidence["yavg"], evidence["ymax"] = stats
    if len(shots) == 2:
        ssim = ffmpeg_ssim(shots[0], shots[1])
        if ssim is not None:
            evidence["ssim"] = ssim
    yavg = evidence.get("yavg")
    ymax = evidence.get("ymax")
    ssim = evidence.get("ssim")
    if isinstance(yavg, float) and isinstance(ymax, float) \
            and yavg < VISUAL_BLACK_YAVG and ymax < VISUAL_BLACK_YMAX:
        evidence["verdict"] = "black"
    elif isinstance(ssim, float) and ssim > VISUAL_FROZEN_SSIM \
            and (lifecycle or "").lower() == "playing":
        evidence["verdict"] = "frozen"
    elif "yavg" in evidence:
        evidence["verdict"] = "content"
    else:
        evidence["verdict"] = "unavailable"
    return evidence


def apply_visual_gate(
    step_result: dict[str, object],
    controller_directory: Path,
) -> None:
    if step_result.get("verdict") != PASS:
        return
    plane = (step_result.get("control_plane") or {})
    lifecycle = plane.get("lifecycle") if isinstance(plane, dict) else None
    visual = capture_visual_evidence(
        controller_directory=controller_directory,
        lifecycle=lifecycle,
    )
    step_result["visual"] = visual
    if visual.get("verdict") in ("black", "frozen"):
        step_result["verdict"] = WRONG_STATE
        step_result["message"] = f"visual evidence: {visual['verdict']}"


def wait_for_clean_open(
    *,
    cell_directory: Path,
    controller_directory: Path,
    target_started_at: float,
    probe_offset: int,
) -> tuple[dict[str, object], list[str]]:
    """A clean open may legitimately land windowed (no format signaling) or
    panoramic (signaled source); the verdict records where it landed and the
    signaling truth table instead of presuming a target presentation."""
    deadline = target_started_at + SETTLEMENT_TIMEOUT_SECONDS
    delta: list[str] = []
    latest_plane: dict[str, str] | None = None
    invisible_steady_polls = 0
    while time.monotonic() < deadline:
        lines, _ = copy_probe_lines(cell_directory)
        if lines is not None and len(lines) >= probe_offset:
            delta = lines[probe_offset:]
            if last_settlement_settled(delta) is True:
                elapsed = time.monotonic() - target_started_at
                return (
                    {
                        "verdict": PASS,
                        "landed": appeared_presentation(delta) or "panorama",
                        "time_to_target_seconds": round(elapsed, 3),
                    },
                    delta,
                )
        plane, _ = read_control_plane(controller_directory)
        if plane is not None:
            latest_plane = plane
            lifecycle = plane.get("lifecycle") or ""
            if (
                plane.get("presentation") == "window"
                and plane.get("transition") == "none"
                and lifecycle.lower() in WINDOWED_STEADY_LIFECYCLES
                and plane.get("videoVisible") != "true"
            ):
                invisible_steady_polls += 1
                if invisible_steady_polls >= 4:
                    elapsed = time.monotonic() - target_started_at
                    return (
                        {
                            "verdict": WRONG_STATE,
                            "landed": "window-invisible",
                            "elapsed_seconds": round(elapsed, 3),
                            "message": "steady lifecycle with videoVisible=false",
                            "control_plane": format_facts(plane),
                        },
                        delta,
                    )
            else:
                invisible_steady_polls = 0
            if lifecycle.lower().startswith("failed"):
                elapsed = time.monotonic() - target_started_at
                return (
                    {
                        "verdict": WRONG_STATE,
                        "landed": "failed",
                        "elapsed_seconds": round(elapsed, 3),
                        "message": lifecycle,
                        "control_plane": format_facts(plane),
                    },
                    delta,
                )
            if (
                plane.get("presentation") == "window"
                and plane.get("transition") == "none"
                and plane.get("videoVisible") == "true"
                and lifecycle.lower() in WINDOWED_STEADY_LIFECYCLES
            ):
                elapsed = time.monotonic() - target_started_at
                return (
                    {
                        "verdict": PASS,
                        "landed": "window",
                        "time_to_target_seconds": round(elapsed, 3),
                        "control_plane": format_facts(plane),
                    },
                    delta,
                )
        time.sleep(1)
    elapsed = time.monotonic() - target_started_at
    return (
        {
            "verdict": STALL_TIMEOUT,
            "landed": None,
            "elapsed_seconds": round(elapsed, 3),
            "control_plane": format_facts(latest_plane),
        },
        delta,
    )


def run_cell(
    *,
    clip: str,
    clip_index: int,
    path_name: str,
    path_index: int,
    rep: int,
    selected_clips: Sequence[str],
    evidence_directory: Path,
    clean: bool = False,
    media_root: Path | None = None,
) -> dict[str, object]:
    cell_directory = (
        evidence_directory
        / f"clip-{clip_index:02d}-{safe_component(Path(clip).name)}"
        / f"path-{path_index:02d}-{path_name}"
        / f"rep-{rep:02d}"
    )
    controller_directory = cell_directory / "controller"
    controller_directory.mkdir(parents=True, exist_ok=True)
    path = PATHS[path_name]
    cell_started_at = time.monotonic()
    clip_name = Path(clip).name

    if clean:
        failure = clean_state_preamble(
            clip=clip,
            media_root=media_root or Path("."),
            controller_directory=controller_directory,
        )
        if failure is not None:
            probe_lines, _ = copy_probe_lines(cell_directory)
            first_step = path[0]
            step_result = drive_error_step(
                step=first_step,
                actions=resolve_actions(first_step, clip_name),
                phase=str(failure.get("phase", "clean-preamble")),
                started_at=cell_started_at,
                message=str(failure.get("message", "")) or None,
            )
            if "controller" in failure:
                step_result["controller"] = failure["controller"]
            return {
                "clip": clip,
                "path": path_name,
                "rep": rep,
                "verdict": DRIVE_ERROR,
                "passed": False,
                "elapsed_seconds": round(time.monotonic() - cell_started_at, 3),
                "session": {},
                "steps": [step_result],
                "wedge_check": None,
                "wedge_evidence": None,
                "evidence_directory": str(cell_directory),
            }
        probe_lines, _ = copy_probe_lines(cell_directory)
        probe_offset = len(probe_lines or [])
        if path_name == "clean-open":
            open_document = controller(
                controller_directory,
                "tap",
                "--identifier",
                f"MediaLibrary-grid-video-{clip_name}",
                "--no-screenshot",
            )
            if open_document.get("success") is not True:
                step_result = drive_error_step(
                    step=path[0],
                    actions=(f"MediaLibrary-grid-video-{clip_name}",),
                    phase="tap",
                    started_at=cell_started_at,
                    controller_document=open_document,
                )
                verdict = DRIVE_ERROR
                steps = [step_result]
            else:
                wait_result, delta = wait_for_clean_open(
                    cell_directory=cell_directory,
                    controller_directory=controller_directory,
                    target_started_at=time.monotonic(),
                    probe_offset=probe_offset,
                )
                excerpt_path = cell_directory / "step-01-open-probe.log"
                text = "\n".join(delta)
                excerpt_path.write_text(
                    text + ("\n" if text else ""), encoding="utf-8"
                )
                step_result = {
                    "name": "open",
                    "actions": [f"MediaLibrary-grid-video-{clip_name}"],
                    "expect_presentation": "any-steady",
                    "probe_excerpt": str(excerpt_path),
                    "stall_recovered": probe_shows_recovered_stall(delta),
                    **wait_result,
                }
                apply_visual_gate(step_result, controller_directory)
                verdict = str(step_result["verdict"])
                steps = [step_result]
            return {
                "clip": clip,
                "path": path_name,
                "rep": rep,
                "verdict": verdict,
                "landed": steps[0].get("landed"),
                "passed": verdict in PASSING_VERDICTS,
                "elapsed_seconds": round(time.monotonic() - cell_started_at, 3),
                "session": {},
                "steps": steps,
                "wedge_check": None,
                "wedge_evidence": None,
                "evidence_directory": str(cell_directory),
            }
        session: dict[str, object] = {"stage": "ready", "success": True}
    else:
        session = controller(
            controller_directory,
            "--developer-dir",
            DEVELOPER_DIR,
            "ensure-session",
        )
    steps: list[dict[str, object]] = []
    probe_offset = 0
    baseline_error: str | None = None
    if session.get("stage") == "ready" and session.get("success") is True:
        baseline_lines, baseline_error = copy_probe_lines(cell_directory)
        if baseline_lines is not None:
            probe_offset = len(baseline_lines)

    if session.get("stage") != "ready" or session.get("success") is not True:
        first_step = path[0]
        step_result = drive_error_step(
            step=first_step,
            actions=resolve_actions(first_step, clip),
            phase="ensure-session",
            started_at=cell_started_at,
            controller_document=session,
        )
        excerpt_path = cell_directory / (
            f"step-01-{safe_component(first_step.name)}-probe.log"
        )
        excerpt_path.write_text("", encoding="utf-8")
        step_result["probe_excerpt"] = str(excerpt_path)
        step_result["probe_error"] = "Session did not reach ready."
        steps.append(step_result)
    elif baseline_error is not None:
        first_step = path[0]
        step_result = drive_error_step(
            step=first_step,
            actions=resolve_actions(first_step, clip),
            phase="probe-baseline",
            started_at=cell_started_at,
            message=baseline_error,
        )
        excerpt_path = cell_directory / "step-01-open-probe.log"
        excerpt_path.write_text("", encoding="utf-8")
        step_result["probe_excerpt"] = str(excerpt_path)
        step_result["probe_error"] = baseline_error
        steps.append(step_result)
    else:
        for step_index, step in enumerate(path, start=1):
            step_result, probe_offset = run_step(
                step=step,
                step_index=step_index,
                clip=Path(clip).name,
                cell_directory=cell_directory,
                controller_directory=controller_directory,
                probe_offset=probe_offset,
            )
            steps.append(step_result)
            if step_result["verdict"] != PASS:
                break

    first_failure = next(
        (step for step in steps if step["verdict"] != PASS),
        None,
    )
    if first_failure is not None:
        verdict = str(first_failure["verdict"])
    elif any(bool(step.get("stall_recovered")) for step in steps):
        verdict = STALL_RECOVERED
    else:
        verdict = PASS

    wedge_check: str | None = None
    wedge_evidence: dict[str, object] | None = None
    # DRIVE_ERROR maps the automation boundary, not a product failure, and a
    # settled panorama has no reachable library to probe a wedge against.
    if verdict in (STALL_TIMEOUT, WRONG_STATE):
        if session.get("stage") != "ready" or session.get("success") is not True:
            wedge_check = "blocked"
            wedge_evidence = {"error": "No ready session for the wedge check."}
        else:
            try:
                wedge_check, wedge_evidence = run_wedge_check(
                    current_clip=Path(clip).name,
                    selected_clips=selected_clips,
                    controller_directory=controller_directory,
                )
            except ValueError as error:
                wedge_check = "blocked"
                wedge_evidence = {"error": str(error)}

    return {
        "clip": clip,
        "path": path_name,
        "rep": rep,
        "verdict": verdict,
        "passed": verdict in PASSING_VERDICTS,
        "elapsed_seconds": round(time.monotonic() - cell_started_at, 3),
        "session": controller_summary(session),
        "steps": steps,
        "wedge_check": wedge_check,
        "wedge_evidence": wedge_evidence,
        "evidence_directory": str(cell_directory),
    }


def append_result(results_path: Path, result: dict[str, object]) -> None:
    with results_path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(result, ensure_ascii=False, sort_keys=True) + "\n")


AUTOMATION_TIMEOUT_SIGNATURE = "Timed out while enabling automation mode"


def sweep_diagnosis(
    evidence_directory: Path, controller_directory: Path
) -> dict[str, object]:
    """Discriminate the shared causes of a DRIVE_ERROR streak. The literal
    runner-log signature is the only valid evidence of the wearer
    authorization wall; the command channel answering while sessions keep
    failing has meant device-side automation degradation, not app state."""
    signature_logs = [
        str(log)
        for log in sorted(evidence_directory.rglob("runner.log"))
        if AUTOMATION_TIMEOUT_SIGNATURE in log.read_text(errors="replace")
    ]
    ping = app_command(controller_directory, "ping")
    if signature_logs:
        diagnosis = "wearer-authorization-required"
    elif ping.get("ok") is True:
        diagnosis = "sessions-fail-while-app-responsive"
    else:
        diagnosis = "app-unreachable"
    return {
        "diagnosis": diagnosis,
        "authSignatureLogs": signature_logs,
        "ping": controller_summary(ping),
    }


def print_summary(
    *,
    clips: Sequence[str],
    paths: Sequence[str],
    reps: int,
    results: Sequence[dict[str, object]],
) -> None:
    result_by_cell = {
        (str(result["clip"]), str(result["path"]), int(result["rep"])): result
        for result in results
    }
    headers = [
        "clip",
        "path",
        *(f"rep-{rep}" for rep in range(1, reps + 1)),
        "PASS_COUNT",
        "RECOVERED",
        "MEDIAN_STEP_TARGET_S",
    ]
    rows: list[list[str]] = []
    for clip in clips:
        for path_name in paths:
            # Cells behind a circuit-breaker abort never ran and have no row.
            row_results = [
                result
                for rep in range(1, reps + 1)
                if (result := result_by_cell.get((clip, path_name, rep)))
                is not None
            ]
            target_times = [
                float(step["time_to_target_seconds"])
                for result in row_results
                if result["verdict"] in PASSING_VERDICTS
                for step in result["steps"]
                if step.get("verdict") == PASS
                and "time_to_target_seconds" in step
            ]
            median_target = (
                f"{statistics.median(target_times):.3f}" if target_times else "-"
            )
            rows.append(
                [
                    clip,
                    path_name,
                    *(
                        str(result["verdict"])
                        if (
                            result := result_by_cell.get(
                                (clip, path_name, rep)
                            )
                        )
                        is not None
                        else "SKIPPED"
                        for rep in range(1, reps + 1)
                    ),
                    str(
                        sum(
                            result["verdict"] in PASSING_VERDICTS
                            for result in row_results
                        )
                    ),
                    str(
                        sum(
                            result["verdict"] == STALL_RECOVERED
                            for result in row_results
                        )
                    ),
                    median_target,
                ]
            )
    widths = [
        max(len(headers[index]), *(len(row[index]) for row in rows))
        for index in range(len(headers))
    ]

    def render(values: Sequence[str]) -> str:
        return "  ".join(
            value.ljust(widths[index]) for index, value in enumerate(values)
        ).rstrip()

    print(render(headers))
    print(render(tuple("-" * width for width in widths)))
    for row in rows:
        print(render(row))


def display_action_template(action: str) -> str:
    return action.replace("{clip}", "<clip>").replace(
        "{stereo_label}", "<stereo_label>"
    )


def print_path_table() -> None:
    print("clip parameters")
    for clip in DEFAULT_CLIPS:
        print(f"  {clip}: stereo_label={STEREO_LABELS[clip]}")
    for path_index, (path_name, steps) in enumerate(PATHS.items(), start=1):
        print(f"{path_index}. {path_name}")
        for step_index, step in enumerate(steps, start=1):
            print(f"   {step_index}. {step.name}")
            for action in step.actions:
                print(f"      tap {display_action_template(action)}")
            print(
                "      expect "
                f"presentation={step.expect_presentation};transition=none"
            )


def positive_reps(value: str) -> int:
    try:
        reps = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("reps must be an integer") from error
    if reps < 1:
        raise argparse.ArgumentTypeError("reps must be at least 1")
    return reps


def default_evidence_directory() -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_EVIDENCE_ROOT / f"run-{timestamp}"


def parse_arguments() -> tuple[argparse.ArgumentParser, argparse.Namespace]:
    parser = argparse.ArgumentParser(
        description="Run the physical Vision Pro playback presentation path matrix."
    )
    parser.add_argument("--clips", nargs="+", default=list(DEFAULT_CLIPS))
    # With a persisted panoramic override both sanctioned clips open straight
    # into panorama, where the main window empties out of the accessibility
    # hierarchy; the paths that need windowed UI from there cannot be driven
    # until a windowed-state clip exists, so they stay opt-in.
    parser.add_argument(
        "--paths",
        nargs="+",
        choices=tuple(PATHS),
        default=["open-default"],
    )
    parser.add_argument("--reps", type=positive_reps, default=3)
    parser.add_argument(
        "--max-consecutive-drive-errors",
        type=int,
        default=3,
        help="Abort the sweep once this many DRIVE_ERROR cells land in a row "
        "(0 disables). A DRIVE_ERROR streak means a shared cause that would "
        "burn every remaining cell, so the runner stops, records the "
        "discriminators, and leaves the remainder for a diagnosed resume.",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Per cell: resetState, push the clip into TestMediaInbox, import "
        "through the production pipeline, relaunch, verify a single-item "
        "library. Clips are then paths relative to --media-root.",
    )
    parser.add_argument(
        "--media-root",
        type=Path,
        default=Path("/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/Samples"),
    )
    parser.add_argument("--evidence-dir", type=Path)
    parser.add_argument(
        "--list-paths",
        action="store_true",
        help="Print the path table without reading or controlling the device.",
    )
    return parser, parser.parse_args()


def configuration_error(arguments: argparse.Namespace) -> str | None:
    banned = [clip for clip in arguments.clips if "hnvr" in clip.casefold()]
    if banned:
        return f"Forbidden clip identifier contains hnvr: {', '.join(banned)}"
    needs_native_stereo = any(
        "{stereo_label}" in action
        for path_name in arguments.paths
        for step in PATHS[path_name]
        for action in step.actions
    )
    if needs_native_stereo:
        unknown = [
            clip
            for clip in arguments.clips
            if Path(clip).name not in STEREO_LABELS
        ]
        if unknown:
            return (
                "No SPEC stereo_label is defined for clip: "
                + ", ".join(unknown)
            )
    return None


def main() -> int:
    parser, arguments = parse_arguments()
    print(REGRESSION_BANNER, file=sys.stderr, flush=True)
    error = configuration_error(arguments)
    if error is not None:
        parser.error(error)
    if arguments.list_paths:
        print_path_table()
        return 0

    evidence_directory = (
        arguments.evidence_dir or default_evidence_directory()
    ).expanduser().resolve()
    evidence_directory.mkdir(parents=True, exist_ok=True)
    results_path = evidence_directory / "results.jsonl"
    results: list[dict[str, object]] = []

    cells = [
        (clip_index, clip, path_index, path_name, rep)
        for clip_index, clip in enumerate(arguments.clips, start=1)
        for path_index, path_name in enumerate(arguments.paths, start=1)
        for rep in range(1, arguments.reps + 1)
    ]
    consecutive_drive_errors = 0
    for position, (clip_index, clip, path_index, path_name, rep) in enumerate(cells):
        print(
            f"running clip={clip} path={path_name} rep={rep}",
            file=sys.stderr,
            flush=True,
        )
        result = run_cell(
            clip=clip,
            clip_index=clip_index,
            path_name=path_name,
            path_index=path_index,
            rep=rep,
            selected_clips=arguments.clips,
            evidence_directory=evidence_directory,
            clean=arguments.clean,
            media_root=arguments.media_root,
        )
        append_result(results_path, result)
        results.append(result)
        print(
            f"finished clip={clip} path={path_name} rep={rep} "
            f"verdict={result['verdict']}",
            file=sys.stderr,
            flush=True,
        )
        if result["verdict"] == DRIVE_ERROR:
            consecutive_drive_errors += 1
        else:
            consecutive_drive_errors = 0
        limit = arguments.max_consecutive_drive_errors
        if limit and consecutive_drive_errors >= limit:
            controller_directory = (
                Path(str(result["evidence_directory"])) / "controller"
            )
            failed_actions = [
                str(step.get("failed_action") or step.get("phase") or "")
                for streak_result in results[-consecutive_drive_errors:]
                for step in streak_result.get("steps", [])
                if step.get("verdict") == DRIVE_ERROR
            ]
            abort = {
                "abort": True,
                "reason": f"{consecutive_drive_errors} consecutive DRIVE_ERROR cells",
                "failedActions": failed_actions,
                **sweep_diagnosis(evidence_directory, controller_directory),
                "remaining": [
                    {"clip": cell_clip, "path": cell_path, "rep": cell_rep}
                    for _, cell_clip, _, cell_path, cell_rep in cells[position + 1 :]
                ],
            }
            # A streak that dies at one identical step is a harness or UI
            # defect at that step, not a session-level cause.
            if (
                failed_actions
                and len(set(failed_actions)) == 1
                and abort["diagnosis"] == "sessions-fail-while-app-responsive"
            ):
                abort["diagnosis"] = f"repeated-step-failure:{failed_actions[0]}"
            append_result(results_path, abort)
            print(
                f"circuit breaker: {abort['reason']}; "
                f"diagnosis={abort['diagnosis']}; "
                f"skipped {len(abort['remaining'])} remaining cells",
                file=sys.stderr,
                flush=True,
            )
            break

    print_summary(
        clips=arguments.clips,
        paths=arguments.paths,
        reps=arguments.reps,
        results=results,
    )
    print(f"results={results_path}")
    return 0 if all(bool(result["passed"]) for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
