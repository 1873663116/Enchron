#!/usr/bin/env python3

"""Reports how much of the rubric corpus a deterministic field predicate covers.

`Regression/oracle-protocol.md` says a rubric written as natural-language
criteria is not deterministic unless an exact field predicate implementation
exists. This check says, per criterion, whether one exists. It does not fail on
a low number: it fails when the compiler cannot run, when a rubric cannot be
read, or when coverage falls below the recorded baseline, which is the ratchet
`docs/CONTEXT.md` describes.

A criterion that yields a predicate is only partly mechanised. The predicate
covers the field assertion it names; the rest of that criterion is still read by
an Agent. The report counts criteria that yield at least one predicate, and says
so in those words, so nobody reads the number as full coverage.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT / "Scripts") not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from regression.core.catalog import load_catalog
from regression.core.errors import RegressionError
from regression.rubric_compiler import RubricCompilerError, compile_rubric

CATALOG_ROOT = REPOSITORY_ROOT / "Regression"
BASELINE_PATH = REPOSITORY_ROOT / "Config/rubric_predicate_baseline.json"
REPORT_SCHEMA = "enchron.regression.rubric-predicate-coverage"


def coverage(catalog_root: Path) -> dict:
    catalog = load_catalog(catalog_root)
    by_rubric = []
    criterion_count = 0
    yielding_count = 0
    predicate_count = 0
    for rubric in sorted(catalog.rubrics, key=lambda item: str(item.id)):
        compiled = compile_rubric(rubric)
        yielding = len(rubric.criteria) - len(compiled.uncompiled)
        criterion_count += len(rubric.criteria)
        yielding_count += yielding
        predicate_count += len(compiled.predicates)
        by_rubric.append(
            {
                "id": str(rubric.id),
                "criteria": len(rubric.criteria),
                "criteriaYieldingPredicates": yielding,
                "predicates": [item.payload() for item in compiled.predicates],
                "uncompiled": list(compiled.uncompiled),
            }
        )
    return {
        "schema": REPORT_SCHEMA,
        "schemaVersion": 1,
        "rubricCount": len(catalog.rubrics),
        "criterionCount": criterion_count,
        "criteriaYieldingPredicates": yielding_count,
        "predicateCount": predicate_count,
        "byRubric": by_rubric,
    }


def load_baseline(path: Path) -> dict:
    if not path.is_file():
        return {"criteriaYieldingPredicates": 0, "predicateCount": 0}
    return json.loads(path.read_text(encoding="utf-8"))


def regressions(report: dict, baseline: dict) -> list[str]:
    found = []
    for key in ("criteriaYieldingPredicates", "predicateCount"):
        recorded = int(baseline.get(key, 0))
        current = int(report[key])
        if current < recorded:
            found.append(
                f"{key} fell from {recorded} to {current}; a rubric that used to "
                "carry a deterministic predicate no longer does"
            )
    return found


def write_baseline(report: dict, path: Path) -> list[str]:
    baseline = load_baseline(path)
    refusals = regressions(report, baseline)
    if refusals:
        return refusals
    path.write_text(
        json.dumps(
            {
                "schema": REPORT_SCHEMA,
                "schemaVersion": 1,
                "criteriaYieldingPredicates": report["criteriaYieldingPredicates"],
                "predicateCount": report["predicateCount"],
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog-root", type=Path, default=CATALOG_ROOT)
    parser.add_argument("--baseline", type=Path, default=BASELINE_PATH)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--write-baseline", action="store_true")
    arguments = parser.parse_args()

    try:
        report = coverage(arguments.catalog_root)
    except (RegressionError, RubricCompilerError, OSError, ValueError) as error:
        print(f"the rubric corpus could not be compiled: {error}", file=sys.stderr)
        return 1

    if arguments.report is not None:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    print(
        f"{report['rubricCount']} rubrics, {report['criterionCount']} criteria, "
        f"{report['criteriaYieldingPredicates']} of them yield at least one field "
        f"predicate, {report['predicateCount']} predicates in all; the remaining "
        f"{report['criterionCount'] - report['criteriaYieldingPredicates']} are read "
        "by an Agent"
    )

    if arguments.write_baseline:
        refusals = write_baseline(report, arguments.baseline)
        for line in refusals:
            print(f"FAIL {line}", file=sys.stderr)
        return 1 if refusals else 0

    refusals = regressions(report, load_baseline(arguments.baseline))
    for line in refusals:
        print(f"FAIL {line}", file=sys.stderr)
    return 1 if refusals else 0


if __name__ == "__main__":
    raise SystemExit(main())
