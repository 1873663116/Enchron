from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import static_tier


def payload(detail: str, exit_code: int = 0) -> dict:
    return {
        "tier": "static",
        "quick": False,
        "exitCode": exit_code,
        "durationMs": 4036,
        "checks": [
            {"checker": "Git hook installation", "state": "PASS", "detail": "installed"},
            {"checker": "Structure checks", "state": "PASS", "detail": detail},
        ],
        "stdout": "",
        "stderr": "",
    }


class SummarizeTests(unittest.TestCase):
    def test_a_run_that_skipped_tooling_self_tests_reports_the_count(self) -> None:
        text = static_tier.summarize(
            payload(
                "all 36 checks passed; outside this mode (25): alpha; "
                "tooling self-tests skipped, CI and test infrastructure unchanged (134): "
                + ", ".join(f"test-{index}" for index in range(134))
            )
        )
        self.assertIn("static passed", text)
        self.assertIn("tooling self-tests skipped (134)", text)

    def test_a_run_that_ran_the_tooling_self_tests_has_no_skip_suffix(self) -> None:
        text = static_tier.summarize(payload("all 170 checks passed"))
        self.assertNotIn("tooling self-tests", text)

    def test_a_failed_run_reports_failed(self) -> None:
        text = static_tier.summarize(payload("checker failed", exit_code=1))
        self.assertIn("static failed", text)


if __name__ == "__main__":
    unittest.main()
