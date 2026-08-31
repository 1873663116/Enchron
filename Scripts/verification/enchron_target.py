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


def copy_from_container(
    *,
    target: str,
    bundle_id: str,
    source: str,
    destination: Path,
    developer_dir: str,
    core_device_identifier: str | None = None,
) -> subprocess.CompletedProcess[str]:
    """Fetch one file out of the app container, whichever lane the target is on.

    The simulator branch is a plain filesystem read, so it cannot reproduce the
    `devicectl` behaviour of hanging instead of failing when the app is not
    running. Callers that treat a timeout as a signal should read the returned
    code, not the elapsed time.
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
        check=False, text=True, capture_output=True,
    )
