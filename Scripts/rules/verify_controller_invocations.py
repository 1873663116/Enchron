#!/usr/bin/env python3

"""Checks that every caller of the Vision Pro controller passes options it has.

`interactive_visionpro_ui.py` is driven by building an argv list in another
script. argparse rejects an unknown option at parse time, so a caller left
behind by a rename fails on its very first call and every call after it, with
no signal that anything is structurally wrong. The run simply measures nothing.

That is not hypothetical. The controller moved from `--derived-data-path`,
`--test-plan` and `--cloned-packages-path` to a single `--execution-input`, and
two callers kept the old flags. `reachability_matrix.py` reported 0 of 221
cells measured and 221 unmeasured, which reads like a device problem and is not
one.

The option set is read out of the controller's own `add_argument` calls, so the
check cannot drift from the parser it guards.
"""

from __future__ import annotations

import ast
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

CONTROLLER = "Scripts/verification/interactive_visionpro_ui.py"
CALLER_ROOTS = ("Scripts",)


def declared_options(source: str) -> set[str]:
    found: set[str] = set()
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else None
        if name not in ("add_argument", "add_parser"):
            continue
        for argument in node.args:
            if isinstance(argument, ast.Constant) and isinstance(argument.value, str):
                if argument.value.startswith("--"):
                    found.add(argument.value)
    return found


def declared_actions(source: str) -> set[str]:
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else None
        if name != "add_argument":
            continue
        for keyword in node.keywords:
            if keyword.arg == "choices" and isinstance(keyword.value, (ast.List, ast.Tuple)):
                return {
                    element.value
                    for element in keyword.value.elts
                    if isinstance(element, ast.Constant) and isinstance(element.value, str)
                }
    return set()


def _mentions_controller(node: ast.AST) -> bool:
    for child in ast.walk(node):
        if isinstance(child, ast.Name) and child.id == "CONTROLLER":
            return True
        if isinstance(child, ast.Constant) and isinstance(child.value, str):
            if child.value.endswith("interactive_visionpro_ui.py"):
                return True
    return False


def invocation_options(source: str) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, (ast.List, ast.Tuple)):
            continue
        if not _mentions_controller(node):
            continue
        for element in node.elts:
            if isinstance(element, ast.Constant) and isinstance(element.value, str):
                if element.value.startswith("--"):
                    found.append((element.lineno, element.value))
    return found


def failures() -> list[str]:
    controller = REPOSITORY_ROOT / CONTROLLER
    if not controller.is_file():
        return [f"{CONTROLLER} is absent"]
    source = controller.read_text(encoding="utf-8")
    options = declared_options(source)
    if not options:
        return [f"{CONTROLLER} declares no options, so nothing can be checked"]

    found: list[str] = []
    for root in CALLER_ROOTS:
        for path in sorted((REPOSITORY_ROOT / root).rglob("*.py")):
            if path == controller:
                continue
            try:
                caller = path.read_text(encoding="utf-8")
            except OSError as error:
                found.append(f"{path}: {error}")
                continue
            if "interactive_visionpro_ui" not in caller:
                continue
            relative = path.relative_to(REPOSITORY_ROOT)
            for line, option in invocation_options(caller):
                if option not in options:
                    found.append(
                        f"{relative}:{line}: passes {option}, which "
                        f"{CONTROLLER} does not accept"
                    )
    return found


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} controller invocation failures")
        return 1
    print(
        "Every controller invocation passes only options "
        f"{CONTROLLER} declares"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
