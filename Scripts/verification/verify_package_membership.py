#!/usr/bin/env python3

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


DEFAULT_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DESIGN_SOURCE_ARCHITECTURE_CHECKER = (
    DEFAULT_REPOSITORY_ROOT
    / "Scripts"
    / "verification"
    / "verify_design_source_architecture.py"
)
APP_EXCEPTION_ID = "E10000162FA1000100E1C001"
DESIGN_PREVIEW_EXCEPTION_ID = "C3A35AC72F85434200DA0D16"
APP_LAYER_DIRECTORY = "Apps/Enchron"
PRODUCT_TARGETS = {
    "Emby",
    "MediaSource",
    "MediaLibrary",
    "Playback",
    "DesignSystem",
}
PLAYBACK_FORBIDDEN_IMPORTS = {
    "Emby",
    "MediaLibrary",
}
MODULE_SOURCE_DIRECTORIES = {
    "Playback": "Playback",
    "MediaLibrary": "MediaLibrary",
}
SWIFT_IMPORT_PATTERN = re.compile(
    r"""
    ^[ \t]*
    (?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n)]*\))?|public|internal|package|private|fileprivate|open)[ \t\r\n]+)*
    import[ \t]+
    (?:(?:typealias|struct|class|enum|protocol|let|var|func)[ \t]+)?
    (?P<module>[A-Za-z_][A-Za-z0-9_]*)
    (?:\.[A-Za-z_][A-Za-z0-9_]*)*
    """,
    flags=re.MULTILINE | re.VERBOSE,
)

IMPORT_PARSER_SELF_CHECKS = (
    ("import Foundation", "Foundation", False),
    ("import Observation", "Observation", False),
    ("@testable import Playback", "Playback", False),
    ("@preconcurrency import RealityKit", "RealityKit", False),
    ("@_implementationOnly import AVFoundation", "AVFoundation", False),
    ("@_exported import PlaybackCore", "PlaybackCore", False),
    ("public import SwiftUI", "SwiftUI", False),
    ("package import struct CoreGraphics.CGPoint", "CoreGraphics", False),
    ("@_spi(Internal)\nprivate import class RealityKit.Entity", "RealityKit", False),
    ("import Emby", "Emby", True),
    ("import MediaLibrary", "MediaLibrary", True),
)

SWIFT_COMMENT_OR_STRING_PATTERN = re.compile(
    "|".join(
        (
            r'#+"""(?:.|\n)*?"""#+',
            r'"""(?:.|\n)*?"""',
            r'#+"(?:.|\n)*?"#+',
            r'"(?:\\.|[^"\\\n])*"',
            r"//[^\n]*",
            r"/\*(?:.|\n)*?\*/",
        )
    )
)
SWIFT_INTERPOLATION_OPENING = re.compile(r"\\#*\(")

SWIFT_TOP_LEVEL_TYPE_PATTERN = re.compile(
    r"""
    ^
    (?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n)]*\))?|public|internal|package|private|fileprivate|open|final|indirect)[ \t]+)*
    (?:struct|class|enum|actor|protocol|typealias)[ \t]+
    (?P<name>[A-Za-z_][A-Za-z0-9_]*)
    """,
    flags=re.MULTILINE | re.VERBOSE,
)

APP_LAYER_REFERENCE_SELF_CHECKS = (
    ("AppModel.recordProbe(fact)", {"AppModel"}),
    ('let fact = "probe \\(AppModel.identity) done"', {"AppModel"}),
    ("state.appModelling()", set()),
    ('accessibilityIdentifier("FileBrowsing-FilesScreen-sort")', set()),
    ("// AppModel owns this fact", set()),
    ("/* FilesScreen composes it */", set()),
    ('let heading = """\nFilesScreen\n"""', set()),
)


