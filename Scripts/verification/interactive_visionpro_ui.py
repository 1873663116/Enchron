#!/usr/bin/env python3
"""Send one runtime-decided XCUIAutomation command to a live Vision Pro runner."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path


RUNNER_BUNDLE_ID = "com.xiongzhipeng.EnchronAppUITests.xctrunner"
APP_BUNDLE_ID = "com.xiongzhipeng.XrPlayer"
# The bundle id never appears in the device process table; processes are
# listed by executable path (…/Enchron.app/Enchron, …/EnchronAppUITests-
# Runner.app/…), so this marker matches both the app and the runner.
DEVICE_PROCESS_MARKER = "Enchron"
CHANNEL_ROOT = "Documents/EnchronInteractiveUI"
APP_COMMAND_PATH = "Documents/test-command.json"
DEFERRED_APP_COMMAND_ROOT = "Documents/test-commands"
APP_RESPONSE_ROOT = "Documents/test-responses"
COMMAND_NOTIFICATION = "com.enchron.interactive-device-ui.command"
if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))
from enchron_artifact_paths import artifact_root, evidence_root

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER_PROCESS_MARKER = Path(__file__).name
RUNNER_PROCESS_MARKERS = (
    "xcodebuild test-without-building",
    "InteractiveDeviceUITests/testInteractiveDeviceSession",
)
# A stop is an ordinary command round trip, and those were measured at a 2.6
# second median with the device busy. Five seconds sat close enough to that to
# expire on a session that was merely playing, which then skipped the graceful
# path entirely. This only elapses when the runner is genuinely not answering.
GRACEFUL_STOP_DEADLINE_SECONDS = 30.0
TERMINATION_DEADLINE_SECONDS = 5.0
# The runner acknowledges a stop before XCTest has torn the test down, and a
# recording session then spends that teardown pulling the video off the headset
# and writing the result bundle. Killing xcodebuild during it leaves a bundle
# with no Info.plist and a recording with no moov atom. This is how long a
# graceful stop may take to become an exit on its own; a session with no
# recording exits well inside it, so waiting costs nothing when there is nothing
# to write.
RESULT_BUNDLE_WRITE_DEADLINE_SECONDS = 180.0
TIMINGS_PATH = REPOSITORY_ROOT / "Scripts/verification/controller_timings.json"
TIMING_SAMPLE_LIMIT = 20
DEVICECTL_CALL_COUNT = 0


def record_timing(action: str, seconds: float, *, device: str) -> None:
    """Rolling window of measured foreground round trips per action. The
    background-context hook reads this file and stays silent about any action
    that has no record here.

    Simulator round trips are roughly an order of magnitude shorter than device
    ones, so they are keyed separately. Sharing one window would let whichever
    transport ran most recently define the expected duration of the other."""
    if is_simulator(device):
        action = f"simulator:{action}"
    try:
        timings = json.loads(TIMINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        timings = {}
    entry = timings.get(action) or {}
    samples = list(entry.get("samples") or [])
    samples.append(round(seconds, 2))
    timings[action] = {
        "samples": samples[-TIMING_SAMPLE_LIMIT:],
        "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    try:
        temporary = TIMINGS_PATH.with_name(TIMINGS_PATH.name + ".tmp")
        temporary.write_text(
            json.dumps(timings, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        temporary.replace(TIMINGS_PATH)
    except OSError:
        # Timing telemetry must not fail the device command it rode on.
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
            timeout=120,
            stdout=subprocess.DEVNULL if quiet else subprocess.PIPE,
            stderr=subprocess.DEVNULL if quiet else subprocess.PIPE,
        )
    except subprocess.TimeoutExpired:
        # The controller only moves command files and screenshots here; a
        # transfer this slow means a wedged devicectl, and an unbounded child
        # would hang every caller above it.
        return subprocess.CompletedProcess(
            command,
            returncode=124,
            stdout="",
            stderr="devicectl exceeded the 120s transport deadline.",
        )


_SIMULATOR_UDIDS: set[str] | None = None


def is_simulator(device: str) -> bool:
    """A simulator carries the whole channel on this Mac's filesystem, so every
    `devicectl` round trip below has a local equivalent that is both faster and
    incapable of the 120s transport hang."""
    global _SIMULATOR_UDIDS
    if _SIMULATOR_UDIDS is None:
        listing = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "--json"],
            check=False, text=True, capture_output=True,
        )
        udids: set[str] = set()
        if listing.returncode == 0:
            try:
                for runtime in json.loads(listing.stdout).get("devices", {}).values():
                    udids.update(entry["udid"] for entry in runtime)
            except (json.JSONDecodeError, KeyError, TypeError):
                pass
        _SIMULATOR_UDIDS = udids
    return device in _SIMULATOR_UDIDS


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
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout or "Unable to send UI command.")


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


def read_ready_state(arguments: argparse.Namespace) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="enchron-interactive-ready-") as directory:
        ready_path = Path(directory) / "ready.json"
        if not copy_from_device(
            device=arguments.device,
            runner_bundle_id=arguments.runner_bundle_id,
            remote_path=f"{CHANNEL_ROOT}/ready.json",
            local_path=ready_path,
            quiet=True,
        ):
            raise RuntimeError(
                "The interactive XCUI runner is not ready. Start its dedicated UI test first."
            )
        return json.loads(ready_path.read_text(encoding="utf-8"))


def wait_for_response(
    *,
    arguments: argparse.Namespace,
    command_id: str,
    response_path: Path,
    deadline_seconds: float | None = None,
) -> bool:
    remote_path = f"{CHANNEL_ROOT}/responses/{command_id}.json"
    started_at = time.monotonic()
    while not copy_from_device(
        device=arguments.device,
        runner_bundle_id=arguments.runner_bundle_id,
        remote_path=remote_path,
        local_path=response_path,
        quiet=True,
    ):
        if (
            deadline_seconds is not None
            and time.monotonic() - started_at >= deadline_seconds
        ):
            return False
        # This is a transport scheduling interval, not a test timeout or retry
        # limit. The caller remains in control and can interrupt at any time.
        time.sleep(0.1)
    return True


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
    """`xcodebuild -project Enchron.xcodeproj` carries no absolute path, so the
    repository is identified by the process working directory. A second checkout
    or worktree of the same project therefore stays out of scope."""
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
        if f"{root}/" in command or working_directory(pid) == root:
            scoped.append((pid, command))
    return scoped


def halt_session(arguments: argparse.Namespace) -> dict[str, object]:
    """Stops this repository's automation scope and nothing else. Prefers the
    runner's own stop command so XCTest saves its result bundle, then resolves
    the remaining Mac-side processes by repository-scoped command line."""
    graceful = "unavailable"
    try:
        ready = read_ready_state(arguments)
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
                )
                else "timedOut"
            )
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError):
        graceful = "unavailable"

    # The runner acts on a stop by ending its test, not by writing a response, so
    # a timed-out acknowledgement does not mean the stop was ignored. Waiting for
    # xcodebuild to exit is the only observation that distinguishes the two, and
    # it is also the one that matters: that exit is when the result bundle and any
    # screen recording finish being written.
    deadline = time.monotonic() + RESULT_BUNDLE_WRITE_DEADLINE_SECONDS
    while time.monotonic() < deadline and scoped_processes():
        time.sleep(0.5)
    settled = not scoped_processes()

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
        # False means xcodebuild was still running when the graceful deadline
        # passed and was killed, so its result bundle is not trustworthy.
        "resultBundleWritten": settled,
        "scope": str(REPOSITORY_ROOT),
        "terminated": [{"pid": pid, "command": command} for pid, command in targets],
        "remaining": [{"pid": pid, "command": command} for pid, command in remaining],
    }


IMMERSIVE_ATTACHMENT_MARKER = "PlayerUI-immersive"
TAP_ACTIONS = ("tap", "tapSequence", "doubleTap", "press")


def session_state_path(arguments: argparse.Namespace) -> Path:
    return Path(arguments.output_directory).expanduser() / "session-state.json"


def load_session_state(arguments: argparse.Namespace) -> dict[str, object]:
    try:
        state = json.loads(session_state_path(arguments).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return state if isinstance(state, dict) else {}


def save_session_state(arguments: argparse.Namespace, state: dict[str, object]) -> None:
    try:
        path = session_state_path(arguments)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    except OSError:
        # Session bookkeeping must not fail the device command it rode on.
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
    save_session_state(arguments, state)


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
        # `launchctl list` on a simulator labels the app by bundle id rather
        # than by executable path, so the marker set differs by transport.
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
        "label",
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
        )
        if not arrived:
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
            # The app polls this single request slot every 500 ms. Give it one
            # full poll interval before a later command may replace the file;
            # the segment retrieves and validates every UUID-named response in
            # one directory copy after all actions finish.
            time.sleep(0.75)
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
        return str(read_ready_state(arguments)["sessionID"])
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, KeyError):
        return None


AUTOMATION_AUTHORIZATION_SIGNATURE = "Timed out while enabling automation mode."


def launch_runner(
    arguments: argparse.Namespace, log_path: Path, result_bundle: Path
) -> None:
    command = [
        "xcodebuild",
        "test-without-building",
        "-project",
        arguments.project,
        "-scheme",
        arguments.scheme,
        "-testPlan",
        arguments.test_plan,
        "-configuration",
        "Debug",
        "-destination",
        (
            f"platform=visionOS Simulator,id={arguments.device}"
            if is_simulator(arguments.device)
            else f"platform=visionOS,id={arguments.destination_id or arguments.device}"
        ),
        "-derivedDataPath",
        arguments.derived_data_path,
        "-parallel-testing-enabled",
        "NO",
        "-test-timeouts-enabled",
        "NO",
        f"-only-testing:{arguments.only_testing}",
        "-resultBundlePath",
        str(result_bundle),
    ]
    if arguments.cloned_packages_path:
        command[2:2] = ["-clonedSourcePackagesDirPath", arguments.cloned_packages_path]

    environment = dict(os.environ)
    if arguments.developer_dir:
        environment["DEVELOPER_DIR"] = arguments.developer_dir
    with log_path.open("w", encoding="utf-8") as log:
        subprocess.Popen(
            command,
            cwd=str(REPOSITORY_ROOT),
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
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
    or the remaining step belongs to the wearer.

    Session bring-up is the step whose apparent length invites backgrounding and
    a handed-back turn. Collapsing halt, launch, readiness and the
    authorization-timeout restart into one call keeps an investigation inside a
    single continuous run: the caller asked for a ready session, and everything
    here executes that one intent."""
    started_at = time.monotonic()
    halt = halt_session(arguments)
    if halt["remaining"]:
        return {
            "success": False,
            "stage": "halt",
            "message": "A previous automation process survived halt.",
            "halt": halt,
        }
    # ready.json outlives the runner that wrote it, so a stale identity would
    # otherwise read as success the moment halt finishes.
    stale_session_id = current_session_id(arguments)

    output_directory = Path(arguments.output_directory)
    output_directory.mkdir(parents=True, exist_ok=True)
    log_path = output_directory / "runner.log"
    archived_log = output_directory / "runner-authorization-timeout.log"

    for attempt in (1, 2):
        result_bundle = (
            Path(arguments.result_bundle_path)
            if arguments.result_bundle_path and attempt == 1
            else output_directory / f"Interactive-{int(time.time())}-{attempt}.xcresult"
        )
        launch_runner(arguments, log_path, result_bundle)

        deadline = time.monotonic() + arguments.ready_timeout
        signature_seen = False
        while time.monotonic() < deadline:
            if AUTOMATION_AUTHORIZATION_SIGNATURE in "\n".join(log_tail(log_path, 200)):
                signature_seen = True
                break
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
                    }
                return {
                    "success": bool(response.get("success")),
                    "stage": "ready",
                    "sessionID": session_id,
                    "appState": response.get("appState"),
                    "resultBundlePath": str(result_bundle),
                    "runnerLog": str(log_path),
                    "haltedProcessCount": len(halt["terminated"]),
                    "authorizationRestarts": attempt - 1,
                    "elapsedSeconds": round(time.monotonic() - started_at, 1),
                }
            time.sleep(3)

        if not signature_seen:
            tail = log_tail(log_path)
            observations: list[dict[str, object]] = [
                {
                    "observation": (
                        f"'{AUTOMATION_AUTHORIZATION_SIGNATURE}' does not appear "
                        "in the runner log"
                    ),
                    "source": str(log_path),
                },
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
                    f"{arguments.ready_timeout:g} seconds and the authorization "
                    "signature was not observed. The observations below state "
                    "what was seen, not why."
                ),
                "observations": observations,
                "runnerLog": str(log_path),
                "elapsedSeconds": round(time.monotonic() - started_at, 1),
            }

        # The signature means this runner has already lost its chance to
        # publish a usable session (device-diagnosed 2026-08-10).
        halt_session(arguments)
        if attempt == 1:
            try:
                log_path.replace(archived_log)
            except OSError:
                pass
            continue
        return {
            "success": False,
            "stage": "authorizationTimeout",
            "message": (
                f"Both runner launches logged "
                f"'{AUTOMATION_AUTHORIZATION_SIGNATURE}'. That signature is "
                "the automation-authorization gate: XCTest did not receive "
                "wearer-side authorization or passcode confirmation within "
                "the launch window (device-diagnosed 2026-08-10; "
                "authorization renews on a measured 8-12 hour cadence). Both "
                "runners were halted and the build is untouched. Wearer "
                "action: complete the automation authorization or passcode "
                "confirmation on the headset, then rerun ensure-session."
            ),
            "runnerLogs": [str(archived_log), str(log_path)],
            "elapsedSeconds": round(time.monotonic() - started_at, 1),
        }
    raise AssertionError("unreachable: both attempts return")


