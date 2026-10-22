from __future__ import annotations

import dataclasses
import json
import subprocess
import sys
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
    precondition_outcomes = _run_preconditions(plan, root, run_directory)
    write_json(
        run_directory / "preconditions.json",
        {"unit": plan.unit, "preconditions": precondition_outcomes},
    )
    unmet = [item for item in precondition_outcomes if not item["ok"]]
    if unmet:
        verdict = "precondition"
        exit_code = EXIT_TERMINAL
    facts: dict[str, str] = {}
    for step in plan.steps if not unmet else ():
        resolved = dataclasses.replace(step, args=_fill(step.args, facts))
        outcome, hit = _run_step(resolved, plan, root, supervisor, steps_directory, budget_scale)
        if outcome.ok and step.capture:
            payload = getattr(outcome, "payload", None)
            if isinstance(payload, dict):
                for field, name in step.capture.items():
                    value = _resolve_field(payload, field)
                    if isinstance(value, (str, int, float)):
                        facts[name] = str(value)
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
        preconditions=tuple(precondition_outcomes),
    )
    write_json(run_directory / "report.json", report_payload(report))
    _append_index(evidence_root, report)
    return report


def _with_fields(payload: dict[str, Any]) -> dict[str, Any]:
    pairs = payload.get("payload")
    if not isinstance(pairs, list):
        return payload
    fields = {
        str(item).split("=", 1)[0]: str(item).split("=", 1)[1]
        for item in pairs
        if isinstance(item, str) and "=" in item
    }
    if not fields:
        return payload
    return {**payload, "fields": fields}


def _fill(value: Any, facts: dict[str, str]) -> Any:
    if isinstance(value, str):
        if value.startswith("$") and len(value) > 1 and value[1:] in facts:
            return facts[value[1:]]
        return value
    if isinstance(value, dict):
        return {key: _fill(item, facts) for key, item in value.items()}
    if isinstance(value, list):
        return [_fill(item, facts) for item in value]
    return value


def _run_preconditions(
    plan: Plan, root: Path, run_directory: Path
) -> list[dict[str, Any]]:
    outcomes: list[dict[str, Any]] = []
    for index, precondition in enumerate(plan.preconditions):
        kind = str(precondition.get("kind"))
        if kind == "media-server":
            provider = str(precondition.get("provider", ""))
            outcome = _ensure_media_server(provider, root)
        else:
            outcome = {
                "index": index,
                "kind": kind,
                "ok": False,
                "detail": f"{kind} has no implementation in this build",
            }
        outcome["index"] = index
        outcome["kind"] = kind
        outcomes.append(outcome)
    return outcomes


def _ensure_media_server(provider: str, root: Path) -> dict[str, Any]:
    script = root / "Scripts" / "verification" / "ensure_test_services.py"
    completed = subprocess.run(
        [sys.executable, str(script), "--service", provider],
        capture_output=True,
        text=True,
        cwd=str(root),
        timeout=900,
    )
    receipt: dict[str, Any] = {}
    try:
        receipt = json.loads(completed.stdout)
    except json.JSONDecodeError:
        receipt = {"stdout": completed.stdout[-2000:]}
    actions = [
        str(item.get("action"))
        for item in receipt.get("receipts", [])
        if isinstance(item, dict)
    ]
    ok = completed.returncode == 0 and any(
        action in {"found", "started", "configured"} for action in actions
    )
    return {
        "kind": "media-server",
        "provider": provider,
        "ok": ok,
        "action": actions[0] if actions else "none",
        "detail": (
            f"{provider} is {actions[0]}"
            if ok
            else f"{provider} did not resolve: {completed.stderr[-300:] or completed.stdout[-300:]}"
        ),
        "receipt": receipt,
    }


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


def _resolve_field(payload: Any, path: str) -> Any:
    current = payload
    for name in path.split("."):
        if isinstance(current, dict):
            current = current.get(name)
        else:
            return None
    return current


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
        evidence, ok, detail = _dispatch(step, root, plan, steps_directory)
        if ok and step.expect is not None:
            expectation = step.expect
            actual = _resolve_field(evidence, expectation.path)
            if expectation.contains is not None:
                if expectation.contains not in str(actual):
                    ok = False
                    detail = (
                        f"{expectation.path} does not contain "
                        f"{expectation.contains!r}"
                    )
            elif actual != expectation.equals:
                ok = False
                detail = (
                    f"{expectation.path} is {actual!r}, expected {expectation.equals!r}"
                )
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
            payload=evidence if isinstance(evidence, dict) else None,
        ),
        hit,
    )


def _dispatch(
    step: Step, root: Path, plan: Plan, steps_directory: Path
) -> tuple[dict[str, Any] | None, bool, str]:
    if step.verb == "static.check":
        return _run_static_check(step, root)
    if step.verb == "device.stage-media":
        return _run_stage_media(step, root, plan)
    if step.verb == "device.stage-identity":
        return _run_stage_identity(step, root, plan)
    if plan.transport == "daemon":
        return _dispatch_daemon(
            step, root, plan.target or _probe_target(), steps_directory
        )
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


def _await_matches(observed: dict[str, str], field: str, expected: Any, mode: str) -> bool:
    value = observed.get(field)
    if mode == "atLeast":
        try:
            return float(value) >= float(expected)
        except (TypeError, ValueError):
            return False
    return value == expected


