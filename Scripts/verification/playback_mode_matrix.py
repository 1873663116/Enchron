#!/usr/bin/env python3
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import sys
import tempfile
import uuid
from dataclasses import dataclass, field
from typing import Any, Callable, NamedTuple, Sequence, TypeVar, cast
if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))
import enchron_target
from enchron_artifact_paths import artifact_root, evidence_root
from presentation_model import FLAT, PANORAMIC, lands_in_immersive_space, lands_in_main_window
from harness import Budget, BudgetProvider, ControllerClient, FaultRecord, Halt, InstrumentFault, LocalToolRunner, ProductFailure, RecoveryPolicy, wait_for
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"
DEFAULT_EVIDENCE_ROOT = evidence_root() / "playback-mode-coverage"
CONTROL_PLANE_IDENTIFIER = "PlayerUI-window-control-plane"
PROBE_REMOTE_PATH = "Documents/surface-tap-probe.log"
REGRESSION_BANNER = "playback_mode_matrix is the regression instrument: it sweeps the clip x path x rep cell grid to surface cross-breakage after a batch of fixes. Each cell re-establishes its own automation session (ensure-session measured 25.7s, 2026-08-09); recorded full rounds take tens of minutes, and the failing moment inside a cell is not observable live. Per-cell verdicts stream to results.jsonl."
PASS = "PASS"
STALL_RECOVERED = "STALL_RECOVERED"
STALL_TIMEOUT = "STALL_TIMEOUT"
WRONG_STATE = "WRONG_STATE"
DRIVE_ERROR = "DRIVE_ERROR"
PRODUCT_ERROR = "PRODUCT_ERROR"
CHROME_DISPLACED = "CHROME_DISPLACED"
PASSING_VERDICTS = frozenset((PASS, STALL_RECOVERED))
DEFAULT_CLIPS = ("180_3D.mp4", "180_3D_TB.mp4")
STEREO_LABELS = {"180_3D.mp4": "Side-by-Side", "180_3D_TB.mp4": "Top-Bottom", "180_3D_loop10.mp4": "Side-by-Side", "180_3D_TB_loop10.mp4": "Top-Bottom"}
FORMAT_FIELDS = ("presentation","transition","projection","formatProvenance","sourceContentKind","effectiveContentIsPanoramic","stereoLayout","mvHEVC","providerProjectionKind","sampleProjectionKind","rendererProjectionKind","rendererViewPackingKind","corePresentationPhase","corePresentationComponentStatus","windowComponentContentType","videoVisible","lifecycle","videoRendererStatus","videoRendererError","videoSamples","rendererInputs","displayedPixel","bootstrapComplete","providerCodecName","providerCodecTag","sampleMediaSubtype","error")
BUNDLE = "com.xiongzhipeng.XrPlayer"
DEVICE = enchron_target.target_device()
CORE_DEVICE = enchron_target.core_device()
DEVELOPER_DIR = enchron_target.developer_directory()
CONTROLLER_TIMEOUT_SECONDS = 600.0
PROBE_COPY_TIMEOUT_SECONDS = 150.0
SETTLEMENT_TIMEOUT_SECONDS = 40.0
POLL_INTERVAL_SECONDS = 2.0
STALL_RECOVERY_SECONDS = 8.0
Outcome = TypeVar("Outcome")


class Step(NamedTuple):
    name: str
    actions: tuple[str, ...]
    expect_presentation: str


class ProbeCursor(NamedTuple):
    sequence: int | None
    line_count: int
PROBE_SEQUENCE_PATTERN = re.compile(r"(?:^| )probeSequence=(\d+)(?: |$)")


def probe_sequence(line: str) -> int | None:
    match = PROBE_SEQUENCE_PATTERN.search(line)
    return int(match.group(1)) if match is not None else None


def probe_cursor(lines: Sequence[str]) -> ProbeCursor:
    sequences = [sequence for line in lines if (sequence := probe_sequence(line)) is not None]
    return ProbeCursor(sequence=max(sequences) if sequences else None, line_count=len(lines))


_probe_cursor = probe_cursor


def probe_lines_since(lines: Sequence[str], cursor: ProbeCursor) -> tuple[list[str], ProbeCursor, str | None]:
    sequenced = [(sequence, line) for line in lines if (sequence := probe_sequence(line)) is not None]
    if sequenced:
        delta = [line for sequence, line in sequenced if cursor.sequence is None or sequence > cursor.sequence]
        return (delta, ProbeCursor(sequence=max(sequence for sequence, _ in sequenced), line_count=len(lines)), None)
    if cursor.sequence is not None:
        return [], ProbeCursor(cursor.sequence, len(lines)), None
    if len(lines) < cursor.line_count:
        return ([], ProbeCursor(None, len(lines)), "Probe line count moved backwards from " + str(cursor.line_count) + " to " + str(len(lines)) + ".")
    return (list(lines[cursor.line_count:]), ProbeCursor(None, len(lines)), None)
OPEN_CLIP = ("MediaLibrary-grid-video-{clip}",)
APPLY_FLAT_MONO = ("PlayerUI-TopAction-videoFormat","PlayerUI-VideoFormat-Projection-Flat","PlayerUI-VideoFormat-Stereo Layout-Mono","PlayerUI-VideoFormat-apply")
APPLY_NATIVE_180 = ("PlayerUI-TopAction-videoFormat","PlayerUI-VideoFormat-Projection-180°","PlayerUI-VideoFormat-Stereo Layout-{stereo_label}","PlayerUI-VideoFormat-apply")
APPLY_360_MONO = ("PlayerUI-TopAction-videoFormat","PlayerUI-VideoFormat-Projection-360°","PlayerUI-VideoFormat-Stereo Layout-Mono","PlayerUI-VideoFormat-apply")
PANORAMIC_WINDOW = lands_in_main_window(PANORAMIC)
FLAT_WINDOW = lands_in_main_window(FLAT)
PANORAMIC_IMMERSIVE = lands_in_immersive_space(PANORAMIC)
FLAT_IMMERSIVE = lands_in_immersive_space(FLAT)
ENTER_PANORAMA = ("PlayerUI-TopAction-resumePanorama",)
MAIN_WINDOW_LANDINGS = frozenset((FLAT_WINDOW, PANORAMIC_WINDOW))
PATHS: dict[str, tuple[Step, ...]] = {
    "open-default": (Step("open", OPEN_CLIP, PANORAMIC_WINDOW),),
    "panorama-portal-cycle": (Step("open", OPEN_CLIP, PANORAMIC_WINDOW), Step("enter-panorama-1", ENTER_PANORAMA, PANORAMIC_IMMERSIVE), Step("exit-to-portal-1", ("PlayerPanel-button-exit-spatial",), PANORAMIC_WINDOW), Step("enter-panorama-2", ENTER_PANORAMA, PANORAMIC_IMMERSIVE), Step("exit-to-portal-2", ("PlayerPanel-button-exit-spatial",), PANORAMIC_WINDOW)),
    "format-flat-roundtrip": (Step("open", OPEN_CLIP, PANORAMIC_WINDOW), Step("apply-flat-mono", APPLY_FLAT_MONO, "window"), Step("apply-native-180", APPLY_NATIVE_180, PANORAMIC_WINDOW)),
    "dock-roundtrip": (Step("open", OPEN_CLIP, PANORAMIC_WINDOW), Step("apply-flat-mono", APPLY_FLAT_MONO, "window"), Step("enter-docked", ("PlayerUI-TopAction-dock","PlayerUI-DockMenu-skybox"), FLAT_IMMERSIVE), Step("exit-to-window", ("PlayerPanel-button-exit-spatial",), FLAT_WINDOW)),
    "reopen-in-session": (Step("open", OPEN_CLIP, PANORAMIC_WINDOW), Step("enter-panorama", ENTER_PANORAMA, PANORAMIC_IMMERSIVE), Step("exit-to-portal", ("PlayerPanel-button-exit-spatial",), PANORAMIC_WINDOW), Step("back-and-reopen", ("PlayerUI-InfoBar-button-back","MediaLibrary-grid-video-{clip}"), PANORAMIC_WINDOW)),
    "format-360": (Step("open", OPEN_CLIP, PANORAMIC_WINDOW), Step("apply-360-mono", APPLY_360_MONO, PANORAMIC_WINDOW)),
    "clean-open": (Step("open", OPEN_CLIP, "any-steady"),),
    "clean-spatial-cycle": (Step("open", OPEN_CLIP, "window"), Step("apply-native-180", ("summon:" + APPLY_NATIVE_180[0], *APPLY_NATIVE_180[1:]), PANORAMIC_WINDOW), Step("enter-panorama-1", ("summon:PlayerUI-TopAction-resumePanorama",), PANORAMIC_IMMERSIVE), Step("exit-to-portal-1", ("summon:PlayerPanel-button-exit-spatial",), PANORAMIC_WINDOW), Step("enter-panorama-2", ("summon:PlayerUI-TopAction-resumePanorama",), PANORAMIC_IMMERSIVE), Step("exit-to-portal-2", ("summon:PlayerPanel-button-exit-spatial",), PANORAMIC_WINDOW)),
    "clean-dock-cycle": (Step("open", OPEN_CLIP, "window"), Step("enter-docked-1", ("summon:PlayerUI-TopAction-dock","PlayerUI-DockMenu-skybox"), "docked"), Step("exit-to-window-1", ("summon:PlayerPanel-button-exit-spatial",), FLAT_WINDOW), Step("enter-docked-2", ("summon:PlayerUI-TopAction-dock","PlayerUI-DockMenu-skybox"), "docked"), Step("exit-to-window-2", ("summon:PlayerPanel-button-exit-spatial",), FLAT_WINDOW)),
    "clean-360-cycle": (Step("open", OPEN_CLIP, "window"), Step("apply-360-mono", ("summon:" + APPLY_360_MONO[0], *APPLY_360_MONO[1:]), PANORAMIC_WINDOW), Step("enter-panorama", ("summon:PlayerUI-TopAction-resumePanorama",), PANORAMIC_IMMERSIVE), Step("exit-to-portal", ("summon:PlayerPanel-button-exit-spatial",), PANORAMIC_WINDOW)),
}


