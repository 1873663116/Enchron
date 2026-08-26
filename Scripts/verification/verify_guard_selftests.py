#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPOSITORY_ROOT / "Config/guard_selftests.json"


def load_manifest(path: Path) -> list[dict[str, object]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    checks = payload.get("checks")
    if payload.get("version") != 1 or not isinstance(checks, list) or not checks:
        raise ValueError("expected version 1 with a non-empty checks list")
    return checks


def create_membership_fixture(root: Path, defect: dict[str, object]) -> list[str]:
    (root / "Apps").mkdir()
    (root / "Config").mkdir()
    os.symlink(REPOSITORY_ROOT / "Apps/Enchron", root / "Apps/Enchron")
    os.symlink(REPOSITORY_ROOT / "Apps/DesignPreview", root / "Apps/DesignPreview")
    os.symlink(REPOSITORY_ROOT / "Modules", root / "Modules")
    os.symlink(REPOSITORY_ROOT / "Enchron.xcodeproj", root / "Enchron.xcodeproj")
    shutil.copyfile(
        REPOSITORY_ROOT / "Config/design_source_architecture_baseline.json",
        root / "Config/design_source_architecture_baseline.json",
    )

    source = REPOSITORY_ROOT / "Config/design_source_architecture_inputs.xcfilelist"
    lines = source.read_text(encoding="utf-8").splitlines()
    entry = defect.get("entry")
    if not isinstance(entry, str) or lines.count(entry) != 1:
        raise ValueError(f"fixture entry must occur exactly once in {source}: {entry!r}")
    lines.remove(entry)
    (root / "Config/design_source_architecture_inputs.xcfilelist").write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )
    return ["--root", str(root)]


