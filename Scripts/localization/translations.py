#!/usr/bin/env python3
"""Move translations between the catalog and a per-language work file.

xcodebuild -exportLocalizations cannot be used here: it re-extracts strings per
target and rewrites the catalog with what it finds, which discards every key
that comes from the SPM packages. The catalog is therefore the source of truth
and this script is the only thing that writes translations into it.

usage:
    translations.py export --language zh-Hans --output work.json
    translations.py import --language zh-Hans --input work.json
    translations.py status
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CATALOG_PATH = "Apps/Enchron/Resources/Localizable.xcstrings"
INFO_PLIST_CATALOG_PATH = "Apps/Enchron/Resources/InfoPlist.xcstrings"
RULES_PATH = "Scripts/localization/rules.json"
GLOSSARY_PATH = "Scripts/localization/glossary.md"
_SPECIFIER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|f|s)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    sub = parser.add_subparsers(dest="command", required=True)

    export = sub.add_parser("export", help="write a work file for one language")
    export.add_argument("--language", required=True)
    export.add_argument("--output", type=Path, required=True)
    export.add_argument(
        "--include-translated",
        action="store_true",
        help="also list entries that already have a value, for a review pass",
    )

    import_ = sub.add_parser("import", help="merge translated values back in")
    import_.add_argument("--language", required=True)
    import_.add_argument("--input", type=Path, required=True)

    sub.add_parser("status", help="report how complete each language is")
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, payload: dict) -> None:
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def catalogs(root: Path) -> list[Path]:
    return [root / CATALOG_PATH, root / INFO_PLIST_CATALOG_PATH]


def source_text(entry: dict, key: str) -> str:
    """The English a translator reads. Info.plist keys carry it in the en entry."""
    unit = entry.get("localizations", {}).get("en", {}).get("stringUnit")
    return unit.get("value", key) if unit else key


def current_value(localization: dict):
    """The stored translation, shaped like what an import expects back."""
    if "stringUnit" in localization:
        return localization["stringUnit"].get("value", "")
    return {
        form: unit.get("stringUnit", {}).get("value", "")
        for form, unit in localization.get("variations", {}).get("plural", {}).items()
    }


def export(root: Path, language: str, output: Path, include_translated: bool) -> None:
    rules = load(root / RULES_PATH)
    plural_keys = set(rules.get("pluralKeys", []))
    entries = []
    for path in catalogs(root):
        catalog = load(path)
        for key, entry in catalog["strings"].items():
            existing = entry.get("localizations", {}).get(language)
            if existing and not include_translated:
                continue
            placeholders = _SPECIFIER.findall(key)
            item = {
                "key": key,
                "source": source_text(entry, key),
                "catalog": path.name,
                "context": entry.get("comment", ""),
            }
            if existing:
                item["current"] = current_value(existing)
            if placeholders:
                item["placeholders"] = placeholders
            if key in plural_keys:
                item["plural"] = True
            entries.append(item)
    entries.sort(key=lambda item: (item["catalog"], item["key"]))
    write(
        output,
        {
            "language": language,
            "instructions": [
                f"Read {GLOSSARY_PATH} before translating; its term renderings and punctuation rules are binding.",
                "Translate every entry. Return the same JSON shape with a top-level 'translations' object mapping key to the translated string.",
                "Keep every placeholder (%@, %lld) verbatim and in the same order.",
                "An entry marked \"plural\": true takes a count. Languages with number agreement (French, German) return {\"one\": \"…\", \"other\": \"…\"} for it; Chinese, Japanese and Korean return a plain string.",
                "Keys that are bare product names or protocol names stay as they are.",
                "An entry with a \"current\" field already has a translation; return it unchanged unless it is wrong.",
            ],
            "entries": entries,
        },
    )
    print(f"{len(entries)} entries for {language} -> {output}")


def normalize(value: str) -> str:
    """Trailing spaces before a line break are never deliberate in a UI string."""
    return "\n".join(line.rstrip() for line in value.split("\n"))


def import_(root: Path, language: str, input_: Path) -> None:
    payload = load(input_)
    translations = payload["translations"]
    paths = catalogs(root)
    loaded = {path: load(path) for path in paths}
    known = {key for catalog in loaded.values() for key in catalog["strings"]}

    written = 0
    for path, catalog in loaded.items():
        touched = False
        for key, value in translations.items():
            entry = catalog["strings"].get(key)
            if entry is None:
                continue
            if isinstance(value, dict):
                entry.setdefault("localizations", {})[language] = {
                    "variations": {
                        "plural": {
                            form: {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": normalize(text),
                                }
                            }
                            for form, text in value.items()
                        }
                    }
                }
            else:
                entry.setdefault("localizations", {})[language] = {
                    "stringUnit": {"state": "translated", "value": normalize(value)}
                }
            touched = True
            written += 1
        if touched:
            write(path, catalog)

    print(f"wrote {written} translations for {language}")
    unknown = sorted(set(translations) - known)
    if unknown:
        print(f"{len(unknown)} translated keys match no catalog entry:", file=sys.stderr)
        for key in unknown[:10]:
            print(f"  {key}", file=sys.stderr)


def status(root: Path) -> None:
    languages: dict[str, int] = {}
    total = 0
    for path in catalogs(root):
        catalog = load(path)
        for entry in catalog["strings"].values():
            total += 1
            for language in entry.get("localizations", {}):
                languages[language] = languages.get(language, 0) + 1
    print(f"{total} keys across {len(catalogs(root))} catalogs")
    for language, count in sorted(languages.items()):
        print(f"  {language}: {count}")


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    if args.command == "export":
        export(root, args.language, args.output, args.include_translated)
    elif args.command == "import":
        import_(root, args.language, args.input)
    else:
        status(root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