@dataclass
class Instruments:
    device: str
    core_device: str
    developer_dir: str
    lane: str
    budgets: BudgetProvider
    tools: LocalToolRunner
    policy: RecoveryPolicy
    history: list[FaultRecord] = field(default_factory=list)
    def record_wait_sample(self, label: str, seconds: float, censored: bool) -> None:
        self.budgets.record_sample(self.lane, label, seconds, censored)
    def tool_env(self) -> dict[str, str]:
        return {**os.environ, "DEVELOPER_DIR": self.developer_dir}


def recovered(instruments: Instruments, location: str, action: Callable[[], Outcome]) -> Outcome:
    while True:
        instruments.policy.record_action()
        try:
            return action()
        except InstrumentFault as fault:
            instruments.history.append(FaultRecord(location=location, kind=fault.kind, censored=fault.kind in ("transport-timeout", "wait-expired")))
            decision = instruments.policy.on_fault(fault, instruments.history)
            if isinstance(decision, Halt):
                fault.evidence["halt"] = {"reason": decision.reason, "faultReport": decision.report}
                raise
_instruments_singleton: Instruments | None = None


def _get_instruments() -> Instruments:
    global _instruments_singleton
    if _instruments_singleton is None:
        device = enchron_target.target_device()
        lane = "simulator" if enchron_target.is_simulator(device) else "device"
        budgets = BudgetProvider()
        _instruments_singleton = Instruments(device=device, core_device=enchron_target.core_device(), developer_dir=enchron_target.developer_directory(), lane=lane, budgets=budgets, tools=LocalToolRunner(lane, budgets=budgets), policy=RecoveryPolicy())
    return _instruments_singleton


def _controller_client(instruments: Instruments, output_directory: Path) -> ControllerClient:
    return ControllerClient(instruments.lane, command_prefix=[sys.executable, str(CONTROLLER), "--device", instruments.device, "--developer-dir", instruments.developer_dir, "--output-directory", str(output_directory)], budgets=instruments.budgets)


def _parse_args_for_invoke(arguments: Sequence[str]) -> tuple[str, list[str]]:
    args = list(arguments)
    filtered: list[str] = []
    index = 0
    while index < len(args):
        token = args[index]
        if token == "--developer-dir" and index + 1 < len(args):
            index += 2
            continue
        if token == "--device" and index + 1 < len(args):
            index += 2
            continue
        if token == "--output-directory" and index + 1 < len(args):
            index += 2
            continue
        filtered.append(token)
        index += 1
    if not filtered:
        return "", []
    verb = filtered[0]
    return verb, filtered[1:]


def controller(output_directory: Path, *arguments: str) -> dict[str, object]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(output_directory))
    verb, verb_args = _parse_args_for_invoke(arguments)
    if not verb:
        return {"success": False, "error": "no verb"}
    try:
        response = recovered(instruments, f"controller:{verb}", lambda: client.invoke(verb, verb_args))
        if response.failure is not None:
            return {"success": False, "error": response.failure.kind, "failure": {"class": "product", "kind": response.failure.kind, "evidence": response.failure.evidence}, "_returncode": 2}
        doc = dict(response.document)
        doc["_returncode"] = 0
        return doc
    except InstrumentFault as fault:
        return {"success": False, "error": fault.kind, "failure": {"class": "instrument", "kind": fault.kind, "evidence": fault.evidence}, "_returncode": 2, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence, "budget": fault.budget.provenance if fault.budget else None}}


def controller_summary(document: dict[str, object]) -> dict[str, object]:
    summary = {key: document[key] for key in ("success","stage","message","error","detail","appState","sessionID","_returncode") if key in document}
    matched = document.get("matchedElement")
    if isinstance(matched, dict):
        summary["matchedElement"] = {key: matched[key] for key in ("identifier","value","isEnabled","isHittable") if key in matched}
    return summary


def parse_control_plane(document: dict[str, object]) -> dict[str, str] | None:
    matched = document.get("matchedElement")
    if not isinstance(matched, dict):
        return None
    value = matched.get("value")
    if not isinstance(value, str) or not value:
        return None
    return dict(part.split("=", 1) for part in value.split(";") if "=" in part)


_CHROME_DISPLACEMENTS: list[dict[str, object]] = []


def reset_chrome_displacements() -> None:
    _CHROME_DISPLACEMENTS.clear()


def chrome_displacements() -> list[dict[str, object]]:
    return list(_CHROME_DISPLACEMENTS)


def record_chrome_displacement(location: str, verb: str, document: dict[str, object]) -> None:
    """A settled displacement is the one the wearer sees. The window resize a
    presentation asks for is asynchronous, so chrome anchored to the content rect
    can sit outside the glass for a frame or two on the way; only a reading taken
    while the control plane reports no transition says the placement stayed
    wrong."""
    violations = document.get("chromeContainment")
    if not isinstance(violations, list) or not violations:
        return
    plane = parse_control_plane(document)
    if plane is None or plane.get("transition") != "none":
        return
    _CHROME_DISPLACEMENTS.append(
        {
            "location": location,
            "verb": verb,
            "presentation": plane.get("presentation"),
            "violations": violations,
        }
    )


def _invoke_controller(instruments: Instruments, client: ControllerClient, location: str, verb: str, *args: str) -> dict[str, object]:
    response = recovered(instruments, location, lambda: client.invoke(verb, list(args)))
    if response.failure is not None:
        raise InstrumentFault(response.failure.kind, response.failure.evidence)
    record_chrome_displacement(location, verb, response.document)
    return response.document


def read_control_plane(output_directory: Path, *, timeout: float = CONTROLLER_TIMEOUT_SECONDS) -> tuple[dict[str, str] | None, dict[str, object]]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(output_directory))
    try:
        document = _invoke_controller(instruments, client, "read-control-plane:snapshot", "snapshot", "--identifier", CONTROL_PLANE_IDENTIFIER, "--no-screenshot")
        return parse_control_plane(document), document
    except InstrumentFault as fault:
        return None, {"success": False, "error": fault.kind, "failure": {"class": "instrument", "kind": fault.kind, "evidence": fault.evidence}}


def _read_control_plane_harness(instruments: Instruments, client: ControllerClient) -> tuple[dict[str, str] | None, dict[str, object]]:
    document = _invoke_controller(instruments, client, "harness:snapshot", "snapshot", "--identifier", CONTROL_PLANE_IDENTIFIER, "--no-screenshot")
    return parse_control_plane(document), document


def copy_probe_lines(cell_directory: Path, *, target: str = DEVICE, core_device_identifier: str = CORE_DEVICE) -> tuple[list[str] | None, str | None]:
    instruments = _get_instruments()
    try:
        lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "compat:probe-copy")
        return lines, None
    except InstrumentFault as fault:
        return None, str(fault.evidence.get("diagnosis") or fault.kind)


def _copy_probe_lines_harness(instruments: Instruments, cell_directory: Path, location: str) -> list[str]:
    def attempt() -> list[str]:
        with tempfile.NamedTemporaryFile(prefix="enchron-probe-", suffix=".log", delete=False) as handle:
            destination = Path(handle.name)
        destination.unlink(missing_ok=True)
        completed = instruments.tools.call("probe-copy", lambda budget: enchron_target.copy_from_container(target=instruments.device, bundle_id=BUNDLE, source=PROBE_REMOTE_PATH, destination=destination, developer_dir=instruments.developer_dir, core_device_identifier=instruments.core_device, budget_seconds=budget.seconds))
        if completed.returncode != 0 or not destination.is_file():
            destination.unlink(missing_ok=True)
            raise InstrumentFault("probe-copy-failed", {"operation": "read", "stderr": (completed.stderr or completed.stdout)[-2000:]})
        lines = destination.read_text(encoding="utf-8", errors="replace").splitlines()
        destination.unlink(missing_ok=True)
        return lines
    return recovered(instruments, location, attempt)


def copy_probe_lines_once(cell_directory: Path, *, target: str = DEVICE, core_device_identifier: str = CORE_DEVICE) -> tuple[list[str] | None, str | None]:
    return copy_probe_lines(Path(cell_directory), target=target, core_device_identifier=core_device_identifier)


