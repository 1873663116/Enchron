#!/usr/bin/env python3

"""Checks that every Catalog Fact value can be traced back to something real.

A Fact decides whether a Scenario applies. If its value is only prose in the
declaration plus a duplicate in the blueprint, nobody notices when the product
moves underneath it. That is not hypothetical: the prefetch Fact claimed a
six-second demux target long after the product removed its six-second watermark
and `verify_demux_buffer_policy.py` started guarding against its return.

So each Fact must name where its value comes from, in one of two closed forms:

  product-constant  read the value out of a named source at a named pattern
  decision          an approved semantic-authority decision authorises it

The checker then does the reading itself. A Fact whose declared value stops
matching the constant it points at fails here, which is the whole point.
"""

from __future__ import annotations

import ast
import json
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

FACTS_ROOT = "Config/regression/catalog-root/facts"
BLUEPRINT = "Config/regression/catalog-v2.json"
DECISIONS = "Config/regression/semantic-authority-decisions.tsv"

FACT_SCHEMA = "enchron.regression.fact"
PROVENANCE_KINDS = ("product-constant", "decision")
TRANSFORMS = ("integer", "number-list", "text", "boolean", "boolean-negated")


def frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise ValueError(f"{path}: expected a frontmatter document")
    return json.loads(text.split("---", 2)[1])


def evaluate_numeric(expression: str) -> float:
    """Evaluate a C or Swift numeric literal such as `15 * 60` or `1.0`."""
    tree = ast.parse(expression.replace("LL", "").strip(), mode="eval")
    allowed = (ast.Expression, ast.BinOp, ast.Constant, ast.Mult, ast.Add, ast.Sub, ast.Div, ast.UnaryOp, ast.USub)
    for node in ast.walk(tree):
        if not isinstance(node, allowed):
            raise ValueError(f"unsupported expression {expression!r}")
    return eval(compile(tree, "<constant>", "eval"))


def extract(provenance: dict, location: str) -> tuple[object | None, str | None]:
    path = REPOSITORY_ROOT / provenance["path"]
    if not path.is_file():
        return None, f"{location}: source {provenance['path']} does not exist"
    match = re.search(provenance["pattern"], path.read_text(encoding="utf-8"), re.MULTILINE)
    if match is None:
        return None, f"{location}: pattern found nothing in {provenance['path']}"
    captured = match.group(1)
    transform = provenance["transform"]
    try:
        if transform == "integer":
            value = evaluate_numeric(captured)
            if value != int(value):
                return None, f"{location}: {captured!r} is not a whole number"
            return int(value), None
        if transform == "number-list":
            parts = [part.strip() for part in captured.split(",") if part.strip()]
            return json.dumps(parts, separators=(",", ":")), None
        if transform in ("boolean", "boolean-negated"):
            asserted = captured.strip() in ("true", "YES", "1")
            return (asserted if transform == "boolean" else not asserted), None
        return captured.strip(), None
    except (ValueError, SyntaxError) as error:
        return None, f"{location}: cannot read {captured!r} as {transform}: {error}"


def decided_ids() -> set[str]:
    path = REPOSITORY_ROOT / DECISIONS
    if not path.is_file():
        return set()
    rows = path.read_text(encoding="utf-8").splitlines()
    header = rows[0].split("\t")
    identifier, status = header.index("id"), header.index("status")
    return {
        columns[identifier]
        for row in rows[1:]
        if len(columns := row.split("\t")) > max(identifier, status)
        and columns[status] == "decided"
    }


def failures() -> list[str]:
    root = REPOSITORY_ROOT / FACTS_ROOT
    if not root.is_dir():
        return [f"{FACTS_ROOT} is absent"]
    approved = decided_ids()
    found: list[str] = []
    declared_values: dict[str, object] = {}

    for path in sorted(root.glob("*.md")):
        location = f"{FACTS_ROOT}/{path.name}"
        try:
            document = frontmatter(path)
        except (ValueError, json.JSONDecodeError) as error:
            found.append(f"{location}: {error}")
            continue
        if document.get("schema") != FACT_SCHEMA:
            found.append(f"{location}: schema is not {FACT_SCHEMA}")
            continue
        identifier = document.get("id", location)

        if "value" not in document:
            found.append(f"{location}: declares no value, so nothing can be checked")
            continue
        declared_values[identifier] = document["value"]

        provenance = document.get("provenance")
        if not isinstance(provenance, dict) or provenance.get("kind") not in PROVENANCE_KINDS:
            found.append(
                f"{location}: needs a provenance whose kind is one of {', '.join(PROVENANCE_KINDS)}"
            )
            continue

        if provenance["kind"] == "decision":
            reference = provenance.get("decision")
            if reference not in approved:
                found.append(
                    f"{location}: names decision {reference!r}, which is not a decided "
                    f"entry in {DECISIONS}"
                )
            continue

        missing = {"path", "pattern", "transform"} - set(provenance)
        if missing:
            found.append(
                f"{location}: product-constant provenance misses {', '.join(sorted(missing))}"
            )
            continue
        if provenance["transform"] not in TRANSFORMS:
            found.append(
                f"{location}: transform must be one of {', '.join(TRANSFORMS)}"
            )
            continue
        read, error = extract(provenance, location)
        if error:
            found.append(error)
            continue
        if read != document["value"]:
            found.append(
                f"{location}: declares {document['value']!r} but "
                f"{provenance['path']} says {read!r}"
            )

    blueprint_path = REPOSITORY_ROOT / BLUEPRINT
    if blueprint_path.is_file():
        blueprint = json.loads(blueprint_path.read_text(encoding="utf-8"))
        blueprint_values = blueprint.get("analysisFactValues", {})
        for identifier, value in sorted(blueprint_values.items()):
            if identifier not in declared_values:
                found.append(f"{BLUEPRINT}: names unknown Fact {identifier}")
            elif declared_values[identifier] != value:
                found.append(
                    f"{BLUEPRINT}: {identifier} is {value!r} here but "
                    f"{declared_values[identifier]!r} in its declaration"
                )
        for identifier in sorted(set(declared_values) - set(blueprint_values)):
            found.append(f"{BLUEPRINT}: does not carry declared Fact {identifier}")

    return found


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} Fact provenance failures")
        return 1
    print(
        "Every Fact value is read back from the constant or decision it names, "
        "and the blueprint agrees with every declaration"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