def _dispatch_daemon(
    step: Step, root: Path, target: str, steps_directory: Path
) -> tuple[dict[str, Any] | None, bool, str]:
    import daemon as daemon_module

    if daemon_module.request(root, {"op": "ping"}, target, timeout=2).get("kind") != "result":
        daemon_module.ensure_running(root, target)
    if step.verb == "device.session.ensure":
        answer = daemon_module.request(
            root, {"op": "ensure", "lane": step.args.get("lane", "simulator")}, target
        )
    elif step.verb == "device.snapshot":
        answer = daemon_module.request(root, {"op": "invoke", "action": "snapshot"}, target)
    elif step.verb == "device.command":
        answer = daemon_module.request(
            root,
            {
                "op": "invoke",
                "action": step.args.get("action", "tap"),
                "identifier": step.args.get("identifier"),
                "identifiers": step.args.get("identifiers"),
                "label": step.args.get("label"),
                "text": step.args.get("text"),
            },
            target,
        )
    elif step.verb == "device.capture-frames":
        flags: list[str] = ["--output-directory", str(steps_directory)]
        if step.args.get("count") is not None:
            flags.extend(["--count", str(step.args["count"])])
        if step.args.get("intervalMs") is not None:
            flags.extend(["--interval-milliseconds", str(step.args["intervalMs"])])
        answer = daemon_module.request(
            root,
            {
                "op": "invoke",
                "action": "screenshotBurst",
                "identifier": step.args.get("identifier"),
                "flags": flags,
            },
            target,
        )
    elif step.verb == "device.await":
        probe = str(step.args.get("probe") or "")
        field = str(step.args.get("field") or "")
        expected = step.args.get("equals")
        mode = str(step.args.get("mode") or "equals")
        deadline = float(step.args.get("timeoutMs", 30_000)) / 1000.0
        interval = float(step.args.get("intervalMs", 250)) / 1000.0
        started = time.monotonic()
        attempts = 0
        observed: dict[str, str] = {}
        last_value: str | None = None
        reached = False
        while True:
            attempts += 1
            answer = daemon_module.request(
                root,
                {"op": "invoke", "action": "snapshot", "identifier": probe},
                target,
            )
            if answer.get("kind") == "result":
                value = answer.get("value", {})
                payload = value.get("payload") or {}
                element = payload.get("matchedElement") or {}
                raw = element.get("value") if isinstance(element, dict) else None
                if isinstance(raw, str):
                    last_value = raw
                    observed = dict(
                        part.split("=", 1) for part in raw.split(";") if "=" in part
                    )
                if not field and isinstance(raw, str):
                    if _await_matches({"": raw}, "", expected, mode):
                        reached = True
                        break
                elif _await_matches(observed, field, expected, mode):
                    reached = True
                    break
            if time.monotonic() - started >= deadline:
                break
            time.sleep(max(interval, 0.01))
        seen = last_value if not field else observed.get(field)
        detail = f"{seen!r} after {attempts} probe(s)"
        answer = (
            {
                "kind": "result",
                "value": {
                    "ok": True,
                    "detail": detail,
                    "payload": {
                        "attempts": attempts,
                        "elapsedMs": int((time.monotonic() - started) * 1000),
                        "fields": observed,
                    },
                },
            }
            if reached
            else {"kind": "error", "message": f"never reached {expected!r}; saw {detail}"}
        )
    elif step.verb == "device.app-command":
        answer = daemon_module.request(
            root,
            {
                "op": "invoke",
                "action": "app-command",
                "verb": step.args.get("verb"),
                "arguments": step.args.get("arguments") or {},
            },
            target,
        )
    elif step.verb == "device.probe":
        answer = daemon_module.request(
            root,
            {"op": "invoke", "action": "snapshot", "identifier": step.args.get("probe")},
            target,
        )
    elif step.verb == "app.relaunch":
        answer = daemon_module.request(root, {"op": "invoke", "action": "relaunch"}, target)
    else:
        return None, True, f"{step.verb} has no daemon dispatch"
    if answer.get("kind") != "result":
        return None, False, answer.get("message", "daemon refused")
    value = answer.get("value", {})
    payload = value.get("payload")
    if step.verb == "device.app-command" and isinstance(payload, dict):
        payload = _with_fields(payload)
    return payload, bool(value.get("ok")), str(value.get("detail", ""))


def _run_stage_media(
    step: Step, root: Path, plan: Plan
) -> tuple[dict[str, Any] | None, bool, str]:
    declared = step.args["source"]
    sources = (
        [_media_source(root, str(item)) for item in declared]
        if isinstance(declared, list)
        else [_media_source(root, str(declared))]
    )
    target = str(step.args["target"])
    device = plan.target or _probe_target()
    payload = transport.stage_media(device, transport.APP_BUNDLE_ID, sources, target)
    if payload is None:
        return None, False, f"could not reach the container on {device}"
    return payload, True, f"staged {payload['fileCount']} file(s) into {target}"


def _run_stage_identity(
    step: Step, root: Path, plan: Plan
) -> tuple[dict[str, Any] | None, bool, str]:
    source = _media_source(root, str(step.args["source"]))
    device = plan.target or _probe_target()
    payload = transport.stage_identity(device, transport.APP_BUNDLE_ID, source)
    if payload is None:
        return None, False, f"could not stage {source} on {device}"
    return payload, True, f"staged the identity with digest {payload['digest'][:19]}"


def _media_source(root: Path, declared: str) -> Path:
    if declared.startswith("test-media:"):
        remainder = declared.split(":", 1)[1]
        return root.parent / "TestMedia" / remainder
    return Path(declared)


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


def _probe_target() -> str:
    import machine

    return machine.probe().target or ""


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
