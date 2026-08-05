#!/usr/bin/env python3

import argparse
from dataclasses import dataclass
import json
from pathlib import Path


@dataclass(frozen=True)
class Evaluation:
    complete_pass: bool
    kind: str
    reason: str


def evaluate(
    summary: dict[str, object],
    expected_test_count: int,
    test_log: str = "",
) -> Evaluation:
    configurations = summary.get("devicesAndConfigurations")
    if isinstance(configurations, list) and configurations:
        execution_counts = [
            configuration
            for configuration in configurations
            if isinstance(configuration, dict)
        ]
        passed = sum(int(item.get("passedTests", 0)) for item in execution_counts)
        failed = sum(int(item.get("failedTests", 0)) for item in execution_counts)
        skipped = sum(int(item.get("skippedTests", 0)) for item in execution_counts)
        total = passed + failed + skipped
    else:
        total = int(summary.get("totalTestCount", 0))
        passed = int(summary.get("passedTests", 0))
        failed = int(summary.get("failedTests", 0))
        skipped = int(summary.get("skippedTests", 0))
    result = str(summary.get("result", "missing"))

    automation_mode_timed_out = (
        "Timed out while enabling automation mode" in test_log
    )
    test_method_started = "Test Case '" in test_log and " started." in test_log
    if automation_mode_timed_out and not test_method_started:
        return Evaluation(
            False,
            "device_infrastructure_failure",
            (
                "physical Vision Pro testing stopped before any test method started: "
                "visionOS timed out while enabling Automation Mode"
            ),
        )

    complete_pass = (
        expected_test_count > 0
        and total == expected_test_count
        and passed == expected_test_count
        and failed == 0
        and skipped == 0
        and result == "Passed"
    )
    if complete_pass:
        return Evaluation(True, "passed", "all planned tests passed")

    return Evaluation(
        False,
        "test_failure" if failed > 0 else "incomplete_test_session",
        (
            "planned test result was incomplete: "
            f"expected={expected_test_count} total={total} passed={passed} "
            f"failed={failed} skipped={skipped} result={result}"
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate that a Vision Pro xcresult summary contains every planned passing test."
    )
    parser.add_argument("summary", type=Path)
    parser.add_argument("expected_test_count", type=int)
    parser.add_argument("--test-log", type=Path)
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        dest="output_format",
    )
    arguments = parser.parse_args()

    summary = json.loads(arguments.summary.read_text())
    test_log = arguments.test_log.read_text(errors="replace") if arguments.test_log else ""
    evaluation = evaluate(summary, arguments.expected_test_count, test_log=test_log)
    if arguments.output_format == "json":
        print(
            json.dumps(
                {
                    "completePass": evaluation.complete_pass,
                    "kind": evaluation.kind,
                    "reason": evaluation.reason,
                },
                sort_keys=True,
            )
        )
    else:
        print(evaluation.reason)
    raise SystemExit(0 if evaluation.complete_pass else 65)


if __name__ == "__main__":
    main()
