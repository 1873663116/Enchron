#!/usr/bin/env python3
"""Check that every language in the catalogs is complete and actually ships.

A language can be present in the catalog yet missing from the built app: a key
added after a translation pass leaves that one string English, and a catalog
language that never made it into the bundle leaves the whole language English.
Both are silent at runtime, so they are asserted here.

The language set comes from rules.json, not from the keys currently present:
deleting one language from every entry must fail instead of shrinking the check.
Entries marked shouldTranslate=false are product names and stay untranslated.

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
RULES_PATH = "Scripts/localization/rules.json"
SOURCE_LANGUAGE = "en"
_SPECIFIER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|lu|llu|d|f|s|u|%)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--app", type=Path, help="built .app to check the shipped tables")
    parser.add_argument("--allow-missing", nargs="*", default=[],
                        help="keys knowingly left untranslated")
    return parser.parse_args()


def load_rules(root: Path) -> dict:
    return json.loads((root / RULES_PATH).read_text(encoding="utf-8"))


def target_languages(rules: dict) -> list[str]:
    languages = list(rules.get("languages") or [])
    if not languages:
        raise SystemExit(f"{RULES_PATH} declares no target languages")
    if SOURCE_LANGUAGE in languages:
        raise SystemExit(f"{RULES_PATH} must not list the source language {SOURCE_LANGUAGE}")
    return languages


def translatable(entry: dict) -> bool:
    return entry.get("shouldTranslate") is not False


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


def fix_hint(key: str) -> str:
    return (
        f"  {key[:90]}\n"
        f"    translate it, or mark it as a product name:\n"
        f"    python3 Scripts/localization/translations.py dont-translate"
        f' --key {json.dumps(key, ensure_ascii=False)} --reason "product name"'
    )


def check_catalog(root: Path, allow_missing: set[str], languages: list[str]) -> int:
    failures = 0
    for relative in CATALOGS:
        path = root / relative
        if not path.exists():
            print(f"missing catalog: {relative}", file=sys.stderr)
            failures += 1
            continue
        catalog = json.loads(path.read_text(encoding="utf-8"))
        strings = catalog["strings"]
        declared = {
            language
            for entry in strings.values()
            for language in entry.get("localizations", {})
            if language != SOURCE_LANGUAGE
        }
        unsupported = sorted(declared - set(languages))
        if unsupported:
            failures += 1
            print(
                f"{relative}: languages missing from {RULES_PATH}: {', '.join(unsupported)}",
                file=sys.stderr,
            )
        fixed = sum(1 for entry in strings.values() if not translatable(entry))
        print(f"{relative}: {len(strings)} keys, {fixed} not translated, languages {languages}")
        for language in languages:
            missing = [
                key
                for key, entry in strings.items()
                if translatable(entry)
                and not translated(entry, language)
                and key not in allow_missing
            ]
            if missing:
                failures += 1
                print(f"  {language}: {len(missing)} untranslated", file=sys.stderr)
                for key in missing[:20]:
                    print(fix_hint(key), file=sys.stderr)
                if len(missing) > 20:
                    print(f"  ... {len(missing) - 20} more", file=sys.stderr)
            for key, entry in strings.items():
                if not translatable(entry) or key in allow_missing:
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


def check_bundle(app: Path, root: Path, allow_missing: set[str], languages: list[str]) -> int:
    failures = 0
    catalogs: dict[str, dict] = {}
    for relative in CATALOGS:
        catalog = json.loads((root / relative).read_text(encoding="utf-8"))
        catalogs[Path(relative).name.replace(".xcstrings", ".strings")] = catalog
    for language in languages:
        directory = app / f"{language}.lproj"
        for table, catalog in sorted(catalogs.items()):
            path = directory / table
            if not path.exists():
                print(f"not shipped: {language}.lproj/{table}", file=sys.stderr)
                failures += 1
                continue
            shipped = plistlib.loads(path.read_bytes())
            dictionary = path.with_suffix(".stringsdict")
            if dictionary.exists():
                shipped.update(plistlib.loads(dictionary.read_bytes()))
            wanted = {
                key
                for key, entry in catalog["strings"].items()
                if translatable(entry) and translated(entry, language) and key not in allow_missing
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
    rules = load_rules(root)
    languages = target_languages(rules)
    allow_missing = set(args.allow_missing)
    failures = check_catalog(root, allow_missing, languages)
    if args.app:
        failures += check_bundle(args.app, root, allow_missing, languages)
    if failures:
        print(f"\n{failures} problem(s)", file=sys.stderr)
        print(
            "Translations enter the catalog through "
            "Scripts/localization/translations.py. "
            "Product names stay as they are with shouldTranslate=false.",
            file=sys.stderr,
        )
        return 1
    print("\nall languages complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