def _write_probe_excerpt_harness(instruments: Instruments, cell_directory: Path, step_index: int, step_name: str, cursor: ProbeCursor, lines: list[str] | None, error: str | None) -> tuple[str, list[str], ProbeCursor, str | None]:
    excerpt_path = Path(cell_directory) / ("step-" + f"{step_index:02d}" + "-" + safe_component(step_name) + "-probe.log")
    if lines is None:
        excerpt_path.write_text("", encoding="utf-8")
        return str(excerpt_path), [], cursor, error
    excerpt, next_cursor, cursor_error = probe_lines_since(lines, cursor)
    text = "\n".join(excerpt)
    excerpt_path.write_text(text + ("\n" if text else ""), encoding="utf-8")
    return str(excerpt_path), excerpt, next_cursor, cursor_error


def write_probe_excerpt(*, cell_directory: Path, step_index: int, step_name: str, cursor: ProbeCursor) -> tuple[str, list[str], ProbeCursor, str | None]:
    instruments = _get_instruments()
    try:
        lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "write-probe:probe-copy")
        error = None
    except InstrumentFault as fault:
        lines = None
        error = str(fault.evidence.get("diagnosis") or fault.kind)
    return _write_probe_excerpt_harness(instruments, Path(cell_directory), step_index, step_name, cursor, lines, error)


def safe_component(value: str) -> str:
    component = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-.")
    return component or "value"


def resolve_actions(step: Step, clip: str) -> tuple[str, ...]:
    values = {"clip": clip, "stereo_label": STEREO_LABELS.get(clip, "{stereo_label}")}
    return tuple(action.format_map(values) for action in step.actions)


def format_facts(plane: dict[str, str] | None) -> dict[str, str | None] | None:
    if plane is None:
        return None
    return {field: plane.get(field) for field in FORMAT_FIELDS}


def observed_state(plane: dict[str, str], elapsed_seconds: float) -> dict[str, object]:
    return {"elapsed_seconds": round(elapsed_seconds, 3), "presentation": plane.get("presentation"), "transition": plane.get("transition"), "lifecycle": plane.get("lifecycle"), "projection": plane.get("projection"), "error": plane.get("error")}


def append_observed_state(observations: list[dict[str, object]], plane: dict[str, str], elapsed_seconds: float) -> None:
    state = observed_state(plane, elapsed_seconds)
    if observations:
        comparable_keys = ("presentation","transition","lifecycle","projection","error")
        if all(observations[-1].get(key) == state.get(key) for key in comparable_keys):
            return
    observations.append(state)
FORMAT_CHANGE_FIELDS = ("projection","stereoLayout","formatProvenance")


def format_changed(baseline: dict[str, str] | None, plane: dict[str, str]) -> bool:
    if baseline is None:
        return True
    return any(plane.get(field) != baseline.get(field) for field in FORMAT_CHANGE_FIELDS)
PRODUCT_ERROR_PROBE_PATTERN = re.compile(r"(?:^|\s)conversionFailed\s+(?P<diagnostic>\S.*)$")


def product_error(plane: dict[str, str] | None) -> str | None:
    category = plane.get("error") if plane is not None else None
    return category if category not in (None, "", "none") else None


def probe_product_error(lines: Sequence[str]) -> str | None:
    for line in reversed(lines):
        match = PRODUCT_ERROR_PROBE_PATTERN.search(line)
        if match is not None:
            return match.group("diagnostic").strip()
    return None


def product_error_evidence(*, category: str, elapsed: float, plane: dict[str, str] | None, observations: Sequence[dict[str, object]] = ()) -> dict[str, object]:
    return {"verdict": PRODUCT_ERROR, "product_error": category, "elapsed_seconds": round(elapsed, 3), "actual_presentation": plane.get("presentation") if plane else None, "control_plane": format_facts(plane), "observed_states": list(observations)}


def hold(instruments: Instruments, label: str, seconds: float) -> None:
    if seconds <= 0:
        return
    started = datetime.now(timezone.utc)
    def probe() -> dict[str, object] | None:
        elapsed = (datetime.now(timezone.utc) - started).total_seconds()
        if elapsed >= seconds:
            return {"heldSeconds": round(elapsed, 3)}
        return None
    wait_for(label, probe, Budget(seconds=seconds + 5.0, provenance="pacing hold " + str(seconds) + "s + 5s slack"), observe=lambda: [], record=instruments.record_wait_sample)


def wait_for_presentation(*, output_directory: Path, expected: str, target_started_at: float, baseline_plane: dict[str, str] | None = None) -> dict[str, object]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(output_directory))
    started_dt = datetime.now(timezone.utc)
    require_format_change = baseline_plane is not None and baseline_plane.get("presentation") == expected and baseline_plane.get("transition") == "none"
    observations: list[dict[str, object]] = []
    latest_plane: dict[str, str] | None = None
    latest_doc: dict[str, object] | None = None
    def probe() -> dict[str, object] | None:
        nonlocal latest_plane, latest_doc
        try:
            plane, doc = _read_control_plane_harness(instruments, client)
        except InstrumentFault:
            raise
        latest_plane = plane
        latest_doc = doc
        elapsed = (datetime.now(timezone.utc) - started_dt).total_seconds()
        if plane is not None:
            append_observed_state(observations, plane, elapsed)
            if (category := product_error(plane)) is not None:
                return product_error_evidence(category=category, elapsed=elapsed, plane=plane, observations=observations)
            if plane.get("presentation") == expected and plane.get("transition") == "none" and (not require_format_change or format_changed(baseline_plane, plane)):
                return {"verdict": PASS, "time_to_target_seconds": round(elapsed, 3), "actual_presentation": plane.get("presentation"), "control_plane": format_facts(plane), "observed_states": list(observations)}
        return None
    def observe() -> list[object]:
        return [{"plane": format_facts(latest_plane), "observed": list(observations)}]
    try:
        return wait_for("presentation", probe, instruments.budgets.budget(instruments.lane, "presentation"), observe, record=instruments.record_wait_sample, poll_interval_seconds=2.0)
    except InstrumentFault as fault:
        if fault.kind == "wait-expired":
            elapsed = (datetime.now(timezone.utc) - started_dt).total_seconds()
            common = {"elapsed_seconds": round(elapsed, 3), "actual_presentation": latest_plane.get("presentation") if latest_plane else None, "control_plane": format_facts(latest_plane), "observed_states": list(observations)}
            if latest_plane is None:
                raise InstrumentFault("control-plane-unavailable", {**common, "waitFault": fault.evidence}, fault.budget) from None
            if latest_plane.get("transition") == "none" and latest_plane.get("presentation") != expected:
                return {**common, "verdict": WRONG_STATE}
            return {**common, "verdict": STALL_TIMEOUT}
        raise


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
    fields = dict(part.split("=", 1) for part in payload.split(",") if "=" in part)
    return fields or None
IMMERSIVE_PRESENTATIONS = frozenset(("panorama","docked"))


def last_settlement_settled(lines: Sequence[str]) -> bool | None:
    settled: bool | None = None
    for line in lines:
        fields = parse_settlement_fields(line)
        if fields is not None and "settled" in fields:
            settled = fields["settled"] == "true"
    return settled
SETTLEMENT_CONJUNCTS: tuple[tuple[str, tuple[str, ...]], ...] = (("ready", ("ready",)), ("immersiveMode", ("immersiveMode",)), ("contentTypeOrOverride", ("contentTypeMatches","overrideAdopted")), ("viewingMode", ("viewingMode",)), ("spatialMode", ("spatialMode",)), ("pixels", ("pixels",)))


def settlement_blocker(fields: dict[str, str]) -> str | None:
    for name, alternatives in SETTLEMENT_CONJUNCTS:
        if not any(fields.get(field) == "true" for field in alternatives):
            return name
    return None


def settlement_trace(lines: Sequence[str]) -> dict[str, object] | None:
    samples = [fields for fields in (parse_settlement_fields(line) for line in lines) if fields is not None and "settled" in fields]
    if not samples:
        return None
    settled_flags = [fields["settled"] == "true" for fields in samples]
    terminal = samples[-1]
    return {"samples": len(samples), "settled_samples": sum(settled_flags), "reached_settled": any(settled_flags), "regressed_after_settled": any(settled_flags[index] and not settled_flags[index + 1] for index in range(len(settled_flags) - 1)), "terminal_settled": settled_flags[-1], "terminal_blocker": settlement_blocker(terminal), "terminal_fields": {field: terminal.get(field) for field in ("ready","immersiveMode","contentTypeMatches","overrideAdopted","viewingMode","spatialMode","pixels","gotImmersive","gotViewing","status","provenance")}}


def appeared_presentation(lines: Sequence[str]) -> str | None:
    presentation: str | None = None
    for line in lines:
        if " immersiveSpaceAppeared " not in line:
            continue
        fields = dict(part.split("=", 1) for part in line.split(" immersiveSpaceAppeared ", 1)[1].split() if "=" in part)
        transition = fields.get("transition")
        if transition and transition != "none":
            presentation = transition
        else:
            presentation = fields.get("presentation", presentation)
    return presentation


