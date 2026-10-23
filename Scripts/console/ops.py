"""Direct operation execution for debugging.

An operation is one verb with its arguments. `console op` runs it against the
live session, prints the result and a short state summary, and writes the
payload under `.scratch/console/debug/`. It never writes under TestEvidence and
never appears in the reuse index, so no debugging run can be mistaken for
adjudicated evidence.

`console replay` runs a recorded sequence again. `console unit scaffold` turns
the sequence into a unit draft a person completes before it joins
Config/console/units.
"""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import engine
import report as report_module
from compile import GUARDRAIL_SET
from guard import Supervisor
from model import MachineProfile, Plan, Step, Terminal
from vocab import VERBS, Verb


DEBUG_ROOT = Path(".scratch/console/debug")
SESSION_SCHEMA = "enchron.console.debug-session"
OPERATION_SCHEMA = "enchron.console.operation"
SESSION_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

DIRECT_VERBS = frozenset(
    {
        "static.check",
        "static.structural-test",
        "device.stage-media",
        "device.stage-identity",
        "device.viewing-storage",
        "device.source-facts",
        "device.connect-source",
        "device.fault-source",
    }
)

STATE_KEYS = (
    "outcome",
    "screen",
    "count",
    "fileCount",
    "matchedIdentifier",
    "matchedLabel",
    "bytesWritten",
)


class OperationRefusal(ValueError):
    pass


def validate_session_name(name: str) -> None:
    if not SESSION_NAME.match(name):
        raise OperationRefusal(
            f"session name {name!r} must be letters, digits, '.', '_' or '-'"
        )


def parse_arguments(text: str) -> dict[str, Any]:
    try:
        payload = json.loads(text or "{}")
    except json.JSONDecodeError as error:
        raise OperationRefusal(f"--args is not json: {error.msg}") from None
    if not isinstance(payload, dict):
        raise OperationRefusal("--args must be a json object")
    return payload


def validate_operation(name: str, args: dict[str, Any]) -> Verb:
    verb = VERBS.get(name)
    if verb is None:
        raise OperationRefusal(
            f"verb {name!r} is outside the vocabulary; adding it needs a recompile"
        )
    if not isinstance(args, dict):
        raise OperationRefusal("--args must be a json object")
    unknown = sorted(set(args) - set(verb.parameter))
    if unknown:
        raise OperationRefusal(
            f"verb {name!r} does not take {', '.join(unknown)}"
        )
    for parameter, allowed in verb.choices.items():
        if parameter in args and args[parameter] not in allowed:
            raise OperationRefusal(
                f"{name} takes {', '.join(allowed)} for {parameter}"
            )
    return verb


def operation_transport(verb: Verb) -> str:
    if verb.lane is None or verb.name in DIRECT_VERBS:
        return "direct"
    return "daemon"


