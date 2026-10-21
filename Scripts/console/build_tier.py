from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any

from report import EXIT_OK, EXIT_TERMINAL, write_json


DEVELOPER_DIR = "/Volumes/Cortisol/Applications/Xcode.app/Contents/Developer"
DERIVED_DATA = Path(".scratch/build")


def _environment() -> dict[str, str]:
    environment = dict(os.environ)
    environment["DEVELOPER_DIR"] = DEVELOPER_DIR
    return environment


def _run(command: list[str], root: Path, evidence_root: Path, name: str) -> dict[str, Any]:
    started = time.monotonic()
    completed = subprocess.run(
        command,
        capture_output=True,
        text=True,
        cwd=str(root),
        env=_environment(),
        timeout=3600,
    )
    duration_ms = int((time.monotonic() - started) * 1000)
    evidence_root.mkdir(parents=True, exist_ok=True)
    log = evidence_root / f"{name}.log"
    log.write_text(completed.stdout + completed.stderr, encoding="utf-8")
    payload = {
        "command": command,
        "exitCode": completed.returncode,
        "durationMs": duration_ms,
        "log": str(log),
    }
    write_json(evidence_root / f"{name}.json", payload)
    return payload


def run_build(root: Path, target: str, evidence_root: Path) -> dict[str, Any]:
    payload = _run(
        [
            "xcodebuild",
            "-project",
            "Enchron.xcodeproj",
            "-scheme",
            "Enchron",
            "-destination",
            f"platform=visionOS Simulator,id={target}",
            "-derivedDataPath",
            str(DERIVED_DATA),
            "-disableAutomaticPackageResolution",
            "build-for-testing",
        ],
        root,
        evidence_root,
        "build",
    )
    specs = sorted((root / DERIVED_DATA / "Build" / "Products").glob("*.xctestrun"))
    payload["xctestrun"] = [path.name for path in specs]
    write_json(evidence_root / "build.json", payload)
    return payload


def run_unit(root: Path, target: str, evidence_root: Path) -> dict[str, Any]:
    common = [
        "-project",
        "Enchron.xcodeproj",
        "-scheme",
        "EnchronDomainTests",
        "-testPlan",
        "EnchronDomain",
        "-destination",
        f"id={target}",
        "-derivedDataPath",
        str(DERIVED_DATA / "DomainTests"),
        "-disableAutomaticPackageResolution",
    ]
    built = _run(
        ["xcodebuild", *common, "build-for-testing"],
        root,
        evidence_root,
        "unit-build",
    )
    tested = _run(
        [
            "xcodebuild",
            *common,
            "test-without-building",
            "-collect-test-diagnostics",
            "never",
        ],
        root,
        evidence_root,
        "unit",
    )
    tested["buildDurationMs"] = built["durationMs"]
    tested["exitCode"] = tested["exitCode"] or built["exitCode"]
    tested["passed"] = (
        built["exitCode"] == 0
        and "Test run with" in Path(tested["log"]).read_text(encoding="utf-8", errors="replace")
    )
    tested["durationMs"] = built["durationMs"] + tested["durationMs"]
    _ = tested.pop("buildDurationMs", None)
    write_json(evidence_root / "unit.json", tested)
    return tested


def summarize(name: str, payload: dict[str, Any]) -> str:
    state = "passed" if payload["exitCode"] == 0 else "failed"
    line = f"{name} {state} in {payload['durationMs']} ms"
    if payload.get("xctestrun"):
        line += f", {len(payload['xctestrun'])} spec(s) written"
    return line


def exit_of(payload: dict[str, Any]) -> int:
    return EXIT_OK if payload["exitCode"] == 0 else EXIT_TERMINAL


def main(argv: list[str] | None = None) -> int:
    import sys

    target = os.environ.get("ENCHRON_TARGET_DEVICE", "")
    if not target:
        print("no target device", file=sys.stderr)
        return 4
    root = Path.cwd()
    evidence = root / "TestEvidence" / "console" / "tiers"
    payload = run_build(root, target, evidence)
    print(json.dumps(payload, indent=1))
    return exit_of(payload)


if __name__ == "__main__":
    raise SystemExit(main())
