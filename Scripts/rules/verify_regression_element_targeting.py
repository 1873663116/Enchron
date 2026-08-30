#!/usr/bin/env python3

"""Checks that Catalog calls name things the product and harness actually offer.

Two ways a call can be written so it runs and still proves nothing:

  a name nobody seeds     a label such as "Enchron Regression Library" reads
                          fine, but the Emby seeder creates "Enchron Regression
                          Emby", so the activation finds no row
  a shared identifier     `FileBrowsing-SourcesSidebar-source-<id>` is applied
                          to the whole row container, so `tap --identifier`
                          resolves to the delete control inside it

Neither is visible in a review of the Catalog alone; both were found by hand in
round 7 and both are decided by comparing two declarations, so both belong here.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

BLUEPRINT = "Config/regression/catalog-v2.json"
VERIFICATION = "Scripts/verification"
PRODUCT_NOTES = ".agents/skills/vp-e2e/references/product.md"

SEEDED_PREFIX = "Enchron Regression"
GRID_CARD = "Modules/DesignSystem/Components/GridCard.swift"
VARIANT_KEY = re.compile(r'case \.\w+: return "(\w+)"')
"""GridCard labels itself `<title>, <variantKey>`, so a card's label is a seeded
name plus one of those suffixes. The variants are read from the component rather
than listed here, so a new card kind cannot quietly widen what this accepts."""
SEEDED_NAME = re.compile(rf"{SEEDED_PREFIX}[A-Za-z0-9 .'\-]*")

ACTIVATE = "operation:accessibility.activate@2"
SELECTING = ("labels", "identifiers")
"""Arguments that look an element up. `text` types a new name into a form, so a
name it has never seen is the point of the call rather than a mistake."""

CONTAINER_IDENTIFIERS = (
    (
        re.compile(r"-SourcesSidebar-source-"),
        "删除按钮、图标与文本共享同一个 identifier",
        "select the source by label or --index",
    ),
)


def blueprint() -> dict:
    return json.loads((REPOSITORY_ROOT / BLUEPRINT).read_text(encoding="utf-8"))


def seeded_names() -> set[str]:
    """Every `Enchron Regression …` name the verification layer can create."""
    found: set[str] = set()
    for path in sorted((REPOSITORY_ROOT / VERIFICATION).rglob("*.py")):
        found.update(
            name.strip() for name in SEEDED_NAME.findall(path.read_text(encoding="utf-8"))
        )
    return found


def card_labels(seeded: set[str]) -> set[str]:
    source = (REPOSITORY_ROOT / GRID_CARD).read_text(encoding="utf-8")
    start = source.find("private var variantKey")
    variants = set(VARIANT_KEY.findall(source[start : start + 400])) if start >= 0 else set()
    return {f"{name}, {variant}" for name in seeded for variant in variants}


def calls(catalog: dict):
    for scenario in catalog.get("scenarios", []):
        for call in scenario.get("operations", []):
            yield scenario.get("id", "<scenario>"), call


def string_arguments(call: dict):
    for key, value in (call.get("arguments") or {}).items():
        if isinstance(value, str):
            yield key, value
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, str):
                    yield key, item


def failures() -> list[str]:
    catalog = blueprint()
    seeded = seeded_names()
    accepted = seeded | card_labels(seeded)
    notes = (REPOSITORY_ROOT / PRODUCT_NOTES).read_text(encoding="utf-8")
    found: list[str] = []

    for pattern, justification, remedy in CONTAINER_IDENTIFIERS:
        if justification not in notes:
            found.append(
                f"{PRODUCT_NOTES}: no longer records {justification!r}, so the rule "
                f"forbidding {pattern.pattern} has lost its stated ground"
            )

    for scenario, call in calls(catalog):
        where = call.get("callId", scenario)
        for key, value in string_arguments(call):
            if key in SELECTING and value.startswith(SEEDED_PREFIX) and value not in accepted:
                found.append(
                    f"{where}: {key} names {value!r}, which nothing under "
                    f"{VERIFICATION} seeds"
                )
            if key != "identifiers" or call.get("operation") != ACTIVATE:
                continue
            for pattern, _, remedy in CONTAINER_IDENTIFIERS:
                if pattern.search(value):
                    found.append(f"{where}: activates container {value!r}; {remedy}")

    return found


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} element targeting failures")
        return 1
    print(
        "Every Catalog call names a seeded fixture and reaches each element by a "
        "handle that resolves to it"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
