from __future__ import annotations

import subprocess
import time
from typing import Callable, Mapping, Sequence, TypeVar

from harness.budgets import Budget, BudgetProvider
from harness.controller import CompletedInvocation
from harness.failures import InstrumentFault

Outcome = TypeVar("Outcome")


class LocalToolRunner:
    def __init__(
        self,
        lane: str,
        budgets: BudgetProvider | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.lane = lane
        self.budgets = budgets if budgets is not None else BudgetProvider()
        self.clock = clock

    def call(self, verb: str, action: Callable[[Budget], Outcome]) -> Outcome:
        budget = self.budgets.budget(self.lane, verb)
        started = self.clock()
        try:
            outcome = action(budget)
        except subprocess.TimeoutExpired:
            self.budgets.record_sample(
                self.lane, verb, budget.seconds, censored=True
            )
            raise InstrumentFault(
                "transport-timeout",
                {
                    "verb": verb,
                    "diagnosis": (
                        f"local tool {verb!r} gave no answer within its budget; "
                        "the process was killed before producing a result"
                    ),
                },
                budget,
            ) from None
        self.budgets.record_sample(
            self.lane, verb, self.clock() - started, censored=False
        )
        return outcome

    def run(
        self,
        verb: str,
        command: Sequence[str],
        env: Mapping[str, str] | None = None,
    ) -> CompletedInvocation:
        def action(budget: Budget) -> CompletedInvocation:
            completed = subprocess.run(
                list(command),
                capture_output=True,
                text=True,
                timeout=budget.seconds,
                check=False,
                env=dict(env) if env is not None else None,
            )
            return CompletedInvocation(
                returncode=completed.returncode,
                stdout=completed.stdout,
                stderr=completed.stderr,
            )

        return self.call(verb, action)
