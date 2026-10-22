from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from model import Diagnostic, Plan, Report


EXIT_OK = 0
EXIT_TERMINAL = 1
EXIT_USAGE = 2
EXIT_REFUSED = 3
EXIT_CAPABILITY = 4
EXIT_GUARDRAIL = 5
EXIT_ENGINE = 6
EXIT_KNOWN = 7


def plan_payload(plan: Plan) -> dict[str, Any]:
    return {
        "unit": plan.unit,
        "tier": plan.tier,
        "transport": plan.transport,
        "layer": plan.layer,
        "requires": sorted(plan.requires),
        "digest": plan.digest,
        "steps": [
            {
                "index": step.index,
                "verb": step.verb,
                "args": step.args,
                "evidence": step.evidence,
            }
            for step in plan.steps
        ],
        "terminal": {
            "kind": plan.terminal.kind,
            "path": plan.terminal.path,
            "equals": plan.terminal.equals,
        },
        "guardrails": [
            {"kind": guardrail.kind, "response": guardrail.response}
            for guardrail in plan.guardrails
        ],
        "evidence": list(plan.evidence),
    }


def report_payload(report: Report) -> dict[str, Any]:
    return {
        "unit": report.unit,
        "digest": report.digest,
        "verdict": report.verdict,
        "tier": report.tier,
        "durationMs": report.duration_ms,
        "steps": [
            {
                "index": step.index,
                "verb": step.verb,
                "ok": step.ok,
                "durationMs": step.duration_ms,
                "detail": step.detail,
                "guardrails": list(step.guardrails),
            }
            for step in report.steps
        ],
        "preconditions": [
            {key: value for key, value in item.items() if key != "receipt"}
            for item in report.preconditions
        ],
        "terminal": {
            "kind": report.terminal.kind,
            "ok": report.terminal.ok,
            "detail": report.terminal.detail,
        },
        "evidenceDir": report.evidence_dir,
        "exitCode": report.exit_code,
    }


def diagnostics_payload(findings: list[tuple[str, str, str]]) -> dict[str, Any]:
    return {
        "ok": not findings,
        "count": len(findings),
        "findings": [
            {"unit": unit, "code": code, "message": message}
            for unit, code, message in findings
        ],
    }


def render_diagnostics(findings: list[tuple[str, str, str]]) -> str:
    if not findings:
        return "every unit compiles and is reachable from a feature map"
    lines = [f"{len(findings)} finding(s)"]
    for unit, code, message in findings:
        lines.append(f"  {code}  {unit}  {message}")
    return "\n".join(lines)


def render_report(report: Report) -> str:
    lines = [
        f"{report.verdict}  {report.unit}  tier={report.tier}  {report.duration_ms} ms",
    ]
    if report.verdict == "known":
        lines.append(
            "  this failure is declared in Config/console/known-failures.md"
        )
    for precondition in report.preconditions:
        mark = "ok  " if precondition.get("ok") else "FAIL"
        lines.append(f"  {mark} pre {precondition.get('kind')}  {precondition.get('detail')}")
    for step in report.steps:
        mark = "ok  " if step.ok else "FAIL"
        lines.append(f"  {mark} {step.index:02d} {step.verb}  {step.duration_ms} ms  {step.detail}")
        for kind in step.guardrails:
            lines.append(f"       guardrail {kind}")
    terminal = report.terminal
    lines.append(
        f"  terminal {terminal.kind} {'ok' if terminal.ok else 'FAIL'}  {terminal.detail}"
    )
    lines.append(f"  evidence {report.evidence_dir}")
    return "\n".join(lines)


def render_plan(plan: Plan) -> str:
    lines = [
        f"{plan.unit}  tier={plan.tier}  transport={plan.transport}  layer={plan.layer}",
        f"  digest {plan.digest}",
        f"  requires {', '.join(sorted(plan.requires)) or 'none'}",
    ]
    for step in plan.steps:
        lines.append(f"  {step.index:02d} {step.verb}")
    lines.append(f"  terminal {plan.terminal.kind}")
    return "\n".join(lines)


def write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, indent=1, sort_keys=False) + "\n", encoding="utf-8"
    )
