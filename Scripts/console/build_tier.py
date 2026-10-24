from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from report import EXIT_OK, EXIT_TERMINAL, write_json


DEVELOPER_DIR = "/Volumes/Cortisol/Applications/Xcode.app/Contents/Developer"
DERIVED_DATA = Path(".scratch/build")


def _environment() -> dict[str, str]:
    environment = dict(os.environ)
    environment.setdefault("DEVELOPER_DIR", DEVELOPER_DIR)
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


BUILD_GATE_STAMP = Path(".scratch/console/build-gate.json")


def run_localization_check(root: Path, evidence_root: Path) -> dict[str, Any]:
    return _run(
        [
            sys.executable,
            "Scripts/localization/extract_strings.py",
            "--derived-data",
            str(DERIVED_DATA),
            "--no-build",
            "--check",
        ],
        root,
        evidence_root,
        "localization",
    )


def run_build(root: Path, target: str, evidence_root: Path) -> dict[str, Any]:
    products = root / DERIVED_DATA / "Build" / "Products"
    fingerprint = unit_build_fingerprint(root)
    stamp = root / BUILD_GATE_STAMP
    specs_present = bool(sorted(products.glob("*.xctestrun")))
    if specs_present and stamp.exists():
        try:
            if json.loads(stamp.read_text(encoding="utf-8")).get("fingerprint") == fingerprint:
                payload = {
                    "exitCode": EXIT_OK,
                    "durationMs": 0,
                    "log": None,
                    "reused": True,
                }
                payload["xctestrun"] = [path.name for path in sorted(products.glob("*.xctestrun"))]
                localization = run_localization_check(root, evidence_root)
                payload["localization"] = localization
                payload["exitCode"] = localization["exitCode"]
                write_json(evidence_root / "build.json", payload)
                return payload
        except (OSError, json.JSONDecodeError):
            pass
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
            "SWIFT_EMIT_LOC_STRINGS=YES",
            "build-for-testing",
        ],
        root,
        evidence_root,
        "build",
    )
    specs = sorted(products.glob("*.xctestrun"))
    payload["xctestrun"] = [path.name for path in specs]
    if payload["exitCode"] == EXIT_OK:
        localization = run_localization_check(root, evidence_root)
        payload["localization"] = localization
        payload["exitCode"] = localization["exitCode"]
    if payload["exitCode"] == EXIT_OK:
        stamp.parent.mkdir(parents=True, exist_ok=True)
        stamp.write_text(json.dumps({"fingerprint": fingerprint}), encoding="utf-8")
    write_json(evidence_root / "build.json", payload)
    return payload


def prune_duplicate_payload(product: Path) -> int:
    removed = 0
    for bundle in (product / "PlugIns").glob("*.xctest"):
        frameworks = bundle / "Frameworks"
        if frameworks.is_dir():
            removed += sum(item.stat().st_size for item in frameworks.rglob("*") if item.is_file())
            shutil.rmtree(frameworks)
        for child in bundle.iterdir():
            if not child.is_dir() or not (product / child.name).exists():
                continue
            removed += sum(item.stat().st_size for item in child.rglob("*") if item.is_file())
            shutil.rmtree(child)
    return removed


UNIT_BUILD_STAMP = Path(".scratch/console/unit-build.json")
UNIT_SOURCE_SUFFIXES = (".swift",".plist",".xctestplan",".pbxproj",".resolved")
FINGERPRINT_EXTRA_INPUTS = (
    "Packages/PlaybackCore/Vendor/FFmpeg/PlaybackFFmpeg.xcframework",
    "Packages/PlaybackCore/Vendor/SubtitleRenderer/PlaybackSubtitleRenderer.xcframework",
)


def unit_build_fingerprint(root: Path) -> str:
    listing = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=str(root),
        capture_output=True,
    )
    digest = hashlib.sha256()
    for name in sorted(entry for entry in listing.stdout.decode().split("\0") if entry):
        if not name.endswith(UNIT_SOURCE_SUFFIXES):
            continue
        try:
            info = (root / name).stat()
        except OSError:
            continue
        digest.update(f"{name}\0{info.st_mtime_ns}\0{info.st_size}\n".encode())
    digest.update(b"localization-strings=1\n")
    for name in FINGERPRINT_EXTRA_INPUTS:
        try:
            info = (root / name).lstat()
        except OSError:
            digest.update(f"{name}\0absent\n".encode())
            continue
        digest.update(f"{name}\0{info.st_mtime_ns}\0{info.st_size}\n".encode())
    return digest.hexdigest()


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
    products = (
        root
        / DERIVED_DATA
        / "DomainTests"
        / "Build"
        / "Products"
        / "Debug-xrsimulator"
        / "Enchron.app"
    )
    fingerprint = unit_build_fingerprint(root)
    stamp = root / UNIT_BUILD_STAMP
    reused = False
    if stamp.exists() and products.exists():
        try:
            reused = json.loads(stamp.read_text(encoding="utf-8")).get("fingerprint") == fingerprint
        except (OSError, json.JSONDecodeError):
            reused = False
    if reused:
        built = {"exitCode": EXIT_OK, "durationMs": 0, "log": None}
        removed = 0
    else:
        built = _run(
            ["xcodebuild", *common, "build-for-testing"],
            root,
            evidence_root,
            "unit-build",
        )
        removed = prune_duplicate_payload(products)
        if built["exitCode"] == EXIT_OK:
            stamp.parent.mkdir(parents=True, exist_ok=True)
            stamp.write_text(json.dumps({"fingerprint": fingerprint}), encoding="utf-8")
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
    tested["buildReused"] = reused
    tested["prunedBytes"] = removed
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
    localization = payload.get("localization") or {}
    if localization.get("exitCode"):
        line += (
            f"; localization drift, see {localization.get('log')}"
            " (add the missing keys to the catalog)"
        )
    verb = "reused" if payload.get("reused") else "written"
    if payload.get("xctestrun"):
        line += f", {len(payload['xctestrun'])} spec(s) {verb}"
    elif payload.get("buildReused"):
        line += ", build reused"
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
