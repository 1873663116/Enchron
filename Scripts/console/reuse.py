from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any


PRODUCT_ROOTS = ("Apps", "Modules", "Packages")
PRODUCT_SUFFIXES = (".swift", ".metal", ".plist", ".entitlements", ".xcconfig")


def product_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for name in PRODUCT_ROOTS:
        base = root / name
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or path.suffix not in PRODUCT_SUFFIXES:
                continue
            relative = path.relative_to(root)
            digest.update(str(relative).encode("utf-8"))
            digest.update(b"\0")
            digest.update(path.read_bytes())
            digest.update(b"\0")
    return digest.hexdigest()[:32]


def safe_name(value: str) -> str:
    return value.replace(":", "-").replace("/", "-")


def runs_of(evidence_root: Path, unit: str) -> list[Path]:
    directory = evidence_root / safe_name(unit)
    if not directory.is_dir():
        return []
    runs = [path for path in directory.iterdir() if (path / "report.json").is_file()]
    return sorted(runs, key=lambda path: path.stat().st_mtime, reverse=True)


def latest_report(evidence_root: Path, unit: str) -> dict[str, Any] | None:
    runs = runs_of(evidence_root, unit)
    if not runs:
        return None
    report = json.loads((runs[0] / "report.json").read_text(encoding="utf-8"))
    report["evidenceDirectory"] = str(runs[0])
    return report


def reusable_report(
    evidence_root: Path, unit: str, plan_digest: str, current_product: str
) -> dict[str, Any] | None:
    report = latest_report(evidence_root, unit)
    if report is None:
        return None
    if report.get("verdict") != "passed":
        return None
    if report.get("digest") != plan_digest:
        return None
    recorded = report.get("productDigest") or ""
    if recorded != current_product:
        return None
    if not (Path(report["evidenceDirectory"]) / "report.json").is_file():
        return None
    return report


def precondition_key(precondition: dict[str, Any]) -> str:
    kind = str(precondition.get("kind", ""))
    provider = str(precondition.get("provider", ""))
    return f"{kind}:{provider}" if provider else kind


def passing_evidence(evidence_root: Path, unit: str, plan_digest: str) -> bool:
    report = latest_report(evidence_root, unit)
    if report is None:
        return False
    return report.get("verdict") == "passed" and report.get("digest") == plan_digest


def unknown_assumptions(
    plan_preconditions: tuple[dict[str, Any], ...], requested: set[str]
) -> list[str]:
    known = {precondition_key(item) for item in plan_preconditions}
    return sorted(requested - known)


def assumed_preconditions(
    plan_preconditions: tuple[dict[str, Any], ...], assumed: set[str]
) -> tuple[list[dict[str, Any]], list[str]]:
    outcomes: list[dict[str, Any]] = []
    unknown: list[str] = []
    for index, precondition in enumerate(plan_preconditions):
        key = precondition_key(precondition)
        if key not in assumed:
            continue
        outcomes.append(
            {
                "index": index,
                "kind": str(precondition.get("kind", "")),
                "provider": str(precondition.get("provider", "")),
                "ok": True,
                "action": "assumed",
                "detail": f"{key} is assumed from a passing run",
                "durationMs": 0,
            }
        )
    known = {precondition_key(item) for item in plan_preconditions}
    for key in sorted(assumed - known):
        unknown.append(key)
    return outcomes, unknown
