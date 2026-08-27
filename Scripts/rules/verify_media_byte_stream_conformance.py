#!/usr/bin/env python3
"""Run the MediaByteStream HTTP byte-range conformance package."""

from __future__ import annotations

import os
from pathlib import Path
import shlex
import subprocess
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PACKAGE_PATH = REPOSITORY_ROOT / "Tests/MediaByteStreamConformance"


def developer_directory() -> str:
    completed = subprocess.run(
        ["/usr/bin/xcode-select", "-p"],
        capture_output=True,
        text=True,
        check=True,
    )
    return completed.stdout.strip()


def host_architecture() -> str:
    completed = subprocess.run(
        ["/usr/sbin/sysctl", "-n", "hw.optional.arm64"],
        capture_output=True,
        text=True,
    )
    return "arm64" if completed.returncode == 0 and completed.stdout.strip() == "1" else "x86_64"


def main() -> int:
    if not (PACKAGE_PATH / "Package.swift").is_file():
        print(f"missing conformance package: {PACKAGE_PATH}", file=sys.stderr)
        return 2

    environment = os.environ.copy()
    try:
        environment["DEVELOPER_DIR"] = developer_directory()
    except subprocess.SubprocessError as error:
        print(f"could not resolve the active developer directory: {error}", file=sys.stderr)
        return 2

    command = [
        "/usr/bin/xcrun",
        "swift",
        "test",
        "--package-path",
        str(PACKAGE_PATH),
        "--triple",
        f"{host_architecture()}-apple-macosx14.0",
        "--disable-xctest",
    ]
    print("$ " + shlex.join(command), flush=True)
    try:
        return subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            env=environment,
        ).returncode
    except OSError as error:
        print(f"could not start the conformance suite: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
