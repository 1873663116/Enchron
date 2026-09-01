from __future__ import annotations

import json
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from harness.budgets import Budget, BudgetProvider
from harness.failures import InstrumentFault, ProductFailure

RUNNER_PATH = Path(__file__).resolve().parent.parent / "interactive_visionpro_ui.py"
EXIT_SUCCESS = 0
EXIT_UNCAUGHT_EXCEPTION = 1
EXIT_REPORTED_FAILURE = 2


@dataclass(frozen=True)
class CompletedInvocation:
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class RunnerResponse:
    document: dict[str, object]
    failure: ProductFailure | None


def run_runner(command: Sequence[str], timeout_seconds: float) -> CompletedInvocation:
    completed = subprocess.run(
        list(command),
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        check=False,
    )
    return CompletedInvocation(
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


class ControllerClient:
    def __init__(
        self,
        lane: str,
        command_prefix: Sequence[str] | None = None,
        budgets: BudgetProvider | None = None,
        run: Callable[[Sequence[str], float], CompletedInvocation] = run_runner,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.lane = lane
        self.command_prefix = list(
            command_prefix
            if command_prefix is not None
            else (sys.executable, str(RUNNER_PATH))
        )
        self.budgets = budgets if budgets is not None else BudgetProvider()
        self.run = run
        self.clock = clock

    def invoke(self, verb: str, arguments: Sequence[str] = ()) -> RunnerResponse:
        budget = self.budgets.budget(self.lane, verb)
        command = [*self.command_prefix, verb, *arguments]
        started = self.clock()
        try:
            completed = self.run(command, budget.seconds)
        except (TimeoutError, subprocess.TimeoutExpired):
            self.budgets.record_sample(
                self.lane, verb, budget.seconds, censored=True
            )
            raise InstrumentFault(
                "transport-timeout",
                {
                    "verb": verb,
                    "diagnosis": (
                        f"runner gave no answer to {verb!r} within its budget; "
                        "the subprocess was killed before producing a verdict"
                    ),
                },
                budget,
            ) from None
        self.budgets.record_sample(
            self.lane, verb, self.clock() - started, censored=False
        )
        return self.reconcile(verb, completed, budget)

    def reconcile(
        self, verb: str, completed: CompletedInvocation, budget: Budget
    ) -> RunnerResponse:
        try:
            decoded = json.loads(completed.stdout)
        except json.JSONDecodeError:
            decoded = None
        document = decoded if isinstance(decoded, dict) else None
        if document is None:
            kind = (
                "runner-crashed"
                if completed.returncode != EXIT_SUCCESS
                else "response-undecodable"
            )
            raise InstrumentFault(
                kind,
                {
                    "verb": verb,
                    "exitCode": completed.returncode,
                    "stdout": completed.stdout[-2000:],
                    "stderr": completed.stderr[-2000:],
                    "diagnosis": (
                        f"runner {verb!r} exited {completed.returncode} without a "
                        "decodable JSON document on stdout"
                    ),
                },
                budget,
            )
        if completed.returncode not in (EXIT_SUCCESS, EXIT_REPORTED_FAILURE):
            raise InstrumentFault(
                "runner-crashed",
                {
                    "verb": verb,
                    "exitCode": completed.returncode,
                    "document": document,
                    "stderr": completed.stderr[-2000:],
                    "diagnosis": (
                        f"runner {verb!r} exited {completed.returncode}; exit 1 is an "
                        "uncaught exception, so the runner itself died"
                    ),
                },
                budget,
            )
        success = document.get("success")
        expected_success = completed.returncode == EXIT_SUCCESS
        if success is not expected_success:
            raise InstrumentFault(
                "contract-mismatch",
                {
                    "verb": verb,
                    "exitCode": completed.returncode,
                    "success": success,
                    "document": document,
                    "diagnosis": (
                        f"runner {verb!r} exit code {completed.returncode} contradicts "
                        f"success={success!r}; exit 0 must carry success=true and "
                        "exit 2 must carry success=false"
                    ),
                },
                budget,
            )
        if success is True:
            return RunnerResponse(document=document, failure=None)
        failure = document.get("failure")
        if (
            not isinstance(failure, dict)
            or not isinstance(failure.get("class"), str)
            or not isinstance(failure.get("kind"), str)
        ):
            raise InstrumentFault(
                "contract-mismatch",
                {
                    "verb": verb,
                    "exitCode": completed.returncode,
                    "document": document,
                    "diagnosis": (
                        f"runner {verb!r} reported success=false without a structured "
                        "failure block carrying class and kind"
                    ),
                },
                budget,
            )
        evidence = failure.get("evidence")
        evidence = evidence if isinstance(evidence, dict) else {}
        if failure["class"] == "instrument":
            raise InstrumentFault(failure["kind"], evidence, budget)
        if failure["class"] == "product":
            return RunnerResponse(
                document=document,
                failure=ProductFailure(kind=failure["kind"], evidence=evidence),
            )
        raise InstrumentFault(
            "contract-mismatch",
            {
                "verb": verb,
                "failureClass": failure["class"],
                "document": document,
                "diagnosis": (
                    f"runner {verb!r} reported failure class {failure['class']!r}; "
                    "only 'product' and 'instrument' exist"
                ),
            },
            budget,
        )
