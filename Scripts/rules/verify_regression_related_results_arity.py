#!/usr/bin/env python3

"""Checks that a Rubric never reads an evidence slot its Scenario does not fill.

Criteria address inlined observations positionally: `relatedResults[1] is that
call's tapSequence response`. The producing call decides how many entries exist.
Rewrite one without the other and the Oracle reaches for an index that is not
there, which resolves to nothing and leaves the obligation Indeterminate — a
silent outcome, because no argument is malformed and no route is missing.

That is a real regression, not a hypothetical: replacing a binding instead of
appending to it left `relatedResults[1]` unfilled on two calls, and the round
that followed reported both obligations as undecidable.

A criterion may be case-guarded, and then its slots belong only to the cases the
sentence names: `Portal inlines relatedResults[0..3]` says nothing about the
window case's producer. So a sentence that names one or more of the Rubric's own
case keys is checked against those cases' producers alone; a sentence that names
none is checked against every producer, which is the stricter reading and the
right default.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT = "Config/regression/catalog-v2.json"
SLOT = re.compile(r"relatedResults\[(\d+)\]")


def blueprint() -> dict:
    return json.loads((REPOSITORY_ROOT / BLUEPRINT).read_text(encoding="utf-8"))


def producing_calls(catalog: dict) -> dict[str, list[tuple[str, int, str | None]]]:
    """Rubric id to the (call id, inlined count, case key) of every binding obligation."""
    calls = {
        call["callId"]: len((call.get("arguments") or {}).get("relatedResults", []))
        for scenario in catalog["scenarios"]
        for call in scenario.get("operations", [])
    }
    found: dict[str, list[tuple[str, int, str | None]]] = {}
    for scenario in catalog["scenarios"]:
        for obligation in scenario.get("obligations", []):
            rubric = obligation.get("rubric")
            producer = obligation.get("producedByCall")
            if rubric is None or producer not in calls:
                continue
            found.setdefault(rubric, []).append(
                (producer, calls[producer], obligation.get("caseKey"))
            )
    return found


# Split on sentence-ending periods only: "relatedResults[1..2]" carries dots
# of its own, and splitting inside it would strand the index from the case
# name that scopes it.
SENTENCE = re.compile(r".+?(?:\.(?=\s|$)|$)", re.DOTALL)


def demands(text: str, case_keys: set[str]) -> list[tuple[int, set[str]]]:
    """Every slot the text reads, paired with the case keys its sentence names."""
    found: list[tuple[int, set[str]]] = []
    for sentence in SENTENCE.findall(text):
        indexes = [int(index) for index in SLOT.findall(sentence)]
        if not indexes:
            continue
        folded = sentence.casefold()
        named = {key for key in case_keys if key.casefold() in folded}
        for index in indexes:
            found.append((index, named))
    return found


def failures() -> list[str]:
    catalog = blueprint()
    binding = producing_calls(catalog)
    found: list[str] = []
    for rubric in catalog["rubrics"]:
        producers = binding.get(rubric["id"]) or []
        case_keys = {case for _, _, case in producers if case}
        wanted: list[tuple[int, set[str]]] = []
        for text in rubric["criteria"] + rubric.get("negativeControls", []):
            wanted.extend(demands(text, case_keys))
        if not wanted:
            continue
        if not producers:
            found.append(f"{rubric['id']}: reads relatedResults but no obligation binds it")
            continue
        for call, inlined, case in producers:
            highest = max(
                (index for index, named in wanted if not named or case in named),
                default=None,
            )
            if highest is not None and inlined <= highest:
                found.append(
                    f"{rubric['id']}: reads relatedResults[{highest}] while {call} "
                    f"inlines {inlined}"
                )
    return found


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} related-results arity failures")
        return 1
    print("Every Rubric reads only evidence slots its producing call inlines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
