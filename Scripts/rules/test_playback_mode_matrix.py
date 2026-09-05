from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))
import playback_mode_matrix as matrix
class HarnessContainerTests(unittest.TestCase):
    def setUp(self):
        matrix._instruments_singleton = None
        self._tmpdir = tempfile.TemporaryDirectory()
        self._tmp = Path(self._tmpdir.name)
        real_provisional = matrix.REPOSITORY_ROOT / "Scripts/verification/harness/provisional_budgets.json"
        self._budgets = matrix.BudgetProvider(timings_directory=self._tmp, provisional_path=real_provisional)
        self._tools = matrix.LocalToolRunner("device", budgets=self._budgets)
        self._policy = matrix.RecoveryPolicy()
        import enchron_target
        self._instruments = matrix.Instruments(device=enchron_target.target_device(), core_device=enchron_target.core_device(), developer_dir=enchron_target.developer_directory(), lane="device", budgets=self._budgets, tools=self._tools, policy=self._policy)
        self._get_patch = patch.object(matrix, "_get_instruments", return_value=self._instruments)
        self._get_patch.start()
    def tearDown(self):
        self._get_patch.stop()
        self._tmpdir.cleanup()
        matrix._instruments_singleton = None
    def test_push_to_inbox_delegates_to_enchron_target(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            media_path = root / "clip.mp4"
            media_path.write_bytes(b"simulator media")
            def fake_copy(**kwargs):
                dest = kwargs.get("destination") or kwargs.get("source")
                return subprocess.CompletedProcess([], returncode=0, stdout="", stderr="")
            with patch.object(matrix.enchron_target, "copy_to_container", side_effect=fake_copy) as mock_copy:
                error = matrix.push_to_inbox(media_path)
            self.assertIsNone(error)
            mock_copy.assert_called_once()
    def test_copy_probe_lines_delegates_to_enchron_target(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            cell_directory = Path(temporary_directory)
            def fake_copy(**kwargs):
                destination = kwargs.get("destination")
                destination.write_text("first\nsecond\n", encoding="utf-8")
                return subprocess.CompletedProcess([], returncode=0, stdout="", stderr="")
            with patch.object(matrix.enchron_target, "copy_from_container", side_effect=fake_copy) as mock_copy:
                lines, error = matrix.copy_probe_lines(cell_directory)
            self.assertEqual(lines, ["first", "second"])
            self.assertIsNone(error)
            mock_copy.assert_called_once()
class ProbeCursorTests(unittest.TestCase):
    def test_sequence_cursor_survives_compaction(self):
        cursor = matrix.probe_cursor(["2026-08-19T00:00:00Z probeSequence=10 old-a","2026-08-19T00:00:01Z probeSequence=11 old-b"])
        delta, next_cursor, error = matrix.probe_lines_since(["2026-08-19T00:00:01Z probeSequence=11 old-b","2026-08-19T00:00:02Z probeSequence=12 new-c"], cursor)
        self.assertEqual(delta, ["2026-08-19T00:00:02Z probeSequence=12 new-c"])
        self.assertEqual(next_cursor.sequence, 12)
        self.assertIsNone(error)
    def test_legacy_cursor_reports_backward_line_count(self):
        cursor = matrix.probe_cursor(["old-a", "old-b"])
        delta, next_cursor, error = matrix.probe_lines_since(["old-b"], cursor)
        self.assertEqual(delta, [])
        self.assertEqual(next_cursor.line_count, 1)
        self.assertEqual(error, "Probe line count moved backwards from 2 to 1.")
if __name__ == "__main__":
    unittest.main()


class ProductErrorGateTests(HarnessContainerTests):
    def test_control_plane_error_is_a_product_error(self):
        self.assertIsNone(matrix.product_error(None))
        self.assertIsNone(matrix.product_error({"error": "none"}))
        self.assertEqual(matrix.product_error({"error": "presentationConversionFailed"}), "presentationConversionFailed")

    def test_probe_journal_conversion_failure_is_a_product_error(self):
        lines = [
            "2026-09-06 01:16:40.000 Df portalLastFrameBridge captured=false reason=conversionFailed",
            "2026-09-06 01:16:40.901 Df conversionFailed outcome=failed(mainWindowUnavailable),operation=main-window-appearance-failed",
        ]
        self.assertEqual(matrix.probe_product_error(lines), "outcome=failed(mainWindowUnavailable),operation=main-window-appearance-failed")
        self.assertIsNone(matrix.probe_product_error(lines[:1]))

    def test_presentation_wait_fails_on_a_product_error_even_at_the_expected_landing(self):
        plane = {"presentation": "window", "transition": "none", "lifecycle": "idle", "error": "presentationConversionFailed"}
        with patch.object(matrix, "_read_control_plane_harness", return_value=(plane, {})):
            result = matrix._wait_for_presentation_harness(instruments=self._instruments, client=None, expected="window", baseline_plane=None, started_dt=matrix.datetime.now(matrix.timezone.utc))
        self.assertEqual(result["verdict"], matrix.PRODUCT_ERROR)
        self.assertEqual(result["product_error"], "presentationConversionFailed")
        self.assertEqual(result["control_plane"]["error"], "presentationConversionFailed")
        self.assertNotIn(matrix.PRODUCT_ERROR, matrix.PASSING_VERDICTS)

    def test_immersive_settlement_fails_on_a_journal_conversion_failure(self):
        lines = ["2026-09-06 01:16:40.901 Df conversionFailed outcome=failed(mainWindowUnavailable),operation=main-window-appearance-failed"]
        with patch.object(matrix, "_copy_probe_lines_harness", return_value=lines):
            result, delta, _ = matrix._wait_for_immersive_settlement_harness(instruments=self._instruments, cell_directory=self._tmp, expected="docked", probe_cursor=matrix.ProbeCursor(None, 0), client=None, target_started_at=matrix.datetime.now(matrix.timezone.utc))
        self.assertEqual(result["verdict"], matrix.PRODUCT_ERROR)
        self.assertEqual(delta, lines)
