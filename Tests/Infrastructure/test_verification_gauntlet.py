import sys
from pathlib import Path
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import run_verification_gauntlet as gauntlet


class VerificationGauntletTests(unittest.TestCase):
    def test_structure_check_modes_keep_corpus_identity_full_only(self) -> None:
        full = {check.identifier for check in gauntlet.STRUCTURE_CHECKS}
        quick = {
            check.identifier
            for check in gauntlet.STRUCTURE_CHECKS
            if check.runs_in_quick_mode
        }

        self.assertEqual(len(full), 11)
        self.assertIn("glass-usage", quick)
        self.assertIn("media-byte-stream-conformance", quick)
        self.assertIn("playback-issue-ownership", quick)
        self.assertIn("format-description-identity", full)
        self.assertNotIn("format-description-identity", quick)

    def test_failure_names_deduplicate_issue_and_terminal_lines(self) -> None:
        output = """
Test expectedFailure() recorded an issue at Test.swift:1: failure
Test expectedFailure() failed after 0.1 seconds with 1 issue.
Test anotherFailure() failed after 0.1 seconds with 1 issue.
Test run with 12 tests in 2 suites failed after 1.0 seconds.
"""

        self.assertEqual(
            gauntlet.failure_names(output),
            {"expectedFailure", "anotherFailure"},
        )
        self.assertEqual(
            gauntlet.test_summary(output),
            gauntlet.TestSummary(12, "failed"),
        )

    def test_timeout_marker_must_belong_to_the_intermittent_test_context(self) -> None:
        output = """
Test unrelated() recorded an issue: Timed out waiting for a sample
Test acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim() failed after 2 seconds.
"""

        self.assertFalse(gauntlet.test_failure_has_marker(
            output,
            "acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim",
            ["Timed out"],
        ))

    def test_parity_accepts_only_named_media_statuses_and_zero_differences(self) -> None:
        results = [
            {"name": "good.mp4", "decode": "ok", "http": {}, "differences": {}},
            {
                "name": "known.mov",
                "decode": "probe_failed",
                "http": {},
                "differences": {},
            },
        ]

        passed, detail = gauntlet.judge_source_parity(
            results,
            [{"name": "known.mov", "decode": "probe_failed"}],
        )

        self.assertTrue(passed)
        self.assertIn("0 transport differences", detail)

    def test_parity_rejects_unknown_status_and_transport_difference(self) -> None:
        results = [
            {
                "name": "unknown.mov",
                "decode": "timeout",
                "http": {},
                "differences": {"decode": ["timeout", "ok"]},
            },
        ]

        passed, detail = gauntlet.judge_source_parity(results, [])

        self.assertFalse(passed)
        self.assertIn("transport differences", detail)
        self.assertIn("unaccepted media states", detail)

    def test_feature_gap_count_distinguishes_gaps_from_checker_failure(self) -> None:
        self.assertEqual(
            gauntlet.feature_gap_count("  10 unguarded:\n", 1),
            10,
        )
        self.assertEqual(
            gauntlet.feature_gap_count(
                "feature evidence coverage: 12 features\n"
                "  every declared evidence has an owner\n",
                0,
            ),
            0,
        )
        self.assertIsNone(gauntlet.feature_gap_count("malformed feature map", 2))

    def test_log_retention_keeps_the_newest_run_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = [
                "20260815T030000Z-1",
                "20260816T030000Z-2",
                "20260817T030000Z-3",
            ]
            for name in names:
                (root / name).mkdir()
            unrelated = root / "manual-notes"
            unrelated.mkdir()

            gauntlet.retain_recent_runs(root, 2, root / names[-1])

            self.assertFalse((root / names[0]).exists())
            self.assertTrue((root / names[1]).is_dir())
            self.assertTrue((root / names[2]).is_dir())
            self.assertTrue(unrelated.is_dir())


if __name__ == "__main__":
    unittest.main()
