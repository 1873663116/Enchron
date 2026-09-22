from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))
import renderer_lead_sweep as sweep

PREFIX = "2026-09-08T14:09:16Z probeSequence=1 probeRetention=evidence probeSession=S windowSettlement "


def settlement(**fields: object) -> str:
    return PREFIX + ",".join(key + "=" + str(value) for key, value in fields.items())


class ParseTests(unittest.TestCase):
    def test_frames_accept_auto_and_integers(self) -> None:
        self.assertEqual(sweep.parse_frames("auto, 8,32"), [None, 8, 32])
        with self.assertRaises(ValueError):
            sweep.parse_frames(" , ")

    def test_settlement_line_becomes_fields(self) -> None:
        sample = sweep.parse_settlement(settlement(synchronizerRate=1.0, leadFramesBudget=32, footprintMB=451))
        self.assertEqual(sample["leadFramesBudget"], "32")
        self.assertEqual(sample["time"], "2026-09-08T14:09:16Z")
        self.assertIsNone(sweep.parse_settlement("2026-09-08T14:09:16Z testcmd seekNormalized begin"))


class SummaryTests(unittest.TestCase):
    def test_displayed_rate_comes_from_consecutive_playing_samples(self) -> None:
        samples = sweep.settlement_samples([
            settlement(synchronizerRate=1.0, synchronizerTime=10.0, displayedFrameObservationCount=100),
            settlement(synchronizerRate=1.0, synchronizerTime=12.0, displayedFrameObservationCount=196),
            settlement(synchronizerRate=0.0, synchronizerTime=13.0, displayedFrameObservationCount=200),
            settlement(synchronizerRate=1.0, synchronizerTime=20.0, displayedFrameObservationCount=300),
            settlement(synchronizerRate=1.0, synchronizerTime=22.0, displayedFrameObservationCount=360),
        ])
        self.assertEqual(sweep.displayed_rates(samples), [48.0, 30.0])

    def test_seek_costs_dedupe_the_carried_values(self) -> None:
        samples = sweep.settlement_samples([
            settlement(seekFlushMs="none", seekTotalMs="none", seekFramesInFlight="none"),
            settlement(seekFlushMs=41.2, seekTotalMs=180.5, seekFramesInFlight=31),
            settlement(seekFlushMs=41.2, seekTotalMs=180.5, seekFramesInFlight=31),
            settlement(seekFlushMs=38.0, seekTotalMs=150.0, seekFramesInFlight=30),
        ])
        self.assertEqual([cost["framesInFlight"] for cost in sweep.seek_costs(samples)], [31.0, 30.0])

    def test_cell_summary_reduces_the_window(self) -> None:
        samples = sweep.settlement_samples([
            settlement(synchronizerRate=1.0, synchronizerTime=10.0, displayedFrameObservationCount=100, leadFramesBudget=13, enqueueLeadMin=0.41, enqueueGapMax=0.02, lateEnqueues=0, footprintMB=440, availableMB=2100),
            settlement(synchronizerRate=1.0, synchronizerTime=12.0, displayedFrameObservationCount=200, leadFramesBudget=32, enqueueLeadMin=0.39, enqueueGapMax=0.05, lateEnqueues=1, footprintMB=455, availableMB=2050),
        ])
        cell = sweep.cell_summary("auto", samples)
        self.assertEqual(cell["budgetFramesSeen"], ["13", "32"])
        self.assertEqual(cell["displayedPerSecondMedian"], 50.0)
        self.assertEqual(cell["enqueueLeadMinSeconds"], 0.39)
        self.assertEqual(cell["enqueueGapMaxSeconds"], 0.05)
        self.assertEqual(cell["footprintMBMax"], 455.0)
        self.assertEqual(cell["availableMBMin"], 2050.0)
        self.assertEqual(cell["seeks"], [])

    def test_default_item_is_a_library_grid_identifier(self) -> None:
        self.assertTrue(sweep.DEFAULT_ITEM.startswith("MediaLibrary-grid-video-"))


if __name__ == "__main__":
    unittest.main()
