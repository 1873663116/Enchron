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
    )
    if target:
        capabilities.add("device")
    if _daemon_reachable():
        capabilities.add("daemon")
    return MachineProfile(capabilities=frozenset(capabilities), target=target)


def _daemon_reachable() -> bool:
    socket_path = daemon_socket()
    return socket_path.exists()


def daemon_socket():
    from pathlib import Path

    root = Path(os.environ.get("ENCHRON_CONSOLE_ROOT", "")) or Path.cwd()
    return root / ".console" / "daemon.sock"


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
