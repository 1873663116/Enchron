from __future__ import annotations

import json
from pathlib import Path
from typing import Any

DEFINITION_ROOT = "Config/console"

from model import (
    PRECONDITION_KINDS,
    UNIT_PACES,
    Expectation,
    LoadRefusal,
    Terminal,
    Unit,
)


FRONT_MATTER_FENCE = "---"


def split_front_matter(text: str, source: str) -> tuple[dict[str, Any], str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != FRONT_MATTER_FENCE:
        raise LoadRefusal("C000", "file does not open with a front matter fence", source)
    try:
        closing = next(
            index
            for index, line in enumerate(lines[1:], start=1)
            if line.strip() == FRONT_MATTER_FENCE
        )
    except StopIteration:
        raise LoadRefusal("C000", "front matter fence is never closed", source) from None
    body = "\n".join(lines[1:closing])
    try:
        metadata = json.loads(body)
    except json.JSONDecodeError as error:
        raise LoadRefusal(
            "C000", f"front matter is not valid json: {error.msg}", source
        ) from None
    if not isinstance(metadata, dict):
        raise LoadRefusal("C000", "front matter must be a json object", source)
    return metadata, "\n".join(lines[closing + 1 :])


def parse_terminal(payload: Any, source: str) -> Terminal:
    if payload is None:
        raise LoadRefusal(
            "C001",
            "unit has no terminal assertion; the guardrails cannot tell an expected "
            "confirmation from an unexpected one without it",
            source,
        )
    if not isinstance(payload, dict):
        raise LoadRefusal("C001", "terminal must be an object", source)
    kind = payload.get("kind")
    if kind not in {"assert", "artifact", "exit"}:
        raise LoadRefusal(
            "C001", f"terminal.kind {kind!r} is outside assert, artifact, exit", source
        )
    path = payload.get("path")
    schema = payload.get("schema")
    equals = payload.get("equals")
    if kind == "artifact" and not isinstance(path, str):
        raise LoadRefusal("C001", "terminal.kind artifact needs a path", source)
    if kind == "assert" and not isinstance(path, str):
        raise LoadRefusal("C001", "terminal.kind assert needs a path", source)
    return Terminal(kind=kind, path=path, equals=equals, schema=schema)


def parse_unit(metadata: dict[str, Any], source: str) -> Unit:
    identifier = metadata.get("id")
    if not isinstance(identifier, str):
        raise LoadRefusal("C002", "unit needs an id", source)
    layer = metadata.get("layer")
    if layer not in (2, 3):
        raise LoadRefusal("C002", f"unit {identifier} has layer {layer!r}", source)
    actions = metadata.get("actions")
    if not isinstance(actions, list) or not actions:
        raise LoadRefusal("C005", f"unit {identifier} has no actions", source)
    terminal = parse_terminal(metadata.get("terminal"), source)
    requires = metadata.get("requires") or []
    if not isinstance(requires, list) or not all(
        isinstance(item, str) for item in requires
    ):
        raise LoadRefusal("C004", f"unit {identifier} has a malformed requires", source)
    role = metadata.get("role") or "unstated"
    return Unit(
        identifier=identifier,
        layer=layer,
        actions=tuple(actions),
        terminal=terminal,
        requires=frozenset(requires),
        role=role,
        source=source,
        preconditions=tuple(parse_preconditions(metadata.get("preconditions"), identifier, source)),
        pace=parse_pace(metadata.get("pace"), identifier, source),
    )


def parse_pace(payload: object, identifier: str, source: str) -> str:
    if payload is None:
        return "fast"
    if payload not in UNIT_PACES:
        raise LoadRefusal(
            "C017",
            f"unit {identifier} names pace {payload!r}; the closed set is "
            + ", ".join(sorted(UNIT_PACES)),
            source,
        )
    return str(payload)


def parse_preconditions(
    payload: object, identifier: str, source: str
) -> list[dict[str, object]]:
    if payload is None:
        return []
    if not isinstance(payload, list):
        raise LoadRefusal(
            "C016", f"unit {identifier} has a malformed preconditions", source
        )
    parsed: list[dict[str, object]] = []
    for item in payload:
        if not isinstance(item, dict):
            raise LoadRefusal(
                "C016", f"unit {identifier} has a non-object precondition", source
            )
        kind = item.get("kind")
        if kind not in PRECONDITION_KINDS:
            raise LoadRefusal(
                "C016",
                f"unit {identifier} names precondition kind {kind!r}; the closed set is "
                + ", ".join(sorted(PRECONDITION_KINDS)),
                source,
            )
        parsed.append(dict(item))
    return parsed


def load_unit(path: Path) -> Unit:
    source = str(path)
    metadata, _ = split_front_matter(path.read_text(encoding="utf-8"), source)
    return parse_unit(metadata, source)


def unit_paths(root: Path) -> tuple[Path, ...]:
    directory = root / DEFINITION_ROOT / "units"
    if not directory.is_dir():
        return ()
    return tuple(sorted(directory.glob("*.md")))


def load_units(root: Path) -> dict[str, Unit]:
    units: dict[str, Unit] = {}
    for path in unit_paths(root):
        unit = load_unit(path)
        if unit.identifier in units:
            raise LoadRefusal(
                "C002",
                f"unit {unit.identifier} is declared twice",
                str(path),
            )
        units[unit.identifier] = unit
    return units


def load_feature_references(root: Path) -> dict[str, set[str]]:
    directory = root / DEFINITION_ROOT / "features"
    references: dict[str, set[str]] = {}
    if not directory.is_dir():
        return references
    for path in sorted(directory.glob("*.md")):
        metadata, _ = split_front_matter(path.read_text(encoding="utf-8"), str(path))
        units = metadata.get("units") or []
        for identifier in units:
            references.setdefault(identifier, set()).add(path.stem)
    return references
