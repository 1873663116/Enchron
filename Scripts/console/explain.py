"""Explain why a finished run failed.

The tool reads the last run of a unit, names the element the failing step wanted,
and ranks the identifiers the app did show against it. It needs no device.
"""
from __future__ import annotations

import difflib
import glob
import json
import os
import re
from pathlib import Path
from typing import Any

IDENTIFIER = re.compile(r"identifier: '([^']+)'")


def _last_run(root: Path, unit: str) -> Path | None:
    name = unit.split("unit:", 1)[-1]
    pattern = str(root / "TestEvidence" / "console" / f"unit-{name}" / "*" / "report.json")
    runs = sorted(glob.glob(pattern), key=os.path.getmtime)
    return Path(runs[-1]).parent if runs else None


def _identifiers(path: Path | None) -> list[str]:
    if path is None or not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    text = payload.get("hierarchy") if isinstance(payload, dict) else None
    if not isinstance(text, str):
        return []
    return sorted(set(IDENTIFIER.findall(text)))


def _evidence_with_hierarchy(run: Path, failing_index: int) -> tuple[Path | None, int]:
    directory = run / "steps"
    candidates = sorted(directory.glob("*.json"))
    ordered: list[tuple[int, Path]] = []
    for path in candidates:
        match = re.match(r"(\d+)-", path.name)
        if match:
            ordered.append((int(match.group(1)), path))
    for index, path in reversed([item for item in ordered if item[0] <= failing_index]):
        if _identifiers(path):
            return path, index
    return None, -1


def report(root: Path, unit: str, limit: int = 6) -> dict[str, Any]:
    run = _last_run(root, unit)
    if run is None:
        return {"unit": unit, "error": "no run evidence for this unit"}
    data = json.loads((run / "report.json").read_text(encoding="utf-8"))
    failing = [step for step in data.get("steps", []) if not step["ok"]]
    if not failing:
        return {"unit": unit, "verdict": data.get("verdict"), "detail": "no failing step"}
    step = failing[0]
    plan = json.loads((run / "plan.json").read_text(encoding="utf-8"))
    index = step["index"]
    planned = next(
        (item for item in plan.get("steps") or [] if item.get("index") == index),
        {},
    )
    args = planned.get("args") or {}
    expectation = planned.get("expect") or {}
    expected = ""
    if expectation.get("contains") is not None:
        expected = f"{expectation.get('path')} contains {expectation.get('contains')!r}"
    elif expectation:
        expected = f"{expectation.get('path')} equals {expectation.get('equals')!r}"
    slowest = sorted(
        (
            {"index": item.get("index"), "verb": item.get("verb"), "durationMs": item.get("durationMs")}
            for item in data.get("steps", [])
        ),
        key=lambda item: item["durationMs"] or 0,
        reverse=True,
    )[:3]
    wanted = (
        args.get("identifier")
        or args.get("probe")
        or args.get("label")
        or (args.get("identifiers") or [None])[0]
        or ""
    )
    path, source = _evidence_with_hierarchy(run, index)
    shown = _identifiers(path)
    ranked = sorted(
        (
            (round(difflib.SequenceMatcher(None, str(wanted), identifier).ratio(), 3), identifier)
            for identifier in shown
        ),
        reverse=True,
    )[:limit]
    return {
        "unit": unit,
        "run": str(run),
        "step": index,
        "verb": step["verb"],
        "detail": step["detail"],
        "expected": expected,
        "wanted": wanted,
        "hierarchyStep": source,
        "identifiersSeen": len(shown),
        "candidates": [name for _, name in ranked],
        "evidence": data.get("evidenceDir", ""),
        "rerun": (
            f"python3 Scripts/console/cli.py run {unit} --tier e2e"
        ),
        "slowest": slowest,
    }


def render(payload: dict[str, Any]) -> str:
    if "error" in payload:
        return f"{payload['unit']}: {payload['error']}"
    if "candidates" not in payload:
        return f"{payload['unit']}: {payload.get('verdict')} — {payload.get('detail')}"
    lines = [
        f"{payload['unit']}  step {payload['step']}  {payload['verb']}",
        f"  wanted  {payload['wanted']}",
        f"  detail  {payload['detail']}",
        f"  looked at step {payload['hierarchyStep']} with {payload['identifiersSeen']} identifier(s)",
    ]
    if payload.get("expected"):
        lines.append(f"  expected  {payload['expected']}")
    for name in payload["candidates"]:
        lines.append(f"    candidate  {name}")
    for item in payload.get("slowest") or []:
        lines.append(
            f"    slowest  {item['index']:02d} {item['verb']}  {item['durationMs']} ms"
        )
    if payload.get("evidence"):
        lines.append(f"  evidence  {payload['evidence']}")
    if payload.get("rerun"):
        lines.append(f"  rerun     {payload['rerun']}")
    return "\n".join(lines)
