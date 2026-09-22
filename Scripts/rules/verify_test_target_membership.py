#!/usr/bin/env python3

"""Checks that every test-bearing directory has its declared harnesses.

Config/test_harness_map.json is the source of truth. For each directory the
check confirms:

- the directory exists;
- every declared xcode harness lists the directory in a
  PBXFileSystemSynchronizedRootGroup attached to that target;
- every declared swiftpm harness has a testTarget with a matching path in
  the owning package's Package.swift (the package's own Tests/<name>
  default counts when the target declares no path);
- every entry under excludedFromMembership appears in the exception set
  for that group's owning target;
- no synchronized group under a test target points at a directory missing
  from the map.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RULE = "test-target-membership"
MAP_PATH = REPOSITORY_ROOT / "Config/test_harness_map.json"
PROJECT_FILE = REPOSITORY_ROOT / "Enchron.xcodeproj/project.pbxproj"
PACKAGE_MANIFESTS = {
    "EnchronModules": REPOSITORY_ROOT / "Package.swift",
    "PlaybackCore": REPOSITORY_ROOT / "Packages/PlaybackCore/Package.swift",
    "Tests/MediaByteStreamConformance": (
        REPOSITORY_ROOT / "Tests/MediaByteStreamConformance/Package.swift"
    ),
}

SYNC_GROUP = re.compile(
    r"([A-F0-9]{24}) /\* (.*?) \*/ = \{\n"
    r"\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
    r"(.*?)\n\t\t\};",
    re.DOTALL,
)
TARGET_BLOCK = re.compile(
    r"([A-F0-9]{24}) /\* (.*?) \*/ = \{\n"
    r"\t\t\tisa = PBXNativeTarget;\n"
    r"(.*?)\n\t\t\};",
    re.DOTALL,
)
EXCEPTION_SET = re.compile(
    r"([A-F0-9]{24}) /\* .*? \*/ = \{\n"
    r"\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
    r"(.*?)\n\t\t\};",
    re.DOTALL,
)
TEST_TARGET_NAME = re.compile(r"\.testTarget\(\s*name:\s*\"(\w+)\"")


def parse_groups(project: str) -> dict[str, dict[str, object]]:
    groups: dict[str, dict[str, object]] = {}
    for match in SYNC_GROUP.finditer(project):
        group_id, name, body = match.groups()
        path_match = re.search(r'path = "?([^";]+)"?;', body)
        exceptions = re.search(r"exceptions = \(\s*([A-F0-9]{24})", body)
        groups[group_id] = {
            "name": name,
            "path": path_match.group(1) if path_match else name,
            "exceptions": exceptions.group(1) if exceptions else None,
        }
    return groups


def parse_targets(project: str) -> dict[str, list[str]]:
    targets: dict[str, list[str]] = {}
    for match in TARGET_BLOCK.finditer(project):
        _, name, body = match.groups()
        sync_match = re.search(
            r"fileSystemSynchronizedGroups = \((.*?)\);", body, re.DOTALL
        )
        groups = (
            re.findall(r"([A-F0-9]{24}) /\* .*? \*/", sync_match.group(1))
            if sync_match
            else []
        )
        targets[name] = groups
    return targets


def parse_exception_sets(project: str) -> dict[str, dict[str, object]]:
    sets: dict[str, dict[str, object]] = {}
    for match in EXCEPTION_SET.finditer(project):
        set_id, body = match.groups()
        members = re.search(r"membershipExceptions = \((.*?)\);", body, re.DOTALL)
        target = re.search(r"target = ([A-F0-9]{24})", body)
        sets[set_id] = {
            "members": re.findall(r'"?([^/*,\n]+?)"?,', members.group(1))
            if members
            else [],
            "target": target.group(1) if target else None,
        }
    return sets


def spm_test_target_paths(manifest: Path) -> dict[str, str]:
    source = manifest.read_text(encoding="utf-8")
    paths: dict[str, str] = {}
    for name_match in TEST_TARGET_NAME.finditer(source):
        name = name_match.group(1)
        depth = 0
        start = source.index("(", name_match.start())
        index = start
        for index in range(start, len(source)):
            if source[index] == "(":
                depth += 1
            elif source[index] == ")":
                depth -= 1
                if depth == 0:
                    break
        body = source[start:index]
        path_match = re.search(r'path:\s*"([^"]+)"', body)
        paths[name] = path_match.group(1) if path_match else f"Tests/{name}"
    return paths


def main() -> int:
    harness_map = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    project = PROJECT_FILE.read_text(encoding="utf-8")
    groups = parse_groups(project)
    targets = parse_targets(project)
    exception_sets = parse_exception_sets(project)
    target_names = {
        group_id: target_name
        for target_name, group_ids in targets.items()
        for group_id in group_ids
    }

    failures: list[str] = []
    directories = harness_map["directories"]
    harnesses = harness_map["harnesses"]

    for directory, spec in directories.items():
        path = REPOSITORY_ROOT / directory
        if not path.is_dir():
            failures.append(
                f"{RULE}: {directory}: mapped directory does not exist"
            )
            continue
        declared = set(spec.get("harnesses", []))
        for harness in declared:
            kind = harnesses[harness]["kind"]
            if kind == "xcode":
                group_id = next(
                    (
                        group_id
                        for group_id, group in groups.items()
                        if group["path"] == directory
                        and target_names.get(group_id) == harness
                    ),
                    None,
                )
                if group_id is None:
                    failures.append(
                        f"{RULE}: {directory}: not synced into Xcode target "
                        f"{harness}"
                    )
                    continue
                excluded = spec.get("excludedFromMembership", [])
                if excluded:
                    set_id = groups[group_id]["exceptions"]
                    members = (
                        [m.strip().strip('"') for m in exception_sets[set_id]["members"]]
                        if set_id in exception_sets
                        else []
                    )
                    for entry in excluded:
                        if entry not in members:
                            failures.append(
                                f"{RULE}: {directory}: {entry} is declared "
                                f"excluded but missing from the exception set "
                                f"of target {harness}"
                            )
            elif kind == "swiftpm":
                package = harnesses[harness]["package"]
                manifest = PACKAGE_MANIFESTS[package]
                package_root = manifest.parent.relative_to(REPOSITORY_ROOT)
                target_paths = spm_test_target_paths(manifest)
                declared_path = target_paths.get(harness)
                resolved = (
                    str(package_root / declared_path) if declared_path else None
                )
                if resolved != directory:
                    failures.append(
                        f"{RULE}: {directory}: no testTarget {harness} with "
                        f"matching path in {manifest.relative_to(REPOSITORY_ROOT)} "
                        f"(found {resolved!r})"
                    )
            elif kind == "tooling":
                continue
            else:
                failures.append(f"{RULE}: {harness}: unknown harness kind {kind}")

    for group_id, group in groups.items():
        group_path = str(group["path"])
        target_name = target_names.get(group_id)
        if target_name is None:
            continue
        target_is_test = target_name.endswith("Tests") or "Test" in target_name
        path_is_test = "Tests" in group_path.split("/") or "Tests" in Path(
            group_path
        ).parts
        if not (target_is_test and path_is_test):
            continue
        spec = directories.get(group_path)
        if spec is None:
            failures.append(
                f"{RULE}: {group_path}: synced into {target_name} but absent "
                "from Config/test_harness_map.json"
            )
        elif target_name not in spec.get("harnesses", []):
            failures.append(
                f"{RULE}: {group_path}: synced into {target_name} but the map "
                f"declares only {spec.get('harnesses')}"
            )

    if failures:
        for line in failures:
            print(f"error: {line}", file=sys.stderr)
        return 1
    print(
        f"test harness map verified: {len(directories)} directories, "
        f"{len(harnesses)} harnesses consistent"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
