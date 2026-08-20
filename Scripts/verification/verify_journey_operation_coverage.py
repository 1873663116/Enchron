#!/usr/bin/env python3
"""Fail when a reachability cell has no coverage verdict of any kind.

A gap is allowed and is reported. What is not allowed is a cell nobody has
looked at: a newly added button lands in the matrix, and without this check it
would sit there reachable and unexamined while every report stayed green.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MATRIX_PATH = REPOSITORY_ROOT / "Config/reachability_matrix_baseline.json"
LEDGER_PATH = REPOSITORY_ROOT / "Config/journey_operation_coverage.json"


def key(entry: dict[str, object]) -> tuple[str, str]:
    return (str(entry["context"]), str(entry["operation"]))


def main() -> int:
    matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))
    ledger = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))

    matrix_cells = {key(cell) for cell in matrix["cells"]}
    ledger_cells = {key(entry) for entry in ledger["cells"]}

    failures: list[str] = []
    for context, operation in sorted(matrix_cells - ledger_cells):
        failures.append(f"未归类: {context} | {operation}")
    for context, operation in sorted(ledger_cells - matrix_cells):
        failures.append(f"账中有而矩阵中已无: {context} | {operation}")
    for entry in ledger["cells"]:
        if entry.get("status") == "unassigned":
            failures.append(f"未归类: {entry['context']} | {entry['operation']}")
        has_verdict = (
            entry.get("journey") or entry.get("primitive") or entry.get("status")
        )
        if not has_verdict:
            failures.append(f"无判定: {entry['context']} | {entry['operation']}")

    tally: dict[str, int] = {}
    for entry in ledger["cells"]:
        verdict = (
            "verified" if entry.get("journey") or entry.get("primitive")
            else str(entry.get("status"))
        )
        tally[verdict] = tally.get(verdict, 0) + 1

    print(f"可达性格数 {len(matrix_cells)}")
    for verdict in sorted(tally):
        print(f"  {verdict}: {tally[verdict]}")

    if failures:
        print()
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        print(
            f"\n{len(failures)} 个格子没有覆盖判定。"
            "新增操作必须在 Config/journey_operation_coverage.json 中归类："
            "指向一条旅程步骤，或显式记为缺口。",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
