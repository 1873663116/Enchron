from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))
import wearer_close_probe as probe


class WearerCloseVerdictTests(unittest.TestCase):
    def test_all_three_markers_in_order_pass(self) -> None:
        delta = [
            "2026-09-08T01:00:00Z testcmd closeMainWindow session=ABC",
            "2026-09-08T01:00:00Z mainWindowScene disconnected trigger=wearer",
            "2026-09-08T01:00:00Z mainWindowScene closedByWearer stoppingPlayback",
        ]
        verdict = probe.wearer_close_verdict(delta)
        self.assertTrue(verdict["passed"])
        self.assertEqual(verdict["missing"], [])

    def test_a_missing_stop_fails(self) -> None:
        delta = [
            "testcmd closeMainWindow session=ABC",
            "mainWindowScene disconnected trigger=wearer",
        ]
        verdict = probe.wearer_close_verdict(delta)
        self.assertFalse(verdict["passed"])
        self.assertEqual(verdict["missing"], ["mainWindowScene closedByWearer stoppingPlayback"])

    def test_markers_out_of_order_fail(self) -> None:
        delta = [
            "mainWindowScene closedByWearer stoppingPlayback",
            "testcmd closeMainWindow session=ABC",
            "mainWindowScene disconnected trigger=wearer",
        ]
        verdict = probe.wearer_close_verdict(delta)
        self.assertFalse(verdict["passed"])
        self.assertFalse(verdict["ordered"])

    def test_default_item_is_a_library_grid_identifier(self) -> None:
        self.assertTrue(probe.DEFAULT_ITEM.startswith("MediaLibrary-grid-video-"))


if __name__ == "__main__":
    unittest.main()
