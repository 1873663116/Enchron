#!/usr/bin/env python3
"""Send one runtime-decided XCUIAutomation command to a live Vision Pro runner."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
import uuid
from pathlib import Path


RUNNER_BUNDLE_ID = "com.xiongzhipeng.EnchronAppUITests.xctrunner"
CHANNEL_ROOT = "Documents/EnchronInteractiveUI"
COMMAND_NOTIFICATION = "com.enchron.interactive-device-ui.command"
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
# A process belongs to this repository's automation scope only when its command
# line carries one of these alongside the repository root. Matching a bare tool
# name would reach an unrelated project's build on the same machine.
SCOPE_MARKERS = ("Enchron.xcodeproj", Path(__file__).name)
GRACEFUL_STOP_DEADLINE_SECONDS = 5.0
TERMINATION_DEADLINE_SECONDS = 5.0


def run_devicectl(arguments: list[str], *, quiet: bool = False) -> subprocess.CompletedProcess[str]:
    command = ["xcrun", "devicectl", *arguments]
    return subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.DEVNULL if quiet else subprocess.PIPE,
        stderr=subprocess.DEVNULL if quiet else subprocess.PIPE,
    )


def copy_from_device(
    *,
    device: str,
    runner_bundle_id: str,
    remote_path: str,
    local_path: Path,
    quiet: bool,
) -> bool:
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
        if not any(marker in command for marker in SCOPE_MARKERS):
            continue
        if root in command or working_directory(pid) == root:
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
            run_devicectl(
                [
                    "device",
                    "process",
                    "signal",
                    "--device",
                    arguments.device,
                    "--signal",
                    "SIGCONT",
                ],
                quiet=True,
            )
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
        "scope": str(REPOSITORY_ROOT),
        "terminated": [{"pid": pid, "command": command} for pid, command in targets],
        "remaining": [{"pid": pid, "command": command} for pid, command in remaining],
    }


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
        "label",
        "index",
        "text",
        "duration",
        "normalizedX",
        "normalizedY",
    ):
        value = getattr(arguments, key)
        if value is not None:
            command[key] = value

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
        notification = run_devicectl(
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
        if notification.returncode != 0:
            raise RuntimeError(
                notification.stderr
                or notification.stdout
                or "Unable to wake the interactive UI runner."
            )
        wait_for_response(
            arguments=arguments,
            command_id=command_id,
            response_path=response_path,
        )
        response = json.loads(response_path.read_text(encoding="utf-8"))
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


def current_session_id(arguments: argparse.Namespace) -> str | None:
    try:
        return str(read_ready_state(arguments)["sessionID"])
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, KeyError):
        return None


def ensure_session(arguments: argparse.Namespace) -> dict[str, object]:
    """Brings up one live session and returns only when it can accept commands.

    Session bring-up is the step whose apparent length invites backgrounding and
    a handed-back turn. Collapsing halt, launch and readiness into one call keeps
    an investigation inside a single continuous run."""
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
    result_bundle = (
        Path(arguments.result_bundle_path)
        if arguments.result_bundle_path
        else output_directory / f"Interactive-{int(time.time())}.xcresult"
    )
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
        f"platform=visionOS,id={arguments.destination_id or arguments.device}",
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
                }
            return {
                "success": bool(response.get("success")),
                "stage": "ready",
                "sessionID": session_id,
                "appState": response.get("appState"),
                "resultBundlePath": str(result_bundle),
                "runnerLog": str(log_path),
                "haltedProcessCount": len(halt["terminated"]),
                "elapsedSeconds": round(time.monotonic() - started_at, 1),
            }
        time.sleep(3)
    return {
        "success": False,
        "stage": "readyTimeout",
        "message": (
            "No new session was published. Read runnerLog for the XCTest "
            "authorization signature before starting another runner."
        ),
        "runnerLog": str(log_path),
        "elapsedSeconds": round(time.monotonic() - started_at, 1),
    }


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
            "doubleTap",
            "press",
            "typeText",
            "swipeUp",
            "swipeDown",
            "swipeLeft",
            "swipeRight",
            "coordinateTap",
            "relaunch",
            "terminate",
            "stop",
            "halt",
            "ensure-session",
        ),
    )
    parser.add_argument("--project", default="Enchron.xcodeproj")
    parser.add_argument("--scheme", default="Enchron")
    parser.add_argument("--test-plan", dest="test_plan", default="Enchron")
    parser.add_argument("--destination-id", dest="destination_id")
    parser.add_argument("--developer-dir", dest="developer_dir")
    parser.add_argument(
        "--derived-data-path",
        dest="derived_data_path",
        default="/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedData",
    )
    parser.add_argument(
        "--cloned-packages-path",
        dest="cloned_packages_path",
        default="/Volumes/Cortisol/DevSpace/Xcode/Enchron/SourcePackages/VisionProCoreRegression",
    )
    parser.add_argument(
        "--only-testing",
        dest="only_testing",
        default="EnchronAppUITests/InteractiveDeviceUITests/testInteractiveDeviceSession",
    )
    parser.add_argument("--result-bundle-path", dest="result_bundle_path")
    parser.add_argument("--ready-timeout", dest="ready_timeout", type=float, default=300.0)
    parser.add_argument("--identifier")
    parser.add_argument("--label")
    parser.add_argument("--index", type=int)
    parser.add_argument("--text")
    parser.add_argument("--duration", type=float)
    parser.add_argument("--normalized-x", dest="normalizedX", type=float)
    parser.add_argument("--normalized-y", dest="normalizedY", type=float)
    parser.add_argument("--no-screenshot", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.action == "halt":
            response = halt_session(arguments)
        elif arguments.action == "ensure-session":
            response = ensure_session(arguments)
        else:
            response = send_command(arguments)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"success": False, "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if response.get("success") else 2


if __name__ == "__main__":
    raise SystemExit(main())
