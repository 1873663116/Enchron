#!/usr/bin/env python3
"""Send one runtime-decided XCUIAutomation command to a live Vision Pro runner."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable


RUNNER_BUNDLE_ID = "com.xiongzhipeng.EnchronAppUITests.xctrunner"
APP_BUNDLE_ID = "com.xiongzhipeng.XrPlayer"
DEVICE_PROCESS_MARKER = "Enchron"
CHANNEL_ROOT = "Documents/EnchronInteractiveUI"
APP_COMMAND_PATH = "Documents/test-command.json"
DEFERRED_APP_COMMAND_ROOT = "Documents/test-commands"
APP_RESPONSE_ROOT = "Documents/test-responses"
APP_REQUEST_SLOT_POLL_INTERVAL_SECONDS = 0.5
DEFERRED_COMMAND_SLOT_HOLD_SECONDS = 1.5 * APP_REQUEST_SLOT_POLL_INTERVAL_SECONDS
COMMAND_NOTIFICATION = "com.enchron.interactive-device-ui.command"
SCRIPTS_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))
from regression.core.contracts import BoundLane
from regression.execution_identity import (
    PhysicalVisionOSDevice,
    PhysicalVisionOSDeviceRegistry,
    PhysicalVisionOSDeviceRegistrySource,
    SimulatorUDIDSource,
    load_execution_input,
    load_frozen_test_launch,
    registered_physical_visionos_devices,
    registered_simulator_udids,
)

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER_PROCESS_MARKER = Path(__file__).name
RUNNER_PROCESS_MARKERS = (
    "xcodebuild test-without-building",
    "-xctestrun",
    "InteractiveDeviceSession",
)
GRACEFUL_STOP_DEADLINE_SECONDS = 30.0
TERMINATION_DEADLINE_SECONDS = 5.0
RESULT_BUNDLE_SETTLE_SECONDS = 2.0
"""How long xcodebuild gets to exit on its own after a stop, before it is asked.

Nothing reads the bundle this waits for. Interactive-*.xcresult has no consumer
anywhere in the repository and resultBundleWritten is written and never read, so
the wait was buying a file the run does not use.

Waiting longer would not have bought it either. On the headset xcodebuild
starts a devicectl diagnose before it exits, and one panorama run shows the test
suite passing at 17:34:30 and the diagnose failing at 18:34:31 - an hour, with
the bundle finalised only afterwards. A hundred and eighty seconds was never
going to reach the other side of that. The simulator never does this, and the
runner log carries two product warnings beside it: a window that cannot be
presented because the scene was invalidated before create completion, and state
modified during a view update. Those are worth their own investigation.

