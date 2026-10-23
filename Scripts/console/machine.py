from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess

from model import MachineProfile


DEVICE_UDID = re.compile(r"\b([0-9A-F]{8}-[0-9A-F]{8,24})\b")


def probe() -> MachineProfile:
    capabilities = {"python"}
    if platform.system() == "Darwin":
        capabilities.add("mac")
        if shutil.which("xcodebuild"):
            capabilities.add("xcode")
        if shutil.which("xcrun"):
            capabilities.add("simulator")
    physical = physical_vision_pro()
    if physical:
        capabilities.add("physical-device")
    target = (
        os.environ.get("ENCHRON_TARGET_DEVICE")
        or os.environ.get("ENCHRON_CORE_DEVICE")
        or _booted_simulator()
        or physical
    )
    if target:
        capabilities.add("device")
    if "mac" in capabilities:
        capabilities.add("daemon")
    return MachineProfile(
        capabilities=frozenset(capabilities), target=target, physical=physical
    )


def parse_physical_vision_pro(output: str) -> str | None:
    for row in output.splitlines()[1:]:
        if "physical" not in row:
            continue
        if "Vision" not in row and "RealityDevice" not in row:
            continue
        match = DEVICE_UDID.search(row)
        if match:
            return match.group(1)
    return None


def physical_vision_pro() -> str | None:
    if not shutil.which("xcrun"):
        return None
    completed = subprocess.run(
        ["xcrun", "devicectl", "list", "devices"],
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        return None
    return parse_physical_vision_pro(completed.stdout)


def _booted_simulator() -> str | None:
    if not shutil.which("xcrun"):
        return None
    completed = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted"],
        capture_output=True,
        text=True,
    )
    for line in completed.stdout.splitlines():
        marker = line.find("(")
        closing = line.find(")", marker)
        if marker == -1 or closing == -1:
            continue
        candidate = line[marker + 1 : closing]
        if candidate.count("-") == 4 and len(candidate) == 36:
            return candidate
    return None


def synthetic(name: str) -> MachineProfile:
    table = {
        "linux": frozenset({"python"}),
        "mac": frozenset({"python", "mac", "xcode", "simulator"}),
        "mac-device": frozenset(
            {"python", "mac", "xcode", "simulator", "device"}
        ),
        "mac-physical": frozenset(
            {"python", "mac", "xcode", "simulator", "device", "physical-device"}
        ),
        "mac-daemon": frozenset(
            {"python", "mac", "xcode", "simulator", "device", "daemon"}
        ),
    }
    if name not in table:
        raise ValueError(f"unknown machine profile {name!r}")
    return MachineProfile(capabilities=table[name], target=None)


def load(name: str | None) -> MachineProfile:
    if name:
        return synthetic(name)
    return probe()
