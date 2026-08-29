#!/usr/bin/env python3

"""Checks that every Oracle can actually be handed the evidence it adjudicates.

An Oracle declares the evidence type and schema pair it accepts, and refuses
anything else. An Operation declares the pairs it emits. If an Oracle names a
pair that no Operation in the closed registry emits, nothing can ever reach it:
the contract reads as coverage while adjudicating nothing.

That is not hypothetical. Retiring `operation:diagnostics.emby-range-log@1` and
`operation:diagnostics.window-control-plane@1` removed the only producers of
`emby.range-log` and `window.control-plane` and left both consuming Oracles
behind, where the deterministic review counted them as two of the eleven the
blueprint requires. The AgentOperability review found them; nothing in the
structure stage did.

The check runs the other way too. An obligation may only name an Oracle whose
pair its producing call actually emits, so a rebind that crosses evidence types
fails here instead of at adjudication time on a device.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VERIFICATION = REPOSITORY_ROOT / "Scripts/verification"

ORACLES_ROOT = "Regression/oracles"
JOURNEYS_ROOT = "Regression/journeys"


def frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise ValueError(f"{path}: expected a frontmatter document")
    return json.loads(text.split("---", 2)[1])


def produced_pairs() -> dict[tuple[str, str], list[str]]:
    if str(VERIFICATION) not in sys.path:
        sys.path.insert(0, str(VERIFICATION))
    import regression_operation_adapter as adapter

    found: dict[tuple[str, str], list[str]] = {}
    for spec in adapter.SPECS.values():
        for pair in spec.outputs:
            found.setdefault(tuple(pair), []).append(spec.identifier)
    return found


def declared_oracles() -> dict[str, tuple[tuple[str, str], ...]]:
    found: dict[str, tuple[tuple[str, str], ...]] = {}
    for path in sorted((REPOSITORY_ROOT / ORACLES_ROOT).glob("*.md")):
        document = frontmatter(path)
        found[document["id"]] = tuple(
            (entry["evidenceType"], entry["evidenceSchema"])
            for entry in document["evidenceSchemas"]
        )
    return found


def scenario_documents() -> list[tuple[str, dict]]:
    root = REPOSITORY_ROOT / JOURNEYS_ROOT
    documents = []
    for path in sorted(root.rglob("*.md")):
        document = frontmatter(path)
        if document.get("schema") == "enchron.regression.scenario":
            documents.append((str(path.relative_to(REPOSITORY_ROOT)), document))
    return documents


def failures() -> list[str]:
    produced = produced_pairs()
    oracles = declared_oracles()
    found: list[str] = []

    for identifier, pairs in sorted(oracles.items()):
        for pair in pairs:
            if pair not in produced:
                found.append(
                    f"{ORACLES_ROOT}: {identifier} adjudicates {pair[0]}/{pair[1]}, "
                    f"which no Operation emits"
                )

    for location, scenario in scenario_documents():
        calls = {call["callId"]: call["operation"] for call in scenario.get("operations", [])}
        for obligation in scenario.get("obligations", []):
            pair = (obligation["evidenceType"], obligation["evidenceSchema"])
            oracle = obligation["oracle"]
            if oracle not in oracles:
                found.append(f"{location}: {obligation['id']} names unknown Oracle {oracle}")
                continue
            if pair not in oracles[oracle]:
                found.append(
                    f"{location}: {obligation['id']} carries {pair[0]}/{pair[1]} "
                    f"but {oracle} accepts {', '.join(f'{a}/{b}' for a, b in oracles[oracle])}"
                )
            producer = calls.get(obligation["producedByCall"])
            if producer is None:
                found.append(
                    f"{location}: {obligation['id']} is produced by "
                    f"{obligation['producedByCall']}, which the Scenario does not call"
                )
            elif producer not in produced.get(pair, ()):
                found.append(
                    f"{location}: {obligation['id']} expects {pair[0]}/{pair[1]} from "
                    f"{producer}, which does not emit it"
                )
    return found


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} Oracle producer failures")
        return 1
    print(
        "Every Oracle adjudicates an evidence pair some Operation emits, and every "
        "obligation is produced by a call that emits the pair its Oracle accepts"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
