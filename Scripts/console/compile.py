from __future__ import annotations

import dataclasses
import hashlib
import json
from pathlib import Path
from typing import Any

from loader import load_feature_references, load_units
from model import (
    CAPABILITIES,
    Expectation,
    Guardrail,
    MachineProfile,
    Plan,
    Step,
    Terminal,
    Unit,
    TIER_ORDER,
)
from vocab import VERBS, verb_or_none


MEDIA_PROVIDERS = frozenset({"emby"})

GUARDRAIL_SET = (
    Guardrail(kind="unexpected-dialog", response="abort"),
    Guardrail(kind="step-budget", response="abort"),
    Guardrail(kind="context-drift", response="abort"),
)

TIER_CAPABILITIES = {
    "static": frozenset({"python"}),
    "build": frozenset({"python", "mac", "xcode"}),
    "unit": frozenset({"python", "mac", "xcode", "simulator"}),
    "e2e": frozenset({"python", "mac", "xcode", "simulator", "device", "daemon"}),
}


def digest_of(payload: Any) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def plan_digest(
    unit: Unit, tier: str, transport: str, steps: tuple[Step, ...]
) -> str:
    return digest_of(
        {
            "unit": unit.identifier,
            "layer": unit.layer,
            "tier": tier,
            "transport": transport,
            "steps": [{"verb": step.verb, "args": step.args} for step in steps],
            "terminal": unit.terminal.kind,
            "terminalPath": unit.terminal.path,
            "requires": sorted(unit.requires),
        }
    )


