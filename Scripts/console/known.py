"""Declared known failures.

A known failure names a unit and a phrase its failing step must contain. A run
whose failure matches stops being a red run and becomes a known one, so a
defect that predates the refactor does not hide new ones.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

DECLARATION = Path("Config/console/known-failures.md")
ENVIRONMENT = "ENCHRON_KNOWN_FAILURES"


def declaration_path(root: Path) -> Path:
    override = os.environ.get(ENVIRONMENT, "").strip()
    return Path(override) if override else root / DECLARATION


def parse_declarations(text: str) -> list[dict[str, Any]]:
    parts = text.split("---")
    if len(parts) < 3:
        return []
    try:
        payload = json.loads(parts[1])
    except json.JSONDecodeError:
        return []
    failures = payload.get("failures") if isinstance(payload, dict) else None
    return list(failures or [])


def declarations(root: Path) -> list[dict[str, Any]]:
    path = declaration_path(root)
    if not path.exists():
        return []
    return parse_declarations(path.read_text(encoding="utf-8"))


def checker_matching(
    root: Path, checker: str, text: str
) -> dict[str, Any] | None:
    for declaration in declarations(root):
        if str(declaration.get("checker")) != checker:
            continue
        phrase = str(declaration.get("match") or "")
        if phrase and phrase in text:
            return declaration
    return None


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
