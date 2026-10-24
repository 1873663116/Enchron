from __future__ import annotations

import dataclasses
import hashlib
import json
import re
import getpass
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from guard import GuardrailHit, Supervisor
from model import Plan, Report, Step, StepOutcome, TerminalOutcome
import known as known_module
import report as report_module
import reuse as reuse_module
import transport
from report import (
    EXIT_GUARDRAIL,
    EXIT_OK,
    EXIT_TERMINAL,
    report_payload,
    write_json,
)
from vocab import VERBS




def run_plan(
    plan: Plan,
    root: Path,
    evidence_root: Path,
    budget_scale: float,
    assumed_preconditions: tuple[dict[str, Any], ...] | set[str] = frozenset(),
) -> Report:
    run_directory = _run_directory(evidence_root, plan.unit)
    steps_directory = run_directory / "steps"
    steps_directory.mkdir(parents=True, exist_ok=True)
    write_json(run_directory / "plan.json", _plan_snapshot(plan))
    supervisor = Supervisor(plan.guardrails, budget_scale)
    started = time.monotonic()
    outcomes: list[StepOutcome] = []
    verdict = "passed"
    exit_code = EXIT_OK
    assumed = set(assumed_preconditions)
    precondition_outcomes = [
        item
        for item in _run_preconditions(plan, root, run_directory, assumed)
    ]
    write_json(
        run_directory / "preconditions.json",
        {"unit": plan.unit, "preconditions": precondition_outcomes},
    )
    unmet = [item for item in precondition_outcomes if not item["ok"]]
    if unmet:
        verdict = "precondition"
        exit_code = EXIT_TERMINAL
    facts: dict[str, str] = {}
    if not unmet and plan.transport == "daemon" and plan.target:
        _clear_session_state(root, plan.target)
    prefetched = _prefetch_structural(plan, root) if not unmet else {}
    try:
        for step in plan.steps if not unmet else ():
            resolved = dataclasses.replace(step, args=_fill(step.args, facts))
            outcome, hit = _run_step(
                resolved, plan, root, supervisor, steps_directory, budget_scale
            )
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
    finally:
        _discard_prefetch(prefetched)
    for step in plan.teardown_steps:
        resolved = dataclasses.replace(step, args=_fill(step.args, facts))
        outcome, _ = _run_step(
            resolved, plan, root, supervisor, steps_directory, budget_scale
        )
        outcomes.append(outcome)
    known = None
    if verdict == "failed":
        known = known_module.matching(root, plan.unit, outcomes)
        if known is not None:
            verdict = "known"
            exit_code = report_module.EXIT_KNOWN
    terminal = _evaluate_terminal(plan, run_directory, steps_directory)
    if not terminal.ok and verdict == "passed":
        verdict = "failed"
        exit_code = EXIT_TERMINAL
    duration_ms = int((time.monotonic() - started) * 1000)
    report = Report(
        unit=plan.unit,
        digest=plan.digest,
        product_digest=reuse_module.product_digest(root),
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


DEFERRED_FAILURES = (
    "not currently hittable",
    "No current element matches",
)


def _journal_unhealthy(answer: dict[str, Any]) -> bool:
    if answer.get("kind") != "result":
        return False
    value = answer.get("value") or {}
    return "probe journal is unhealthy" in str(value.get("detail", "")).lower()


def _absent(answer: dict[str, Any]) -> bool:
    if answer.get("kind") != "result":
        return False
    value = answer.get("value") or {}
    return "No current element matches" in str(value.get("detail", ""))


def _settled(answer: dict[str, Any]) -> bool:
    if answer.get("kind") != "result":
        return True
    value = answer.get("value") or {}
    return bool(value.get("ok")) or not any(
        marker in str(value.get("detail", "")) for marker in DEFERRED_FAILURES
    )


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
    plan: Plan,
    root: Path,
    run_directory: Path,
    assumed: set[str] = frozenset(),
) -> list[dict[str, Any]]:
    outcomes: list[dict[str, Any]] = []
    for index, precondition in enumerate(plan.preconditions):
        kind = str(precondition.get("kind"))
        provider = str(precondition.get("provider", ""))
        key = f"{kind}:{provider}" if provider else kind
        if key in assumed:
            outcomes.append(
                {
                    "index": index,
                    "kind": kind,
                    "provider": provider,
                    "ok": True,
                    "action": "assumed",
                    "detail": f"{key} is assumed from a passing run",
                    "durationMs": 0,
                }
            )
            continue
        started = time.monotonic()
        if kind == "media-server":
            provider = str(precondition.get("provider", ""))
            outcome = _ensure_media_server(provider, root)
        elif kind == "media-progress":
            outcome = _ensure_media_progress(root)
        elif kind == "media-source":
            outcome = _ensure_media_source(str(precondition.get("provider", "")), root)
        elif kind == "media-fixture":
            outcome = _ensure_media_fixture(precondition, root)
        else:
            outcome = {
                "index": index,
                "kind": kind,
                "ok": False,
                "detail": f"{kind} has no implementation in this build",
            }
        outcome["index"] = index
        outcome["kind"] = kind
        if provider:
            outcome["provider"] = provider
        outcome.setdefault("durationMs", int((time.monotonic() - started) * 1000))
        outcomes.append(outcome)
    return outcomes


