#!/usr/bin/env python3
"""Check that every language in the catalogs is complete and actually ships.

A language can be present in the catalog yet missing from the built app: a key
added after a translation pass leaves that one string English, and a catalog
language that never made it into the bundle leaves the whole language English.
Both are silent at runtime, so they are asserted here.

usage:
    locale_coverage.py                       check the catalog only
    locale_coverage.py --app path/to/Enchron.app    also check the built bundle
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import plistlib
import re
import sys
from pathlib import Path

CATALOGS = (
    "Apps/Enchron/Resources/Localizable.xcstrings",
    "Apps/Enchron/Resources/InfoPlist.xcstrings",
)
SOURCE_LANGUAGE = "en"
_SPECIFIER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|f|s)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--app", type=Path, help="built .app to check the shipped tables")
    parser.add_argument("--allow-missing", nargs="*", default=[],
                        help="keys knowingly left untranslated")
    return parser.parse_args()


def translated(entry: dict, language: str) -> bool:
    value = entry.get("localizations", {}).get(language)
    if not value:
        return False
    if "stringUnit" in value:
        return bool(value["stringUnit"].get("value"))
    if "variations" in value:
        return all(
            unit.get("stringUnit", {}).get("value")
            for unit in value["variations"].get("plural", {}).values()
        )
    return False


def values(entry: dict, language: str) -> list[str]:
    """Every translated string for a language, one per plural form."""
    localization = entry.get("localizations", {}).get(language)
    if not localization:
        return []
    if "stringUnit" in localization:
        return [localization["stringUnit"].get("value", "")]
    return [
        unit.get("stringUnit", {}).get("value", "")
        for unit in localization.get("variations", {}).get("plural", {}).values()
    ]


def placeholders(text: str) -> dict[str, int]:
    return Counter(_SPECIFIER.findall(text))


def check_catalog(root: Path, allow_missing: set[str]) -> int:
    failures = 0
    for relative in CATALOGS:
        path = root / relative
        if not path.exists():
            print(f"missing catalog: {relative}", file=sys.stderr)
            failures += 1
            continue
        catalog = json.loads(path.read_text(encoding="utf-8"))
        strings = catalog["strings"]
        languages = sorted({
            language
            for entry in strings.values()
            for language in entry.get("localizations", {})
            if language != SOURCE_LANGUAGE
        })
        print(f"{relative}: {len(strings)} keys, languages {languages or '(none)'}")
        for language in languages:
            missing = [
                key for key, entry in strings.items()
                if not translated(entry, language) and key not in allow_missing
            ]
            if missing:
                failures += 1
                print(f"  {language}: {len(missing)} untranslated", file=sys.stderr)
                for key in missing[:10]:
                    print(f"    {key[:90]}", file=sys.stderr)
            for key, entry in strings.items():
                if key in allow_missing:
                    continue
                expected = placeholders(key)
                for value in values(entry, language):
                    if placeholders(value) != expected:
                        failures += 1
                        print(
                            f"  {language}: placeholder mismatch in {key[:60]!r}"
                            f" -> {value[:60]!r}",
                            file=sys.stderr,
                        )
    return failures


def check_bundle(app: Path, root: Path, allow_missing: set[str]) -> int:
    failures = 0
    expected: dict[str, set[str]] = {}
    for relative in CATALOGS:
        catalog = json.loads((root / relative).read_text(encoding="utf-8"))
        table = Path(relative).name.replace(".xcstrings", ".strings")
        for language in {
            language
            for entry in catalog["strings"].values()
            for language in entry.get("localizations", {})
            if language != SOURCE_LANGUAGE
        }:
            expected.setdefault(language, set()).add(table)
    for language, tables in sorted(expected.items()):
        directory = app / f"{language}.lproj"
        for table in sorted(tables):
            path = directory / table
            if not path.exists():
                print(f"not shipped: {language}.lproj/{table}", file=sys.stderr)
                failures += 1
                continue
            shipped = plistlib.loads(path.read_bytes())
            dictionary = path.with_suffix(".stringsdict")
            if dictionary.exists():
                # Plural keys compile into a stringsdict, not into the strings table.
                shipped.update(plistlib.loads(dictionary.read_bytes()))
            catalog = json.loads(
                (root / next(r for r in CATALOGS if Path(r).name.replace(".xcstrings", ".strings") == table))
                .read_text(encoding="utf-8")
            )
            wanted = {
                key for key, entry in catalog["strings"].items()
                if translated(entry, language) and key not in allow_missing
            }
            absent = wanted - set(shipped)
            if absent:
                print(f"{language}.lproj/{table}: {len(absent)} translated keys absent", file=sys.stderr)
                for key in sorted(absent)[:5]:
                    print(f"    {key[:80]}", file=sys.stderr)
                failures += 1
            else:
                print(f"{language}.lproj/{table}: {len(shipped)} strings")
    return failures


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    allow_missing = set(args.allow_missing)
    failures = check_catalog(root, allow_missing)
    if args.app:
        failures += check_bundle(args.app, root, allow_missing)
    if failures:
        print(f"\n{failures} problem(s)", file=sys.stderr)
        return 1
    print("\nall languages complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
