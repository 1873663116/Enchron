#!/usr/bin/env python3
"""Rebuild the String Catalog from the strings the Swift compiler emits.

User-facing text is written as SwiftUI string literals all over Apps/Enchron and
the five SPM packages under Modules/. The compiler emits one .stringsdata per
compiled file when SWIFT_EMIT_LOC_STRINGS is on, carrying the key and the source
location. That emission is the only extraction path that is type-aware — it
resolves `\\(count) items` to the key `%lld items`, and it sees literals passed
to LocalizedStringKey parameters, which string-literal scanning cannot.

The project sets SWIFT_EMIT_LOC_STRINGS only on the app target, so the build here
passes it on the command line, which does reach the package targets.

usage:
    extract_strings.py                build, then rewrite the catalog
    extract_strings.py --no-build     rewrite from the last build's output
    extract_strings.py --check        report drift, exit 1 when stale
    extract_strings.py --prune        also drop keys no longer in sources
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

CATALOG_PATH = "Apps/Enchron/Resources/Localizable.xcstrings"
RULES_PATH = "Scripts/localization/rules.json"
DERIVED_DATA = ".scratch/derived-data"
INTERMEDIATES = "Build/Intermediates.noindex"
EMITTING_TARGETS = ("Enchron.build", "EnchronModules.build")
SOURCE_ROOTS = ("Apps/Enchron", "Modules")
DESTINATION = "platform=visionOS Simulator,name=Apple Vision Pro"

_LANGUAGE_CHARACTER = re.compile(r"[A-Za-z]")
_SPECIFIER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|f|s|%)")
_OUR_COMMENT = re.compile(r"^[^\s:]+\.swift:\d+$")
_PREVIEW_MACRO = re.compile(r"#Preview\b")
_SKIPPED_ARTIFACTS = {"ExtractedAppShortcutsMetadata"}


@dataclass(frozen=True)
class ExtractedString:
    source: str
    key: str
    line: int
    column: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--derived-data", type=Path)
    parser.add_argument("--no-build", action="store_true", help="reuse the last build")
    parser.add_argument("--check", action="store_true", help="report drift without writing")
    parser.add_argument("--prune", action="store_true", help="delete keys no longer in sources")
    parser.add_argument("--report", type=Path, help="write the extracted inventory here")
    return parser.parse_args()


def load_rules(root: Path) -> dict:
    return json.loads((root / RULES_PATH).read_text(encoding="utf-8"))


def build(root: Path, derived_data: Path) -> None:
    result = subprocess.run(
        [
            "xcodebuild",
            "-project", "Enchron.xcodeproj",
            "-scheme", "Enchron",
            "-destination", DESTINATION,
            "-derivedDataPath", str(derived_data),
            "SWIFT_EMIT_LOC_STRINGS=YES",
            "build",
        ],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        failures = [line for line in result.stdout.splitlines() if "error:" in line]
        raise SystemExit("\n".join(failures[:20]) or result.stdout[-4000:])


def read_stringsdata(root: Path, derived_data: Path) -> list[ExtractedString]:
    found: list[ExtractedString] = []
    for target in EMITTING_TARGETS:
        for path in sorted((derived_data / INTERMEDIATES / target).rglob("*.stringsdata")):
            if path.stem in _SKIPPED_ARTIFACTS:
                continue
            payload = json.loads(path.read_text(encoding="utf-8"))
            source = Path(payload["source"])
            if not source.exists():
                continue
            relative = source.relative_to(root).as_posix()
            for entries in payload.get("tables", {}).values():
                for entry in entries:
                    location = entry.get("location", {})
                    found.append(
                        ExtractedString(
                            source=relative,
                            key=entry["key"],
                            line=int(location.get("startingLine", 0)),
                            column=int(location.get("startingColumn", 0)),
                        )
                    )
    return found


def has_natural_language(key: str) -> bool:
    return _LANGUAGE_CHARACTER.search(_SPECIFIER.sub("", key)) is not None


def preview_line_ranges(path: Path) -> list[tuple[int, int]]:
    """Line ranges covered by #Preview macros, which never render in the app."""
    source = path.read_text(encoding="utf-8")
    ranges: list[tuple[int, int]] = []
    for match in _PREVIEW_MACRO.finditer(source):
        opening = source.find("{", match.end())
        if opening < 0:
            continue
        depth = 0
        cursor = opening
        while cursor < len(source):
            if source[cursor] == "{":
                depth += 1
            elif source[cursor] == "}":
                depth -= 1
                if depth == 0:
                    break
            cursor += 1
        ranges.append((source[:opening].count("\n") + 1, source[:cursor].count("\n") + 1))
    return ranges