def state_summary(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {}
    summary: dict[str, Any] = {}
    fields = payload.get("fields")
    if isinstance(fields, dict):
        summary.update({str(key): value for key, value in fields.items()})
    for key in STATE_KEYS:
        value = payload.get(key)
        if isinstance(value, (str, int, float, bool)):
            summary[key] = value
    return summary


def operation_plan(verb: Verb, target: str) -> Plan:
    return Plan(
        unit=f"unit:op.{verb.name.replace('.', '-')}@1",
        tier="e2e",
        transport=operation_transport(verb),
        target=target,
        layer=3 if verb.lane else 2,
        requires=verb.capabilities,
        steps=(
            Step(
                index=1,
                verb=verb.name,
                args={},
                expect=None,
                evidence=verb.evidence,
            ),
        ),
        terminal=Terminal(kind="artifact", path=None, equals=None, schema=None),
        guardrails=GUARDRAIL_SET,
        evidence=(),
        digest="op",
    )


def _ensure_session(root: Path, target: str) -> tuple[int, str]:
    import daemon as daemon_module

    started = time.monotonic()
    if not daemon_module.ensure_running(root, target):
        raise OperationRefusal("the daemon did not start")
    answer = daemon_module.request(
        root, {"op": "ensure", "lane": "simulator"}, target, timeout=1200
    )
    elapsed = int((time.monotonic() - started) * 1000)
    value = answer.get("value") or {}
    if answer.get("kind") != "result" or not value.get("ok"):
        raise OperationRefusal(
            "the session is not ready: " + str(value.get("detail") or answer.get("message"))
        )
    return elapsed, str(value.get("detail") or "")


def execute_operation(
    root: Path,
    verb: Verb,
    args: dict[str, Any],
    target: str,
    steps_directory: Path,
    timeout_scale: float,
) -> dict[str, Any]:
    plan = operation_plan(verb, target)
    step = Step(
        index=1,
        verb=verb.name,
        args=dict(args),
        expect=None,
        evidence=verb.evidence,
    )
    session_ms = 0
    session_detail = ""
    if plan.transport == "daemon" and verb.name != "device.session.ensure":
        session_ms, session_detail = _ensure_session(root, target)
    supervisor = Supervisor(plan.guardrails, timeout_scale)
    outcome, _ = engine._run_step(
        step, plan, root, supervisor, steps_directory, timeout_scale
    )
    return {
        "ok": outcome.ok,
        "detail": outcome.detail,
        "durationMs": outcome.duration_ms,
        "guardrails": list(outcome.guardrails),
        "payload": outcome.payload,
        "target": target,
        "sessionEnsureMs": session_ms,
        "sessionDetail": session_detail,
    }


def session_directory(root: Path, name: str) -> Path:
    validate_session_name(name)
    return root / DEBUG_ROOT / name


def _write_json(path: Path, payload: Any) -> None:
    report_module.write_json(path, payload)


def record_operation(
    root: Path,
    name: str,
    index: int,
    verb_name: str,
    args: dict[str, Any],
    result: dict[str, Any],
) -> Path:
    directory = session_directory(root, name)
    meta_path = directory / "session.json"
    if not meta_path.exists():
        _write_json(
            meta_path,
            {
                "schema": SESSION_SCHEMA,
                "schemaVersion": 1,
                "name": name,
                "target": result.get("target", ""),
                "createdAt": datetime.now(timezone.utc).isoformat(),
            },
        )
    payload_name = f"{index:02d}-{verb_name.replace('.', '-')}.json"
    payload_path = directory / "ops" / payload_name
    entry = {
        "schema": OPERATION_SCHEMA,
        "schemaVersion": 1,
        "index": index,
        "verb": verb_name,
        "args": args,
        "ok": result.get("ok", False),
        "durationMs": result.get("durationMs", 0),
        "detail": result.get("detail", ""),
        "state": state_summary(result.get("payload")),
        "guardrails": result.get("guardrails", []),
        "sessionEnsureMs": result.get("sessionEnsureMs", 0),
        "payload": payload_path.relative_to(directory).as_posix(),
        "at": datetime.now(timezone.utc).isoformat(),
    }
    _write_json(payload_path, entry)
    with (directory / "session.jsonl").open("a", encoding="utf-8") as sink:
        sink.write(json.dumps(entry, sort_keys=True) + "\n")
    return payload_path


def read_session(root: Path, name: str) -> list[dict[str, Any]]:
    directory = session_directory(root, name)
    path = directory / "session.jsonl"
    if not path.is_file():
        raise OperationRefusal(f"no debug session named {name!r}")
    entries: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    if not entries:
        raise OperationRefusal(f"debug session {name!r} has no operations")
    return entries


def run_operation(
    root: Path,
    profile: MachineProfile,
    verb_name: str,
    args: dict[str, Any],
    session: str = "",
    timeout_scale: float = 1.0,
    execute: Callable[..., dict[str, Any]] | None = None,
) -> dict[str, Any]:
    verb = validate_operation(verb_name, args)
    target = profile.target or ""
    if operation_transport(verb) == "daemon" and not target:
        raise OperationRefusal("no target device; set ENCHRON_TARGET_DEVICE or boot a simulator")
    directory = (
        session_directory(root, session)
        if session
        else root / DEBUG_ROOT / f"adhoc-{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}"
    )
    steps_directory = directory / "ops"
    steps_directory.mkdir(parents=True, exist_ok=True)
    handler = execute or execute_operation
    if session:
        directory.mkdir(parents=True, exist_ok=True)
        journal = directory / "session.jsonl"
        recorded = (
            sum(1 for line in journal.read_text(encoding="utf-8").splitlines() if line.strip())
            if journal.exists()
            else 0
        )
        index = recorded + 1
    else:
        index = 1
    started = time.monotonic()
    try:
        result = handler(root, verb, args, target, steps_directory, timeout_scale)
    except OperationRefusal:
        raise
    except Exception as error:
        result = {
            "ok": False,
            "detail": f"{type(error).__name__}: {error}",
            "durationMs": int((time.monotonic() - started) * 1000),
            "guardrails": [],
            "payload": None,
            "target": target,
            "sessionEnsureMs": 0,
        }
    if session:
        record_operation(root, session, index, verb_name, args, result)
    result["verb"] = verb_name
    result["args"] = args
    result["state"] = state_summary(result.get("payload"))
    result["session"] = session
    result["index"] = index
    result["stepsDirectory"] = str(steps_directory)
    return result


def replay_session(
    root: Path,
    profile: MachineProfile,
    name: str,
    timeout_scale: float = 1.0,
    execute: Callable[..., dict[str, Any]] | None = None,
) -> dict[str, Any]:
    entries = read_session(root, name)
    results: list[dict[str, Any]] = []
    mismatched: list[dict[str, Any]] = []
    for entry in entries:
        result = run_operation(
            root,
            profile,
            str(entry["verb"]),
            dict(entry.get("args") or {}),
            session="",
            timeout_scale=timeout_scale,
            execute=execute,
        )
        matched = bool(result["ok"]) == bool(entry["ok"])
        results.append(
            {
                "index": entry["index"],
                "verb": entry["verb"],
                "ok": result["ok"],
                "recordedOk": entry["ok"],
                "matched": matched,
                "durationMs": result["durationMs"],
                "recordedDurationMs": entry["durationMs"],
                "detail": result["detail"],
            }
        )
        if not matched:
            mismatched.append(results[-1])
    summary = {
        "schema": "enchron.console.debug-replay",
        "schemaVersion": 1,
        "session": name,
        "operations": len(entries),
        "matched": len(entries) - len(mismatched),
        "mismatched": mismatched,
        "results": results,
        "at": datetime.now(timezone.utc).isoformat(),
    }
    replay_directory = (
        session_directory(root, name)
        / "replays"
        / time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    )
    _write_json(replay_directory / "summary.json", summary)
    return summary


def scaffold_unit(root: Path, name: str, out: str = "") -> dict[str, Any]:
    entries = read_session(root, name)
    actions: list[dict[str, Any]] = []
    requires: set[str] = set()
    layer = 2
    terminal: dict[str, Any] | None = None
    for entry in entries:
        verb = VERBS.get(entry["verb"])
        if verb is None:
            continue
        actions.append({"verb": verb.name, "args": dict(entry.get("args") or {})})
        requires.update(verb.capabilities - {"python"})
        if verb.lane:
            layer = 3
        if verb.evidence:
            terminal = {"kind": "artifact", "path": verb.evidence}
    if terminal is None:
        terminal = {"kind": "assert", "path": "terminal.json"}
    identifier = f"unit:debug.{name.replace('_', '-')}@1"
    metadata = {
        "schema": "enchron.console.unit",
        "schemaVersion": 1,
        "id": identifier,
        "layer": layer,
        "role": "verification",
        "requires": sorted(requires),
        "actions": actions,
        "terminal": terminal,
    }
    body = (
        f"Draft from the debug session {name}. Complete the terminal assertion, then "
        "add a feature-map reference and move the file into Config/console/units.\n"
    )
    text = "---\n" + json.dumps(metadata, indent=2) + "\n---\n\n" + body
    path = Path(out) if out else session_directory(root, name) / "unit-draft.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return {
        "session": name,
        "path": str(path),
        "unit": identifier,
        "actions": len(actions),
        "terminal": terminal,
    }


