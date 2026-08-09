#!/usr/bin/env python3
"""Send one runtime-decided XCUIAutomation command to a live Vision Pro runner."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import time
import uuid
from pathlib import Path


RUNNER_BUNDLE_ID = "com.xiongzhipeng.EnchronAppUITests.xctrunner"
CHANNEL_ROOT = "Documents/EnchronInteractiveUI"
COMMAND_NOTIFICATION = "com.enchron.interactive-device-ui.command"


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
) -> None:
    remote_path = f"{CHANNEL_ROOT}/responses/{command_id}.json"
    while not copy_from_device(
        device=arguments.device,
        runner_bundle_id=arguments.runner_bundle_id,
        remote_path=remote_path,
        local_path=response_path,
        quiet=True,
    ):
        # This is a transport scheduling interval, not a test timeout or retry
        # limit. The caller remains in control and can interrupt at any time.
        time.sleep(0.1)


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
        ),
    )
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
        response = send_command(arguments)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"success": False, "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if response.get("success") else 2


if __name__ == "__main__":
    raise SystemExit(main())