def _wait_for_immersive_settlement_harness(*, instruments: Instruments, cell_directory: Path, expected: str, probe_cursor: ProbeCursor, client: ControllerClient, target_started_at: datetime) -> tuple[dict[str, object], list[str], ProbeCursor]:
    latest_delta: list[str] = []
    observed_cursor = probe_cursor
    def probe() -> dict[str, object] | None:
        nonlocal latest_delta, observed_cursor
        lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "immersive-settlement:probe-copy")
        delta, next_cursor, _ = probe_lines_since(lines, probe_cursor)
        latest_delta = delta
        observed_cursor = next_cursor
        elapsed = (datetime.now(timezone.utc) - target_started_at).total_seconds()
        if (diagnostic := probe_product_error(delta)) is not None:
            return product_error_evidence(category=diagnostic, elapsed=elapsed, plane=None)
        if last_settlement_settled(delta) is True:
            appeared = appeared_presentation(delta)
            if appeared is not None and appeared != expected:
                return {"verdict": WRONG_STATE, "actual_presentation": appeared, "elapsed_seconds": round(elapsed, 3)}
            return {"verdict": PASS, "time_to_target_seconds": round(elapsed, 3), "actual_presentation": appeared or expected, "elapsed_seconds": round(elapsed, 3)}
        return None
    def observe() -> list[object]:
        return cast(list[object], latest_delta[-20:])
    try:
        evidence = wait_for("immersive-settlement", probe, instruments.budgets.budget(instruments.lane, "immersive-settlement"), observe, record=instruments.record_wait_sample)
        return evidence, latest_delta, observed_cursor
    except InstrumentFault as fault:
        if fault.kind == "wait-expired":
            elapsed = (datetime.now(timezone.utc) - target_started_at).total_seconds()
            if any(parse_settlement_fields(line) for line in latest_delta):
                return {"verdict": STALL_TIMEOUT, "elapsed_seconds": round(elapsed, 3)}, latest_delta, observed_cursor
            try:
                plane, _ = _read_control_plane_harness(instruments, client)
            except InstrumentFault:
                plane = None
            if plane is not None:
                return {"verdict": WRONG_STATE, "actual_presentation": plane.get("presentation"), "control_plane": format_facts(plane), "elapsed_seconds": round(elapsed, 3)}, latest_delta, observed_cursor
            raise InstrumentFault("probe-unavailable", {"elapsed_seconds": round(elapsed, 3), "waitFault": fault.evidence}, fault.budget) from None
        raise


def wait_for_immersive_settlement(*, cell_directory: Path, expected: str, target_started_at: float, probe_cursor: ProbeCursor, controller_directory: Path) -> tuple[dict[str, object], list[str], ProbeCursor]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    dt = datetime.now(timezone.utc)
    return _wait_for_immersive_settlement_harness(instruments=instruments, cell_directory=Path(cell_directory), expected=expected, probe_cursor=probe_cursor, client=client, target_started_at=dt)


def probe_shows_recovered_stall(lines: Sequence[str]) -> bool:
    none_since: datetime | None = None
    for line in lines:
        timestamp = parse_probe_timestamp(line)
        fields = parse_settlement_fields(line)
        if timestamp is None or fields is None:
            continue
        if fields.get("settled") == "true":
            if none_since is not None and (timestamp - none_since).total_seconds() >= STALL_RECOVERY_SECONDS:
                return True
            none_since = None
        elif fields.get("gotImmersive") == "none":
            if none_since is None:
                none_since = timestamp
        else:
            none_since = None
    return False


def drive_error_step(*, step: Step, actions: Sequence[str], phase: str, started_at: float, controller_document: dict[str, object] | None = None, message: str | None = None) -> dict[str, object]:
    result: dict[str, object] = {"name": step.name, "actions": list(actions), "expect_presentation": step.expect_presentation, "verdict": DRIVE_ERROR, "phase": phase, "elapsed_seconds": round((datetime.now(timezone.utc) - datetime.fromtimestamp(started_at, tz=timezone.utc)).total_seconds(), 3) if isinstance(started_at, (int,float)) else 0}
    if controller_document is not None:
        result["controller"] = controller_summary(controller_document)
    if message is not None:
        result["message"] = message
    return result


def _drive_error_from_fault(*, step: Step, actions: Sequence[str], phase: str, started: datetime, fault: InstrumentFault) -> dict[str, object]:
    return {"name": step.name, "actions": list(actions), "expect_presentation": step.expect_presentation, "verdict": DRIVE_ERROR, "phase": phase, "elapsed_seconds": round((datetime.now(timezone.utc) - started).total_seconds(), 3), "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence, "budget": fault.budget.provenance if fault.budget else None}}


def _run_step_harness(*, instruments: Instruments, client: ControllerClient, step: Step, step_index: int, clip: str, cell_directory: Path, probe_cursor: ProbeCursor) -> tuple[dict[str, object], ProbeCursor]:
    actions = resolve_actions(step, clip)
    started_dt = datetime.now(timezone.utc)
    started_f = started_dt.timestamp()
    immersive_target = step.expect_presentation in IMMERSIVE_PRESENTATIONS
    baseline_plane: dict[str, str] | None = None
    if not immersive_target:
        try:
            baseline_plane, _ = _read_control_plane_harness(instruments, client)
        except InstrumentFault:
            baseline_plane = None
    target_started_at: datetime | None = None
    result: dict[str, object] | None = None
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
            target_started_at = datetime.now(timezone.utc)
        if kind == "scheme":
            scheme_action = payload[0]
            if scheme_action.startswith("summon:"):
                try:
                    doc = summon_and_tap_harness(instruments, client, scheme_action[len("summon:"):])
                except InstrumentFault as fault:
                    return _drive_error_from_fault(step=step, actions=actions, phase="summon-tap", started=started_dt, fault=fault), probe_cursor
                if doc.get("success") is not True and doc.get("ok") is not True:
                    return drive_error_step(step=step, actions=actions, phase="summon-tap", started_at=started_f, controller_document=doc), probe_cursor
            else:
                try:
                    doc = app_command_harness(instruments, client, scheme_action[len("app:"):])
                except InstrumentFault as fault:
                    return _drive_error_from_fault(step=step, actions=actions, phase="app-command", started=started_dt, fault=fault), probe_cursor
                if doc.get("ok") is not True:
                    return drive_error_step(step=step, actions=actions, phase="app-command", started_at=started_f, controller_document=doc), probe_cursor
            continue
        try:
            if len(payload) == 1:
                doc = _invoke_controller(instruments, client, "tap:single", "tap", "--identifier", payload[0], "--no-screenshot")
            else:
                doc = _invoke_controller(instruments, client, "tap:sequence", "tapSequence", "--identifiers", *payload, "--no-screenshot")
        except InstrumentFault as fault:
            tmp = _drive_error_from_fault(step=step, actions=actions, phase="tap", started=started_dt, fault=fault)
            tmp["failed_action"] = " -> ".join(payload)
            return tmp, probe_cursor
        if doc.get("success") is not True:
            tmp = drive_error_step(step=step, actions=actions, phase="tap", started_at=started_f, controller_document=doc)
            tmp["failed_action"] = " -> ".join(payload)
            return tmp, probe_cursor
    if result is None:
        if target_started_at is None:
            return drive_error_step(step=step, actions=actions, phase="path-data", started_at=started_f, message="Step has no target-triggering action."), probe_cursor
        elif immersive_target:
            try:
                wait_result, delta, next_cursor = _wait_for_immersive_settlement_harness(instruments=instruments, cell_directory=Path(cell_directory), expected=step.expect_presentation, probe_cursor=probe_cursor, client=client, target_started_at=target_started_at)
            except InstrumentFault as fault:
                return _drive_error_from_fault(step=step, actions=actions, phase="probe", started=started_dt, fault=fault), probe_cursor
            result = {"name": step.name, "actions": list(actions), "expect_presentation": step.expect_presentation, **wait_result}
            excerpt_path = Path(cell_directory) / ("step-" + f"{step_index:02d}" + "-" + safe_component(step.name) + "-probe.log")
            text = "\n".join(delta)
            excerpt_path.write_text(text + ("\n" if text else ""), encoding="utf-8")
            result["probe_excerpt"] = str(excerpt_path)
            result["stall_recovered"] = result["verdict"] == PASS and probe_shows_recovered_stall(delta)
            result["settlement_trace"] = settlement_trace(delta)
            apply_visual_gate_harness(instruments, client, result)
            return result, next_cursor
        else:
            try:
                wait_result = _wait_for_presentation_harness(instruments=instruments, client=client, expected=step.expect_presentation, baseline_plane=baseline_plane, started_dt=target_started_at)
            except InstrumentFault as fault:
                return _drive_error_from_fault(step=step, actions=actions, phase="control-plane", started=started_dt, fault=fault), probe_cursor
            result = {"name": step.name, "actions": list(actions), "expect_presentation": step.expect_presentation, "baseline_control_plane": format_facts(baseline_plane), **wait_result}
    try:
        lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "step:probe-copy")
        excerpt, new_cursor, probe_error = probe_lines_since(lines, probe_cursor) if False else (lines, probe_cursor, None)
        excerpt_path2 = Path(cell_directory) / ("step-" + f"{step_index:02d}" + "-" + safe_component(step.name) + "-probe.log")
        text2 = "\n".join(lines)
        excerpt_path2.write_text(text2 + ("\n" if text2 else ""), encoding="utf-8")
        result["probe_excerpt"] = str(excerpt_path2)
        if probe_error is not None:
            result["probe_error"] = probe_error
        result["stall_recovered"] = result["verdict"] == PASS and probe_shows_recovered_stall(lines)
        result["settlement_trace"] = settlement_trace(lines)
        new_offset = probe_cursor
        if lines is not None:
            _, new_offset, _ = probe_lines_since(lines, probe_cursor)
        return result, new_offset
    except InstrumentFault as fault:
        excerpt_path3 = Path(cell_directory) / ("step-" + f"{step_index:02d}" + "-" + safe_component(step.name) + "-probe.log")
        excerpt_path3.write_text("", encoding="utf-8")
        result["probe_excerpt"] = str(excerpt_path3)
        result["probe_error"] = str(fault.evidence.get("diagnosis") or fault.kind)
        result["stall_recovered"] = False
        result["settlement_trace"] = None
        return result, probe_cursor