def render_operation(result: dict[str, Any]) -> str:
    mark = "ok  " if result.get("ok") else "FAIL"
    lines = [
        f"{mark} {result.get('verb')}  {result.get('durationMs', 0)} ms"
        + (f"  session+{result['sessionEnsureMs']} ms" if result.get("sessionEnsureMs") else ""),
        f"  detail  {result.get('detail', '')}",
    ]
    state = result.get("state") or {}
    if state:
        rendered = "  ".join(f"{key}={value}" for key, value in sorted(state.items()))
        lines.append(f"  state   {rendered}")
    if result.get("guardrails"):
        lines.append(f"  guard   {', '.join(result['guardrails'])}")
    if result.get("session"):
        lines.append(f"  saved   {result.get('stepsDirectory')}")
    return "\n".join(lines)


def render_replay(summary: dict[str, Any]) -> str:
    lines = [
        f"replay {summary['session']}  {summary['operations']} op(s), "
        f"{summary['matched']} matched, {len(summary['mismatched'])} mismatched"
    ]
    for result in summary["results"]:
        mark = "ok  " if result["matched"] else "DIFF"
        lines.append(
            f"  {mark} {result['index']:02d} {result['verb']}  "
            f"{result['durationMs']} ms (recorded {result['recordedDurationMs']} ms)"
        )
    return "\n".join(lines)


def render_scaffold(summary: dict[str, Any]) -> str:
    return (
        f"unit scaffold {summary['session']}  {summary['actions']} action(s)  "
        f"-> {summary['path']}"
    )
