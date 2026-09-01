#!/usr/bin/env python3

"""Which Vision Pro the regression runners drive, and how to reach its container.

The lane a run belongs to is a property of the target, not of the runner: the
same operation units, the same resident XCUITest runner and the same controller
serve both. Pinning a physical CoreDevice ID as a module constant made that
untrue in practice, because a simulator UDID had nowhere to enter. These helpers
are the entry point.

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

# Last reconciled 2026-08-09. `xcrun devicectl list devices` is the source of
# truth when the headset changes.
PHYSICAL_DESTINATION = "00008142-001871A11491401C"
PHYSICAL_CORE_DEVICE = "59E3D57A-0288-53DC-9A7D-B657B6939558"

_SIMULATOR_UDIDS: set[str] | None = None


def target_device() -> str:
    """The destination the controller drives. A simulator UDID moves the lane."""
    return os.environ.get("ENCHRON_TARGET_DEVICE") or PHYSICAL_DESTINATION


def core_device() -> str:
    """The CoreDevice a physical run uses for `devicectl`."""
    return os.environ.get("ENCHRON_CORE_DEVICE") or PHYSICAL_CORE_DEVICE


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
        raise ValueError("container target must not be empty")
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
    return subprocess.run(
        [
            "xcrun", "devicectl", "device", "copy", "to",
            "--device", str(core_device_identifier),
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
        raise ValueError("container target must not be empty")
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
    return subprocess.run(
        [
            "xcrun", "devicectl", "device", "copy", "to",
            "--device", str(core_device_identifier),
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
        raise ValueError("container target must not be empty")
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
            # devicectl copies a directory whole, and the deferred response
            # batch is one. Copying only files would have left every batched
            # response behind on the simulator lane.
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(origin, destination)
        else:
            shutil.copyfile(origin, destination)
        return subprocess.CompletedProcess([], returncode=0, stdout="", stderr="")
    return subprocess.run(
        [
            "xcrun", "devicectl", "device", "copy", "from",
            "--device", core_device_identifier or core_device(),
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
        raise ValueError("container target must not be empty")
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
    command = [
        "xcrun", "devicectl", "device", "info", "files",
        "--device", str(core_device_identifier or core_device()),
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


def uninstall_app(
    *,
    target: str,
    bundle_id: str,
    developer_dir: str | None = None,
    budget_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    if not target:
        raise ValueError("uninstall target must not be empty")
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
