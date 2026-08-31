#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPOSITORY_ROOT / "Config/guard_selftests.json"
ENTRY_POINT = REPOSITORY_ROOT / "Scripts/rules/run_verification.py"
SELF_TEST_ROOTS = ("Scripts", "Tests")


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
    illegal.parent.mkdir(parents=True, exist_ok=True)
    illegal.write_text(
        """func overwriteIssue(runtime: PlaybackRuntime, issue: PlaybackUserVisibleIssue) {
    runtime.userVisibleIssue = issue
}
""",
        encoding="utf-8",
    )
    return ["--root", str(root)]


def registered_structure_checks() -> set[str]:
    source = ENTRY_POINT.read_text(encoding="utf-8")
    table = re.search(r"STRUCTURE_CHECKS[^=]*=\s*\((.*?)\n\)", source, re.S)
    if table is None:
        raise ValueError(f"no STRUCTURE_CHECKS table in {ENTRY_POINT}")
    return set(re.findall(r'"([^"]+\.(?:py|swift|sh|zsh))"', table.group(1)))


def checks_with_a_self_test(registered: set[str]) -> set[str]:
    exercised: set[str] = set()
    for directory in SELF_TEST_ROOTS:
        for test in sorted((REPOSITORY_ROOT / directory).rglob("test_*.py")):
            source = test.read_text(encoding="utf-8", errors="replace")
            for candidate in registered:
                stem = candidate.rsplit(".", 1)[0]
                if re.search(r"(?<![\w])" + re.escape(stem) + r"(?![\w])", source):
                    exercised.add(candidate)
    return exercised


def coverage_failures(payload: dict[str, object], checks: list[dict[str, object]]) -> list[str]:
    registered = registered_structure_checks()
    covered = {
        Path(str(check.get("guard", ""))).name
        for check in checks
        if isinstance(check.get("guard"), str)
    }
    declared = payload.get("externalSubject", [])
    if not isinstance(declared, list):
        return ["externalSubject must be a list"]
    exempt: dict[str, str] = {}
    failures: list[str] = []
    for entry in declared:
        if not isinstance(entry, dict):
            failures.append("every externalSubject entry must be an object")
            continue
        name = entry.get("check")
        reason = entry.get("reason")
        if not isinstance(name, str) or not isinstance(reason, str) or not reason.strip():
            failures.append(f"externalSubject entry needs a check and a reason: {entry!r}")
            continue
        if name not in registered:
            failures.append(f"{name} is declared external-subject but is not a structure check")
        if name in covered:
            failures.append(f"{name} has a known bad sample, so drop its externalSubject entry")
        exempt[name] = reason

    proven = covered | checks_with_a_self_test(registered)
    for name in sorted(registered - proven - set(exempt)):
        failures.append(
            f"{name} has never been shown to reject anything; "
            "add a known bad sample, a self-test, or an externalSubject reason"
        )
    return failures


def interpreter_for(path: Path) -> list[str]:
    if path.suffix == ".swift":
        return ["swift", str(path)]
    if path.suffix in (".sh", ".zsh"):
        return ["zsh", str(path)]
    return [sys.executable, str(path)]