class Compiler:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.references = load_feature_references(root)

    def compile(
        self, unit: Unit, tier: str, machine: MachineProfile
    ) -> tuple[Plan | None, list[tuple[str, str]]]:
        errors: list[tuple[str, str]] = []
        if tier not in TIER_ORDER:
            return None, [("C002", f"tier {tier!r} is outside {', '.join(TIER_ORDER)}")]
        for index, precondition in enumerate(unit.preconditions):
            provider = precondition.get("provider")
            if precondition["kind"] == "media-server" and provider not in MEDIA_PROVIDERS:
                errors.append(
                    (
                        "C016",
                        f"precondition {index} names provider {provider!r}; the closed set is "
                        + ", ".join(sorted(MEDIA_PROVIDERS)),
                    )
                )
        missing = sorted(unit.requires - set(CAPABILITIES))
        if missing:
            errors.append(("C004", f"requires names unknown capabilities {missing}"))
        absent = sorted(unit.requires - machine.capabilities)
        if absent:
            errors.append(
                ("C004", f"machine lacks {', '.join(absent)}; declared by the unit")
            )
        steps = self._steps(unit, tier, errors)
        if unit.layer == 3 and unit.terminal.kind == "exit":
            errors.append(("C009", "a layer 3 unit cannot terminate on exit"))
        declared_schema = unit.terminal.schema
        if declared_schema:
            producer = next(
                (
                    verb
                    for verb in self._verbs(unit)
                    if verb and verb.evidence == unit.terminal.path
                ),
                None,
            )
            if producer is not None and (
                producer.schema is None or producer.schema != declared_schema
            ):
                errors.append(
                    (
                        "C014",
                        f"terminal claims {declared_schema}, but {producer.name} "
                        f"produces {producer.schema or 'no documented schema'}",
                    )
                )
        lane_verbs = [verb for verb in self._verbs(unit) if verb and verb.lane]
        if unit.layer == 3 and not lane_verbs:
            errors.append(
                (
                    "C006",
                    "a layer 3 unit drives the interface but none of its verbs occupies a lane",
                )
            )
        if unit.layer == 2 and not unit.requires <= {"python"}:
            errors.append(
                ("C006", "a layer 2 unit runs on the host and needs no machine capability")
            )
        if unit.layer == 2 and any(step_verb.lane for step_verb in self._verbs(unit) if step_verb):
            errors.append(("C006", "a layer 2 unit must not use a lane bound verb"))
        produced = {verb.evidence for verb in self._verbs(unit) if verb and verb.evidence}
        if unit.terminal.path and unit.terminal.path not in produced:
            errors.append(
                (
                    "C008",
                    f"terminal path {unit.terminal.path} is produced by no verb in the unit",
                )
            )
        transport = self._transport(steps, machine, errors)
        if transport == "daemon" and not machine.has("daemon"):
            errors.append(("C015", "plan resolves to daemon transport without that capability"))
        if errors:
            return None, errors
        teardown_steps = self._teardown_steps(unit, tier, errors)
        steps = self._isolation_steps(unit, steps)
        plan = Plan(
            unit=unit.identifier,
            tier=tier,
            transport=transport,
            target=machine.target or "",
            layer=unit.layer,
            requires=unit.requires,
            steps=steps,
            terminal=unit.terminal,
            guardrails=GUARDRAIL_SET,
            evidence=tuple(sorted(produced)),
            digest=plan_digest(unit, tier, transport, steps),
            preconditions=unit.preconditions,
            teardown_steps=teardown_steps,
        )
        return plan, []

    def _verbs(self, unit: Unit):
        return [verb_or_none(step_verb_name(action)) for action in unit.actions]

    def _steps(
        self, unit: Unit, tier: str, errors: list[tuple[str, str]]
    ) -> tuple[Step, ...]:
        steps: list[Step] = []
        for index, action in enumerate(unit.actions, start=1):
            verb_name = step_verb_name(action)
            verb = verb_or_none(verb_name)
            if verb is None:
                errors.append(
                    ("C003", f"verb {verb_name!r} is outside the vocabulary; adding it needs a recompile")
                )
                continue
            if TIER_ORDER[verb.tier] > TIER_ORDER[tier]:
                errors.append(
                    (
                        "C006",
                        f"verb {verb_name!r} belongs to tier {verb.tier}, above {tier}",
                    )
                )
            undeclared = sorted(verb.capabilities - unit.requires - {"python"})
            if undeclared:
                errors.append(
                    (
                        "C007",
                        f"verb {verb_name!r} needs {', '.join(undeclared)} that the unit does not declare",
                    )
                )
            args = action.get("args") or {}
            if not isinstance(args, dict):
                errors.append(("C005", f"action {index} args must be an object"))
                continue
            unknown = sorted(set(args) - set(verb.parameter))
            if unknown:
                errors.append(
                    ("C005", f"verb {verb_name!r} does not take {', '.join(unknown)}")
                )
            for name, allowed in verb.choices.items():
                if name in args and args[name] not in allowed:
                    errors.append(
                        (
                            "C005",
                            f"{verb_name} takes {', '.join(allowed)} for {name}",
                        )
                    )
            expect = None
            declared_expect = action.get("expect")
            if declared_expect is not None:
                if (
                    not isinstance(declared_expect, dict)
                    or not isinstance(declared_expect.get("path"), str)
                    or not declared_expect.get("path")
                ):
                    errors.append(
                        ("C005", f"expect on {verb_name!r} needs a path")
                    )
                elif (
                    "equals" not in declared_expect
                    and not isinstance(declared_expect.get("contains"), str)
                ):
                    errors.append(
                        (
                            "C005",
                            f"expect on {verb_name!r} needs equals or contains",
                        )
                    )
                else:
                    expect = Expectation(
                        path=declared_expect["path"],
                        equals=declared_expect.get("equals"),
                        contains=declared_expect.get("contains"),
                    )
            if expect is not None and verb.evidence is None:
                errors.append(
                    ("C010", f"verb {verb_name!r} produces no evidence to expect on")
                )
            capture = action.get("capture")
            if capture is not None:
                if not isinstance(capture, dict) or not capture or not all(
                    isinstance(key, str) and isinstance(value, str) and value
                    for key, value in capture.items()
                ):
                    errors.append(
                        ("C018", f"capture on {verb_name!r} must map payload fields to names")
                    )
                    capture = None
                elif verb.evidence is None:
                    errors.append(
                        ("C018", f"verb {verb_name!r} produces no payload to capture")
                    )
                    capture = None
            steps.append(
                Step(
                    index=index,
                    verb=verb_name,
                    args=args,
                    expect=expect,
                    evidence=verb.evidence,
                    capture=dict(capture) if capture else None,
                )
            )
        captured: dict[str, int] = {}
        for step in steps:
            for reference in argument_references(step.args):
                if reference not in captured:
                    errors.append(
                        (
                            "C018",
                            f"{step.verb} reads {reference!r} before any earlier step captures it",
                        )
                    )
            for name in (step.capture or {}).values():
                if name in captured:
                    errors.append(("C018", f"capture name {name!r} is written twice"))
                captured[name] = step.index
        return tuple(steps)

    def _isolation_steps(self, unit: Unit, steps: list[Step]) -> list[Step]:
        if unit.isolation != "clean-library":
            return steps
        for step in steps:
            if step.verb == "device.home" and step.args.get("clear"):
                return steps
        preamble = Step(
            index=0,
            verb="device.app-command",
            args={"verb": "clearMediaLibrary", "arguments": {}},
            expect=None,
            evidence="app-command.json",
            capture=None,
        )
        reindexed = [
            Step(
                index=position + 1,
                verb=step.verb,
                args=step.args,
                expect=step.expect,
                evidence=step.evidence,
                capture=step.capture,
            )
            for position, step in enumerate(steps)
        ]
        if reindexed and reindexed[0].verb == "device.session.ensure":
            ordered = [reindexed[0], preamble, *reindexed[1:]]
        else:
            ordered = [preamble, *reindexed]
        return [
            Step(
                index=position,
                verb=step.verb,
                args=step.args,
                expect=step.expect,
                evidence=step.evidence,
                capture=step.capture,
            )
            for position, step in enumerate(ordered)
        ]

    def _teardown_steps(
        self, unit: Unit, tier: str, errors: list[tuple[str, str]]
    ) -> tuple[Step, ...]:
        if not unit.teardown:
            return ()
        shadow = Unit(
            identifier=unit.identifier,
            layer=unit.layer,
            actions=unit.teardown,
            terminal=unit.terminal,
            requires=unit.requires,
            role=unit.role,
            source=unit.source,
            preconditions=(),
            pace=unit.pace,
        )
        return self._steps(shadow, tier, errors)

    def _transport(
        self, steps: tuple[Step, ...], machine: MachineProfile, errors: list[tuple[str, str]]
    ) -> str:
        needs_daemon = any(
            verb and verb.lane for verb in (verb_or_none(step.verb) for step in steps)
        )
        if needs_daemon:
            return "daemon"
        return "direct"