def select(extracted: list[ExtractedString], root: Path, rules: dict) -> tuple[list, list]:
    excluded_files = set(rules["excludedFiles"])
    excluded_keys = set(rules["excludedKeys"])
    previews: dict[str, list[tuple[int, int]]] = {}
    kept: list[ExtractedString] = []
    skipped: list[ExtractedString] = []
    for entry in extracted:
        if not entry.source.startswith(SOURCE_ROOTS):
            skipped.append(entry)
            continue
        if entry.source in excluded_files or entry.key in excluded_keys:
            skipped.append(entry)
            continue
        if not has_natural_language(entry.key):
            skipped.append(entry)
            continue
        if entry.source not in previews:
            path = root / entry.source
            previews[entry.source] = preview_line_ranges(path) if path.exists() else []
        if any(start <= entry.line <= end for start, end in previews[entry.source]):
            skipped.append(entry)
            continue
        kept.append(entry)
    return kept, skipped


def load_catalog(path: Path) -> dict:
    if not path.exists():
        return {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    return json.loads(path.read_text(encoding="utf-8"))


def merge(catalog: dict, entries: list[ExtractedString], prune: bool) -> tuple[list[str], list[str]]:
    strings = catalog.setdefault("strings", {})
    added: list[str] = []
    removed: list[str] = []
    for entry in sorted(entries, key=lambda item: item.key):
        comment = f"{entry.source}:{entry.line}"
        existing = strings.get(entry.key)
        if existing is None:
            strings[entry.key] = {"comment": comment, "extractionState": "extracted"}
            added.append(entry.key)
            continue
        existing.pop("extractionState", None)
        if _OUR_COMMENT.match(existing.get("comment") or ""):
            existing["comment"] = comment
    live = {entry.key for entry in entries}
    for key in sorted(set(strings) - live):
        if prune:
            del strings[key]
            removed.append(key)
        else:
            strings[key]["extractionState"] = "stale"
    catalog["strings"] = {key: strings[key] for key in sorted(strings)}
    return added, removed


def write_catalog(path: Path, catalog: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    derived_data = (args.derived_data or (root / DERIVED_DATA)).resolve()
    rules = load_rules(root)
    catalog_path = root / CATALOG_PATH

    if not args.no_build:
        build(root, derived_data)

    extracted = read_stringsdata(root, derived_data)
    if not extracted:
        raise SystemExit(f"no stringsdata under {derived_data}; run without --no-build")

    entries, skipped = select(extracted, root, rules)
    catalog = load_catalog(catalog_path)
    added, removed = merge(catalog, entries, prune=args.prune)

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            "\n".join(
                f"{entry.source}:{entry.line}\t{entry.key}"
                for entry in sorted(entries, key=lambda item: (item.source, item.line))
            ) + "\n",
            encoding="utf-8",
        )

    distinct = len({entry.key for entry in entries})
    print(f"{'would add' if args.check else 'added'} {len(added)} keys, {len(catalog['strings'])} total")
    print(f"{distinct} distinct keys across {len(entries)} sites; skipped {len(skipped)}")
    if removed:
        print(f"pruned {len(removed)} keys")

    if args.check:
        for key in added[:20]:
            print(f"  + {key}")
        return 1 if added else 0

    write_catalog(catalog_path, catalog)
    print(f"wrote {catalog_path.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