class WorkingTreeSnapshot:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.populated = False

    def materialise(self) -> Path:
        if self.populated:
            return self.root
        listing = subprocess.run(
            [
                "git",
                "ls-files",
                "-z",
                "--cached",
                "--others",
                "--exclude-standard",
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        for relative in listing.stdout.split("\0"):
            if not relative:
                continue
            source = REPOSITORY_ROOT / relative
            if not source.exists() and not source.is_symlink():
                continue
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination, follow_symlinks=False)
        self.populated = True
        return self.root

    def restore(self, relative: str) -> None:
        shutil.copy2(
            REPOSITORY_ROOT / relative,
            self.root / relative,
            follow_symlinks=False,
        )


def apply_text_replacement(snapshot: WorkingTreeSnapshot, defect: dict[str, object]) -> str:
    relative = defect.get("file")
    find = defect.get("find")
    replacement = defect.get("replaceWith")
    if not isinstance(relative, str) or not isinstance(find, str) or not isinstance(replacement, str):
        raise ValueError("replace-text needs string file, find and replaceWith")
    expected = defect.get("occurrences", 1)
    if not isinstance(expected, int) or expected < 1:
        raise ValueError("occurrences must be a positive integer")

    root = snapshot.materialise()
    target = root / relative
    if not target.is_file():
        raise ValueError(f"mutation target does not exist: {relative}")
    source = target.read_text(encoding="utf-8")
    found = source.count(find)
    if found != expected:
        raise ValueError(
            f"{relative} contains {found} occurrences of {find!r}, expected {expected}"
        )
    mutated = source.replace(find, replacement)
    introduced = defect.get("introduces")
    if introduced is None:
        if find in mutated:
            raise ValueError(
                f"{replacement!r} still contains {find!r}, so the mutation removes nothing"
            )
    elif not isinstance(introduced, str):
        raise ValueError("introduces must be a string")
    elif introduced in source:
        raise ValueError(f"{introduced!r} is already present, so the mutation introduces nothing")
    elif introduced not in mutated:
        raise ValueError(f"the mutation does not introduce {introduced!r}")
    target.write_text(mutated, encoding="utf-8")
    return relative


def baseline_verdict(snapshot: WorkingTreeSnapshot, guard: str) -> str | None:
    root = snapshot.materialise()
    completed = subprocess.run(
        interpreter_for(root / guard),
        cwd=root,
        capture_output=True,
        text=True,
    )
    if completed.returncode == 0:
        return None
    output = (completed.stdout + completed.stderr).strip()
    return output.splitlines()[-1] if output else f"exit {completed.returncode}"


def command_for(
    check: dict[str, object],
    root: Path,
    snapshot: WorkingTreeSnapshot,
) -> tuple[list[str], Path, str | None]:
    guard = check.get("guard")
    defect = check.get("defect")
    if not isinstance(guard, str) or not isinstance(defect, dict):
        raise ValueError("every self-test needs a guard path and defect object")
    guard_path = REPOSITORY_ROOT / guard
    if not guard_path.is_file():
        raise ValueError(f"guard does not exist: {guard}")

    defect_type = defect.get("type")
    if defect_type == "replace-text":
        rejected = baseline_verdict(snapshot, guard)
        if rejected is not None:
            raise ValueError(
                f"guard already rejects the unmutated tree, so the case proves nothing: {rejected}"
            )
        mutated = apply_text_replacement(snapshot, defect)
        return (
            interpreter_for(snapshot.root / guard),
            snapshot.root,
            mutated,
        )
    if defect_type == "remove-xcfilelist-entry":
        arguments = create_membership_fixture(root, defect)
    elif defect_type == "remove-playback-gap-baseline-entry":
        arguments = create_playback_structure_fixture(root, defect)
    elif defect_type == "add-playback-issue-write":
        arguments = create_playback_issue_fixture(root)
    else:
        raise ValueError(f"unknown defect type: {defect_type!r}")
    return [sys.executable, str(guard_path), *arguments], REPOSITORY_ROOT, None


def run_check(
    check: dict[str, object],
    temporary_root: Path,
    snapshot: WorkingTreeSnapshot,
) -> str | None:
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
    mutated: str | None = None
    try:
        command, working_directory, mutated = command_for(check, fixture_root, snapshot)
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        return f"{identifier}: could not prepare the bad sample: {error}"
    try:
        completed = subprocess.run(
            command,
            cwd=working_directory,
            capture_output=True,
            text=True,
        )
    finally:
        if mutated is not None:
            snapshot.restore(mutated)
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
        payload = json.loads(arguments.manifest.read_text(encoding="utf-8"))
        checks = load_manifest(arguments.manifest)
        uncovered = coverage_failures(payload, checks)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"guard self-test manifest is invalid: {error}", file=sys.stderr)
        return 2

    if uncovered:
        for failure in uncovered:
            print(f"FAIL {failure}", file=sys.stderr)
        print(
            f"Structure checks without a demonstrated rejection: {len(uncovered)}",
            file=sys.stderr,
        )
        return 1

    failures: list[str] = []
    scratch = REPOSITORY_ROOT / ".scratch"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="guard-selftests-", dir=scratch
    ) as directory:
        temporary_root = Path(directory)
        snapshot_root = temporary_root / "working-tree-snapshot"
        snapshot_root.mkdir()
        snapshot = WorkingTreeSnapshot(snapshot_root)
        for check in checks:
            failure = run_check(check, temporary_root, snapshot)
            identifier = check.get("id", "unnamed")
            if failure is None:
                print(f"PASS {identifier}")
            else:
                print(f"FAIL {failure}", file=sys.stderr)
                failures.append(failure)

    if failures:
        print(f"Guard self-tests failed: {len(failures)}", file=sys.stderr)
        return 1
    declared = payload.get("externalSubject", [])
    print(
        f"Guard self-tests passed: {len(checks)} known bad samples were rejected; "
        f"{len(declared)} structure check(s) declared external-subject"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
