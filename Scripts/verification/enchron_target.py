#!/usr/bin/env python3

"""Which Vision Pro the regression runners drive, and how to reach its container.

The lane a run belongs to is a property of the target, not of the runner: the
same operation units, the same resident XCUITest runner and the same controller
serve both. Pinning a physical CoreDevice ID as a module constant made that
untrue in practice, because a simulator UDID had nowhere to enter. Pinning it
also made an unconfigured run drive one particular headset instead of saying it
had no target. Both identifiers now come from the environment and nowhere else.
These helpers are the entry point.

`ENCHRON_TARGET_DEVICE` selects the xcodebuild destination the controller drives.
Set it to a simulator UDID to move a whole regression round onto the simulator
lane; the controller detects the transport from the same value.

`ENCHRON_CORE_DEVICE` selects the CoreDevice a physical run uses for `devicectl`.
It is meaningless on the simulator, where the container is a local directory.
"""

from __future__ import annotations

import os
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

_SIMULATOR_UDIDS: set[str] | None = None


def target_device() -> str:
    """The destination the controller drives. A simulator UDID moves the lane.

    Empty when `ENCHRON_TARGET_DEVICE` is unset. Several harnesses bind this at
    import time, so the absence travels as a value and is refused by whichever
    operation actually needs a target, naming the variable that was missing.
    """
    return os.environ.get("ENCHRON_TARGET_DEVICE", "")


def core_device() -> str:
    """The CoreDevice a physical run uses for `devicectl`.

    Empty when `ENCHRON_CORE_DEVICE` is unset, and refused by the devicectl
    branches rather than passed to `--device` as an empty or `None` argument.
    """
    return os.environ.get("ENCHRON_CORE_DEVICE", "")


MISSING_TARGET = (
    "target must not be empty: set ENCHRON_TARGET_DEVICE to the destination to drive"
)
MISSING_CORE_DEVICE = (
    "devicectl needs a CoreDevice identifier: "
    "pass core_device_identifier or set ENCHRON_CORE_DEVICE"
)


def require_target_device() -> str:
    """The destination, refusing an unconfigured run instead of picking a lane for it.

    `target_device()` answers `""` when the variable is unset, and
    `is_simulator("")` is false, so a lane derived straight from it reads as the
    device lane: an unconfigured run reports itself as a physical-headset run
    and every later message names a headset that was never selected. Whoever
    needs a lane rather than a value asks here, and gets a refusal naming the
    variable that was missing.
    """
    device = target_device()
    if not device:
        raise SystemExit(MISSING_TARGET)
    return device


def refusal(reason: str) -> subprocess.CompletedProcess[str]:
    """A failed result carrying why it failed.

    Every caller of these helpers reads `returncode` and records `stderr`;
    `wake_target_device` in the reachability matrix explicitly tolerates a
    failed launch and records it as an event. An unconfigured target is that
    kind of failure, not a reason to abort a round with a traceback.
    """
    return subprocess.CompletedProcess([], returncode=1, stdout="", stderr=reason)


def developer_directory() -> str:
    """The active developer directory, honoring an explicit DEVELOPER_DIR."""
    explicit = os.environ.get("DEVELOPER_DIR")
    if explicit:
        return explicit
    completed = subprocess.run(
        ["xcode-select", "-p"],
        check=True, text=True, capture_output=True,
    )
    return completed.stdout.strip()


def is_simulator(device: str) -> bool:
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