def _wait_for_presentation_harness(*, instruments: Instruments, client: ControllerClient, expected: str, baseline_plane: dict[str, str] | None, started_dt: datetime) -> dict[str, object]:
    require_format_change = baseline_plane is not None and baseline_plane.get("presentation") == expected and baseline_plane.get("transition") == "none"
    observations: list[dict[str, object]] = []
    latest_plane: dict[str, str] | None = None
    def probe() -> dict[str, object] | None:
        nonlocal latest_plane
        plane, _ = _read_control_plane_harness(instruments, client)
        latest_plane = plane
        elapsed = (datetime.now(timezone.utc) - started_dt).total_seconds()
        if plane is not None:
            append_observed_state(observations, plane, elapsed)
            if (category := product_error(plane)) is not None:
                return product_error_evidence(category=category, elapsed=elapsed, plane=plane, observations=observations)
            if plane.get("presentation") == expected and plane.get("transition") == "none" and (not require_format_change or format_changed(baseline_plane, plane)):
                return {"verdict": PASS, "time_to_target_seconds": round(elapsed, 3), "actual_presentation": plane.get("presentation"), "control_plane": format_facts(plane), "observed_states": list(observations)}
        return None
    def observe() -> list[object]:
        return [{"plane": format_facts(latest_plane), "observed": list(observations)}]
    try:
        return wait_for("presentation", probe, instruments.budgets.budget(instruments.lane, "presentation"), observe, record=instruments.record_wait_sample, poll_interval_seconds=2.0)
    except InstrumentFault as fault:
        if fault.kind == "wait-expired":
            elapsed = (datetime.now(timezone.utc) - started_dt).total_seconds()
            common = {"elapsed_seconds": round(elapsed, 3), "actual_presentation": latest_plane.get("presentation") if latest_plane else None, "control_plane": format_facts(latest_plane), "observed_states": list(observations)}
            if latest_plane is None:
                raise InstrumentFault("control-plane-unavailable", {**common, "waitFault": fault.evidence}, fault.budget) from None
            if latest_plane.get("transition") == "none" and latest_plane.get("presentation") != expected:
                return {**common, "verdict": WRONG_STATE}
            return {**common, "verdict": STALL_TIMEOUT}
        raise


def run_step(*, step: Step, step_index: int, clip: str, cell_directory: Path, controller_directory: Path, probe_cursor: ProbeCursor) -> tuple[dict[str, object], ProbeCursor]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    return _run_step_harness(instruments=instruments, client=client, step=step, step_index=step_index, clip=clip, cell_directory=Path(cell_directory), probe_cursor=probe_cursor)


def control_signature(plane: dict[str, str] | None) -> tuple[str | None, str | None] | None:
    if plane is None:
        return None
    return plane.get("lifecycle"), plane.get("presentation")


def choose_wedge_clip(current_clip: str, selected_clips: Sequence[str]) -> str:
    for candidate in (*selected_clips, *DEFAULT_CLIPS):
        if candidate != current_clip and "hnvr" not in candidate.casefold():
            return candidate
    raise ValueError("No alternate allowed clip is available for the wedge check.")


def _run_wedge_check_harness(*, instruments: Instruments, client: ControllerClient, current_clip: str, selected_clips: Sequence[str]) -> tuple[str, dict[str, object]]:
    alternate_clip = choose_wedge_clip(current_clip, selected_clips)
    baseline_plane, baseline_document = _read_control_plane_harness(instruments, client)
    baseline_signature = control_signature(baseline_plane)
    identifier = "MediaLibrary-grid-video-" + alternate_clip
    target_started_at = datetime.now(timezone.utc)
    try:
        tap_document = _invoke_controller(instruments, client, "wedge:tap", "tap", "--identifier", identifier, "--no-screenshot")
    except InstrumentFault as fault:
        return "blocked", {"clip": alternate_clip, "identifier": identifier, "baseline": {"signature": baseline_signature, "control_plane": format_facts(baseline_plane), "controller": controller_summary(baseline_document)}, "tap": {"error": fault.kind, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}, "observed_states": []}
    evidence: dict[str, object] = {"clip": alternate_clip, "identifier": identifier, "baseline": {"signature": baseline_signature, "control_plane": format_facts(baseline_plane), "controller": controller_summary(baseline_document)}, "tap": controller_summary(tap_document), "observed_states": []}
    if tap_document.get("success") is not True:
        return "blocked", evidence
    observations: list[dict[str, object]] = []
    latest_plane: dict[str, str] | None = None
    def probe() -> dict[str, object] | None:
        nonlocal latest_plane
        plane, _ = _read_control_plane_harness(instruments, client)
        latest_plane = plane
        elapsed = (datetime.now(timezone.utc) - target_started_at).total_seconds()
        if plane is not None:
            append_observed_state(observations, plane, elapsed)
            if control_signature(plane) != baseline_signature:
                return {"changed": True, "plane": plane}
        return None
    def observe() -> list[object]:
        return list(observations)
    try:
        wait_for("wedge", probe, instruments.budgets.budget(instruments.lane, "wedge"), observe, record=instruments.record_wait_sample, poll_interval_seconds=2.0)
        evidence["observed_states"] = observations
        evidence["changed_control_plane"] = format_facts(latest_plane)
        return "opened", evidence
    except InstrumentFault:
        evidence["observed_states"] = observations
        evidence["last_controller"] = controller_summary(tap_document)
        return "blocked", evidence


def run_wedge_check(*, current_clip: str, selected_clips: Sequence[str], controller_directory: Path) -> tuple[str, dict[str, object]]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    return _run_wedge_check_harness(instruments=instruments, client=client, current_clip=current_clip, selected_clips=selected_clips)


def app_command(controller_directory: Path, verb: str, *arguments: str) -> dict[str, object]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    try:
        return app_command_harness(instruments, client, verb, *arguments)
    except InstrumentFault as fault:
        return {"ok": False, "error": fault.kind, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}


def app_command_harness(instruments: Instruments, client: ControllerClient, verb_name: str, *args: str) -> dict[str, object]:
    parts: list[str] = ["--verb", verb_name]
    for a in args:
        parts.extend(["--arg", a])
    document = _invoke_controller(instruments, client, "app-command:" + verb_name, "app-command", *parts)
    return document


def summon_and_tap(controller_directory: Path, identifier: str) -> dict[str, object]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    return summon_and_tap_harness(instruments, client, identifier)


def summon_and_tap_harness(instruments: Instruments, client: ControllerClient, identifier: str) -> dict[str, object]:
    try:
        doc = _invoke_controller(instruments, client, "summon-tap:" + identifier, "tap", "--identifier", identifier, "--no-screenshot")
        if doc.get("success") is True:
            return doc
    except InstrumentFault as fault:
        raise
    for _ in range(2):
        toggled = app_command_harness(instruments, client, "toggleControls")
        if toggled.get("ok") is not True:
            return toggled
        try:
            doc = _invoke_controller(instruments, client, "summon-tap-retry:" + identifier, "tapSequence", "--identifiers", identifier, "--no-screenshot")
        except InstrumentFault as fault:
            continue
        if doc.get("success") is True:
            return doc
    return doc


def push_to_inbox(media_path: Path) -> str | None:
    instruments = _get_instruments()
    try:
        push_to_inbox_harness(instruments, Path(media_path))
        return None
    except InstrumentFault as fault:
        return str(fault.evidence.get("diagnosis") or fault.kind)[:300]


def push_to_inbox_harness(instruments: Instruments, media_path: Path) -> None:
    def attempt() -> None:
        completed = instruments.tools.call("media-push", lambda budget: enchron_target.copy_to_container(target=instruments.device, bundle_id=BUNDLE, source=Path(media_path), destination="Documents/TestMediaInbox/" + Path(media_path).name, developer_dir=instruments.developer_dir, core_device_identifier=instruments.core_device, budget_seconds=budget.seconds))
        if completed.returncode != 0:
            raise InstrumentFault("media-push-failed", {"source": str(media_path), "stderr": (completed.stderr or completed.stdout)[-500:]})
    recovered(instruments, "push-to-inbox:media-push", attempt)