def parse_arguments() -> argparse.Namespace:
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
            "doubleTap",
            "press",
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
    parser.add_argument("--project", default="Enchron.xcodeproj")
    parser.add_argument("--scheme", default="Enchron")
    parser.add_argument(
        "--test-plan", dest="test_plan", default="InteractiveDeviceSession"
    )
    parser.add_argument("--destination-id", dest="destination_id")
    parser.add_argument("--developer-dir", dest="developer_dir")
    parser.add_argument(
        "--derived-data-path",
        dest="derived_data_path",
        # Every runner reaches the device through this controller, and none of
        # them had a way to say which build to install. A run that silently used
        # a stale app reported the previous build's diagnostics as if they were
        # the current one's.
        default=os.environ.get("ENCHRON_DERIVED_DATA")
            or str(artifact_root() / "DerivedData"),
    )
    parser.add_argument(
        "--cloned-packages-path",
        dest="cloned_packages_path",
        default=str(artifact_root() / "SourcePackages/VisionProCoreRegression"),
    )
    parser.add_argument(
        "--only-testing",
        dest="only_testing",
        default="EnchronAppUITests/InteractiveDeviceUITests/testInteractiveDeviceSession",
    )
    parser.add_argument("--result-bundle-path", dest="result_bundle_path")
    parser.add_argument("--ready-timeout", dest="ready_timeout", type=float, default=300.0)
    parser.add_argument("--identifier")
    parser.add_argument("--identifiers", nargs="+")
    parser.add_argument("--label")
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
    arguments = parser.parse_args()
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


