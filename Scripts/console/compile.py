from __future__ import annotations

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
    Unit,
    TIER_ORDER,
)
from vocab import VERBS, verb_or_none


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
            steps.append(
                Step(
                    index=index,
                    verb=verb_name,
                    args=args,
                    expect=expect,
                    evidence=verb.evidence,
                )
            )
        return tuple(steps)

    def _transport(
        self, steps: tuple[Step, ...], machine: MachineProfile, errors: list[tuple[str, str]]
    ) -> str:
        needs_daemon = any(
            verb and verb.lane for verb in (verb_or_none(step.verb) for step in steps)
        )
        if needs_daemon:
            return "daemon"
        return "direct"


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
        shape_machine = MachineProfile(
            capabilities=frozenset(CAPABILITIES), target=machine.target
        )
        plan, errors = compiler.compile(
            unit, tier or natural_tier(unit), shape_machine
        )
        for code, message in errors:
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
