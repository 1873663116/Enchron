import sys
from pathlib import Path
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import validate_visionpro_regression_result as validator


class VisionProRegressionResultTests(unittest.TestCase):
    def test_current_xcode_passed_summary_is_complete(self) -> None:
        summary = {
            "result": "Passed",
            "totalTestCount": 3,
            "passedTests": 3,
            "failedTests": 0,
            "skippedTests": 0,
        }

        evaluation = validator.evaluate(summary, expected_test_count=3)

        self.assertTrue(evaluation.complete_pass)
        self.assertEqual(evaluation.reason, "all planned tests passed")

    def test_repeated_runs_use_configuration_execution_counts(self) -> None:
        summary = {
            "result": "Passed",
            "totalTestCount": 1,
            "passedTests": 1,
            "failedTests": 0,
            "skippedTests": 0,
            "devicesAndConfigurations": [
                {
                    "passedTests": 5,
                    "failedTests": 0,
                    "skippedTests": 0,
                }
            ],
        }

        evaluation = validator.evaluate(summary, expected_test_count=5)

        self.assertTrue(evaluation.complete_pass)
        self.assertEqual(evaluation.reason, "all planned tests passed")

    def test_zero_executed_tests_cannot_pass(self) -> None:
        summary = {
            "result": "Passed",
            "totalTestCount": 0,
            "passedTests": 0,
            "failedTests": 0,
            "skippedTests": 0,
        }

        evaluation = validator.evaluate(summary, expected_test_count=1)

        self.assertFalse(evaluation.complete_pass)
        self.assertIn("expected=1", evaluation.reason)
        self.assertIn("total=0", evaluation.reason)

    def test_skipped_or_failed_tests_cannot_pass(self) -> None:
        skipped = validator.evaluate(
            {
                "result": "Passed",
                "totalTestCount": 2,
                "passedTests": 1,
                "failedTests": 0,
                "skippedTests": 1,
            },
            expected_test_count=2,
        )
        failed = validator.evaluate(
            {
                "result": "Failed",
                "totalTestCount": 2,
                "passedTests": 1,
                "failedTests": 1,
                "skippedTests": 0,
            },
            expected_test_count=2,
        )

        self.assertFalse(skipped.complete_pass)
        self.assertFalse(failed.complete_pass)

    def test_unknown_result_value_cannot_pass(self) -> None:
        evaluation = validator.evaluate(
            {
                "result": "succeeded",
                "totalTestCount": 1,
                "passedTests": 1,
                "failedTests": 0,
                "skippedTests": 0,
            },
            expected_test_count=1,
        )

        self.assertFalse(evaluation.complete_pass)
        self.assertIn("result=succeeded", evaluation.reason)

    def test_automation_mode_timeout_before_test_entry_is_device_infrastructure_failure(
        self,
    ) -> None:
        evaluation = validator.evaluate(
            {
                "result": "Failed",
                "totalTestCount": 1,
                "passedTests": 0,
                "failedTests": 1,
                "skippedTests": 0,
            },
            expected_test_count=1,
            test_log=(
                "The test runner failed to initialize for UI testing. "
                "Timed out while enabling automation mode."
            ),
        )

        self.assertFalse(evaluation.complete_pass)
        self.assertEqual(evaluation.kind, "device_infrastructure_failure")
        self.assertEqual(
            evaluation.reason,
            (
                "physical Vision Pro testing stopped before any test method started: "
                "visionOS timed out while enabling Automation Mode"
            ),
        )

    def test_automation_message_after_test_entry_does_not_hide_a_test_failure(
        self,
    ) -> None:
        evaluation = validator.evaluate(
            {
                "result": "Failed",
                "totalTestCount": 1,
                "passedTests": 0,
                "failedTests": 1,
                "skippedTests": 0,
            },
            expected_test_count=1,
            test_log=(
                "Test Case '-[ExampleTests testPlayback]' started.\n"
                "Timed out while enabling automation mode."
            ),
        )

        self.assertFalse(evaluation.complete_pass)
        self.assertEqual(evaluation.kind, "test_failure")
        self.assertIn("failed=1", evaluation.reason)


if __name__ == "__main__":
    unittest.main()
