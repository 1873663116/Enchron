"""Declared known failures.

A known failure names a unit and a phrase its failing step must contain. A run
whose failure matches stops being a red run and becomes a known one, so a
defect that predates the refactor does not hide new ones.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

DECLARATION = Path("Config/console/known-failures.md")


def _front_matter(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    parts = text.split("---")
    if len(parts) < 3:
        return {}
    return json.loads(parts[1])


def declarations(root: Path) -> list[dict[str, Any]]:
    return list(_front_matter(root / DECLARATION).get("failures") or [])


def matching(root: Path, unit: str, steps: list[Any]) -> dict[str, Any] | None:
    for declaration in declarations(root):
        if str(declaration.get("unit")) != unit:
            continue
        phrase = str(declaration.get("match") or "")
        for step in steps:
            if getattr(step, "ok", True):
                continue
            if phrase and phrase in str(getattr(step, "detail", "")):
                return declaration
    return None