def explain_failure(arguments, response: dict) -> dict:
    """Attach the design-state facts behind the failures that otherwise read
    as a missing accessibility surface. Facts only, stated with their source;
    what to do about them stays with the caller."""
    if response.get("success") is True:
        return response
    if response.get("stage") == "responseTimeout":
        # No runner report arrived, so there is no runner-reported state to
        # explain; the timeout observations already carry the scene.
        return response
    identifiers = list(getattr(arguments, "identifiers", None) or [])
    identifier = getattr(arguments, "identifier", None)
    if identifier:
        identifiers.append(identifier)
    message = str(response.get("message", ""))

    if response.get("appState") in (None, "notRunning"):
        response["diagnosis"] = (
            "The runner reports appState notRunning: no running app was "
            "attached to this session when the event was sent "
            "(runner-reported state)."
        )
        return response

    lowered = message.lower()
    element_is_absent = (
        "no matching element" in lowered or "no current element matches" in lowered
    )
    if element_is_absent and any(
        name.startswith(AUTO_HIDING_PREFIXES) for name in identifiers
    ):
        response["diagnosis"] = (
            "Player chrome auto-hides about eight seconds after it is "
            "summoned (measured design behavior, 2026-08-10), and each "
            "controller command pays a device round trip, so a tap sent as "
            "its own command can arrive after the hide; a tapSequence "
            "delivers several taps inside one round trip (controller "
            "design). A load-failure view replaces the chrome entirely "
            "when a load fails (PlayerUI-loadFailure-primary/-secondary in "
            "the hierarchy)."
        )
    return response


SWIPE_ACTIONS = ("swipeUp", "swipeDown", "swipeLeft", "swipeRight")


def main() -> int:
    arguments = parse_arguments()
    if arguments.action in SWIPE_ACTIONS and not (
        arguments.identifier or arguments.label
    ):
        # Without a target the runner swipes the Application element, which
        # belongs to no visionOS Scene; the resulting failure ends the
        # long-lived test method and tears the session down.
        print(
            json.dumps(
                {
                    "success": False,
                    "error": (
                        f"{arguments.action} requires --identifier or --label."
                        " Swiping the application element kills the session"
                        " on visionOS."
                    ),
                },
                ensure_ascii=False,
            )
        )
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
            response = explain_failure(arguments, send_command(arguments))
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"success": False, "error": str(error)}, ensure_ascii=False))
        return 1
    if response.get("success"):
        record_timing(
            arguments.action,
            time.monotonic() - started_at,
            device=arguments.device,
        )
    response["devicectlCallCount"] = DEVICECTL_CALL_COUNT
    print(json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if response.get("success") else 2


if __name__ == "__main__":
    raise SystemExit(main())