def argument_references(value: Any) -> list[str]:
    found: list[str] = []
    if isinstance(value, str):
        if value.startswith("$") and len(value) > 1:
            found.append(value[1:])
    elif isinstance(value, dict):
        for item in value.values():
            found.extend(argument_references(item))
    elif isinstance(value, list):
        for item in value:
            found.extend(argument_references(item))
    return found


def step_verb_name(action: Any) -> str:
    if isinstance(action, dict):
        name = action.get("verb")
        if isinstance(name, str):
            return name
    return "<malformed>"


def compile_unit(
    root: Path, identifier: str, tier: str, machine: MachineProfile
) -> tuple[Plan | None, list[tuple[str, str]], Unit | None]:
    units = load_units(root)
    unit = units.get(identifier)
    if unit is None:
        return None, [("C011", f"no unit named {identifier}")], None
    compiler = Compiler(root)
    plan, errors = compiler.compile(unit, tier, machine)
    return plan, errors, unit


def case_plan(
    plan: Plan, unit: Unit, key: str
) -> tuple[Plan | None, str]:
    cases = list(unit.cases)
    if not cases:
        return None, f"{unit.identifier} records no case boundaries"
    names = [case["key"] for case in cases]
    if key not in names:
        return None, (
            f"{unit.identifier} has no case {key!r}; the cases are "
            + ", ".join(names)
        )
    index = names.index(key)
    offset = len(plan.steps) - len(unit.actions)
    if offset < 0:
        return None, f"{unit.identifier} compiles fewer steps than it declares"
    start = offset + cases[index]["start"]
    end = offset + (
        cases[index + 1]["start"] if index + 1 < len(cases) else len(unit.actions)
    )
    preamble = offset + cases[0]["start"]
    steps = plan.steps[:preamble] + plan.steps[start:end]
    terminal = None
    for step in reversed(steps):
        verb = VERBS.get(step.verb)
        if verb is not None and verb.evidence:
            terminal = Terminal(kind="artifact", path=verb.evidence, equals=None, schema=None)
            break
    if terminal is None:
        terminal = Terminal(kind="exit", path=None, equals=0, schema=None)
    return (
        dataclasses.replace(
            plan,
            unit=f"{plan.unit}#{key}",
            steps=steps,
            terminal=terminal,
            digest=digest_of({"plan": plan.digest, "case": key}),
        ),
        "",
    )


def natural_tier(unit: Unit) -> str:
    tiers = [
        VERBS[step_verb_name(action)].tier
        for action in unit.actions
        if step_verb_name(action) in VERBS
    ]
    return max(tiers, key=lambda name: TIER_ORDER[name]) if tiers else "static"


def check_all(
    root: Path, tier: str | None, machine: MachineProfile
) -> list[tuple[str, str, str]]:
    units = load_units(root)
    references = load_feature_references(root)
    compiler = Compiler(root)
    findings: list[tuple[str, str, str]] = []
    for identifier, unit in sorted(units.items()):
        for index, precondition in enumerate(unit.preconditions):
            provider = precondition.get("provider")
            if precondition["kind"] == "media-server" and provider not in MEDIA_PROVIDERS:
                errors.append(
                    (
                        "C016",
                        f"precondition {index} names provider {provider!r}; the closed set is "
                        + ", ".join(sorted(MEDIA_PROVIDERS)),
                    )
                )
        shape_machine = MachineProfile(
            capabilities=frozenset(CAPABILITIES), target=machine.target
        )
        run_tier = natural_tier(unit)
        plan, errors = compiler.compile(unit, run_tier, shape_machine)
        for code, message in errors:
            findings.append((identifier, code, message))
        if tier is not None and TIER_ORDER[run_tier] <= TIER_ORDER[tier]:
            _, reachable = compiler.compile(unit, run_tier, machine)
            for code, message in reachable:
                findings.append((identifier, code, message))
        if identifier not in references:
            findings.append(
                (
                    identifier,
                    "C013",
                    "no feature map references this unit; it cannot be reached by any run",
                )
            )
    for identifier in sorted(references):
        if identifier not in units:
            findings.append(
                (
                    identifier,
                    "C012",
                    "a feature map references this unit but it is not declared",
                )
            )
    return findings
