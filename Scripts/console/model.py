from __future__ import annotations

from dataclasses import dataclass
from typing import Any


CAPABILITIES = frozenset({"python", "mac", "xcode", "simulator", "device", "daemon"})
TIERS = ("static", "build", "unit", "e2e")
TIER_ORDER = {name: index for index, name in enumerate(TIERS)}


class LoadRefusal(Exception):
    def __init__(self, code: str, message: str, source: str | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.source = source


@dataclass(frozen=True)
class MachineProfile:
    capabilities: frozenset[str]
    target: str | None

    def has(self, capability: str) -> bool:
        return capability in self.capabilities


@dataclass(frozen=True)
class Expectation:
    path: str
    equals: Any = None
    contains: str | None = None


@dataclass(frozen=True)
class Step:
    index: int
    verb: str
    args: dict[str, Any]
    expect: Expectation | None
    evidence: str | None
    capture: dict[str, str] | None = None


@dataclass(frozen=True)
class Terminal:
    kind: str
    path: str | None
    equals: Any
    schema: str | None


@dataclass(frozen=True)
class Guardrail:
    kind: str
    response: str


PRECONDITION_KINDS = frozenset({"media-server"})
UNIT_PACES = frozenset({"fast", "slow", "catalog"})


@dataclass(frozen=True)
class Unit:
    identifier: str
    layer: int
    actions: tuple[dict[str, Any], ...]
    terminal: Terminal
    requires: frozenset[str]
    role: str
    source: str
    preconditions: tuple[dict[str, Any], ...] = ()
    pace: str = "fast"


@dataclass(frozen=True)
class Plan:
    unit: str
    tier: str
    transport: str
    target: str
    layer: int
    requires: frozenset[str]
    steps: tuple[Step, ...]
    terminal: Terminal
    guardrails: tuple[Guardrail, ...]
    evidence: tuple[str, ...]
    digest: str
    preconditions: tuple[dict[str, Any], ...] = ()


@dataclass(frozen=True)
class Diagnostic:
    code: str
    message: str
    unit: str
    source: str | None


@dataclass(frozen=True)
class StepOutcome:
    index: int
    verb: str
    ok: bool
    duration_ms: int
    detail: str
    guardrails: tuple[str, ...]
    payload: dict[str, Any] | None = None


@dataclass(frozen=True)
class TerminalOutcome:
    kind: str
    ok: bool
    detail: str


@dataclass(frozen=True)
class Report:
    unit: str
    digest: str
    verdict: str
    tier: str
    duration_ms: int
    steps: tuple[StepOutcome, ...]
    terminal: TerminalOutcome
    evidence_dir: str
    exit_code: int
    preconditions: tuple[dict[str, Any], ...] = ()
