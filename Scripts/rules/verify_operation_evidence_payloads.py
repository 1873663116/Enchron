#!/usr/bin/env python3

"""Checks that a declared evidence pair is satisfiable from what the handler returns.

An Operation declares the evidence pairs it emits. The Oracle adapter refuses an
artifact whose payload lacks the keys that pair requires. Nothing connected the
two, so an Operation could declare a pair its handler never populates at the top
level, and the mismatch surfaced only when an obligation was adjudicated on a
device, hours into a run.

The required keys are read out of the Oracle adapter's own validator branches and
the produced keys out of the handler's own top-level return, so neither side can
drift from the code it describes. Keys nested inside a returned list or object do
not count: the validator reads the operation output itself, and a control plane
recorded per frame is not a control plane at the top level. Missing that
distinction is what this check exists to catch.
"""

from __future__ import annotations

import ast
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

OPERATION_ADAPTER = "Scripts/verification/regression_operation_adapter.py"
ORACLE_ADAPTER = "Scripts/verification/regression_oracle_adapter.py"

REQUIRE_CALLS = {
    "_require_nonempty_object",
    "_require_nonempty_text",
    "_require_object_array",
    "_require_text_array",
}


def _module(relative: str) -> ast.Module:
    return ast.parse((REPOSITORY_ROOT / relative).read_text(encoding="utf-8"))


def required_keys() -> dict[str, set[str]]:
    """Evidence type to the output keys the Oracle adapter demands of it."""
    found: dict[str, set[str]] = {}
    for node in ast.walk(_module(ORACLE_ADAPTER)):
        if not isinstance(node, ast.If):
            continue
        test = node.test
        if not (
            isinstance(test, ast.Compare)
            and isinstance(test.left, ast.Name)
            and test.left.id == "evidence_type"
            and len(test.comparators) == 1
            and isinstance(test.comparators[0], ast.Constant)
        ):
            continue
        evidence_type = test.comparators[0].value
        keys: set[str] = set()
        for inner in node.body:
            for call in ast.walk(inner):
                if not isinstance(call, ast.Call) or not isinstance(call.func, ast.Name):
                    continue
                if call.func.id not in REQUIRE_CALLS or len(call.args) < 2:
                    continue
                argument = call.args[1]
                if isinstance(argument, ast.Constant) and isinstance(argument.value, str):
                    keys.add(argument.value)
        found[evidence_type] = keys
    return found


def _own_returns(function: ast.FunctionDef) -> list[ast.Return]:
    found: list[ast.Return] = []

    class Walker(ast.NodeVisitor):
        def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
            if node is function:
                self.generic_visit(node)

        def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
            return

        def visit_Lambda(self, node: ast.Lambda) -> None:
            return

        def visit_Return(self, node: ast.Return) -> None:
            found.append(node)

    Walker().visit(function)
    return found


def _literal_keys(value: ast.expr) -> set[str] | None:
    if not isinstance(value, ast.Dict):
        return None
    return {
        key.value
        for key in value.keys
        if isinstance(key, ast.Constant) and isinstance(key.value, str)
    }


def produced_keys(function: ast.FunctionDef) -> set[str] | None:
    """Keys every top-level return of this handler provides, or None when unreadable."""
    assignments: dict[str, set[str]] = {}
    for node in ast.walk(function):
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            keys = _literal_keys(node.value) if node.value else None
            if keys is not None:
                assignments[node.target.id] = set(keys)
        elif isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            if isinstance(target, ast.Name):
                keys = _literal_keys(node.value)
                if keys is not None:
                    assignments[target.id] = set(keys)

    common: set[str] | None = None
    for statement in _own_returns(function):
        if statement.value is None:
            continue
        keys = _literal_keys(statement.value)
        if keys is None and isinstance(statement.value, ast.Name):
            keys = assignments.get(statement.value.id)
        if keys is None:
            return None
        common = set(keys) if common is None else (common & keys)
    return common


def handler_functions() -> dict[str, ast.FunctionDef]:
    return {
        node.name: node
        for node in ast.walk(_module(OPERATION_ADAPTER))
        if isinstance(node, ast.FunctionDef)
    }


def compare(
    declarations: dict[str, tuple[tuple[str, str], ...]],
    handler_names: dict[str, str],
    handlers: dict[str, ast.FunctionDef],
    demands: dict[str, set[str]],
) -> list[str]:
    found: list[str] = []
    for identifier, outputs in sorted(declarations.items()):
        if not outputs:
            continue
        name = handler_names[identifier]
        function = handlers.get(name)
        if function is None:
            found.append(f"{identifier}: handler {name} is absent from {OPERATION_ADAPTER}")
            continue
        produced = produced_keys(function)
        if produced is None:
            found.append(
                f"{identifier}: {name} returns a value this check cannot read, so its "
                f"declared evidence cannot be verified"
            )
            continue
        for evidence_type, evidence_schema in outputs:
            if evidence_type not in demands:
                found.append(
                    f"{identifier}: declares {evidence_type}/{evidence_schema}, which "
                    f"{ORACLE_ADAPTER} validates in no branch"
                )
                continue
            missing = sorted(demands[evidence_type] - produced)
            if missing:
                found.append(
                    f"{identifier}: declares {evidence_type} but {name} returns no "
                    f"top-level {', '.join(missing)}"
                )
    return found


def failures() -> list[str]:
    verification = REPOSITORY_ROOT / "Scripts/verification"
    if str(verification) not in sys.path:
        sys.path.insert(0, str(verification))
    import regression_operation_adapter as adapter

    return compare(
        {identifier: spec.outputs for identifier, spec in adapter.SPECS.items()},
        {identifier: adapter.resident_handler_name(identifier) for identifier in adapter.SPECS},
        handler_functions(),
        required_keys(),
    )


def main() -> int:
    found = failures()
    for failure in found:
        print(f"FAIL {failure}")
    if found:
        print(f"\n{len(found)} evidence payload failures")
        return 1
    print(
        "Every declared evidence pair is satisfiable from its handler's top-level return"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
