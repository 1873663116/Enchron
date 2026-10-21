from __future__ import annotations

from typing import Any

from model import Guardrail


class GuardrailHit(Exception):
    def __init__(self, kind: str, detail: str) -> None:
        super().__init__(detail)
        self.kind = kind
        self.detail = detail


class Supervisor:
    def __init__(self, guardrails: tuple[Guardrail, ...], budget_scale: float) -> None:
        self.guardrails = guardrails
        self.budget_scale = budget_scale
        self.hits: list[str] = []

    def before(self, verb: str, evidence: dict[str, Any] | None) -> None:
        if evidence is None:
            return
        dialog = evidence.get("alert") or evidence.get("dialog")
        if dialog:
            self.hits.append("unexpected-dialog")
            raise GuardrailHit(
                "unexpected-dialog",
                f"an alert appeared before {verb}: {dialog}",
            )

    def after(
        self,
        verb: str,
        budget_ms: int,
        elapsed_ms: int,
        evidence: dict[str, Any] | None,
    ) -> None:
        if elapsed_ms > budget_ms * self.budget_scale:
            self.hits.append("step-budget")
            raise GuardrailHit(
                "step-budget",
                f"{verb} took {elapsed_ms} ms against a {budget_ms} ms budget",
            )
        if evidence is None:
            return
        drift = evidence.get("contextDrift")
        if drift:
            self.hits.append("context-drift")
            raise GuardrailHit("context-drift", f"{verb} landed outside its context: {drift}")

    def drain(self) -> tuple[str, ...]:
        return tuple(self.hits)
