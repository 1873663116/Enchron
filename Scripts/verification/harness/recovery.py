from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence, Union

from harness.failures import InstrumentFault


@dataclass(frozen=True)
class FaultRecord:
    location: str
    kind: str
    censored: bool = False


@dataclass(frozen=True)
class Retry:
    reason: str


@dataclass(frozen=True)
class Halt:
    reason: str
    report: dict[str, object]


Decision = Union[Retry, Halt]


class RecoveryPolicy:
    def __init__(self) -> None:
        self.action_count = 0
        self.fault_count = 0

    def record_action(self) -> None:
        self.action_count += 1

    def fault_report(self) -> dict[str, object]:
        return {
            "instrumentFaults": self.fault_count,
            "actions": self.action_count,
            "faultRate": (
                self.fault_count / self.action_count if self.action_count else None
            ),
        }

    def on_fault(
        self, fault: InstrumentFault, history: Sequence[FaultRecord]
    ) -> Decision:
        assert history, (
            "history must end with the record of the fault being decided"
        )
        current = history[-1]
        assert current.kind == fault.kind, (
            f"history tail describes {current.kind!r} but the fault being decided "
            f"is {fault.kind!r}"
        )
        self.fault_count += 1
        if len(history) >= 2:
            previous = history[-2]
            if previous.location == current.location and previous.kind == current.kind:
                return Halt(
                    reason=(
                        f"{current.kind} struck twice in a row at "
                        f"{current.location}; that is deterministic, a harness "
                        "defect, and retrying would only burn time"
                    ),
                    report=self.fault_report(),
                )
        if current.censored:
            return Retry(
                reason=(
                    f"censored sample at {current.location} signals a "
                    "miscalibrated budget; the measurement stream corrects it "
                    "and this occurrence is treated as transient"
                )
            )
        return Retry(
            reason=(
                f"first occurrence of {current.kind} at {current.location}; "
                "one caller-provided recovery is allowed"
            )
        )