def clean_state_preamble(*, clip: str, media_root: Path, controller_directory: Path) -> dict[str, object] | None:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    return _clean_state_preamble_harness(instruments=instruments, client=client, clip=clip, media_root=Path(media_root))


def _clean_state_preamble_harness(*, instruments: Instruments, client: ControllerClient, clip: str, media_root: Path) -> dict[str, object] | None:
    media_path = Path(media_root) / clip
    if not Path(media_path).is_file():
        return {"phase": "clean-media", "message": "No such media: " + str(media_path)}
    try:
        _invoke_controller(instruments, client, "clean:relaunch", "relaunch", "--no-screenshot")
    except InstrumentFault:
        try:
            doc = _invoke_controller(instruments, client, "clean:ensure-session-fallback", "ensure-session")
            if doc.get("stage") != "ready":
                return {"phase": "clean-relaunch", "controller": controller_summary(doc)}
        except InstrumentFault as fault:
            return {"phase": "clean-relaunch", "controller": {"error": fault.kind, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}}
    try:
        reset = app_command_harness(instruments, client, "resetState")
    except InstrumentFault as fault:
        reset = {"ok": False, "error": fault.kind}
    if reset.get("ok") is not True:
        try:
            session = _invoke_controller(instruments, client, "clean:ensure-session", "ensure-session")
            if session.get("stage") != "ready":
                return {"phase": "clean-session", "controller": controller_summary(session)}
        except InstrumentFault as fault:
            return {"phase": "clean-session", "controller": {"error": fault.kind, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}}
        try:
            reset = app_command_harness(instruments, client, "resetState")
        except InstrumentFault as fault:
            reset = {"ok": False, "error": fault.kind}
        if reset.get("ok") is not True:
            return {"phase": "clean-reset", "controller": controller_summary(reset)}
    try:
        push_to_inbox_harness(instruments, Path(media_path))
    except InstrumentFault as fault:
        return {"phase": "clean-push", "message": str(fault.evidence.get("diagnosis") or fault.kind)}
    try:
        imported = app_command_harness(instruments, client, "importMedia", "file=" + Path(media_path).name)
    except InstrumentFault as fault:
        return {"phase": "clean-import", "controller": {"error": fault.kind, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}}
    if imported.get("ok") is not True:
        return {"phase": "clean-import", "controller": controller_summary(imported)}
    try:
        listing = app_command_harness(instruments, client, "listLibrary")
    except InstrumentFault as fault:
        return {"phase": "clean-list", "controller": {"error": fault.kind, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}}
    if listing.get("ok") is not True:
        return {"phase": "clean-list", "controller": controller_summary(listing)}
    names = listing.get("payload")
    if names != ["reference=" + Path(media_path).name]:
        return {"phase": "clean-verify", "message": "Library after clean import is " + str(names) + "."}
    return None
WINDOWED_STEADY_LIFECYCLES = frozenset(("playing","ready","paused","ended"))
VISUAL_BLACK_YAVG = 18.0
VISUAL_BLACK_YMAX = 40.0
VISUAL_FROZEN_SSIM = 0.995


def ffmpeg_luma_stats(image_path: str) -> tuple[float, float] | None:
    instruments = _get_instruments()
    return _ffmpeg_luma_stats_harness(instruments, image_path)


def _ffmpeg_luma_stats_harness(instruments: Instruments, image_path: str) -> tuple[float, float] | None:
    completed = instruments.tools.run("ffmpeg-luma", ["ffmpeg", "-hide_banner", "-i", image_path, "-vf", "signalstats,metadata=mode=print", "-frames:v", "1", "-f", "null", "-"], env=instruments.tool_env())
    yavg = ymax = None
    for line in (completed.stderr + "\n" + completed.stdout).splitlines():
        if "signalstats.YAVG=" in line:
            try:
                yavg = float(line.rsplit("=", 1)[1])
            except ValueError:
                pass
        elif "signalstats.YMAX=" in line:
            try:
                ymax = float(line.rsplit("=", 1)[1])
            except ValueError:
                pass
    if yavg is None or ymax is None:
        return None
    return yavg, ymax


def ffmpeg_ssim(first_path: str, second_path: str) -> float | None:
    instruments = _get_instruments()
    return _ffmpeg_ssim_harness(instruments, first_path, second_path)


def _ffmpeg_ssim_harness(instruments: Instruments, first_path: str, second_path: str) -> float | None:
    completed = instruments.tools.run("ffmpeg-ssim", ["ffmpeg", "-hide_banner", "-i", first_path, "-i", second_path, "-filter_complex", "ssim", "-f", "null", "-"], env=instruments.tool_env())
    match = re.search(r"All:([0-9.]+)", completed.stderr + completed.stdout)
    return float(match.group(1)) if match else None


def capture_visual_evidence(*, controller_directory: Path, lifecycle: str | None) -> dict[str, object]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    return _capture_visual_evidence_harness(instruments=instruments, client=client, lifecycle=lifecycle)


def _capture_visual_evidence_harness(*, instruments: Instruments, client: ControllerClient, lifecycle: str | None) -> dict[str, object]:
    shots: list[str] = []
    for index in (1, 2):
        try:
            document = _invoke_controller(instruments, client, "visual:snapshot-" + str(index), "snapshot")
        except InstrumentFault:
            document = {}
        path = document.get("localScreenshotPath")
        if isinstance(path, str):
            shots.append(path)
        if index == 1:
            hold(instruments, "visual-hold", 2.5)
    evidence: dict[str, object] = {"screenshots": shots}
    if not shots:
        evidence["verdict"] = "unavailable"
        return evidence
    stats = _ffmpeg_luma_stats_harness(instruments, shots[0])
    if stats is not None:
        evidence["yavg"], evidence["ymax"] = stats
    if len(shots) == 2:
        ssim = _ffmpeg_ssim_harness(instruments, shots[0], shots[1])
        if ssim is not None:
            evidence["ssim"] = ssim
    yavg = evidence.get("yavg")
    ymax = evidence.get("ymax")
    ssim = evidence.get("ssim")
    if isinstance(yavg, float) and isinstance(ymax, float) and yavg < VISUAL_BLACK_YAVG and ymax < VISUAL_BLACK_YMAX:
        evidence["verdict"] = "black"
    elif isinstance(ssim, float) and ssim > VISUAL_FROZEN_SSIM and (lifecycle or "").lower() == "playing":
        evidence["verdict"] = "frozen"
    elif "yavg" in evidence:
        evidence["verdict"] = "content"
    else:
        evidence["verdict"] = "unavailable"
    return evidence


def apply_visual_gate(step_result: dict[str, object], controller_directory: Path) -> None:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    apply_visual_gate_harness(instruments, client, step_result)


def apply_visual_gate_harness(instruments: Instruments, client: ControllerClient, step_result: dict[str, object]) -> None:
    if step_result.get("verdict") != PASS:
        return
    plane = step_result.get("control_plane") or {}
    lifecycle = plane.get("lifecycle") if isinstance(plane, dict) else None
    visual = _capture_visual_evidence_harness(instruments=instruments, client=client, lifecycle=lifecycle)
    step_result["visual"] = visual
    if visual.get("verdict") in ("black","frozen"):
        step_result["verdict"] = WRONG_STATE
        step_result["message"] = "visual evidence: " + str(visual["verdict"])