def _ensure_media_progress(root: Path) -> dict[str, Any]:
    script = root / "Scripts" / "verification" / "seed_emby_progress.py"
    completed = subprocess.run(
        [sys.executable, str(script)],
        capture_output=True,
        text=True,
        cwd=str(root),
        timeout=300,
    )
    receipt: dict[str, Any] = {}
    try:
        receipt = json.loads(completed.stdout)
    except json.JSONDecodeError:
        receipt = {"stdout": completed.stdout[-2000:]}
    episodes = receipt.get("episodes") or []
    ok = completed.returncode == 0 and receipt.get("ready") is True
    detail = (
        f"seeded progress on {len(episodes)} episode(s)"
        if ok
        else f"seed_emby_progress failed: {completed.stderr[-300:]}"
    )
    return {"ok": ok, "detail": detail, "receipt": receipt}


def _ensure_media_fixture(
    precondition: dict[str, Any], root: Path
) -> dict[str, Any]:
    media_root = root.parent / "TestMedia"
    missing = [
        str(name)
        for name in precondition.get("fixtures") or []
        if not list(media_root.rglob(str(name)))
    ]
    return {
        "kind": "media-fixture",
        "ok": not missing,
        "detail": "missing " + ", ".join(missing) if missing else "present",
    }


_MEDIA_SOURCE_CACHE: dict[tuple[str, str], dict[str, Any]] = {}


def _ensure_media_source(provider: str, root: Path) -> dict[str, Any]:
    cache_key = (str(root), provider)
    cached = _MEDIA_SOURCE_CACHE.get(cache_key)
    if cached is not None and cached.get("ok"):
        return cached
    cached = _read_service_cache(root, provider, "source")
    if cached is not None:
        _MEDIA_SOURCE_CACHE[cache_key] = cached
        return cached
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
        action in {"found", "started", "configured", "moved"} for action in actions
    )
    result = {
        "kind": "media-source",
        "provider": provider,
        "ok": ok,
        "detail": ", ".join(actions) or "no receipt",
        "receipt": receipt,
    }
    if ok:
        _MEDIA_SOURCE_CACHE[cache_key] = result
        _write_service_cache(root, provider, "source", result)
    return result


SERVICE_CACHE_ROOT = Path(".scratch/console/service-cache")
SERVICE_CACHE_SECONDS = 180.0


def _service_cache_path(root: Path, provider: str, kind: str) -> Path:
    return root / SERVICE_CACHE_ROOT / f"{provider}-{kind}.json"


def _read_service_cache(root: Path, provider: str, kind: str) -> dict[str, Any] | None:
    path = _service_cache_path(root, provider, kind)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    stamp = payload.get("stamp")
    if not isinstance(stamp, (int, float)):
        return None
    if time.time() - float(stamp) > SERVICE_CACHE_SECONDS:
        return None
    receipt = payload.get("receipt")
    return receipt if isinstance(receipt, dict) else None


def _write_service_cache(
    root: Path, provider: str, kind: str, receipt: dict[str, Any]
) -> None:
    path = _service_cache_path(root, provider, kind)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"stamp": time.time(), "receipt": receipt}, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass


def _ensure_media_server(provider: str, root: Path) -> dict[str, Any]:
    cached = _read_service_cache(root, provider, "server")
    if cached is not None:
        return cached
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
    result = {
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
    if ok:
        _write_service_cache(root, provider, "server", result)
    return result


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
    if step.verb == "static.structural-test":
        return _run_structural_test(step, root, plan)
    if step.verb == "device.viewing-storage":
        return _run_viewing_storage(step, root, plan)
    if step.verb == "device.source-facts":
        return _run_source_facts(step, root, plan)
    if step.verb == "device.connect-source":
        return _run_connect_source(step, root, plan)
    if step.verb == "device.fault-source":
        return _run_fault_source(step, root, plan)
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


def _expects_many(expected: Any) -> bool:
    return isinstance(expected, dict)


def _await_matches(observed: dict[str, str], field: str, expected: Any, mode: str) -> bool:
    if isinstance(expected, dict):
        return all(
            _await_matches(observed, name, target, mode)
            for name, target in expected.items()
        )
    value = observed.get(field)
    if mode == "atLeast":
        try:
            return float(value) >= float(expected)
        except (TypeError, ValueError):
            return False
    if mode == "differs":
        return value is not None and value != str(expected)
    return value == expected


SIMULATOR_UDID = re.compile(
    r"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"
)


def _is_simulator_target(target: str) -> bool:
    return bool(target) and SIMULATOR_UDID.match(target) is not None


def _hierarchy_ready(
    root: Path,
    target: str,
    seconds: float = 15.0,
    reject_modals: bool = False,
) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        answer = _daemon_request(
            root,
            {
                "op": "invoke",
                "action": "snapshot",
                "hierarchy": True,
                "no_screenshot": True,
            },
            target,
        )
        payload = (answer.get("value") or {}).get("payload") or {}
        hierarchy = payload.get("hierarchy")
        if isinstance(hierarchy, str) and len(hierarchy) > 200:
            if not reject_modals or not any(
                marker in hierarchy for marker in (" Sheet,", " Alert,")
            ):
                return True
        time.sleep(0.25)
    return False


def _wait_for_hierarchy(root: Path, target: str, seconds: float = 15.0) -> None:
    _hierarchy_ready(root, target, seconds)


def _clear_session_state(root: Path, target: str) -> None:
    for verb in ("exitSpatial", "leavePlayback", "resetMediaNavigation"):
        try:
            _daemon_request(
                root,
                {
                    "op": "invoke",
                    "action": "app-command",
                    "verb": verb,
                    "arguments": {},
                },
                target,
                timeout=60,
            )
        except OSError:
            pass
    if _hierarchy_ready(root, target, seconds=3.0, reject_modals=True):
        return
    try:
        _daemon_request(root, {"op": "restart"}, target, timeout=300)
    except OSError:
        return
    _hierarchy_ready(root, target, seconds=30.0, reject_modals=True)


def _dispatch_daemon(
    step: Step, root: Path, target: str, steps_directory: Path
) -> tuple[dict[str, Any] | None, bool, str]:
    import daemon as daemon_module

    if _daemon_request(root, {"op": "ping"}, target, timeout=2).get("kind") != "result":
        daemon_module.ensure_running(root, target)

    if step.verb == "device.session.ensure":
        answer = _daemon_request(
            root, {"op": "ensure", "lane": step.args.get("lane", "simulator")}, target
        )
    elif step.verb == "device.snapshot":
        answer = _daemon_request(
            root,
            {
                "op": "invoke",
                "action": "snapshot",
                "hierarchy": bool(step.args.get("hierarchy", True)),
            },
            target,
        )
    elif step.verb == "device.command":
        request: dict[str, Any] = {"op": "invoke"}
        for key in (
            "identifier",
            "identifiers",
            "identifierPrefix",
            "label",
            "labelPrefix",
            "waitMilliseconds",
            "text",
            "index",
            "trailingLabel",
            "duration",
            "normalizedX",
            "normalizedY",
        ):
            request[key] = step.args.get(key)
        request["action"] = step.args.get("action", "tap")
        request["hierarchy"] = bool(step.args.get("hierarchy"))
        answer = _daemon_request(root, request, target)
        attempts = 8 if _absent(answer) else 3
        for _ in range(attempts):
            if answer.get("kind") == "result" and _settled(answer):
                break
            time.sleep(0.5)
            answer = _daemon_request(root, request, target)
    elif step.verb == "device.set-stereo-layout":
        answer = _daemon_request(
            root,
            {
                "op": "invoke",
                "action": "app-command",
                "verb": "setStereoLayout",
                "arguments": {"layout": str(step.args.get("layout"))},
            },
            target,
        )
    elif step.verb == "device.app-commands":
        calls = step.args.get("calls") or []
        answer = _daemon_request(
            root,
            {
                "op": "invoke",
                "action": "app-command",
                "verb": "batch",
                "arguments": {"calls": json.dumps(calls, ensure_ascii=False)},
            },
            target,
        )
    elif step.verb == "device.home":
        answer = _daemon_request(
            root,
            {
                "op": "invoke",
                "action": "app-command",
                "verb": "returnHome",
                "arguments": {"clear": "true"} if step.args.get("clear") else {},
            },
            target,
        )
        if answer.get("kind") == "result" and answer.get("value", {}).get("ok"):
            answer = {
                "kind": "result",
                "value": {
                    "ok": True,
                    "detail": "the library home is in front",
                    "payload": {"outcome": "home"},
                },
            }
        else:
            _daemon_request(
                root,
                {
                    "op": "invoke",
                    "action": "app-command",
                    "verb": "leavePlayback",
                    "arguments": {},
                },
                target,
            )
            answer = _daemon_request(
                root,
                {
                    "op": "invoke",
                    "action": "tap",
                    "identifier": "Navigation-Ornament-tab-files",
                },
                target,
            )
            answer = {
                "kind": "result",
                "value": {
                    "ok": True,
                    "detail": "the library home is in front",
                    "payload": {"outcome": "home"},
                },
            }
    elif step.verb == "device.capture-frames":
        answer: dict[str, Any] | None = None
        if _is_simulator_target(target):
            count = max(1, int(step.args.get("count") or 1))
            interval = max(0.0, float(step.args.get("intervalMs") or 0) / 1000.0)
            captured = time.monotonic()
            written: list[str] = []
            host_error = ""
            staging = Path(tempfile.mkdtemp(prefix="enchron-frames-"))
            try:
                for index in range(count):
                    staged = staging / f"frame-{index:02d}.png"
                    completed = subprocess.run(
                        [
                            "xcrun",
                            "simctl",
                            "io",
                            target,
                            "screenshot",
                            "--type=png",
                            str(staged),
                        ],
                        capture_output=True,
                        text=True,
                    )
                    if completed.returncode != 0:
                        host_error = (completed.stderr or completed.stdout).strip()
                        break
                    destination = steps_directory / f"{step.index:02d}-frame-{index:02d}.png"
                    shutil.move(str(staged), str(destination))
                    written.append(str(destination))
                    if interval > 0 and index + 1 < count:
                        time.sleep(interval)
            finally:
                shutil.rmtree(staging, ignore_errors=True)
            if written:
                elapsed = int((time.monotonic() - captured) * 1000)
                answer = {
                    "kind": "result",
                    "value": {
                        "ok": True,
                        "detail": f"Captured {len(written)} frames over {elapsed} ms.",
                        "payload": {"frames": written},
                    },
                }
        if answer is None:
            if host_error:
                try:
                    log = steps_directory.parent.parent / "host-capture.log"
                    with log.open("a", encoding="utf-8") as handle:
                        handle.write(f"{steps_directory.name} step {step.index}: {host_error}\n")
                except OSError:
                    pass
            flags: list[str] = ["--output-directory", str(steps_directory)]
            if step.args.get("count") is not None:
                flags.extend(["--count", str(step.args["count"])])
            if step.args.get("intervalMs") is not None:
                flags.extend(["--interval-milliseconds", str(step.args["intervalMs"])])
            answer = _daemon_request(
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
            answer = _daemon_request(
                root,
                {
                    "op": "invoke",
                    "action": "snapshot",
                    "identifier": None if probe == "element" else probe,
                    "hierarchy": True,
                },
                target,
            )
            if probe == "viewing-storage":
                answer = _daemon_request(
                    root,
                    {
                        "op": "invoke",
                        "action": "app-command",
                        "verb": "viewingStorageProbe",
                        "arguments": {},
                    },
                    target,
                )
                value = answer.get("value", {})
                payload = value.get("payload") or {}
                canonical = json.dumps(
                    payload.get("viewingStorageSnapshot") or {},
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
                normalized = {
                    "snapshotDigest": "sha256:"
                    + hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
                    "viewingStateRecordCount": _resolve_field(
                        payload, "viewingStorageSnapshot.viewingState.viewingRecordCount"
                    ),
                    "persistedRecordCount": _resolve_field(
                        payload, "viewingStorageSnapshot.viewingState.persistedRecordCount"
                    ),
                    "containerIndexEntryCount": _resolve_field(
                        payload, "viewingStorageSnapshot.containerIndex.entryCount"
                    ),
                }
                names = list(expected) if isinstance(expected, dict) else [field]
                observed = {}
                for name in names:
                    if name in normalized:
                        current = normalized[name]
                    else:
                        current = _resolve_field(payload, name)
                    observed[name] = "" if current is None else str(current)
                last_value = observed[names[0]]
                if _await_matches(observed, field, expected, mode):
                    reached = True
                    break
            elif answer.get("kind") == "result" and probe == "element":
                value = answer.get("value", {})
                payload = value.get("payload") or {}
                hierarchy = payload.get("hierarchy")
                if isinstance(hierarchy, str) and field == "identifierPrefix":
                    if re.search(rf"identifier: '{re.escape(str(expected))}", hierarchy):
                        reached = True
                        break
                elif isinstance(hierarchy, str):
                    wanted = (
                        {str(name): str(value) for name, value in expected.items()}
                        if isinstance(expected, dict)
                        else {field: str(expected)}
                    )
                    observed = {
                        name: value
                        for name, value in wanted.items()
                        if re.search(
                            rf"{name}: '{re.escape(value)}'",
                            hierarchy,
                        )
                        is not None
                    }
                    matched = len(observed) == len(wanted)
                    if (mode == "absent" and not matched) or (
                        mode != "absent" and matched
                    ):
                        reached = True
                        break
            elif answer.get("kind") == "result":
                value = answer.get("value", {})
                payload = value.get("payload") or {}
                element = payload.get("matchedElement") or {}
                raw = element.get("value") if isinstance(element, dict) else None
                if isinstance(raw, str):
                    last_value = raw
                    observed = dict(
                        part.split("=", 1) for part in raw.split(";") if "=" in part
                    )
                if isinstance(expected, dict):
                    if _await_matches(observed, "", expected, mode):
                        reached = True
                        break
                elif not field and isinstance(raw, str):
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
        request = {
            "op": "invoke",
            "action": "app-command",
            "verb": step.args.get("verb"),
            "arguments": step.args.get("arguments") or {},
        }
        answer = _daemon_request(root, request, target)
        if _journal_unhealthy(answer):
            _daemon_request(
                root, {"op": "invoke", "action": "relaunch"}, target
            )
            answer = _daemon_request(root, request, target)
    elif step.verb == "device.probe":
        probe = step.args.get("probe")
        answer = _daemon_request(
            root,
            {"op": "invoke", "action": "snapshot", "identifier": probe, "hierarchy": True},
            target,
        )
        if (
            answer.get("kind") == "result"
            and answer.get("value", {}).get("ok")
            and probe
            and step.expect is None
        ):
            payload = answer["value"].get("payload") or {}
            if not isinstance(payload.get("matchedElement"), dict):
                answer = {
                    "kind": "result",
                    "value": {
                        "ok": False,
                        "detail": f"no element carries the identifier {probe}",
                        "payload": payload,
                    },
                }
    elif step.verb == "app.relaunch":
        answer = _daemon_request(root, {"op": "invoke", "action": "relaunch"}, target)
        if answer.get("kind") == "result" and answer.get("value", {}).get("ok"):
            _wait_for_hierarchy(root, target)
    else:
        return None, True, f"{step.verb} has no daemon dispatch"
    if answer.get("kind") != "result":
        return None, False, answer.get("message", "daemon refused")
    value = answer.get("value", {})
    payload = value.get("payload")
    if step.verb == "device.app-command" and isinstance(payload, dict):
        payload = _with_fields(payload)
    return payload, bool(value.get("ok")), str(value.get("detail", ""))


def _daemon_request(
    root: Path, payload: dict[str, Any], target: str, timeout: float = 1200
) -> dict[str, Any]:
    import daemon as daemon_module

    answer = daemon_module.request(root, payload, target, timeout)
    if answer.get("kind") == "error" and answer.get("message") == "no daemon socket":
        daemon_module.ensure_running(root, target)
        answer = daemon_module.request(root, payload, target, timeout)
    return answer



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


def _environment_credentials(root: Path, provider: str) -> dict[str, str]:
    path = root / ".env"
    if not path.is_file():
        return {}
    prefix = {"webdav": "WEBDAV", "smb": "SMB", "emby": "EMBY"}.get(provider, provider.upper())
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line or line.strip().startswith("#"):
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    user = values.get(f"{prefix}_USER")
    secret = values.get(f"{prefix}_PASSWORD")
    if user and secret:
        return {"username": user, "password": secret}
    return {}


def _address_hosts(address: str) -> list[str]:
    from urllib.parse import urlsplit

    parts = urlsplit(address)
    host = (parts.hostname or "").lower()
    port = parts.port or (443 if parts.scheme == "https" else 80)
    hosts = [f"{host}:{port}"] if host else []
    resolved = _lan_address(host)
    if resolved:
        hosts.append(f"{resolved}:{port}")
    return hosts


def _lan_address(host: str) -> str | None:
    try:
        completed = subprocess.run(
            ["/usr/bin/dscacheutil", "-q", "host", "-a", "name", f"{host}."],
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    for line in completed.stdout.splitlines():
        if line.startswith("ip_address:"):
            candidate = line.split(":", 1)[1].strip()
            if candidate.count(".") == 3:
                return candidate
    return None


def _remote_source_controller(root: Path, provider: str):
    import sys

    verification = root / "Scripts" / "verification"
    if str(verification) not in sys.path:
        sys.path.insert(0, str(verification))
    import regression_remote_source as remote

    from ensure_test_services import primary_lan_ipv4

    configuration = remote.ServiceConfiguration(
        runtime_root=root.parent / "test-services" / provider,
        registry_path=remote.DEFAULT_REGISTRY,
        source_root=remote.DEFAULT_SOURCE_ROOT,
        bind_host=primary_lan_ipv4() or "127.0.0.1",
        port=8443 if provider == "webdav" else 445,
    )
    return remote, remote.RemoteSourceController(configuration)


def _run_fault_source(
    step: Step, root: Path, plan: Plan
) -> tuple[dict[str, Any] | None, bool, str]:
    provider = str(step.args.get("provider", "webdav"))
    phase = str(step.args.get("phase", "activate"))
    recipe = str(step.args.get("recipe", ""))
    try:
        remote, controller = _remote_source_controller(root, provider)
    except Exception as error:
        return None, False, f"the {provider} controller is unavailable: {error}"
    try:
        if phase == "activate":
            _restore_active_recipe(controller)
            receipt = controller.activate(recipe)
            ACTIVE_FAULTS.append(receipt.get("receiptID", ""))
            return receipt, True, f"activated the {recipe} recipe"
        if phase == "restore":
            if not ACTIVE_FAULTS:
                return {}, True, "no fault was active"
            receipt_id = ACTIVE_FAULTS.pop()
            report = controller.restore(str(receipt_id))
            return report, True, f"restored {receipt_id}"
    except Exception as error:
        return None, False, f"the {provider} recipe {recipe} was rejected: {error}"
    return None, False, f"unknown phase {phase}"


def _restore_active_recipe(controller) -> None:
    status = controller.status()
    active_recipe = str(status.get("recipe", "healthy"))
    generation = int(status.get("generation", 0))
    for candidate in (generation, generation - 1):
        try:
            controller.restore(f"receipt:g-{candidate:06d}:{active_recipe}")
            return
        except Exception:
            continue
    if active_recipe == "healthy":
        return
    controller.stop()
    controller.ensure()


ACTIVE_FAULTS: list[str] = []


def _display_fingerprint(fingerprint: str) -> str:
    hex_digits = fingerprint.split(":", 1)[1] if fingerprint.startswith("sha256:") else fingerprint
    hex_digits = "".join(character for character in hex_digits if character in "0123456789abcdefABCDEF")
    pairs = [hex_digits[index : index + 2].upper() for index in range(0, len(hex_digits), 2)]
    return ":".join(pairs)


def _certificate_already_trusted(
    device: str, host: str, expected: str
) -> bool:
    completed = subprocess.run(
        [
            "xcrun",
            "simctl",
            "spawn",
            device,
            "defaults",
            "read",
            transport.APP_BUNDLE_ID,
            f"server-certificate-fingerprint.{host}",
        ],
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        return False
    return completed.stdout.strip() == expected


def _trust_certificate(
    root: Path, device: str, address: str, fingerprint: str
) -> None:
    fingerprint = _display_fingerprint(fingerprint)
    hosts = _address_hosts(address)
    if hosts and all(
        _certificate_already_trusted(device, host, fingerprint) for host in hosts
    ):
        return
    if hosts:
        answer = _daemon_request(
            root,
            {
                "op": "invoke",
                "action": "app-command",
                "verb": "trustCertificate",
                "arguments": {
                    "addresses": ",".join(hosts),
                    "fingerprint": fingerprint,
                },
            },
            device,
        )
        if answer.get("kind") == "result" and (answer.get("value") or {}).get("ok"):
            return
    for host in hosts:
        subprocess.run(
            [
                "xcrun",
                "simctl",
                "spawn",
                device,
                "defaults",
                "write",
                transport.APP_BUNDLE_ID,
                f"server-certificate-fingerprint.{host}",
                fingerprint,
            ],
            capture_output=True,
        )
    transport.send_command(
        transport.parse_arguments(
            [
                "relaunch",
                "--device",
                device,
                "--no-screenshot",
                "--output-directory",
                "/tmp/enchron-connect",
            ]
        )
    )
    time.sleep(3.0)


STRUCTURAL_CHECKS: dict[str, tuple[str, ...]] | None = None


def _structural_commands() -> dict[str, tuple[str, ...]]:
    global STRUCTURAL_CHECKS
    if STRUCTURAL_CHECKS is None:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))
        import regression_operation_adapter as adapter

        STRUCTURAL_CHECKS = {
            str(name): tuple(str(item) for item in command)
            for name, command in adapter.STRUCTURAL_CHECKS.items()
        }
    return STRUCTURAL_CHECKS


STRUCTURAL_PREFETCH: dict[tuple[str, int], subprocess.Popen[str]] = {}


def _prefetch_structural(
    plan: Plan, root: Path
) -> dict[tuple[str, int], subprocess.Popen[str]]:
    commands = _structural_commands()
    environment = dict(os.environ)
    environment.setdefault(
        "DEVELOPER_DIR", "/Volumes/Cortisol/Applications/Xcode27.2RC.app/Contents/Developer"
    )
    started: dict[tuple[str, int], subprocess.Popen[str]] = {}
    for step in plan.steps:
        if step.verb != "static.structural-test":
            continue
        command = commands.get(str(step.args.get("check", "")))
        if command is None:
            continue
        process = subprocess.Popen(
            list(command),
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        key = (plan.digest, step.index)
        STRUCTURAL_PREFETCH[key] = process
        started[key] = process
    return started


def _discard_prefetch(
    started: dict[tuple[str, int], subprocess.Popen[str]]
) -> None:
    for key, process in started.items():
        STRUCTURAL_PREFETCH.pop(key, None)
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()


def _run_structural_test(
    step: Step, root: Path, plan: Plan | None = None
) -> tuple[dict[str, Any] | None, bool, str]:
    check = str(step.args.get("check", ""))
    commands = _structural_commands()
    command = commands.get(check)
    if command is None:
        return {"check": check}, False, f"{check} is not a known structural check"
    environment = dict(os.environ)
    environment.setdefault(
        "DEVELOPER_DIR", "/Volumes/Cortisol/Applications/Xcode27.2RC.app/Contents/Developer"
    )
    process = None
    if plan is not None:
        process = STRUCTURAL_PREFETCH.get((plan.digest, step.index))
    if process is not None:
        try:
            stdout, stderr = process.communicate(timeout=900)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate()
        completed = subprocess.CompletedProcess(
            list(command), process.returncode, stdout, stderr
        )
    else:
        completed = subprocess.run(
            list(command),
            cwd=root,
            capture_output=True,
            text=True,
            timeout=900,
            env=environment,
        )
    payload = {
        "check": check,
        "command": " ".join(command),
        "exitCode": completed.returncode,
        "stdout": completed.stdout[-8000:],
        "stderr": completed.stderr[-8000:],
    }
    return payload, completed.returncode == 0, f"{check} exited {completed.returncode}"


def _run_viewing_storage(
    step: Step, root: Path, plan: Plan
) -> tuple[dict[str, Any] | None, bool, str]:
    target = plan.target or _probe_target()
    answer = _daemon_request(
        root,
        {
            "op": "invoke",
            "action": "app-command",
            "verb": "viewingStorageProbe",
            "arguments": {},
        },
        target,
    )
    if answer.get("kind") != "result":
        return None, False, answer.get("message", "daemon refused the storage probe")
    value = answer.get("value", {})
    payload = value.get("payload")
    if not isinstance(payload, dict):
        return None, False, str(value.get("detail") or "the storage probe answered no payload")
    snapshot = payload.get("viewingStorageSnapshot")
    if not isinstance(snapshot, dict):
        return None, False, "the storage probe answered no viewing storage snapshot"
    canonical = json.dumps(
        snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    enriched = {
        **payload,
        "snapshotDigest": "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
        "viewingStateRecordCount": int(
            _resolve_field(snapshot, "viewingState.persistedRecordCount") or 0
        ),
        "containerIndexEntryCount": int(
            _resolve_field(snapshot, "containerIndex.entryCount") or 0
        ),
        "viewingStateProtectedStateDigest": str(
            _resolve_field(snapshot, "viewingState.protectedStateDigest") or ""
        ),
        "protectedStateDigest": str(
            _resolve_field(snapshot, "protectedState.digest") or ""
        ),
    }
    return (
        enriched,
        True,
        f"viewing storage snapshot {enriched['snapshotDigest']}",
    )


def _run_source_facts(
    step: Step, root: Path, plan: Plan
) -> tuple[dict[str, Any] | None, bool, str]:
    provider = str(step.args.get("provider", "webdav"))
    receipt = _ensure_media_source(provider, root)
    address = ""
    for item in (receipt.get("receipt") or {}).get("receipts", []):
        address = str(item.get("address") or "")
        if address:
            break
    if not address:
        return None, False, f"the {provider} source has no reachable address"
    fingerprint = ""
    runtime_payload: dict[str, Any] = {}
    runtime_file = root.parent / "test-services" / provider / "runtime.json"
    if runtime_file.is_file():
        try:
            runtime_payload = json.loads(runtime_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            runtime_payload = {}
        fingerprint = str(runtime_payload.get("certificateFingerprint") or "")
    if step.args.get("trust") is True and fingerprint:
        device = plan.target or _probe_target()
        _trust_certificate(root, device, address, fingerprint)
    credentials = _environment_credentials(root, provider)
    payload = {
        "url": address,
        "username": str(runtime_payload.get("user") or credentials.get("username", "")),
        "password": str(
            runtime_payload.get("password") or credentials.get("password", "")
        ),
    }
    return payload, True, f"{provider} facts at {address}"


def _run_connect_source(
    step: Step, root: Path, plan: Plan
) -> tuple[dict[str, Any] | None, bool, str]:
    provider = str(step.args.get("provider", "webdav"))
    name = str(step.args.get("name", "Enchron Regression WebDAV"))
    try:
        _, controller = _remote_source_controller(root, provider)
        _restore_active_recipe(controller)
    except Exception:
        pass
    receipt = _ensure_media_source(provider, root)
    address = ""
    for item in (receipt.get("receipt") or {}).get("receipts", []):
        address = str(item.get("address") or "")
        if address:
            break
    if not address:
        return None, False, f"the {provider} source has no reachable address"
    fingerprint = ""
    runtime_file = root.parent / "test-services" / provider / "runtime.json"
    if runtime_file.is_file():
        try:
            runtime_payload = json.loads(runtime_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            runtime_payload = {}
        fingerprint = str(runtime_payload.get("certificateFingerprint") or "")
    if not fingerprint:
        for item in (receipt.get("receipt") or {}).get("receipts", []):
            for candidate in (item.get("evidence") or {}).get("candidates", []):
                observed = str(candidate.get("observedIdentity") or "")
                if observed.startswith("sha256:"):
                    fingerprint = observed
                    break
            if fingerprint:
                break
    device = plan.target or _probe_target()
    if fingerprint:
        _trust_certificate(root, device, address, fingerprint)
    recipe = str(step.args.get("recipe") or "")
    if recipe:
        try:
            _, controller = _remote_source_controller(root, provider)
            _restore_active_recipe(controller)
            controller.activate(recipe)
        except Exception:
            pass
    expect_failure = bool(step.args.get("expectFailure"))
    credentials = _environment_credentials(root, provider)
    answer = _daemon_request(
        root,
        {
            "op": "invoke",
            "action": "app-command",
            "verb": "connectWebDAV",
            "arguments": {"url": address, "name": name, **credentials},
        },
        device,
    )
    payload = (answer.get("value") or {}).get("payload") or {}
    connected = bool((answer.get("value") or {}).get("ok"))
    if expect_failure:
        if connected:
            return payload, False, f"{name} connected although the {recipe} recipe was active"
        return payload, True, f"{name} failed to connect with the {recipe} recipe active"
    if not connected:
        return payload, False, f"the app could not connect {address}"
    return payload, True, f"connected {name} at {address}"


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