def package_description(repository_root: Path) -> dict:
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = "/tmp/ench-clang-module-cache"
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = "/tmp/ench-swiftpm-module-cache"
    result = subprocess.run(
        ["swift", "package", "describe", "--type", "json"],
        cwd=repository_root,
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def package_module_sources(description: dict, repository_root: Path) -> set[str]:
    sources: set[str] = set()
    for target in description["targets"]:
        if target["name"] not in PRODUCT_TARGETS:
            continue
        target_path = Path(target["path"])
        modules_root = repository_root / "Modules" if target_path.is_absolute() else Path("Modules")
        relative_target_path = target_path.relative_to(modules_root)
        for source in target["sources"]:
            sources.add((relative_target_path / source).as_posix())
    return sources


def membership_exceptions(repository_root: Path, exception_id: str) -> set[str]:
    project = (repository_root / "Enchron.xcodeproj" / "project.pbxproj").read_text()
    block_match = re.search(
        rf"{exception_id}.*?membershipExceptions = \((.*?)\);\s*target =",
        project,
        flags=re.DOTALL,
    )
    if block_match is None:
        raise RuntimeError(
            f"Modules membership exception block is missing: {exception_id}"
        )
    entries = set()
    for raw_line in block_match.group(1).splitlines():
        value = raw_line.strip().removesuffix(",").strip('"')
        if value:
            entries.add(value)
    return entries


def target_sources(
    description: dict,
    target_name: str,
    repository_root: Path,
) -> list[Path]:
    for target in description["targets"]:
        if target["name"] != target_name:
            continue
        target_path = Path(target["path"])
        target_root = target_path if target_path.is_absolute() else repository_root / target_path
        return [target_root / source for source in target["sources"]]
    raise RuntimeError(f"Swift package target is missing: {target_name}")


def swift_import_modules(source: str) -> list[str]:
    return [match.group("module") for match in SWIFT_IMPORT_PATTERN.finditer(source)]


def verify_import_parser() -> None:
    for declaration, expected_module, expected_forbidden in IMPORT_PARSER_SELF_CHECKS:
        modules = swift_import_modules(declaration)
        if modules != [expected_module]:
            raise RuntimeError(
                f"Swift import parser did not recognize {declaration!r}: {modules!r}"
            )
        if (expected_module in PLAYBACK_FORBIDDEN_IMPORTS) != expected_forbidden:
            raise RuntimeError(
                f"Swift import denylist self-check has an unexpected result for {declaration!r}"
            )

    ignored = swift_import_modules('// import RealityKit\nlet importToken = "AVFoundation"')
    if ignored:
        raise RuntimeError(f"Swift import parser matched non-import text: {ignored!r}")


def blanked_comment_or_string(match: re.Match[str]) -> str:
    text = match.group()
    if text.startswith("/"):
        return "".join(character if character == "\n" else " " for character in text)

    blanked: list[str] = []
    index = 0
    while index < len(text):
        opening = SWIFT_INTERPOLATION_OPENING.match(text, index)
        if opening is None:
            blanked.append(text[index] if text[index] == "\n" else " ")
            index += 1
            continue
        blanked.append(" " * (opening.end() - index))
        index = opening.end()
        depth = 1
        while index < len(text):
            character = text[index]
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    blanked.append(" ")
                    index += 1
                    break
            blanked.append(character)
            index += 1
    return "".join(blanked)


def swift_code_without_comments_or_strings(source: str) -> str:
    return SWIFT_COMMENT_OR_STRING_PATTERN.sub(blanked_comment_or_string, source)


def app_layer_type_names(repository_root: Path) -> set[str]:
    names: set[str] = set()
    for path in sorted((repository_root / APP_LAYER_DIRECTORY).rglob("*.swift")):
        code = swift_code_without_comments_or_strings(path.read_text())
        names.update(
            match.group("name")
            for match in SWIFT_TOP_LEVEL_TYPE_PATTERN.finditer(code)
        )
    return names


def app_layer_type_references(source: str, names: set[str]) -> set[str]:
    code = swift_code_without_comments_or_strings(source)
    return {name for name in names if re.search(rf"\b{name}\b", code)}


def verify_app_layer_reference_parser() -> None:
    names = {"AppModel", "FilesScreen"}
    for snippet, expected in APP_LAYER_REFERENCE_SELF_CHECKS:
        found = app_layer_type_references(snippet, names)
        if found != expected:
            raise RuntimeError(
                f"Swift App-layer reference parser misread {snippet!r}: {sorted(found)}"
            )


def design_preview_app_layer_references(
    repository_root: Path,
) -> list[tuple[str, str]]:
    names = app_layer_type_names(repository_root)
    references: list[tuple[str, str]] = []
    for entry in sorted(
        membership_exceptions(repository_root, DESIGN_PREVIEW_EXCEPTION_ID)
    ):
        source = (repository_root / "Modules" / entry).read_text()
        references += [
            (f"Modules/{entry}", name)
            for name in sorted(app_layer_type_references(source, names))
        ]
    return references


def playback_import_violations(
    description: dict,
    repository_root: Path,
) -> list[tuple[Path, str]]:
    violations: list[tuple[Path, str]] = []
    for source in target_sources(description, "Playback", repository_root):
        if source.suffix != ".swift":
            continue
        for module in swift_import_modules(source.read_text()):
            if module in PLAYBACK_FORBIDDEN_IMPORTS:
                violations.append((source.relative_to(repository_root), module))
    return violations


def playback_app_layer_references(
    description: dict,
    repository_root: Path,
) -> list[tuple[Path, str]]:
    names = app_layer_type_names(repository_root)
    references: list[tuple[Path, str]] = []
    for source in target_sources(description, "Playback", repository_root):
        if source.suffix != ".swift":
            continue
        found = app_layer_type_references(source.read_text(), names)
        references += [
            (source.relative_to(repository_root), name) for name in sorted(found)
        ]
    return references


def module_excluded_sources(
    description: dict,
    repository_root: Path,
) -> list[str]:
    missing = []
    for target, directory in MODULE_SOURCE_DIRECTORIES.items():
        root = repository_root / "Modules" / directory
        if not root.is_dir():
            missing.append(f"{directory} (source directory is absent)")
            continue
        compiled = {
            path.relative_to(repository_root / "Modules").as_posix()
            for path in target_sources(description, target, repository_root)
        }
        expected = {
            path.relative_to(repository_root / "Modules").as_posix()
            for path in root.rglob("*.swift")
        }
        missing.extend(sorted(expected - compiled))
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify Swift Package and Enchron Xcode target source ownership."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=DEFAULT_REPOSITORY_ROOT,
        help="repository root to inspect",
    )
    arguments = parser.parse_args()
    repository_root = arguments.root.resolve()

    design_check = subprocess.run(
        [
            sys.executable,
            str(DESIGN_SOURCE_ARCHITECTURE_CHECKER),
            "--root",
            str(repository_root),
        ],
        cwd=repository_root,
    )
    if design_check.returncode != 0:
        return design_check.returncode

    verify_app_layer_reference_parser()
    app_layer_references = design_preview_app_layer_references(repository_root)
    if app_layer_references:
        print(
            "Modules sources in DesignPreview that reference Apps/Enchron types:",
            file=sys.stderr,
        )
        for path, name in app_layer_references:
            print(f"  {path}: {name}", file=sys.stderr)
        return 1

    verify_import_parser()
    description = package_description(repository_root)
    package_sources = package_module_sources(description, repository_root)
    exceptions = membership_exceptions(repository_root, APP_EXCEPTION_ID)
    missing = sorted(package_sources - exceptions)
    stale = sorted(exceptions - package_sources)
    import_violations = playback_import_violations(description, repository_root)
    playback_app_references = playback_app_layer_references(
        description,
        repository_root,
    )
    excluded_module_sources = module_excluded_sources(description, repository_root)
    if missing or stale or import_violations or playback_app_references or excluded_module_sources:
        if missing:
            print("Package sources still compiled directly by Enchron:", file=sys.stderr)
            for path in missing:
                print(f"  {path}", file=sys.stderr)
        if stale:
            print("Stale Enchron package-source exceptions:", file=sys.stderr)
            for path in stale:
                print(f"  {path}", file=sys.stderr)
        if import_violations:
            print("Playback imports inside its denylist:", file=sys.stderr)
            for path, module in import_violations:
                print(f"  {path}: {module}", file=sys.stderr)
        if playback_app_references:
            print("Playback sources that reference Apps/Enchron types:", file=sys.stderr)
            for path, name in playback_app_references:
                print(f"  {path}: {name}", file=sys.stderr)
        if excluded_module_sources:
            print("Module sources excluded from their own target:", file=sys.stderr)
            for path in excluded_module_sources:
                print(f"  {path}", file=sys.stderr)
        return 1
    print(f"Enchron excludes all {len(package_sources)} package-owned Swift sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