Two seconds lets an ordinary exit finish without being signalled."""

TIMINGS_DEVICE_PATH = REPOSITORY_ROOT / "Scripts/verification/controller_timings.device.json"
TIMINGS_SIMULATOR_PATH = REPOSITORY_ROOT / "Scripts/verification/controller_timings.simulator.json"
TIMING_SAMPLE_LIMIT = 40
DEVICECTL_TRANSPORT_DEADLINE_SECONDS = 120.0
DEVICECTL_CALL_COUNT = 0


def record_timing(
    action: str, seconds: float, *, device: str, frozen: bool = False, censored: bool = False
) -> None:
    if frozen:
        return
    path = TIMINGS_SIMULATOR_PATH if is_simulator(device) else TIMINGS_DEVICE_PATH
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        data = {"verbs": {}, "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    if not isinstance(data, dict):
        data = {"verbs": {}, "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    verbs = data.get("verbs")
    if not isinstance(verbs, dict):
        verbs = {}
        for key, value in list(data.items()):
            if key in ("verbs", "updatedAt"):
                continue
            if isinstance(value, dict) and "samples" in value:
                verbs[key] = value
    entry = verbs.get(action)
    if not isinstance(entry, dict):
        entry = {}
    samples = entry.get("samples")
    if not isinstance(samples, list):
        samples = []
    at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    samples.append({"seconds": round(seconds, 2), "censored": bool(censored), "at": at})
    verbs[action] = {"samples": samples[-TIMING_SAMPLE_LIMIT:]}
    data = {"verbs": verbs, "updatedAt": at}
    try:
        temporary = path.with_name(path.name + ".tmp")
        temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(path)
    except OSError:
        pass


def run_devicectl(arguments: list[str], *, quiet: bool = False) -> subprocess.CompletedProcess[str]:
    global DEVICECTL_CALL_COUNT
    DEVICECTL_CALL_COUNT += 1
    command = ["xcrun", "devicectl", *arguments]
    try:
        return subprocess.run(
            command,
            check=False,
            text=True,
            timeout=DEVICECTL_TRANSPORT_DEADLINE_SECONDS,
            stdout=subprocess.DEVNULL if quiet else subprocess.PIPE,
            stderr=subprocess.DEVNULL if quiet else subprocess.PIPE,
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(
            command,
            returncode=124,
            stdout="",
            stderr=(
                "devicectl exceeded the "
                f"{DEVICECTL_TRANSPORT_DEADLINE_SECONDS:.0f} second transport "
                "deadline. This controller moves only command files and "
                "screenshots over it, so a transfer this slow means devicectl "
                "is wedged."
            ),
        )


_SIMULATOR_UDIDS: frozenset[str] | None = None


def is_simulator(
    device: str, *, simulator_udids: frozenset[str] | None = None
) -> bool:
    """A simulator carries the whole channel on this Mac's filesystem, so every
    `devicectl` round trip below has a local equivalent that is both faster and
    incapable of the 120s transport hang."""
    global _SIMULATOR_UDIDS
    if not isinstance(device, str) or not device.strip():
        raise RuntimeError("The controller target must be non-empty text.")
    if simulator_udids is None:
        if _SIMULATOR_UDIDS is None:
            _SIMULATOR_UDIDS = registered_simulator_udids()
        simulator_udids = _SIMULATOR_UDIDS
    return device in simulator_udids


def simulator_container(device: str, bundle_id: str) -> Path | None:
    result = subprocess.run(
        ["xcrun", "simctl", "get_app_container", device, bundle_id, "data"],
        check=False, text=True, capture_output=True,
    )
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip())


def copy_from_device(
    *,
    device: str,
    runner_bundle_id: str,
    remote_path: str,
    local_path: Path,
    quiet: bool,
) -> bool:
    if is_simulator(device):
        container = simulator_container(device, runner_bundle_id)
        source = container / remote_path if container else None
        if source is None or not source.exists():
            return False
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(source.read_bytes())
        return True
    result = run_devicectl(
        [
            "device",
            "copy",
            "from",
            "--device",
            device,
            "--source",
            remote_path,
            "--destination",
            str(local_path),
            "--domain-type",
            "appDataContainer",
            "--domain-identifier",
            runner_bundle_id,
        ],
        quiet=quiet,
    )
    return result.returncode == 0


def copy_to_device(
    *,
    device: str,
    runner_bundle_id: str,
    local_path: Path,
    remote_path: str,
) -> None:
    if is_simulator(device):
        container = simulator_container(device, runner_bundle_id)
        if container is None:
            raise RuntimeError("The runner container is not installed on this simulator.")
        destination = container / remote_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(local_path.read_bytes())
        return
    detail = "Unable to send UI command."
    for attempt in range(DEVICE_TRANSFER_ATTEMPTS):
        result = run_devicectl(
            [
                "device",
                "copy",
                "to",
                "--device",
                device,
                "--source",
                str(local_path),
                "--destination",
                remote_path,
                "--domain-type",
                "appDataContainer",
                "--domain-identifier",
                runner_bundle_id,
            ]
        )
        if result.returncode == 0:
            return
        detail = result.stderr or result.stdout or detail
        if attempt + 1 < DEVICE_TRANSFER_ATTEMPTS:
            device_transfer_pause(DEVICE_TRANSFER_RETRY_SECONDS)
    raise RuntimeError(
        f"{detail.strip()} (after {DEVICE_TRANSFER_ATTEMPTS} devicectl transfer attempts)"
    )


def wake_runner(arguments: argparse.Namespace) -> None:
    """A runner between commands is parked on a Darwin notification, so a command
    file that lands with no notification behind it is read only if the runner
    happens to loop again for another reason. Every command, stop included, is
    delivered by posting this notification."""
    if is_simulator(arguments.device):
        posted = subprocess.run(
            ["xcrun", "simctl", "spawn", arguments.device, "notifyutil", "-p",
             COMMAND_NOTIFICATION],
            check=False, text=True, capture_output=True,
        )
        if posted.returncode != 0:
            raise RuntimeError(
                posted.stderr or "Unable to wake the interactive UI runner."
            )
        return
    result = run_devicectl(
        [
            "device",
            "notification",
            "post",
            "--device",
            arguments.device,
            "--name",
            COMMAND_NOTIFICATION,
        ]
    )
    if result.returncode != 0:
        raise RuntimeError(
            result.stderr or result.stdout or "Unable to wake the interactive UI runner."
        )


READY_CACHE_KEY = "readyCache"


def ready_cache_applies(arguments: argparse.Namespace) -> bool:
    if getattr(arguments, "output_directory", None) is None:
        return False
    return not is_simulator(arguments.device)


def cached_ready_state(arguments: argparse.Namespace) -> dict[str, object] | None:
    if not ready_cache_applies(arguments):
        return None
    cached = load_session_state(arguments).get(READY_CACHE_KEY)
    return cached if isinstance(cached, dict) and "sessionID" in cached else None


def remember_ready_state(arguments: argparse.Namespace, ready: dict[str, object]) -> None:
    if not ready_cache_applies(arguments):
        return
    state = load_session_state(arguments)
    state[READY_CACHE_KEY] = ready
    save_session_state_best_effort(arguments, state)


def forget_ready_state(arguments: argparse.Namespace) -> None:
    if getattr(arguments, "output_directory", None) is None:
        return
    state = load_session_state(arguments)
    if READY_CACHE_KEY in state:
        del state[READY_CACHE_KEY]
        save_session_state_best_effort(arguments, state)


def read_ready_state(
    arguments: argparse.Namespace, *, fresh: bool = False
) -> dict[str, object]:
    if not fresh:
        cached = cached_ready_state(arguments)
        if cached is not None:
            return cached
    with tempfile.TemporaryDirectory(prefix="enchron-interactive-ready-") as directory:
        ready_path = Path(directory) / "ready.json"
        if not copy_from_device(
            device=arguments.device,
            runner_bundle_id=arguments.runner_bundle_id,
            remote_path=f"{CHANNEL_ROOT}/ready.json",
            local_path=ready_path,
            quiet=True,
        ):
            forget_ready_state(arguments)
            raise RuntimeError(
                "The interactive XCUI runner is not ready. Start its dedicated UI test first."
            )
        ready = json.loads(ready_path.read_text(encoding="utf-8"))
        remember_ready_state(arguments, ready)
        return ready


RESPONSE_ARRIVED = "arrived"
RESPONSE_TIMED_OUT = "timedOut"
RESPONSE_RUNNER_GONE = "runnerGone"
LIVENESS_INTERVAL_SECONDS = 5.0
RESPONSE_POLL_INTERVAL_SECONDS = 0.1
DEVICE_TRANSFER_ATTEMPTS = 3
DEVICE_TRANSFER_RETRY_SECONDS = 1.5
device_transfer_pause = time.sleep


def runner_alive() -> bool:
    return bool(scoped_processes())


def wait_for_response(
    *,
    arguments: argparse.Namespace,
    command_id: str,
    response_path: Path,
    deadline_seconds: float | None = None,
    liveness: Callable[[], bool] | None = None,
) -> str:
    remote_path = f"{CHANNEL_ROOT}/responses/{command_id}.json"
    started_at = time.monotonic()
    last_liveness_check: float | None = None
    while not copy_from_device(
        device=arguments.device,
        runner_bundle_id=arguments.runner_bundle_id,
        remote_path=remote_path,
        local_path=response_path,
        quiet=True,
    ):
        now = time.monotonic()
        if liveness is not None and (
            last_liveness_check is None
            or now - last_liveness_check >= LIVENESS_INTERVAL_SECONDS
        ):
            last_liveness_check = now
            if not liveness():
                return RESPONSE_RUNNER_GONE
        if deadline_seconds is not None and now - started_at >= deadline_seconds:
            return RESPONSE_TIMED_OUT
        time.sleep(RESPONSE_POLL_INTERVAL_SECONDS)
    return RESPONSE_ARRIVED


def process_table() -> list[tuple[int, int, str]]:
    listing = subprocess.run(
        ["ps", "-Ao", "pid=,ppid=,command="],
        check=False,
        text=True,
        capture_output=True,
    ).stdout
    rows: list[tuple[int, int, str]] = []
    for line in listing.splitlines():
        fields = line.strip().split(maxsplit=2)
        if len(fields) < 3:
            continue
        try:
            rows.append((int(fields[0]), int(fields[1]), fields[2]))
        except ValueError:
            continue
    return rows


def own_lineage(rows: list[tuple[int, int, str]]) -> set[int]:
    """This controller and the shell that launched it match the scope markers
    themselves. Terminating them would kill the halt in progress."""
    parents = {pid: ppid for pid, ppid, _ in rows}
    lineage = set()
    pid = os.getpid()
    while pid > 1 and pid not in lineage:
        lineage.add(pid)
        pid = parents.get(pid, 0)
    return lineage


def working_directory(pid: int) -> str | None:
    listing = subprocess.run(
        ["lsof", "-a", "-d", "cwd", "-p", str(pid), "-Fn"],
        check=False,
        text=True,
        capture_output=True,
    ).stdout
    for line in listing.splitlines():
        if line.startswith("n"):
            return line[1:]
    return None


def scoped_processes() -> list[tuple[int, str]]:
    """A runner works in the worktree that launched it, so its working
    directory is the scope. The frozen xctestrun path is not: it may live under
    another worktree's artifact root, or name no repository at all, so it only
    counts when the working directory cannot be read."""
    rows = process_table()
    lineage = own_lineage(rows)
    root = str(REPOSITORY_ROOT)
    scoped: list[tuple[int, str]] = []
    for pid, _, command in rows:
        if pid in lineage:
            continue
        is_controller = CONTROLLER_PROCESS_MARKER in command
        is_interactive_runner = all(
            marker in command for marker in RUNNER_PROCESS_MARKERS
        )
        if not is_controller and not is_interactive_runner:
            continue
        directory = working_directory(pid)
        if directory is None:
            if f"{root}/" in command:
                scoped.append((pid, command))
        elif directory == root:
            scoped.append((pid, command))
    return scoped


def halt_session(arguments: argparse.Namespace) -> dict[str, object]:
    """Stops this repository's automation scope and nothing else. Prefers the
    runner's own stop command so XCTest saves its result bundle, then resolves
    the remaining Mac-side processes by repository-scoped command line."""
    graceful = "unavailable"
    forget_ready_state(arguments)
    try:
        ready = read_ready_state(arguments, fresh=True)
        command_id = str(uuid.uuid4())
        with tempfile.TemporaryDirectory(prefix="enchron-interactive-halt-") as directory:
            command_path = Path(directory) / "command.json"
            command_path.write_text(
                json.dumps(
                    {
                        "id": command_id,
                        "sessionID": ready["sessionID"],
                        "action": "stop",
                        "includeScreenshot": False,
                    }
                ),
                encoding="utf-8",
            )
            copy_to_device(
                device=arguments.device,
                runner_bundle_id=arguments.runner_bundle_id,
                local_path=command_path,
                remote_path=f"{CHANNEL_ROOT}/command.json",
            )
            wake_runner(arguments)
            graceful = (
                "acknowledged"
                if wait_for_response(
                    arguments=arguments,
                    command_id=command_id,
                    response_path=Path(directory) / "response.json",
                    deadline_seconds=GRACEFUL_STOP_DEADLINE_SECONDS,
                ) == RESPONSE_ARRIVED
                else "timedOut"
            )
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError):
        graceful = "unavailable"

    deadline = time.monotonic() + RESULT_BUNDLE_SETTLE_SECONDS
    while time.monotonic() < deadline and scoped_processes():
        time.sleep(0.5)
    xcodebuild_exited_on_its_own = not scoped_processes()

    targets = scoped_processes()
    for pid, _ in targets:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
    deadline = time.monotonic() + TERMINATION_DEADLINE_SECONDS
    while time.monotonic() < deadline and scoped_processes():
        time.sleep(0.2)
    for pid, _ in scoped_processes():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            continue
    remaining = scoped_processes()
    return {
        "success": not remaining,
        "gracefulStop": graceful,
        "resultBundleWritten": xcodebuild_exited_on_its_own,
        "scope": str(REPOSITORY_ROOT),
        "terminated": [{"pid": pid, "command": command} for pid, command in targets],
        "remaining": [{"pid": pid, "command": command} for pid, command in remaining],
    }


IMMERSIVE_ATTACHMENT_MARKER = "PlayerUI-immersive"
TAP_ACTIONS = (
    "tap",
    "tapSequence",
    "tapFirstMatch",
    "doubleTap",
    "press",
    "adjust",
)


def session_state_path(arguments: argparse.Namespace) -> Path:
    return Path(arguments.output_directory).expanduser() / "session-state.json"


def load_session_state(arguments: argparse.Namespace) -> dict[str, object]:
    try:
        state = json.loads(session_state_path(arguments).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return state if isinstance(state, dict) else {}


def save_session_state_best_effort(
    arguments: argparse.Namespace, state: dict[str, object]
) -> None:
    try:
        path = session_state_path(arguments)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    except OSError:
        pass


def annotate_response(
    arguments: argparse.Namespace, session_id: str, response: dict[str, object]
) -> None:
    """Attach observed session facts to a runner response. Every sentence
    names how it was observed; nothing here interprets or predicts."""
    targets = list(getattr(arguments, "identifiers", None) or [])
    identifier = getattr(arguments, "identifier", None)
    if identifier:
        targets.append(identifier)
    if arguments.action in TAP_ACTIONS and any(
        name.startswith(IMMERSIVE_ATTACHMENT_MARKER) for name in targets
    ):
        response["deliveryFacts"] = (
            "Synthetic taps on immersive-space attachments report success "
            "without carrying gaze-plus-pinch semantics; whether the app "
            "received the gesture is recorded only in the probe file "
            "(device-measured 2026-08-09)."
        )

    hierarchy = response.get("hierarchy")
    if not isinstance(hierarchy, str):
        return
    response["alerts"] = alerts_from_hierarchy(hierarchy)
    in_immersive = IMMERSIVE_ATTACHMENT_MARKER in hierarchy
    state = load_session_state(arguments)
    if state.get("sessionID") != session_id:
        state = {"sessionID": session_id, "immersiveEntries": 0, "inImmersive": False}
    if in_immersive and not state.get("inImmersive"):
        state["immersiveEntries"] = int(state.get("immersiveEntries") or 0) + 1
        response["immersiveFacts"] = (
            "This response's hierarchy contains an immersive attachment "
            f"({IMMERSIVE_ATTACHMENT_MARKER}*): immersive entry number "
            f"{state['immersiveEntries']} of this session (controller count "
            "of hierarchy observations). Probe measurements (2026-08-10) "
            "show every immersive entry disconnects the main window's "
            "UIScene; XCTest input binds to that scene."
        )
    state["inImmersive"] = in_immersive
    save_session_state_best_effort(arguments, state)


HIERARCHY_ELEMENT_PATTERN = re.compile(r"^(?P<indent>\s*)(?:→)?(?P<role>[A-Za-z]+), 0x[0-9a-f]+")
HIERARCHY_ATTRIBUTE_PATTERN = re.compile(r", (?P<name>identifier|label|value): '(?P<value>.*?)'(?=, [a-zA-Z]+: |$)")


def hierarchy_attributes(line: str) -> dict[str, str]:
    return {match.group("name"): match.group("value") for match in HIERARCHY_ATTRIBUTE_PATTERN.finditer(line)}


def alerts_from_hierarchy(hierarchy: str) -> list[dict[str, object]]:
    alerts: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    current_indent = -1
    for line in hierarchy.splitlines():
        match = HIERARCHY_ELEMENT_PATTERN.match(line)
        if match is None:
            continue
        indent = len(match.group("indent"))
        role = match.group("role")
        attributes = hierarchy_attributes(line)
        if current is not None and indent <= current_indent:
            current = None
        if role == "Alert":
            current = {"title": attributes.get("label", ""), "lines": [], "buttons": []}
            current_indent = indent
            alerts.append(current)
            continue
        if current is None:
            continue
        if role == "StaticText" and attributes.get("label") != current["title"]:
            cast_lines = current["lines"]
            assert isinstance(cast_lines, list)
            cast_lines.append({"identifier": attributes.get("identifier", ""), "label": attributes.get("label", ""), "value": attributes.get("value")})
        elif role == "Button":
            cast_buttons = current["buttons"]
            assert isinstance(cast_buttons, list)
            cast_buttons.append(attributes.get("identifier") or attributes.get("label", ""))
    return alerts


def timeout_observations(arguments: argparse.Namespace) -> list[dict[str, object]]:
    """The scene collected when a command gets no answer: direct observations
    only, each with its source, no inferred cause."""
    observations: list[dict[str, object]] = []

    scoped = scoped_processes()
    observations.append(
        {
            "observation": [command[:160] for _, command in scoped]
            or "no repository-scoped automation process is running on this Mac",
            "source": "ps table filtered to this repository's scope markers",
        }
    )

    processes = (
        subprocess.run(
            ["xcrun", "simctl", "spawn", arguments.device, "launchctl", "list"],
            check=False, text=True, capture_output=True,
        )
        if is_simulator(arguments.device)
        else run_devicectl(
            ["device", "info", "processes", "--device", arguments.device]
        )
    )
    if processes.returncode == 0:
        markers = (
            (DEVICE_PROCESS_MARKER, APP_BUNDLE_ID, arguments.runner_bundle_id)
            if is_simulator(arguments.device)
            else (DEVICE_PROCESS_MARKER,)
        )
        matches = [
            line.strip()
            for line in processes.stdout.splitlines()
            if any(marker in line for marker in markers)
        ]
        observations.append(
            {
                "observation": matches
                or (
                    "the device process table lists no path containing "
                    f"'{DEVICE_PROCESS_MARKER}'"
                ),
                "source": "xcrun devicectl device info processes",
            }
        )
    else:
        failure = (processes.stderr or processes.stdout or "").strip().splitlines()
        observations.append(
            {
                "observation": "device process query failed: "
                + (failure[0] if failure else "no output"),
                "source": "xcrun devicectl device info processes",
            }
        )

    log_path = Path(arguments.output_directory).expanduser() / "runner.log"
    try:
        tail = log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-5:]
        observations.append({"observation": tail, "source": str(log_path)})
    except OSError:
        observations.append(
            {
                "observation": "no readable runner.log in the output directory",
                "source": str(log_path),
            }
        )

    state = load_session_state(arguments)
    observations.append(
        {
            "observation": (
                f"controller state records {int(state.get('immersiveEntries') or 0)} "
                f"immersive entr(y/ies) for session {state.get('sessionID')}"
            ),
            "source": f"{session_state_path(arguments)} (hierarchy observations)",
        }
    )
    return observations


def resolve_command_text(arguments: argparse.Namespace) -> str | None:
    text_file = getattr(arguments, "text_file", None)
    if text_file is None:
        return getattr(arguments, "text", None)

    path = Path(text_file).expanduser().resolve()
    value = path.read_text(encoding="utf-8")
    key = getattr(arguments, "text_json_key", None)
    if key is None:
        return value

    document = json.loads(value)
    if not isinstance(document, dict) or not isinstance(document.get(key), str):
        raise ValueError(f"{path} has no string field {key!r}.")
    return document[key]


def redact_command_text(value: object, text: str) -> object:
    if not text:
        return value
    if isinstance(value, str):
        return value.replace(text, "<redacted-input>")
    if isinstance(value, list):
        return [redact_command_text(item, text) for item in value]
    if isinstance(value, dict):
        return {
            key: redact_command_text(item, text)
            for key, item in value.items()
        }
    return value


def send_command(arguments: argparse.Namespace) -> dict[str, object]:
    ready = read_ready_state(arguments)
    command_id = str(uuid.uuid4())
    command = {
        "id": command_id,
        "sessionID": ready["sessionID"],
        "action": arguments.action,
        "includeScreenshot": not arguments.no_screenshot,
    }
    for key in (
        "identifier",
        "identifiers",
        "identifierPrefix",
        "assertAbsent",
        "alsoInspect",
        "label",
        "trailingLabel",
        "index",
        "duration",
        "normalizedX",
        "normalizedY",
    ):
        value = getattr(arguments, key)
        if value is not None:
            command[key] = value
    text = resolve_command_text(arguments)
    if text is not None:
        command["text"] = text

    with tempfile.TemporaryDirectory(prefix="enchron-interactive-command-") as directory:
        directory_path = Path(directory)
        command_path = directory_path / "command.json"
        response_path = directory_path / "response.json"
        command_path.write_text(
            json.dumps(command, ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        copy_to_device(
            device=arguments.device,
            runner_bundle_id=arguments.runner_bundle_id,
            local_path=command_path,
            remote_path=f"{CHANNEL_ROOT}/command.json",
        )
        wake_runner(arguments)
        arrived = wait_for_response(
            arguments=arguments,
            command_id=command_id,
            response_path=response_path,
            deadline_seconds=arguments.timeout_seconds,
            liveness=runner_alive,
        )
        if arrived == RESPONSE_RUNNER_GONE:
            forget_ready_state(arguments)
            return {
                "success": False,
                "stage": "runnerGone",
                "message": (
                    f"The resident runner left this repository's automation "
                    f"scope while {arguments.action} was pending, so no answer "
                    "can arrive. The observations below were collected at "
                    "that moment; they state what was seen, not why."
                ),
                "observations": timeout_observations(arguments),
            }
        if arrived != RESPONSE_ARRIVED:
            forget_ready_state(arguments)
            return {
                "success": False,
                "stage": "responseTimeout",
                "message": (
                    f"The runner did not answer {arguments.action} within "
                    f"{arguments.timeout_seconds:g} seconds. The observations "
                    "below were collected at the timeout; they state what was "
                    "seen, not why."
                ),
                "observations": timeout_observations(arguments),
            }
        response = json.loads(response_path.read_text(encoding="utf-8"))
        if getattr(arguments, "redact_response_text", False):
            response = redact_command_text(response, text or "")
        annotate_response(arguments, str(ready["sessionID"]), response)
        screenshot_relative_path = response.get("screenshotRelativePath")
        if screenshot_relative_path:
            output_directory = Path(arguments.output_directory).expanduser().resolve()
            output_directory.mkdir(parents=True, exist_ok=True)
            screenshot_path = output_directory / f"{command_id}.png"
            copied = copy_from_device(
                device=arguments.device,
                runner_bundle_id=arguments.runner_bundle_id,
                remote_path=f"{CHANNEL_ROOT}/{screenshot_relative_path}",
                local_path=screenshot_path,
                quiet=False,
            )
            if not copied:
                raise RuntimeError("The UI response arrived, but its screenshot could not be copied.")
            response["localScreenshotPath"] = str(screenshot_path)
        return response


def app_command(arguments: argparse.Namespace) -> dict[str, object]:
    if not arguments.verb:
        raise ValueError("app-command requires --verb.")
    if arguments.timeout_seconds <= 0:
        raise ValueError("--timeout-seconds must be greater than zero.")

    command_arguments: dict[str, str] = {}
    for item in arguments.app_arguments:
        key, separator, value = item.partition("=")
        if not separator or not key:
            raise ValueError(f"Invalid --arg {item!r}; expected key=value.")
        command_arguments[key] = value

    command_id = str(uuid.uuid4())
    command = {
        "id": command_id,
        "verb": arguments.verb,
        "args": command_arguments,
    }
    with tempfile.TemporaryDirectory(prefix="enchron-app-command-") as directory:
        directory_path = Path(directory)
        command_path = directory_path / "command.json"
        response_path = directory_path / "response.json"
        command_path.write_text(
            json.dumps(command, ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        copy_to_device(
            device=arguments.device,
            runner_bundle_id=APP_BUNDLE_ID,
            local_path=command_path,
            remote_path=(
                f"{DEFERRED_APP_COMMAND_ROOT}/{command_id}.json"
                if arguments.defer_response
                else APP_COMMAND_PATH
            ),
        )
        if arguments.defer_response:
            time.sleep(DEFERRED_COMMAND_SLOT_HOLD_SECONDS)
            return {
                "success": True,
                "deferred": True,
                "id": command_id,
                "verb": arguments.verb,
            }

        deadline = time.monotonic() + arguments.timeout_seconds
        while not copy_from_device(
            device=arguments.device,
            runner_bundle_id=APP_BUNDLE_ID,
            remote_path=f"{APP_RESPONSE_ROOT}/{command_id}.json",
            local_path=response_path,
            quiet=True,
        ):
            if time.monotonic() >= deadline:
                return {
                    "success": False,
                    "message": (
                        f"App command {arguments.verb} did not respond within "
                        f"{arguments.timeout_seconds:g} seconds."
                    ),
                    "id": command_id,
                }
            time.sleep(1.0)

        response = json.loads(response_path.read_text(encoding="utf-8"))
        if not isinstance(response, dict):
            raise ValueError("The app command response is not a JSON object.")
        if response.get("id") != command_id:
            raise ValueError("The app command response ID does not match its request.")
        if not isinstance(response.get("ok"), bool):
            raise ValueError("The app command response has no Boolean ok field.")
        response["success"] = response["ok"]
        response["message"] = response.get("detail") or (
            f"App command {arguments.verb} completed."
            if response["ok"]
            else f"App command {arguments.verb} failed."
        )
        return response


def current_session_id(arguments: argparse.Namespace) -> str | None:
    try:
        return str(read_ready_state(arguments, fresh=True)["sessionID"])
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, KeyError):
        return None


FrozenTestLaunchLoader = Callable[[Path, BoundLane, str], object]


def _execution_input_path(arguments: argparse.Namespace) -> Path:
    value = getattr(arguments, "execution_input", None)
    if not isinstance(value, (str, os.PathLike)) or not str(value).strip():
        raise RuntimeError(
            "Runner launch requires --execution-input or ENCHRON_EXECUTION_INPUT."
        )
    path = Path(value)
    return path if path.is_absolute() else REPOSITORY_ROOT / path


def _developer_environment(developer_dir: str | None) -> dict[str, str]:
    environment = dict(os.environ)
    if not developer_dir:
        return environment
    ambient = os.environ.get("DEVELOPER_DIR")
    if ambient is None:
        selected = subprocess.run(
            ["xcode-select", "-p"],
            check=False,
            text=True,
            capture_output=True,
        )
        if selected.returncode != 0 or not selected.stdout.strip():
            raise RuntimeError(
                selected.stderr.strip()
                or "Cannot determine the active Xcode developer directory."
            )
        ambient = selected.stdout.strip()
    if Path(developer_dir).resolve() != Path(ambient).resolve():
        raise RuntimeError(
            "--developer-dir must match the developer directory used to validate "
            "the frozen execution input."
        )
    environment["DEVELOPER_DIR"] = developer_dir
    return environment


def _load_frozen_test_launch(
    path: Path,
    lane: BoundLane,
    target_id: str,
    loader: FrozenTestLaunchLoader | None,
) -> object:
    selected_loader = loader or load_frozen_test_launch
    if not callable(selected_loader):
        raise RuntimeError("Frozen test launch loading is unavailable.")
    return selected_loader(path, lane, target_id)


def _validate_frozen_test_launch(
    launch: object,
    *,
    lane: BoundLane,
    target_id: str,
    destination_specifier: str,
) -> None:
    if getattr(launch, "lane", None) != lane:
        raise RuntimeError("The frozen test launch resolved to a different lane.")
    if getattr(launch, "target_id", None) != target_id:
        raise RuntimeError("The frozen test launch resolved to a different target.")
    if getattr(launch, "destination_specifier", None) != destination_specifier:
        raise RuntimeError("The frozen test launch destination is not the validated target.")
    if not isinstance(getattr(launch, "xctestrun_path", None), Path):
        raise RuntimeError("The frozen test launch has no typed .xctestrun path.")
    artifact = getattr(launch, "lane_artifact", None)
    if artifact is None or getattr(artifact, "lane", None) != lane:
        raise RuntimeError("The frozen test launch artifact resolved to a different lane.")
    for field_name in (
        "xctestrun_digest",
        "test_products_digest",
        "application_code_digest",
    ):
        if not str(getattr(artifact, field_name, "")).strip():
            raise RuntimeError(
                f"The frozen test launch artifact has no {field_name}."
            )


def _launch_provenance(
    launch: object,
    *,
    execution_input_path: Path,
    result_bundle: Path,
    process_id: int,
) -> dict[str, object]:
    artifact = getattr(launch, "lane_artifact")
    lane = getattr(launch, "lane")
    return {
        "executionInputPath": str(execution_input_path),
        "lane": lane.value,
        "targetId": getattr(launch, "target_id"),
        "xctestrunPath": str(getattr(launch, "xctestrun_path")),
        "destinationSpecifier": getattr(launch, "destination_specifier"),
        "xctestrunDigest": str(getattr(artifact, "xctestrun_digest")),
        "testProductsDigest": str(getattr(artifact, "test_products_digest")),
        "applicationCodeDigest": str(
            getattr(artifact, "application_code_digest")
        ),
        "resultBundlePath": str(result_bundle),
        "processId": process_id,
    }


def _resident_runner_path(arguments: argparse.Namespace) -> Path:
    execution_input = _execution_input_path(arguments)
    artifact_root = execution_input.parent
    lane = BoundLane.SIMULATOR if is_simulator(arguments.device) else BoundLane.DEVICE
    return artifact_root / "lanes" / lane.value / "resident-runner.json"


def _current_lane_digests(arguments: argparse.Namespace) -> tuple[str, str, str]:
    execution_input = _execution_input_path(arguments)
    lane = BoundLane.SIMULATOR if is_simulator(arguments.device) else BoundLane.DEVICE
    execution = load_execution_input(execution_input)
    for artifact in execution.build_identity.lane_artifacts:
        if artifact.lane == lane:
            return (
                str(artifact.xctestrun_digest),
                str(artifact.test_products_digest),
                str(artifact.application_code_digest),
            )
    raise RuntimeError("current lane artifact not found")


def _read_resident_runner(path: Path) -> dict[str, object] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    for key in ("sessionID", "xctestrunDigest", "testProductsDigest", "applicationCodeDigest"):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip():
            return None
    return data


def _write_resident_runner(path: Path, session_id: str, provenance: dict[str, object]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "sessionID": session_id,
            "xctestrunDigest": str(provenance.get("xctestrunDigest", "")),
            "testProductsDigest": str(provenance.get("testProductsDigest", "")),
            "applicationCodeDigest": str(provenance.get("applicationCodeDigest", "")),
        }
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass


def _is_no_runner_error(error: Exception) -> bool:
    return isinstance(error, RuntimeError) and "The interactive XCUI runner is not ready" in str(error)


def launch_runner(
    arguments: argparse.Namespace,
    log_path: Path,
    result_bundle: Path,
    *,
    simulator_udid_source: SimulatorUDIDSource | None = None,
    physical_visionos_device_registry_source: (
        PhysicalVisionOSDeviceRegistrySource | None
    ) = None,
    frozen_test_launch_loader: FrozenTestLaunchLoader | None = None,
) -> dict[str, object]:
    global _SIMULATOR_UDIDS
    simulator_udids = (simulator_udid_source or registered_simulator_udids)()
    physical_visionos_devices = (
        physical_visionos_device_registry_source
        or registered_physical_visionos_devices
    )()
    if not isinstance(physical_visionos_devices, PhysicalVisionOSDeviceRegistry):
        raise RuntimeError("The physical device registry source returned the wrong value.")
    _SIMULATOR_UDIDS = simulator_udids
    launch_destination = arguments.destination_id or arguments.device
    if arguments.destination_id is not None and (
        not isinstance(arguments.destination_id, str)
        or not arguments.destination_id.strip()
    ):
        raise RuntimeError("The runner launch destination must be non-empty text.")
    simulator = is_simulator(
        arguments.device, simulator_udids=simulator_udids
    )
    controller_device: PhysicalVisionOSDevice | None = None
    if not simulator:
        controller_device = physical_visionos_devices.get(arguments.device)
    if not simulator and controller_device is None:
        raise RuntimeError(
            "The controller target is not a paired physical visionOS device."
        )
    launch_is_simulator = is_simulator(
        launch_destination, simulator_udids=simulator_udids
    )
    destination_device: PhysicalVisionOSDevice | None = None
    if not launch_is_simulator:
        destination_device = physical_visionos_devices.get(launch_destination)
    if not launch_is_simulator and destination_device is None:
        raise RuntimeError(
            "The runner destination is not a paired physical visionOS device."
        )
    if launch_is_simulator is not simulator:
        raise RuntimeError(
            "The controller transport target and runner launch destination "
            "resolve to different lanes."
        )
    if simulator and launch_destination != arguments.device:
        raise RuntimeError(
            "The controller transport target and runner launch destination "
            "resolve to different simulator devices."
        )
    if (
        controller_device is not None
        and destination_device is not None
        and controller_device != destination_device
    ):
        raise RuntimeError(
            "The controller transport target and runner launch destination "
            "resolve to different physical visionOS devices."
        )
    physical_destination = (
        destination_device.hardware_udid
        if destination_device is not None
        else None
    )
    lane = BoundLane.SIMULATOR if simulator else BoundLane.DEVICE
    target_id = arguments.device if simulator else physical_destination
    assert target_id is not None
    destination_specifier = (
        f"platform=visionOS Simulator,id={target_id}"
        if simulator
        else f"platform=visionOS,id={target_id}"
    )
    execution_input_path = _execution_input_path(arguments)

    environment = _developer_environment(arguments.developer_dir)
    launch = _load_frozen_test_launch(
        execution_input_path, lane, target_id, frozen_test_launch_loader
    )
    _validate_frozen_test_launch(
        launch,
        lane=lane,
        target_id=target_id,
        destination_specifier=destination_specifier,
    )
    with log_path.open("w", encoding="utf-8") as log:
        revalidated = _load_frozen_test_launch(
            execution_input_path, lane, target_id, frozen_test_launch_loader
        )
        _validate_frozen_test_launch(
            revalidated,
            lane=lane,
            target_id=target_id,
            destination_specifier=destination_specifier,
        )
        if revalidated != launch:
            raise RuntimeError(
                "The frozen test launch changed during runner preparation."
            )
        command = [
            "xcodebuild",
            "test-without-building",
            "-xctestrun",
            str(getattr(revalidated, "xctestrun_path")),
            "-destination",
            str(getattr(revalidated, "destination_specifier")),
            "-parallel-testing-enabled",
            "NO",
            "-test-timeouts-enabled",
            "NO",
            "-resultBundlePath",
            str(result_bundle),
        ]
        process = subprocess.Popen(
            command,
            cwd=str(REPOSITORY_ROOT),
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    return _launch_provenance(
        revalidated,
        execution_input_path=execution_input_path,
        result_bundle=result_bundle,
        process_id=process.pid,
    )


def log_tail(log_path: Path, lines: int = 5) -> list[str]:
    try:
        return log_path.read_text(encoding="utf-8", errors="replace").splitlines()[
            -lines:
        ]
    except OSError:
        return []


def ensure_session(arguments: argparse.Namespace) -> dict[str, object]:
    """Brings up one live session and returns only when it can accept commands
    or the launch window expires.

    Session bring-up is the step whose apparent length invites backgrounding and
    a handed-back turn. Collapsing halt, launch and readiness into one call keeps
    an investigation inside a single continuous run: the caller asked for a ready
    session, and everything here executes that one intent."""
    started_at = time.monotonic()
    adoption_refused: str | None = None
    ready: dict[str, object] | None = None
    try:
        ready = read_ready_state(arguments, fresh=True)
    except RuntimeError as error:
        if _is_no_runner_error(error):
            adoption_refused = "no-ready"
            ready = None
        else:
            raise
    if ready is not None:
        session_id = ready.get("sessionID")
        if not isinstance(session_id, str) or not session_id:
            adoption_refused = "missing-sessionID"
        else:
            resident_path: Path | None = None
            try:
                resident_path = _resident_runner_path(arguments)
            except RuntimeError as error:
                adoption_refused = str(error)
            if adoption_refused is None and resident_path is not None:
                resident = _read_resident_runner(resident_path)
                if resident is None:
                    try:
                        exists = resident_path.exists()
                    except OSError:
                        exists = False
                    if not exists:
                        adoption_refused = "resident-file-missing"
                    else:
                        adoption_refused = "resident-file-unreadable"
                elif resident.get("sessionID") != session_id:
                    adoption_refused = "resident-session-mismatch"
                else:
                    try:
                        expected_x, expected_t, expected_a = _current_lane_digests(arguments)
                    except Exception:
                        adoption_refused = "current-digests-unavailable"
                        expected_x = expected_t = expected_a = None
                    if adoption_refused is None:
                        if resident.get("xctestrunDigest") != expected_x:
                            adoption_refused = "xctestrunDigest-mismatch"
                        elif resident.get("testProductsDigest") != expected_t:
                            adoption_refused = "testProductsDigest-mismatch"
                        elif resident.get("applicationCodeDigest") != expected_a:
                            adoption_refused = "applicationCodeDigest-mismatch"
                        else:
                            probe = argparse.Namespace(**vars(arguments))
                            probe.action = "snapshot"
                            probe.no_screenshot = True
                            response: dict[str, object] | None = None
                            try:
                                response = send_command(probe)
                            except RuntimeError as error:
                                if _is_no_runner_error(error):
                                    adoption_refused = "probe-error"
                                    response = None
                                else:
                                    raise
                            if adoption_refused is None:
                                if not isinstance(response, dict) or response.get("success") is not True:
                                    adoption_refused = "probe-not-success"
                                else:
                                    fresh: dict[str, object] | None = None
                                    try:
                                        fresh = read_ready_state(arguments, fresh=True)
                                    except RuntimeError as error:
                                        if _is_no_runner_error(error):
                                            adoption_refused = "no-ready-after-probe"
                                            fresh = None
                                        else:
                                            raise
                                    if adoption_refused is None:
                                        if not isinstance(fresh, dict) or fresh.get("sessionID") != session_id:
                                            adoption_refused = "sessionID-changed-after-probe"
                                        else:
                                            return {
                                                "success": True,
                                                "stage": "adopted",
                                                "sessionID": session_id,
                                                "elapsedSeconds": round(time.monotonic() - started_at, 1),
                                                "adoption": {"attempted": True, "refused": None},
                                            }
    if adoption_refused is None:
        adoption_refused = "no-ready" if ready is None else "unknown"
    halt = halt_session(arguments)
    if halt["remaining"]:
        return {
            "success": False,
            "stage": "halt",
            "message": "A previous automation process survived halt.",
            "halt": halt,
            "adoption": {"attempted": True, "refused": adoption_refused},
        }
    stale_session_id = current_session_id(arguments)

    output_directory = Path(arguments.output_directory)
    output_directory.mkdir(parents=True, exist_ok=True)
    log_path = output_directory / "runner.log"

    result_bundle = output_directory / f"Interactive-{int(time.time())}.xcresult"
    launch_provenance = launch_runner(arguments, log_path, result_bundle)

    deadline = time.monotonic() + arguments.ready_timeout
    while time.monotonic() < deadline:
        session_id = current_session_id(arguments)
        if session_id is not None and session_id != stale_session_id:
            probe = argparse.Namespace(**vars(arguments))
            probe.action = "snapshot"
            probe.no_screenshot = True
            try:
                response = send_command(probe)
            except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
                return {
                    "success": False,
                    "stage": "firstCommand",
                    "message": str(error),
                    "sessionID": session_id,
                    "runnerLog": str(log_path),
                    "adoption": {"attempted": True, "refused": adoption_refused},
                }
            _write_resident_runner(_resident_runner_path(arguments), session_id, launch_provenance)
            return {
                "success": bool(response.get("success")),
                "stage": "ready",
                "sessionID": session_id,
                "appState": response.get("appState"),
                "launchProvenance": launch_provenance,
                "resultBundlePath": str(result_bundle),
                "runnerLog": str(log_path),
                "haltedProcessCount": len(halt["terminated"]),
                "elapsedSeconds": round(time.monotonic() - started_at, 1),
                "adoption": {"attempted": True, "refused": adoption_refused},
            }
        time.sleep(3)

    tail = log_tail(log_path)
    observations: list[dict[str, object]] = [
        {"observation": tail, "source": f"{log_path} (last lines)"},
    ]
    if any("Wait for" in line and "to idle" in line for line in tail):
        observations.append(
            {
                "observation": (
                    "'Wait for ... to idle' is XCTest's normal "
                    "synchronization line; it also appears in recorded "
                    "successful runs"
                ),
                "source": "references/diagnostics.md, device evidence 2026-08-09",
            }
        )
    return {
        "success": False,
        "stage": "readyTimeout",
        "message": (
            f"No new session was published within "
            f"{arguments.ready_timeout:g} seconds. The observations below state "
            "what was seen, not why."
        ),
        "observations": observations,
        "launchProvenance": launch_provenance,
        "runnerLog": str(log_path),
        "elapsedSeconds": round(time.monotonic() - started_at, 1),
        "adoption": {"attempted": True, "refused": adoption_refused},
    }


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Control one step of a live Vision Pro XCUITest session and return "
            "the resulting Accessibility hierarchy and screenshot."
        )
    )
    parser.add_argument("--device", required=True)
    parser.add_argument("--runner-bundle-id", default=RUNNER_BUNDLE_ID)
    parser.add_argument(
        "--output-directory",
        default="/tmp/enchron-interactive-ui",
    )
    parser.add_argument(
        "action",
        choices=(
            "snapshot",
            "tap",
            "tapSequence",
            "tapFirstMatch",
            "doubleTap",
            "press",
            "adjust",
            "typeText",
            "replaceText",
            "swipeUp",
            "swipeDown",
            "swipeLeft",
            "swipeRight",
            "coordinateTap",
            "activate",
            "relaunch",
            "terminate",
            "stop",
            "halt",
            "ensure-session",
            "app-command",
        ),
    )
    parser.add_argument(
        "--execution-input",
        dest="execution_input",
        type=Path,
        default=os.environ.get("ENCHRON_EXECUTION_INPUT"),
    )
    parser.add_argument("--destination-id", dest="destination_id")
    parser.add_argument("--developer-dir", dest="developer_dir")
    parser.add_argument("--ready-timeout", dest="ready_timeout", type=float, default=300.0)
    parser.add_argument("--identifier")
    parser.add_argument("--identifiers", nargs="+")
    parser.add_argument("--identifier-prefix", dest="identifierPrefix")
    parser.add_argument("--assert-absent", dest="assertAbsent", nargs="+")
    parser.add_argument("--also-inspect", dest="alsoInspect", nargs="+")
    parser.add_argument("--label")
    parser.add_argument("--trailing-label", dest="trailingLabel")
    parser.add_argument("--index", type=int)
    text_source = parser.add_mutually_exclusive_group()
    text_source.add_argument("--text")
    text_source.add_argument("--text-file", dest="text_file", type=Path)
    parser.add_argument("--text-json-key", dest="text_json_key")
    parser.add_argument(
        "--redact-response-text",
        dest="redact_response_text",
        action="store_true",
    )
    parser.add_argument("--duration", type=float)
    parser.add_argument("--normalized-x", dest="normalizedX", type=float)
    parser.add_argument("--normalized-y", dest="normalizedY", type=float)
    parser.add_argument("--no-screenshot", action="store_true")
    parser.add_argument("--verb")
    parser.add_argument("--arg", dest="app_arguments", action="append", default=[])
    parser.add_argument("--defer-response", action="store_true")
    parser.add_argument(
        "--timeout-seconds",
        dest="timeout_seconds",
        type=float,
        default=30.0,
    )
    arguments = parser.parse_args(argv)
    if arguments.text_json_key is not None and arguments.text_file is None:
        parser.error("--text-json-key requires --text-file")
    return arguments


AUTO_HIDING_PREFIXES = (
    "PlayerUI-TopAction-",
    "PlayerUI-InfoBar-",
    "PlayerUI-VideoFormat",
    "PlayerUI-DockMenu-",
    "PlayerPanel-",
)

_AUTO_HIDE_DIAGNOSIS = "Player chrome auto-hides about eight seconds after it is summoned (measured design behavior, 2026-08-10), and each controller command pays a device round trip, so a tap sent as its own command can arrive after the hide; a tapSequence delivers several taps inside one round trip (controller design). A load-failure view replaces the chrome entirely when a load fails (PlayerUI-loadFailure-primary/-secondary in the hierarchy)."
_NOT_RUNNING_DIAGNOSIS = "The runner reports appState notRunning: no running app was attached to this session when the event was sent (runner-reported state)."


def _attach_failure(arguments, response: dict) -> dict:
    if response.get("success") is True:
        return response
    if "failure" in response:
        return response
    stage = response.get("stage")
    app_state = response.get("appState")
    message = str(response.get("message", response.get("error", "")))
    lower = message.lower()
    raw_obs = response.pop("observations", None)
    observations = raw_obs if isinstance(raw_obs, list) else []
    response.pop("diagnosis", None)
    kind = ""
    diagnosis = ""
    if stage == "responseTimeout":
        kind = "response-timeout"
        diagnosis = message
    elif stage == "runnerGone":
        kind = "runner-gone"
        diagnosis = message
    elif stage == "readyTimeout":
        kind = "session-lost"
        diagnosis = message
    elif stage == "halt":
        kind = "session-lost"
        diagnosis = message
    elif stage == "firstCommand":
        kind = "app-not-running"
        diagnosis = message
    elif isinstance(arguments, argparse.Namespace) and getattr(arguments, "action", None) == "app-command" and "did not respond within" in lower:
        kind = "response-timeout"
        diagnosis = message
    elif "appState" in response and app_state in (None, "notRunning"):
        kind = "app-not-running"
        diagnosis = _NOT_RUNNING_DIAGNOSIS
    elif "crashed" in lower or "crash" in lower:
        kind = "app-crashed"
        diagnosis = message
    else:
        element_is_absent = "no matching element" in lower or "no current element matches" in lower
        hittable_missing = "is not currently hittable" in lower
        identifiers = list(getattr(arguments, "identifiers", None) or [])
        identifier = getattr(arguments, "identifier", None)
        if identifier:
            identifiers.append(identifier)
        has_auto = any(name.startswith(AUTO_HIDING_PREFIXES) for name in identifiers) if identifiers else False
        if element_is_absent and has_auto:
            kind = "assertion-mismatch"
            diagnosis = _AUTO_HIDE_DIAGNOSIS
        elif element_is_absent or hittable_missing:
            kind = "assertion-mismatch"
            diagnosis = message if message else "Element not found"
        else:
            kind = "assertion-mismatch"
            diagnosis = message if message else "Assertion mismatch"
    if not kind:
        kind = "assertion-mismatch"
        diagnosis = message
    cls = "product" if kind in ("app-crashed", "assertion-mismatch") else "instrument"
    response["failure"] = {"class": cls, "kind": kind, "evidence": {"diagnosis": diagnosis, "observations": observations}}
    return response


SWIPE_ACTIONS = ("swipeUp", "swipeDown", "swipeLeft", "swipeRight")


def main() -> int:
    arguments = parse_arguments()
    if arguments.action in SWIPE_ACTIONS and not (arguments.identifier or arguments.label):
        response = {"success": False, "error": f"{arguments.action} requires --identifier or --label. Swiping the application element kills the session on visionOS."}
        response = _attach_failure(arguments, response)
        response["devicectlCallCount"] = DEVICECTL_CALL_COUNT
        response["transportCallCount"] = DEVICECTL_CALL_COUNT
        print(json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True))
        return 2
    started_at = time.monotonic()
    try:
        if arguments.action == "halt":
            response = halt_session(arguments)
        elif arguments.action == "ensure-session":
            response = ensure_session(arguments)
        elif arguments.action == "app-command":
            response = app_command(arguments)
        else:
            response = send_command(arguments)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        response = {"success": False, "error": str(error)}
        response = _attach_failure(arguments, response)
        response["devicectlCallCount"] = DEVICECTL_CALL_COUNT
        response["transportCallCount"] = DEVICECTL_CALL_COUNT
        print(json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True))
        return 1
    if not response.get("success"):
        response = _attach_failure(arguments, response)
    censored = False
    failure_kind = ""
    try:
        failure_kind = response.get("failure", {}).get("kind", "")
    except (AttributeError, TypeError):
        failure_kind = ""
    if failure_kind == "response-timeout":
        censored = True
    elif response.get("stage") == "responseTimeout":
        censored = True
    elif arguments.action == "app-command" and "did not respond within" in str(response.get("message", "")).lower():
        censored = True
    elif arguments.action == "ensure-session" and response.get("stage") == "readyTimeout":
        censored = True
    if censored:
        if arguments.action == "ensure-session":
            try:
                seconds = float(getattr(arguments, "ready_timeout", 300.0))
            except (TypeError, ValueError):
                seconds = 300.0
        else:
            try:
                seconds = float(getattr(arguments, "timeout_seconds", 30.0))
            except (TypeError, ValueError):
                seconds = 30.0
    else:
        seconds = time.monotonic() - started_at
    record_timing(arguments.action, seconds, device=arguments.device, frozen=getattr(arguments, "execution_input", None) is not None, censored=censored)
    response["devicectlCallCount"] = DEVICECTL_CALL_COUNT
    response["transportCallCount"] = DEVICECTL_CALL_COUNT
    print(json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if response.get("success") else 2


if __name__ == "__main__":
    raise SystemExit(main())