def _wait_for_clean_open_harness(*, instruments: Instruments, cell_directory: Path, client: ControllerClient, target_started_at: datetime) -> tuple[dict[str, object], list[str], ProbeCursor]:
    latest_delta: list[str] = []
    observed_cursor: ProbeCursor = ProbeCursor(None, 0)
    latest_plane: dict[str, str] | None = None
    invisible_steady_polls = 0
    started = target_started_at
    init_cursor = ProbeCursor(None, 0)
    try:
        init_lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "clean-open:init-probe")
        init_cursor = probe_cursor(init_lines)
    except InstrumentFault:
        init_cursor = ProbeCursor(None, 0)
    def probe() -> dict[str, object] | None:
        nonlocal latest_delta, observed_cursor, latest_plane, invisible_steady_polls
        try:
            lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "clean-open:probe-copy")
            delta, next_cursor, _ = probe_lines_since(lines, init_cursor)
            latest_delta = delta
            observed_cursor = next_cursor
            if last_settlement_settled(delta) is True:
                elapsed = (datetime.now(timezone.utc) - started).total_seconds()
                return {"verdict": PASS, "landed": appeared_presentation(delta) or PANORAMIC_WINDOW, "time_to_target_seconds": round(elapsed, 3)}
        except InstrumentFault:
            pass
        try:
            plane, _ = _read_control_plane_harness(instruments, client)
            latest_plane = plane
        except InstrumentFault:
            plane = None
            latest_plane = None
        if plane is not None:
            lifecycle = plane.get("lifecycle") or ""
            if (category := product_error(plane)) is not None:
                elapsed = (datetime.now(timezone.utc) - started).total_seconds()
                return {**product_error_evidence(category=category, elapsed=elapsed, plane=plane), "landed": "failed"}
            if plane.get("presentation") in MAIN_WINDOW_LANDINGS and plane.get("transition") == "none" and lifecycle.lower() in WINDOWED_STEADY_LIFECYCLES and plane.get("videoVisible") != "true":
                invisible_steady_polls += 1
                if invisible_steady_polls >= 4:
                    elapsed = (datetime.now(timezone.utc) - started).total_seconds()
                    return {"verdict": WRONG_STATE, "landed": "window-invisible", "elapsed_seconds": round(elapsed, 3), "message": "steady lifecycle with videoVisible=false", "control_plane": format_facts(plane)}
            else:
                invisible_steady_polls = 0
            if lifecycle.lower().startswith("failed"):
                elapsed = (datetime.now(timezone.utc) - started).total_seconds()
                return {"verdict": WRONG_STATE, "landed": "failed", "elapsed_seconds": round(elapsed, 3), "message": lifecycle, "control_plane": format_facts(plane)}
            if plane.get("presentation") in MAIN_WINDOW_LANDINGS and plane.get("transition") == "none" and plane.get("videoVisible") == "true" and lifecycle.lower() in WINDOWED_STEADY_LIFECYCLES:
                elapsed = (datetime.now(timezone.utc) - started).total_seconds()
                return {"verdict": PASS, "landed": plane.get("presentation"), "time_to_target_seconds": round(elapsed, 3), "control_plane": format_facts(plane)}
        return None
    def observe() -> list[object]:
        return [{"plane": format_facts(latest_plane), "delta": latest_delta}]
    try:
        evidence = wait_for("clean-open", probe, instruments.budgets.budget(instruments.lane, "clean-open"), observe, record=instruments.record_wait_sample)
        return evidence, latest_delta, observed_cursor
    except InstrumentFault as fault:
        if fault.kind == "wait-expired":
            elapsed = (datetime.now(timezone.utc) - started).total_seconds()
            return {"verdict": STALL_TIMEOUT, "landed": None, "elapsed_seconds": round(elapsed, 3), "control_plane": format_facts(latest_plane)}, latest_delta, observed_cursor
        raise


def wait_for_clean_open(*, cell_directory: Path, controller_directory: Path, target_started_at: float, probe_cursor: ProbeCursor | None = None, probe_offset: int | None = None) -> tuple[dict[str, object], list[str], ProbeCursor]:
    instruments = _get_instruments()
    client = _controller_client(instruments, Path(controller_directory))
    if isinstance(probe_cursor, ProbeCursor):
        cursor = probe_cursor
    elif probe_offset is not None:
        cursor = ProbeCursor(None, int(probe_offset))
    else:
        cursor = ProbeCursor(None, 0)
        try:
            lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "clean-open:compat-probe")
            cursor = _probe_cursor(lines)
        except InstrumentFault:
            cursor = ProbeCursor(None, 0)
    started_dt = datetime.now(timezone.utc)
    result, delta, new_cursor = _wait_for_clean_open_harness(instruments=instruments, cell_directory=Path(cell_directory), client=client, target_started_at=started_dt)
    return result, delta, new_cursor


