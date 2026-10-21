from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any

from guard import GuardrailHit, Supervisor
from model import Plan, Report, Step, StepOutcome, TerminalOutcome
import report as report_module
import transport
from report import (
    EXIT_GUARDRAIL,
    EXIT_OK,
    EXIT_TERMINAL,
    report_payload,
    write_json,
)
from vocab import VERBS


TARGET_BUNDLE = "com.xiongzhipeng.EnchronAppUITests.xctrunner"


def run_plan(plan: Plan, root: Path, evidence_root: Path, budget_scale: float) -> Report:
    run_directory = _run_directory(evidence_root, plan.unit)
    steps_directory = run_directory / "steps"
    steps_directory.mkdir(parents=True, exist_ok=True)
    write_json(run_directory / "plan.json", _plan_snapshot(plan))
    supervisor = Supervisor(plan.guardrails, budget_scale)
    started = time.monotonic()
    outcomes: list[StepOutcome] = []
    verdict = "passed"
    exit_code = EXIT_OK
    for step in plan.steps:
        outcome, hit = _run_step(step, plan, root, supervisor, steps_directory, budget_scale)
        outcomes.append(outcome)
        if hit is not None:
            verdict = "blocked"
            exit_code = EXIT_GUARDRAIL
            break
        if not outcome.ok:
            verdict = "failed"
            exit_code = EXIT_TERMINAL
            break
    terminal = _evaluate_terminal(plan, run_directory, steps_directory)
    if not terminal.ok and verdict == "passed":
        verdict = "failed"
        exit_code = EXIT_TERMINAL
    duration_ms = int((time.monotonic() - started) * 1000)
    report = Report(
        unit=plan.unit,
        digest=plan.digest,
        verdict=verdict,
        tier=plan.tier,
        duration_ms=duration_ms,
        steps=tuple(outcomes),
        terminal=terminal,
        evidence_dir=str(run_directory),
        exit_code=exit_code,
    )
    write_json(run_directory / "report.json", report_payload(report))
    _append_index(evidence_root, report)
    return report


def _safe_name(value: Any) -> str:
    return str(value).replace(":", "-").replace("/", "-")


def _run_directory(evidence_root: Path, unit: str) -> Path:
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    base = evidence_root / _safe_name(unit) / stamp
    if not base.exists():
        return base
    index = 1
    while True:
        candidate = base.with_name(f"{base.name}-{index}")
        if not candidate.exists():
            return candidate
        index += 1


def _plan_snapshot(plan: Plan) -> dict[str, Any]:
    return report_module.plan_payload(plan)


