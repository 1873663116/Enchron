from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Verb:
    name: str
    tier: str
    capabilities: frozenset[str]
    lane: str | None
    parameter: tuple[str, ...]
    evidence: str | None
    budget_ms: int


VERBS: dict[str, Verb] = {
    item.name: item
    for item in (
        Verb(
            name="static.check",
            tier="static",
            capabilities=frozenset({"python"}),
            lane=None,
            parameter=("checker",),
            evidence="static-check.json",
            budget_ms=600_000,
        ),
        Verb(
            name="device.session.ensure",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("lane",),
            evidence=None,
            budget_ms=300_000,
        ),
        Verb(
            name="device.command",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("action", "identifier", "text"),
            evidence="command.json",
            budget_ms=30_000,
        ),
        Verb(
            name="device.snapshot",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=(),
            evidence="hierarchy.json",
            budget_ms=30_000,
        ),
        Verb(
            name="device.app-command",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("verb", "arguments"),
            evidence="app-command.json",
            budget_ms=60_000,
        ),
        Verb(
            name="device.probe",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("probe",),
            evidence="probe.json",
            budget_ms=30_000,
        ),
        Verb(
            name="app.relaunch",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=(),
            evidence=None,
            budget_ms=60_000,
        ),
    )
}


def verb_or_none(name: str) -> Verb | None:
    return VERBS.get(name)