def run_cell(*, clip: str, clip_index: int, path_name: str, path_index: int, rep: int, selected_clips: Sequence[str], evidence_directory: Path, clean: bool = False, media_root: Path | None = None) -> dict[str, object]:
    instruments = _get_instruments()
    cell_directory = Path(evidence_directory) / ("clip-" + f"{clip_index:02d}" + "-" + safe_component(Path(clip).name)) / ("path-" + f"{path_index:02d}" + "-" + path_name) / ("rep-" + f"{rep:02d}")
    controller_directory = Path(cell_directory) / "controller"
    controller_directory.mkdir(parents=True, exist_ok=True)
    client = _controller_client(instruments, Path(controller_directory))
    reset_chrome_displacements()
    path = PATHS[path_name]
    cell_started_dt = datetime.now(timezone.utc)
    cell_started_f = cell_started_dt.timestamp()
    clip_name = Path(clip).name
    if clean:
        failure = _clean_state_preamble_harness(instruments=instruments, client=client, clip=clip, media_root=Path(media_root) if media_root else Path("."))
        if failure is not None:
            try:
                _copy_probe_lines_harness(instruments, Path(cell_directory), "clean:probe-copy")
            except InstrumentFault:
                pass
            first_step = path[0]
            step_result: dict[str, object]
            try:
                raise InstrumentFault(str(failure.get("phase", "clean-preamble")), {"message": str(failure.get("message", ""))})
            except InstrumentFault as fault:
                step_result = _drive_error_from_fault(step=first_step, actions=resolve_actions(first_step, clip_name), phase=str(failure.get("phase", "clean-preamble")), started=cell_started_dt, fault=fault)
                step_result["message"] = str(failure.get("message", "")) or None
                if "controller" in failure:
                    step_result["controller"] = failure["controller"]
                step_result["instrumentFault"] = {"kind": fault.kind, "evidence": fault.evidence}
            return {"clip": clip, "path": path_name, "rep": rep, "verdict": DRIVE_ERROR, "passed": False, "elapsed_seconds": round((datetime.now(timezone.utc) - cell_started_dt).total_seconds(), 3), "session": {}, "steps": [step_result], "wedge_check": None, "wedge_evidence": None, "evidence_directory": str(cell_directory)}
        try:
            probe_lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "clean:probe-copy")
        except InstrumentFault:
            probe_lines = []
        current_probe_cursor = probe_cursor(probe_lines or [])
        if path_name == "clean-open":
            try:
                doc = _invoke_controller(instruments, client, "clean-open:tap", "tap", "--identifier", "MediaLibrary-grid-video-" + clip_name, "--no-screenshot")
            except InstrumentFault as fault:
                step_result = _drive_error_from_fault(step=path[0], actions=("MediaLibrary-grid-video-" + clip_name,), phase="tap", started=cell_started_dt, fault=fault)
                verdict = DRIVE_ERROR
                steps = [step_result]
                return {"clip": clip, "path": path_name, "rep": rep, "verdict": verdict, "landed": steps[0].get("landed"), "passed": verdict in PASSING_VERDICTS, "elapsed_seconds": round((datetime.now(timezone.utc) - cell_started_dt).total_seconds(), 3), "session": {}, "steps": steps, "wedge_check": None, "wedge_evidence": None, "evidence_directory": str(cell_directory)}
            if doc.get("success") is not True:
                step_result = drive_error_step(step=path[0], actions=("MediaLibrary-grid-video-" + clip_name,), phase="tap", started_at=cell_started_f, controller_document=doc)
                verdict = DRIVE_ERROR
                steps = [step_result]
                return {"clip": clip, "path": path_name, "rep": rep, "verdict": verdict, "landed": steps[0].get("landed"), "passed": verdict in PASSING_VERDICTS, "elapsed_seconds": round((datetime.now(timezone.utc) - cell_started_dt).total_seconds(), 3), "session": {}, "steps": steps, "wedge_check": None, "wedge_evidence": None, "evidence_directory": str(cell_directory)}
            else:
                started_open = datetime.now(timezone.utc)
                wait_result, delta, _ = _wait_for_clean_open_harness(instruments=instruments, cell_directory=Path(cell_directory), client=client, target_started_at=started_open)
                excerpt_path = Path(cell_directory) / "step-01-open-probe.log"
                text = "\n".join(delta)
                excerpt_path.write_text(text + ("\n" if text else ""), encoding="utf-8")
                step_result = {"name": "open", "actions": ["MediaLibrary-grid-video-" + clip_name], "expect_presentation": "any-steady", "probe_excerpt": str(excerpt_path), "stall_recovered": probe_shows_recovered_stall(delta), **wait_result}
                try:
                    apply_visual_gate_harness(instruments, client, step_result)
                except InstrumentFault as fault:
                    step_result["visual"] = {"verdict": "unavailable", "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}
                verdict = str(step_result["verdict"])
                steps = [step_result]
                return {"clip": clip, "path": path_name, "rep": rep, "verdict": verdict, "landed": steps[0].get("landed"), "passed": verdict in PASSING_VERDICTS, "elapsed_seconds": round((datetime.now(timezone.utc) - cell_started_dt).total_seconds(), 3), "session": {}, "steps": steps, "wedge_check": None, "wedge_evidence": None, "evidence_directory": str(cell_directory)}
        session: dict[str, object] = {"stage": "ready", "success": True}
    else:
        try:
            session = _invoke_controller(instruments, client, "ensure-session", "ensure-session")
            if session.get("stage") != "ready":
                raise InstrumentFault("session-lost", {"document": session})
        except InstrumentFault as fault:
            session = {"success": False, "error": fault.kind, "stage": "failed", "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}
    steps: list[dict[str, object]] = []
    current_probe_cursor = probe_cursor([])
    baseline_error: str | None = None
    if session.get("stage") == "ready" and session.get("success") is True:
        try:
            baseline_lines = _copy_probe_lines_harness(instruments, Path(cell_directory), "cell:baseline-probe")
            current_probe_cursor = probe_cursor(baseline_lines)
        except InstrumentFault as fault:
            baseline_error = str(fault.evidence.get("diagnosis") or fault.kind)
    if session.get("stage") != "ready" or session.get("success") is not True:
        first_step = path[0]
        try:
            raise InstrumentFault("session-lost", {"session": session})
        except InstrumentFault as fault:
            step_result = _drive_error_from_fault(step=first_step, actions=resolve_actions(first_step, clip), phase="ensure-session", started=cell_started_dt, fault=fault)
            step_result["controller"] = controller_summary(session)
            excerpt_path = Path(cell_directory) / ("step-01-" + safe_component(first_step.name) + "-probe.log")
            excerpt_path.write_text("", encoding="utf-8")
            step_result["probe_excerpt"] = str(excerpt_path)
            step_result["probe_error"] = "Session did not reach ready."
            steps.append(step_result)
    elif baseline_error is not None:
        first_step = path[0]
        try:
            raise InstrumentFault("probe-baseline-failed", {"diagnosis": baseline_error})
        except InstrumentFault as fault:
            step_result = _drive_error_from_fault(step=first_step, actions=resolve_actions(first_step, clip), phase="probe-baseline", started=cell_started_dt, fault=fault)
            step_result["message"] = baseline_error
            excerpt_path = Path(cell_directory) / "step-01-open-probe.log"
            excerpt_path.write_text("", encoding="utf-8")
            step_result["probe_excerpt"] = str(excerpt_path)
            step_result["probe_error"] = baseline_error
            steps.append(step_result)
    else:
        for step_index, step in enumerate(path, start=1):
            step_result, current_probe_cursor = _run_step_harness(instruments=instruments, client=client, step=step, step_index=step_index, clip=Path(clip).name, cell_directory=Path(cell_directory), probe_cursor=current_probe_cursor)
            steps.append(step_result)
            if step_result["verdict"] != PASS:
                break
    displacements = chrome_displacements()
    first_failure = next((step for step in steps if step["verdict"] != PASS), None)
    if first_failure is not None:
        verdict = str(first_failure["verdict"])
    elif displacements:
        verdict = CHROME_DISPLACED
    elif any(bool(step.get("stall_recovered")) for step in steps):
        verdict = STALL_RECOVERED
    else:
        verdict = PASS
    wedge_check: str | None = None
    wedge_evidence: dict[str, object] | None = None
    if verdict in (STALL_TIMEOUT, WRONG_STATE, PRODUCT_ERROR):
        if session.get("stage") != "ready" or session.get("success") is not True:
            wedge_check = "blocked"
            wedge_evidence = {"error": "No ready session for the wedge check."}
        else:
            try:
                wedge_check, wedge_evidence = _run_wedge_check_harness(instruments=instruments, client=client, current_clip=Path(clip).name, selected_clips=selected_clips)
            except InstrumentFault as fault:
                wedge_check = "blocked"
                wedge_evidence = {"error": fault.kind, "instrumentFault": {"kind": fault.kind, "evidence": fault.evidence}}
            except ValueError as error:
                wedge_check = "blocked"
                wedge_evidence = {"error": str(error)}
    return {"clip": clip, "path": path_name, "rep": rep, "verdict": verdict, "passed": verdict in PASSING_VERDICTS, "elapsed_seconds": round((datetime.now(timezone.utc) - cell_started_dt).total_seconds(), 3), "session": controller_summary(session), "steps": steps, "chrome_displacements": displacements, "wedge_check": wedge_check, "wedge_evidence": wedge_evidence, "evidence_directory": str(cell_directory)}


def append_result(results_path: Path, result: dict[str, object]) -> None:
    with Path(results_path).open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(result, ensure_ascii=False, sort_keys=True) + "\n")


def print_summary(*, clips: Sequence[str], paths: Sequence[str], reps: int, results: Sequence[dict[str, object]]) -> None:
    result_by_cell = {(str(result["clip"]), str(result["path"]), int(cast(int, result["rep"]))): result for result in results}
    headers = ["clip","path",*(f"rep-{rep}" for rep in range(1, reps + 1)),"PASS_COUNT","RECOVERED","MEDIAN_STEP_TARGET_S"]
    rows: list[list[str]] = []
    for clip in clips:
        for path_name in paths:
            row_results = [result for rep in range(1, reps + 1) if (result := result_by_cell.get((clip, path_name, rep))) is not None]
            target_times = [float(cast(Any, cast(dict[str, object], step)["time_to_target_seconds"])) for result in row_results if cast(str, result["verdict"]) in PASSING_VERDICTS for step in cast(Sequence[dict[str, object]], result["steps"]) if cast(dict[str, object], step).get("verdict") == PASS and "time_to_target_seconds" in cast(dict[str, object], step)]
            median_target = f"{statistics.median(target_times):.3f}" if target_times else "-"
            rows.append([clip, path_name, *(str(cast(str, result["verdict"])) if (result := result_by_cell.get((clip, path_name, rep))) is not None else "SKIPPED" for rep in range(1, reps + 1)), str(sum(cast(str, result["verdict"]) in PASSING_VERDICTS for result in row_results)), str(sum(cast(str, result["verdict"]) == STALL_RECOVERED for result in row_results)), median_target])
    widths = [max(len(headers[index]), *(len(row[index]) for row in rows)) for index in range(len(headers))]
    def render(values: Sequence[str]) -> str:
        return "  ".join(value.ljust(widths[index]) for index, value in enumerate(values)).rstrip()
    print(render(headers))
    print(render(tuple("-" * width for width in widths)))
    for row in rows:
        print(render(row))


def display_action_template(action: str) -> str:
    return action.replace("{clip}", "<clip>").replace("{stereo_label}", "<stereo_label>")


def print_path_table() -> None:
    print("clip parameters")
    for clip in DEFAULT_CLIPS:
        print("  " + clip + ": stereo_label=" + STEREO_LABELS[clip])
    for path_index, (path_name, steps) in enumerate(PATHS.items(), start=1):
        print(str(path_index) + ". " + path_name)
        for step_index, step in enumerate(steps, start=1):
            print("   " + str(step_index) + ". " + step.name)
            for action in step.actions:
                print("      tap " + display_action_template(action))
            print("      expect presentation=" + step.expect_presentation + ";transition=none")


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
    return DEFAULT_EVIDENCE_ROOT / ("run-" + timestamp)


def parse_arguments() -> tuple[argparse.ArgumentParser, argparse.Namespace]:
    parser = argparse.ArgumentParser(description="Run the physical Vision Pro playback presentation path matrix.")
    parser.add_argument("--clips", nargs="+", default=list(DEFAULT_CLIPS))
    parser.add_argument("--paths", nargs="+", choices=tuple(PATHS), default=["open-default"])
    parser.add_argument("--reps", type=positive_reps, default=3)
    parser.add_argument("--max-consecutive-drive-errors", type=int, default=0)
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--media-root", type=Path, default=Path("/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/Samples"))
    parser.add_argument("--evidence-dir", type=Path)
    parser.add_argument("--list-paths", action="store_true")
    return parser, parser.parse_args()


def configuration_error(arguments: argparse.Namespace) -> str | None:
    banned = [clip for clip in arguments.clips if "hnvr" in clip.casefold()]
    if banned:
        return "Forbidden clip identifier contains hnvr: " + ", ".join(banned)
    needs_native_stereo = any("{stereo_label}" in action for path_name in arguments.paths for step in PATHS[path_name] for action in step.actions)
    if needs_native_stereo:
        unknown = [clip for clip in arguments.clips if Path(clip).name not in STEREO_LABELS]
        if unknown:
            return "No SPEC stereo_label is defined for clip: " + ", ".join(unknown)
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
    evidence_directory = (arguments.evidence_dir or default_evidence_directory()).expanduser().resolve()
    evidence_directory.mkdir(parents=True, exist_ok=True)
    results_path = evidence_directory / "results.jsonl"
    results: list[dict[str, object]] = []
    cells = [(clip_index, clip, path_index, path_name, rep) for clip_index, clip in enumerate(arguments.clips, start=1) for path_index, path_name in enumerate(arguments.paths, start=1) for rep in range(1, arguments.reps + 1)]
    for clip_index, clip, path_index, path_name, rep in cells:
        print("running clip=" + clip + " path=" + path_name + " rep=" + str(rep), file=sys.stderr, flush=True)
        result = run_cell(clip=clip, clip_index=clip_index, path_name=path_name, path_index=path_index, rep=rep, selected_clips=arguments.clips, evidence_directory=evidence_directory, clean=arguments.clean, media_root=arguments.media_root)
        append_result(results_path, result)
        results.append(result)
        print("finished clip=" + clip + " path=" + path_name + " rep=" + str(rep) + " verdict=" + str(result["verdict"]), file=sys.stderr, flush=True)
    print_summary(clips=arguments.clips, paths=arguments.paths, reps=arguments.reps, results=results)
    print("results=" + str(results_path))
    return 0 if all(bool(result["passed"]) for result in results) else 1
if __name__ == "__main__":
    raise SystemExit(main())
