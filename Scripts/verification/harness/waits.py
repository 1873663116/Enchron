from __future__ import annotations

import time
from typing import Callable

from harness.budgets import Budget
from harness.failures import InstrumentFault

Evidence = dict[str, object]

DEFAULT_POLL_INTERVAL_SECONDS = 1.0


def wait_for(
    label: str,
    probe: Callable[[], Evidence | None],
    budget: Budget,
    observe: Callable[[], list[object]],
    record: Callable[[str, float, bool], None] | None = None,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
    poll_interval_seconds: float = DEFAULT_POLL_INTERVAL_SECONDS,
) -> Evidence:
    started = clock()
    deadline = started + budget.seconds
    while True:
        evidence = probe()
        if evidence is not None:
            if record is not None:
                record(label, clock() - started, False)
            return evidence
        remaining = deadline - clock()
        if remaining <= 0:
            break
        sleep(min(poll_interval_seconds, remaining))
    observations = observe()
    if record is not None:
        record(label, budget.seconds, True)
    raise InstrumentFault(
        "wait-expired",
        {
            "label": label,
            "observations": observations,
            "budget": budget.provenance,
            "diagnosis": (
                f"{label} produced no evidence within {budget.seconds:.1f}s "
                f"({budget.provenance}); the scene was observed at expiry and "
                "no stale snapshot is returned"
            ),
        },
        budget,
    )
