from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Literal

if TYPE_CHECKING:
    from harness.budgets import Budget

FailureClass = Literal["product", "instrument"]

INSTRUMENT_KINDS = frozenset(
    {
        "transport-timeout",
        "runner-crashed",
        "response-undecodable",
        "contract-mismatch",
        "wait-expired",
        "app-not-running",
        "session-lost",
        "authorization-required",
        "provisional-budget-expired",
        "evidence-destroyed",
    }
)

PRODUCT_KINDS = frozenset({"assertion-mismatch", "app-crashed"})


@dataclass(frozen=True)
class ProductFailure:
    kind: str
    evidence: dict[str, object]


class InstrumentFault(Exception):
    def __init__(
        self,
        kind: str,
        evidence: dict[str, object] | None = None,
        budget: Budget | None = None,
    ) -> None:
        self.kind = kind
        self.evidence = dict(evidence or {})
        self.budget = budget
        detail = f"instrument fault {kind}: subsequent observations are untrusted"
        if budget is not None:
            detail = f"{detail} (budget {budget.provenance})"
        super().__init__(detail)
