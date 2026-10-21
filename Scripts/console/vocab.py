from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Verb:
    name: str
    tier: str
    capabilities: frozenset[str]
    lane: str | None
    parameter: tuple[str, ...]
    evidence: str | None
    budget_ms: int
    schema: str | None = None
    choices: dict[str, tuple[str, ...]] = field(default_factory=dict)


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
            schema="enchron.console.static-check@1",
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
            choices={
                "action": (
                    "tap",
                    "doubleTap",
                    "press",
                    "adjust",
                    "typeText",
                    "replaceText",
                    "swipeUp",
                    "swipeDown",
                    "swipeLeft",
                    "swipeRight",
                    "coordinateTap",
                )
            },
            evidence="command.json",
            schema="enchron.console.command@1",
            budget_ms=30_000,
        ),
        Verb(
            name="device.snapshot",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=(),
            evidence="hierarchy.json",
            schema="enchron.console.hierarchy@1",
            budget_ms=30_000,
        ),
        Verb(
            name="device.capture-frames",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("count", "intervalMs", "identifier"),
            evidence="frames.json",
            schema="enchron.console.frames@1",
            budget_ms=120_000,
        ),
        Verb(
            name="device.await",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("probe", "field", "equals", "mode", "timeoutMs", "intervalMs"),
            evidence="await.json",
            schema="enchron.console.await@1",
            budget_ms=120_000,
        ),
        Verb(
            name="device.app-command",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("verb", "arguments"),
            evidence="app-command.json",
            schema="enchron.console.app-command@1",
            budget_ms=60_000,
        ),
        Verb(
            name="device.probe",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("probe",),
            evidence="probe.json",
            schema="enchron.console.probe@1",
            budget_ms=30_000,
        ),
        Verb(
            name="device.stage-media",
            tier="e2e",
            capabilities=frozenset({"mac", "device", "daemon"}),
            lane="device",
            parameter=("source", "target"),
            evidence="staged-media.json",
            schema="enchron.console.staged-media@1",
            budget_ms=120_000,
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
