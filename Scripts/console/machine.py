from __future__ import annotations

import os
import platform
import shutil
import subprocess

from model import MachineProfile


def probe() -> MachineProfile:
    capabilities = {"python"}
    if platform.system() == "Darwin":
        capabilities.add("mac")
        if shutil.which("xcodebuild"):
            capabilities.add("xcode")
        if shutil.which("xcrun"):
            capabilities.add("simulator")
    target = os.environ.get("ENCHRON_TARGET_DEVICE") or os.environ.get(
        "ENCHRON_CORE_DEVICE"
    ) or _booted_simulator()
    if target:
        capabilities.add("device")
    if "mac" in capabilities:
        capabilities.add("daemon")
    return MachineProfile(capabilities=frozenset(capabilities), target=target)


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
