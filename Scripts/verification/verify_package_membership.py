#!/usr/bin/env python3

import json
import os
from pathlib import Path
import re
import subprocess
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROJECT_FILE = REPOSITORY_ROOT / "Enchron.xcodeproj" / "project.pbxproj"
DESIGN_SOURCE_ARCHITECTURE_CHECKER = (
    REPOSITORY_ROOT / "Scripts" / "verification" / "verify_design_source_architecture.py"
)
APP_EXCEPTION_ID = "E10000162FA1000100E1C001"
PRODUCT_TARGETS = {
    "MediaSource",
    "MediaLibrary",
    "PlaybackFeature",
    "PlaybackPresentation",
    "DesignSystem",
}
PLAYBACK_PRESENTATION_ALLOWED_IMPORTS = {
    "CoreGraphics",
    "Foundation",
    "Observation",
    "PlaybackFeature",
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
    ("import Foundation", "Foundation", True),
    ("import Observation", "Observation", True),
    ("@testable import PlaybackFeature", "PlaybackFeature", True),
    ("@preconcurrency import RealityKit", "RealityKit", False),
    ("@_implementationOnly import AVFoundation", "AVFoundation", False),
    ("@_exported import PlaybackCore", "PlaybackCore", False),
    ("public import SwiftUI", "SwiftUI", False),
    ("package import struct CoreGraphics.CGPoint", "CoreGraphics", True),
    ("@_spi(Internal)\nprivate import class RealityKit.Entity", "RealityKit", False),
)


def package_description() -> dict:
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = "/tmp/ench-clang-module-cache"
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = "/tmp/ench-swiftpm-module-cache"
    result = subprocess.run(
        ["swift", "package", "describe", "--type", "json"],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def package_module_sources(description: dict) -> set[str]:
    sources: set[str] = set()
    for target in description["targets"]:
        if target["name"] not in PRODUCT_TARGETS:
            continue
        target_path = Path(target["path"])
        modules_root = REPOSITORY_ROOT / "Modules" if target_path.is_absolute() else Path("Modules")
        relative_target_path = target_path.relative_to(modules_root)
        for source in target["sources"]:
            sources.add((relative_target_path / source).as_posix())
    return sources


def app_membership_exceptions() -> set[str]:
    project = PROJECT_FILE.read_text()
    block_match = re.search(
        rf"{APP_EXCEPTION_ID}.*?membershipExceptions = \((.*?)\);\s*target =",
        project,
        flags=re.DOTALL,
    )
    if block_match is None:
        raise RuntimeError("Enchron Modules membership exception block is missing")
    entries = set()
    for raw_line in block_match.group(1).splitlines():
        value = raw_line.strip().removesuffix(",").strip('"')
        if value:
            entries.add(value)
    return entries


def target_sources(description: dict, target_name: str) -> list[Path]:
    for target in description["targets"]:
        if target["name"] != target_name:
            continue
        target_path = Path(target["path"])
        target_root = target_path if target_path.is_absolute() else REPOSITORY_ROOT / target_path
        return [target_root / source for source in target["sources"]]
    raise RuntimeError(f"Swift package target is missing: {target_name}")


def swift_import_modules(source: str) -> list[str]:
    return [match.group("module") for match in SWIFT_IMPORT_PATTERN.finditer(source)]


def verify_import_parser() -> None:
    for declaration, expected_module, expected_allowed in IMPORT_PARSER_SELF_CHECKS:
        modules = swift_import_modules(declaration)
        if modules != [expected_module]:
            raise RuntimeError(
                f"Swift import parser did not recognize {declaration!r}: {modules!r}"
            )
        if (expected_module in PLAYBACK_PRESENTATION_ALLOWED_IMPORTS) != expected_allowed:
            raise RuntimeError(
                f"Swift import allowlist self-check has an unexpected result for {declaration!r}"
            )

    ignored = swift_import_modules('// import RealityKit\nlet importToken = "AVFoundation"')
    if ignored:
        raise RuntimeError(f"Swift import parser matched non-import text: {ignored!r}")


def playback_presentation_import_violations(description: dict) -> list[tuple[Path, str]]:
    violations: list[tuple[Path, str]] = []
    for source in target_sources(description, "PlaybackPresentation"):
        for module in swift_import_modules(source.read_text()):
            if module not in PLAYBACK_PRESENTATION_ALLOWED_IMPORTS:
                violations.append((source.relative_to(REPOSITORY_ROOT), module))
    return violations


def main() -> int:
    design_check = subprocess.run(
        [sys.executable, str(DESIGN_SOURCE_ARCHITECTURE_CHECKER)],
        cwd=REPOSITORY_ROOT,
    )
    if design_check.returncode != 0:
        return design_check.returncode

    verify_import_parser()
    description = package_description()
    package_sources = package_module_sources(description)
    exceptions = app_membership_exceptions()
    missing = sorted(package_sources - exceptions)
    stale = sorted(exceptions - package_sources)
    import_violations = playback_presentation_import_violations(description)
    if missing or stale or import_violations:
        if missing:
            print("Package sources still compiled directly by Enchron:", file=sys.stderr)
            for path in missing:
                print(f"  {path}", file=sys.stderr)
        if stale:
            print("Stale Enchron package-source exceptions:", file=sys.stderr)
            for path in stale:
                print(f"  {path}", file=sys.stderr)
        if import_violations:
            print("PlaybackPresentation imports outside its allowlist:", file=sys.stderr)
            for path, module in import_violations:
                print(f"  {path}: {module}", file=sys.stderr)
        return 1
    print(f"Enchron excludes all {len(package_sources)} package-owned Swift sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
