#!/usr/bin/env python3

"""Refuse a cell lookup the inventory has not been asked about first.

`self.cells` is keyed by (proof context, operation). Shared chrome stays in the
hierarchy across surfaces, so a scenario driving one context reaches controls
the inventory derives for another, and a lookup that assumes the key exists
raises. That killed the docked segment four separate times, each in a different
place: observe, then tap, then mark_driven, then the parent lookup inside
delivered_by_debug_menu_selection. Each fix guarded one site and the next run
found the next one.

`provable` answers the question the lookup depends on, so every subscript of
`self.cells` has to sit behind it. This check reads the source rather than
waiting for a segment to die on the device.
"""

from __future__ import annotations

import ast
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MATRIX = REPOSITORY_ROOT / "Scripts/verification/reachability_matrix.py"
GUARD = "provable"
ASSIGNMENT_IS_FINE = "the key is being created, not read"


def subscripts_of_cells(tree: ast.AST) -> list[ast.Subscript]:
    found = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Subscript):
            continue
        value = node.value
        if (
            isinstance(value, ast.Attribute)
            and value.attr == "cells"
            and isinstance(value.value, ast.Name)
            and value.value.id == "self"
        ):
            found.append(node)
    return found


def written_keys(tree: ast.AST) -> set[int]:
    written = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Subscript):
                    written.add(id(target))
    return written


def guarded_lines(source: str) -> set[int]:
    """Lines a reader can see the guard on.

    Two shapes count. A function that calls provable() somewhere guards the
    lookups in it, which is coarse but matches how the fixes were written. A
    comprehension carrying its own membership test guards itself, and the two
    that build the ordered cell list do exactly that - asking provable() there
    would record every context as having looked at every operation.
    """
    tree = ast.parse(source)
    guarded: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            body = ast.get_source_segment(source, node) or ""
            if GUARD in body:
                guarded.update(range(node.lineno, (node.end_lineno or node.lineno) + 1))
        elif isinstance(node, (ast.ListComp, ast.SetComp, ast.GeneratorExp, ast.DictComp)):
            tests = " ".join(
                ast.get_source_segment(source, condition) or ""
                for generator in node.generators
                for condition in generator.ifs
            )
            if "in self.cells" in tests:
                guarded.update(range(node.lineno, (node.end_lineno or node.lineno) + 1))
    return guarded


def main() -> int:
    source = MATRIX.read_text(encoding="utf-8")
    tree = ast.parse(source)
    created = written_keys(tree)
    guarded = guarded_lines(source)

    unguarded = [
        node for node in subscripts_of_cells(tree)
        if id(node) not in created and node.lineno not in guarded
    ]
    for node in unguarded:
        line = source.splitlines()[node.lineno - 1].strip()
        print(
            f"{MATRIX.relative_to(REPOSITORY_ROOT)}:{node.lineno}: reads self.cells "
            f"without asking {GUARD}() first: {line[:80]}",
            file=sys.stderr,
        )
    if unguarded:
        print(
            f"{len(unguarded)} unguarded cell lookup(s); a context that cannot prove "
            "an operation must be answered, not indexed",
            file=sys.stderr,
        )
        return 1
    print(
        f"every self.cells lookup in {MATRIX.name} sits behind {GUARD}() "
        f"({ASSIGNMENT_IS_FINE})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