def copy_to_container(
    *,
    target: str,
    bundle_id: str,
    source: Path,
    destination: str,
    developer_dir: str,
    core_device_identifier: str | None = None,
    timeout: float = 120.0,
    budget_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    """Put one file into the app container, whichever lane the target is on.

    Every write went through `devicectl --device <CoreDevice>` while every read
    was already routed. On a simulator the CoreDevice names a headset that is
    not there, and devicectl answers "RemoteServiceDiscovery connectivity is not
    available to the device" - which reads as a broken headset rather than as a
    write aimed at the wrong lane.

    `budget_seconds` overrides the fixed timeout; the harness passes a derived
    budget through it because drivers may not spell timeout keywords.
    """
    if budget_seconds is not None:
        timeout = budget_seconds
    if not target:
        return refusal(MISSING_TARGET)
    if is_simulator(target):
        container = simulator_container(target, bundle_id)
        if container is None:
            return subprocess.CompletedProcess(
                ["simctl", "get_app_container", target, bundle_id],
                returncode=1, stdout="", stderr="container is not readable.",
            )
        into = container / destination
        into.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, into, dirs_exist_ok=True)
        else:
            shutil.copyfile(source, into)
        return subprocess.CompletedProcess([], returncode=0, stdout="", stderr="")
    identifier = core_device_identifier or core_device()
    if not identifier:
        return refusal(MISSING_CORE_DEVICE)
    return subprocess.run(
        [
            "xcrun", "devicectl", "device", "copy", "to",
            "--device", identifier,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundle_id,
            "--source", str(source),
            "--destination", destination,
        ],
        env={"DEVELOPER_DIR": developer_dir, "PATH": "/usr/bin:/bin"},
        capture_output=True, text=True, timeout=timeout, check=False,
    )