# Path.rglob does not descend into symlinked directories, so a fixture that
# symlinks whole directories reads as an empty tree to the guards that scan it.
def mirror_tree(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for entry in sorted(source.rglob("*")):
        mirrored = destination / entry.relative_to(source)
        if entry.is_dir():
            mirrored.mkdir(exist_ok=True)
        else:
            os.symlink(entry, mirrored)


def create_app_layer_reference_fixture(
    root: Path,
    defect: dict[str, object],
) -> list[str]:
    entry = defect.get("entry")
    if not isinstance(entry, str):
        raise ValueError("fixture needs the Modules-relative source to spoil")
    spoiled = Path(entry)
    original = REPOSITORY_ROOT / "Modules" / spoiled
    if not original.is_file():
        raise ValueError(f"fixture source does not exist: {original}")

    (root / "Apps").mkdir()
    (root / "Config").mkdir()
    os.symlink(REPOSITORY_ROOT / "Apps/Enchron", root / "Apps/Enchron")
    os.symlink(REPOSITORY_ROOT / "Apps/DesignPreview", root / "Apps/DesignPreview")
    os.symlink(REPOSITORY_ROOT / "Enchron.xcodeproj", root / "Enchron.xcodeproj")
    for name in (
        "design_source_architecture_baseline.json",
        "design_source_architecture_inputs.xcfilelist",
    ):
        shutil.copyfile(REPOSITORY_ROOT / "Config" / name, root / "Config" / name)

    mirror_tree(REPOSITORY_ROOT / "Modules", root / "Modules")
    (root / "Modules" / spoiled).unlink()
    (root / "Modules" / spoiled).write_text(
        original.read_text(encoding="utf-8")
        + """
func recordIllegalProbe() {
    AppModel.recordProbe("reverse dependency")
}
""",
        encoding="utf-8",
    )
    return ["--root", str(root)]


def create_playback_structure_fixture(
    root: Path,
    defect: dict[str, object],
) -> list[str]:
    source = REPOSITORY_ROOT / "Config/playback_surface_structure_baseline.json"
    payload = json.loads(source.read_text(encoding="utf-8"))
    name = defect.get("name")
    original = payload["knownGaps"]
    payload["knownGaps"] = [entry for entry in original if entry.get("name") != name]
    if len(payload["knownGaps"]) != len(original) - 1:
        raise ValueError(f"fixture gap must occur exactly once in {source}: {name!r}")
    baseline = root / "playback_surface_structure_baseline.json"
    baseline.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return ["--baseline", str(baseline)]


def create_playback_issue_fixture(root: Path) -> list[str]:
    owner = root / "Modules/Playback/PlaybackRuntime.swift"
    owner.parent.mkdir(parents=True)
    owner.write_text(
        """public final class PlaybackRuntime {
    public private(set) var userVisibleIssue: PlaybackUserVisibleIssue?

    public func setUserVisibleIssue(_ issue: PlaybackUserVisibleIssue?) {
        userVisibleIssue = issue
    }
}
""",
        encoding="utf-8",
    )
    illegal = root / "Modules/Playback/IllegalPlaybackIssueWriter.swift"
    illegal.parent.mkdir(parents=True)
    illegal.write_text(
        """func overwriteIssue(runtime: PlaybackRuntime, issue: PlaybackUserVisibleIssue) {
    runtime.userVisibleIssue = issue
}
""",
        encoding="utf-8",
    )
    return ["--root", str(root)]


def command_for(check: dict[str, object], root: Path) -> list[str]:
    guard = check.get("guard")
    defect = check.get("defect")
    if not isinstance(guard, str) or not isinstance(defect, dict):
        raise ValueError("every self-test needs a guard path and defect object")
    guard_path = REPOSITORY_ROOT / guard
    if not guard_path.is_file():
        raise ValueError(f"guard does not exist: {guard}")

    defect_type = defect.get("type")
    if defect_type == "remove-xcfilelist-entry":
        arguments = create_membership_fixture(root, defect)
    elif defect_type == "remove-playback-gap-baseline-entry":
        arguments = create_playback_structure_fixture(root, defect)
    elif defect_type == "add-app-layer-reference":
        arguments = create_app_layer_reference_fixture(root, defect)
    elif defect_type == "add-playback-issue-write":
        arguments = create_playback_issue_fixture(root)
    else:
        raise ValueError(f"unknown defect type: {defect_type!r}")
    return [sys.executable, str(guard_path), *arguments]


def run_check(check: dict[str, object], temporary_root: Path) -> str | None:
    identifier = check.get("id")
    expected = check.get("expected")
    if not isinstance(identifier, str) or not isinstance(expected, dict):
        return "self-test needs a string id and expected object"
    expected_code = expected.get("exitCode")
    expected_text = expected.get("outputContains")
    if not isinstance(expected_code, int) or not isinstance(expected_text, list):
        return f"{identifier}: expected result is malformed"
    if not all(isinstance(marker, str) for marker in expected_text):
        return f"{identifier}: outputContains must contain strings"

    fixture_root = temporary_root / identifier
    fixture_root.mkdir()
    try:
        command = command_for(check, fixture_root)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        return f"{identifier}: could not prepare the bad sample: {error}"
    completed = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
    )
    output = completed.stdout + completed.stderr
    missing_markers = [marker for marker in expected_text if marker not in output]
    if completed.returncode == 0:
        return f"{identifier}: guard accepted the known bad sample"
    if completed.returncode != expected_code:
        return (
            f"{identifier}: exit code was {completed.returncode}, "
            f"expected {expected_code}"
        )
    if missing_markers:
        return f"{identifier}: output omitted {missing_markers!r}"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Feed retained bad samples to repository guards."
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    arguments = parser.parse_args()
    try:
        checks = load_manifest(arguments.manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"guard self-test manifest is invalid: {error}", file=sys.stderr)
        return 2

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="enchron-guard-selftests-") as directory:
        temporary_root = Path(directory)
        for check in checks:
            failure = run_check(check, temporary_root)
            identifier = check.get("id", "unnamed")
            if failure is None:
                print(f"PASS {identifier}")
            else:
                print(f"FAIL {failure}", file=sys.stderr)
                failures.append(failure)

    if failures:
        print(f"Guard self-tests failed: {len(failures)}", file=sys.stderr)
        return 1
    print(f"Guard self-tests passed: {len(checks)} known bad samples were rejected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