def _evaluate_terminal(
    plan: Plan, run_directory: Path, steps_directory: Path
) -> TerminalOutcome:
    terminal = plan.terminal
    if terminal.kind == "exit":
        return TerminalOutcome(kind=terminal.kind, ok=True, detail="process exit is the verdict")
    name = terminal.path or ""
    candidates = [run_directory / name, steps_directory / name]
    for step in plan.steps:
        verb = VERBS.get(step.verb)
        if verb and verb.evidence == name:
            candidates.append(steps_directory / f"{step.index:02d}-{_safe_name(step.verb)}.json")
    target = next((path for path in candidates if path.exists()), None)
    if target is None:
        return TerminalOutcome(
            kind=terminal.kind,
            ok=False,
            detail=f"expected evidence {name} was never written",
        )
    if terminal.kind == "artifact":
        return TerminalOutcome(kind=terminal.kind, ok=True, detail=f"{name} present")
    try:
        payload = json.loads(target.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return TerminalOutcome(
            kind=terminal.kind, ok=False, detail=f"{name} is not json: {error.msg}"
        )
    if terminal.path and terminal.equals is not None:
        observed = _resolve(payload, terminal.path)
        if observed != terminal.equals:
            return TerminalOutcome(
                kind=terminal.kind,
                ok=False,
                detail=f"expected {terminal.path} to equal {terminal.equals!r}, saw {observed!r}",
            )
    return TerminalOutcome(kind=terminal.kind, ok=True, detail="assertion held")


def _resolve(payload: Any, path: str) -> Any:
    current = payload
    for part in [segment for segment in path.split(".") if segment]:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            return None
    return current


def _append_index(evidence_root: Path, report: Report) -> None:
    evidence_root.mkdir(parents=True, exist_ok=True)
    line = json.dumps(
        {
            "unit": report.unit,
            "verdict": report.verdict,
            "tier": report.tier,
            "durationMs": report.duration_ms,
            "evidenceDir": report.evidence_dir,
        },
        sort_keys=True,
    )
    with (evidence_root / "index.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def _run_step(
    step: Step,
    plan: Plan,
    root: Path,
    supervisor: Supervisor,
    steps_directory: Path,
    budget_scale: float,
) -> tuple[StepOutcome, GuardrailHit | None]:
    verb = VERBS[step.verb]
    started = time.monotonic()
    detail = ""
    ok = True
    evidence: dict[str, Any] | None = None
    hit: GuardrailHit | None = None
    try:
        supervisor.before(step.verb, evidence)
        evidence, ok, detail = _dispatch(step, root, plan.transport)
        elapsed = int((time.monotonic() - started) * 1000)
        supervisor.after(step.verb, verb.budget_ms, elapsed, evidence)
    except GuardrailHit as caught:
        hit = caught
        detail = caught.detail
        ok = False
    duration_ms = int((time.monotonic() - started) * 1000)
    if evidence is not None:
        write_json(
            steps_directory / f"{step.index:02d}-{_safe_name(step.verb)}.json", evidence
        )
    return (
        StepOutcome(
            index=step.index,
            verb=step.verb,
            ok=ok,
            duration_ms=duration_ms,
            detail=detail,
            guardrails=supervisor.drain(),
        ),
        hit,
    )


def _dispatch(
    step: Step, root: Path, transport: str
) -> tuple[dict[str, Any] | None, bool, str]:
    if step.verb == "static.check":
        return _run_static_check(step, root)
    if transport == "daemon":
        return _dispatch_daemon(step, root)
    if step.verb == "device.snapshot":
        return _invoke_channel(root, "snapshot", None, None)
    if step.verb == "device.command":
        action = str(step.args.get("action", "tap"))
        identifier = step.args.get("identifier")
        text = step.args.get("text")
        return _invoke_channel(
            root,
            action,
            str(identifier) if identifier else None,
            str(text) if text else None,
        )
    return None, True, f"{step.verb} has no dispatch in this build"


def _dispatch_daemon(
    step: Step, root: Path
) -> tuple[dict[str, Any] | None, bool, str]:
    import daemon as daemon_module

    if step.verb == "device.session.ensure":
        answer = daemon_module.request(
            root, {"op": "ensure", "lane": step.args.get("lane", "simulator")}
        )
    elif step.verb == "device.snapshot":
        answer = daemon_module.request(root, {"op": "invoke", "action": "snapshot"})
    elif step.verb == "device.command":
        answer = daemon_module.request(
            root,
            {
                "op": "invoke",
                "action": step.args.get("action", "tap"),
                "identifier": step.args.get("identifier"),
                "text": step.args.get("text"),
            },
        )
    elif step.verb == "device.probe":
        answer = daemon_module.request(
            root, {"op": "invoke", "action": "snapshot", "identifier": step.args.get("probe")}
        )
    elif step.verb == "app.relaunch":
        answer = daemon_module.request(root, {"op": "invoke", "action": "relaunch"})
    else:
        return None, True, f"{step.verb} has no daemon dispatch"
    if answer.get("kind") != "result":
        return None, False, answer.get("message", "daemon refused")
    value = answer.get("value", {})
    return value.get("payload"), bool(value.get("ok")), str(value.get("detail", ""))


def _run_static_check(
    step: Step, root: Path
) -> tuple[dict[str, Any] | None, bool, str]:
    checker = str(step.args.get("checker", ""))
    script = root / "Scripts" / "rules" / checker
    if not script.exists():
        return {"checker": checker, "present": False}, False, f"{checker} does not exist"
    completed = subprocess.run(
        ["python3", str(script)], capture_output=True, text=True, timeout=600
    )
    payload = {
        "checker": checker,
        "exitCode": completed.returncode,
        "stdout": completed.stdout[-4000:],
        "stderr": completed.stderr[-4000:],
    }
    return payload, completed.returncode == 0, f"{checker} exited {completed.returncode}"


def _invoke_channel(
    root: Path,
    action: str,
    identifier: str | None,
    text: str | None,
) -> tuple[dict[str, Any] | None, bool, str]:
    target = _device_target()
    if target is None:
        return None, False, "no booted simulator answers this machine"
    argv = [action, "--device", target]
    if identifier is not None:
        argv.extend(["--identifier", identifier])
    if text is not None:
        argv.extend(["--text", text])
    arguments = transport.parse_arguments(argv)
    answer = transport.send_command(arguments)
    ok = bool(answer.get("success", False))
    detail = str(answer.get("message") or answer.get("error") or f"{action} answered")
    return answer, ok, detail


def _device_target() -> str | None:
    booted = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted", "-j"],
        capture_output=True,
        text=True,
    )
    if booted.returncode != 0:
        return None
    try:
        listing = json.loads(booted.stdout)
    except json.JSONDecodeError:
        return None
    for runtime in listing.get("devices", {}).values():
        for device in runtime:
            if device.get("state") == "Booted":
                return str(device.get("udid"))
    return None


def _device_target(root: Path) -> str | None:
    booted = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted", "-j"],
        capture_output=True,
        text=True,
    )
    if booted.returncode != 0:
        return None
    try:
        listing = json.loads(booted.stdout)
    except json.JSONDecodeError:
        return None
    for runtime in listing.get("devices", {}).values():
        for device in runtime:
            if device.get("state") == "Booted":
                return str(device.get("udid"))
    return None
