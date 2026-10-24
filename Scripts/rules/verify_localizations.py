#!/usr/bin/env python3
"""Fail when a catalog key is not translated in every declared language.

The catalog is the single source of truth for user-facing text. A key that has
no value in one target language ships English in that language, silently. This
check is pure text: it reads the catalogs and rules.json and needs no build.

Entries marked shouldTranslate=false are product names and are skipped.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCALIZATION = ROOT / "Scripts" / "localization"
sys.path.insert(0, str(LOCALIZATION))

import locale_coverage


def main() -> int:
    rules = locale_coverage.load_rules(ROOT)
    languages = locale_coverage.target_languages(rules)
    failures = locale_coverage.check_catalog(ROOT, set(), languages)
    if failures:
        print(
            f"localization: {failures} problem(s); "
            "translations enter the catalog through Scripts/localization/translations.py",
            file=sys.stderr,
        )
        return 1
    print("localization: every catalog key is translated in every declared language")
    return 0


if __name__ == "__main__":
    sys.exit(main())