def truncate_in_container(
    *,
    target: str,
    bundle_id: str,
    source: str,
    developer_dir: str,
    core_device_identifier: str | None = None,
    timeout: float = 120.0,
    budget_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    """Empty one file inside the app container, whichever lane the target is on.

    Reads were routed per lane and writes were not, so clearing the probe went
    through `devicectl --device <CoreDevice>` on both. A simulator has no
    CoreDevice, so the clear could only fail there, and a segment inherited
    whatever the previous run had written. That is how a panorama segment came
    back with four hundred and sixty-two journal lines carrying a session id
    from an earlier run, and a replay that could verify nothing.

    `budget_seconds` overrides the fixed timeout; the harness passes a derived
    budget through it because drivers may not spell timeout keywords.
    """
    if budget_seconds is not None:
        timeout = budget_seconds
    if not target:
        return refusal(MISSING_TARGET)
    if is_simulator(target):
        container = simulator_container(target, bundle_id)
        origin = container / source if container else None
        if origin is None:
            return subprocess.CompletedProcess(
                ["simctl", "get_app_container", target, bundle_id],
                returncode=1, stdout="", stderr="container is not readable.",
            )
        origin.parent.mkdir(parents=True, exist_ok=True)
        origin.write_text("", encoding="utf-8")
        return subprocess.CompletedProcess([], returncode=0, stdout="", stderr="")
    empty = Path(tempfile.gettempdir()) / "enchron-container-truncate.empty"
    empty.write_text("", encoding="utf-8")
    identifier = core_device_identifier or core_device()
    if not identifier:
        return refusal(MISSING_CORE_DEVICE)
    return subprocess.run(
        [
            "xcrun", "devicectl", "device", "copy", "to",
            "--device", identifier,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundle_id,
            "--source", str(empty),
            "--destination", source,
            "--timeout", str(int(timeout)),
        ],
        env={"DEVELOPER_DIR": developer_dir, "PATH": "/usr/bin:/bin"},
        capture_output=True, text=True, timeout=timeout, check=False,
    )


def copy_from_container(
    *,
    target: str,
    bundle_id: str,
    source: str,
    destination: Path,
    developer_dir: str,
    core_device_identifier: str | None = None,
    budget_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    """Fetch one file out of the app container, whichever lane the target is on.

    The simulator branch is a plain filesystem read, so it cannot reproduce the
    `devicectl` behaviour of hanging instead of failing when the app is not
    running. Callers that treat a timeout as a signal should read the returned
    code, not the elapsed time. `budget_seconds` bounds the devicectl copy so a
    hang surfaces as `subprocess.TimeoutExpired` instead of blocking forever;
    None preserves the historical unbounded read.
    """
    if not target:
        return refusal(MISSING_TARGET)
    if is_simulator(target):
        container = simulator_container(target, bundle_id)
        origin = container / source if container else None
        if origin is None or not origin.exists():
            return subprocess.CompletedProcess(
                ["simctl", "get_app_container", target, bundle_id],
                returncode=1, stdout="", stderr=f"{source} is not in the container.",
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        if origin.is_dir():
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(origin, destination)
        else:
            shutil.copyfile(origin, destination)
        return subprocess.CompletedProcess([], returncode=0, stdout="", stderr="")
    identifier = core_device_identifier or core_device()
    if not identifier:
        return refusal(MISSING_CORE_DEVICE)
    return subprocess.run(
        [
            "xcrun", "devicectl", "device", "copy", "from",
            "--device", identifier,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundle_id,
            "--source", source,
            "--destination", str(destination),
        ],
        env={"DEVELOPER_DIR": developer_dir, "PATH": "/usr/bin:/bin"},
        check=False, text=True, capture_output=True, timeout=budget_seconds,
    )


def list_container_file(
    *,
    target: str,
    bundle_id: str,
    source: str,
    json_output: Path,
    developer_dir: str,
    core_device_identifier: str | None = None,
    budget_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    if not target:
        return refusal(MISSING_TARGET)
    remote = Path(source)
    if is_simulator(target):
        container = simulator_container(target, bundle_id)
        origin = container / source if container else None
        if origin is None or not origin.exists():
            return subprocess.CompletedProcess(
                ["simctl", "get_app_container", target, bundle_id],
                returncode=1, stdout="", stderr=f"{source} is not in the container.",
            )
        json_output.parent.mkdir(parents=True, exist_ok=True)
        json_output.write_text(
            json.dumps({
                "result": {
                    "files": [{
                        "name": remote.name,
                        "path": source,
                        "size": origin.stat().st_size,
                    }]
                }
            }, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return subprocess.CompletedProcess([], returncode=0, stdout="", stderr="")
    identifier = core_device_identifier or core_device()
    if not identifier:
        return refusal(MISSING_CORE_DEVICE)
    command = [
        "xcrun", "devicectl", "device", "info", "files",
        "--device", identifier,
        "--domain-type", "appDataContainer",
        "--domain-identifier", bundle_id,
        "--subdirectory", str(remote.parent),
        "--filter", f"Name = '{remote.name}'",
        "--no-recurse",
        "--json-output", str(json_output),
    ]
    if budget_seconds is not None:
        command.extend(("--timeout", str(int(budget_seconds))))
    return subprocess.run(
        command,
        env={"DEVELOPER_DIR": developer_dir, "PATH": "/usr/bin:/bin"},
        capture_output=True, text=True, timeout=budget_seconds, check=False,
    )


def launch_app(
    *,
    target: str,
    bundle_id: str,
    developer_dir: str | None = None,
    budget_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    if not target:
        return refusal(MISSING_TARGET)
    if is_simulator(target):
        command = ["xcrun", "simctl", "launch", target, bundle_id]
    else:
        command = [
            "xcrun", "devicectl", "device", "process", "launch",
            "--device", target, "--terminate-existing", bundle_id,
        ]
    env = None
    if developer_dir is not None:
        env = {"DEVELOPER_DIR": developer_dir, "PATH": "/usr/bin:/bin"}
    return subprocess.run(
        command,
        env=env,
        capture_output=True, text=True, timeout=budget_seconds, check=False,
    )


def uninstall_app(
    *,
    target: str,
    bundle_id: str,
    developer_dir: str | None = None,
    budget_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    if not target:
        return refusal(MISSING_TARGET)
    if is_simulator(target):
        command = ["xcrun", "simctl", "uninstall", target, bundle_id]
    else:
        command = [
            "xcrun", "devicectl", "device", "uninstall", "app",
            "--device", target, bundle_id,
        ]
    env = None
    if developer_dir is not None:
        env = {"DEVELOPER_DIR": developer_dir, "PATH": "/usr/bin:/bin"}
    return subprocess.run(
        command,
        env=env,
        capture_output=True, text=True, timeout=budget_seconds, check=False,
    )
