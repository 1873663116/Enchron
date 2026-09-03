from __future__ import annotations

import ast
from typing import Iterable, Mapping

from harness.lane_partition import DEVICE, SIMULATOR, identifier_opens_playback

RUN_CLASS = "ReachabilityRun"
DISPATCH_METHOD = "run_named_segment_scenario"


class ScenarioTableMissing(RuntimeError):
    pass


def _self_attribute(node: ast.AST) -> str | None:
    if (
        isinstance(node, ast.Attribute)
        and isinstance(node.value, ast.Name)
        and node.value.id == "self"
    ):
        return node.attr
    return None


def _self_method_references(node: ast.AST) -> set[str]:
    references: set[str] = set()
    for child in ast.walk(node):
        attribute = _self_attribute(child)
        if attribute is not None:
            references.add(attribute)
    return references


def _string_literals(node: ast.AST) -> set[str]:
    literals: set[str] = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Constant) and isinstance(child.value, str):
            literals.add(child.value)
        elif isinstance(child, ast.JoinedStr) and child.values:
            head = child.values[0]
            if isinstance(head, ast.Constant) and isinstance(head.value, str):
                literals.add(head.value)
    return literals


def _methods(source: str) -> dict[str, ast.FunctionDef]:
    module = ast.parse(source)
    for node in module.body:
        if isinstance(node, ast.ClassDef) and node.name == RUN_CLASS:
            return {
                item.name: item
                for item in node.body
                if isinstance(item, ast.FunctionDef)
            }
    raise ScenarioTableMissing(f"no class {RUN_CLASS} in the harness source")


def _dispatch_table(methods: Mapping[str, ast.FunctionDef]) -> ast.Dict:
    dispatch = methods.get(DISPATCH_METHOD)
    if dispatch is None:
        raise ScenarioTableMissing(f"{RUN_CLASS} has no {DISPATCH_METHOD}")
    for node in ast.walk(dispatch):
        if isinstance(node, ast.Dict):
            return node
    raise ScenarioTableMissing(f"{DISPATCH_METHOD} holds no scenario table")


def _reaches_playback_open(
    roots: Iterable[str], methods: Mapping[str, ast.FunctionDef]
) -> bool:
    pending = list(roots)
    visited: set[str] = set()
    while pending:
        name = pending.pop()
        if name in visited or name not in methods:
            continue
        visited.add(name)
        body = methods[name]
        if any(identifier_opens_playback(text) for text in _string_literals(body)):
            return True
        pending.extend(_self_method_references(body))
    return False


def classify(source: str) -> dict[str, str]:
    methods = _methods(source)
    table = _dispatch_table(methods)
    lanes: dict[str, str] = {}
    for key, value in zip(table.keys, table.values):
        if not isinstance(key, ast.Constant) or not isinstance(key.value, str):
            raise ScenarioTableMissing("scenario table keys must be string literals")
        opens = _reaches_playback_open(_self_method_references(value), methods)
        lanes[key.value] = DEVICE if opens else SIMULATOR
    return lanes
