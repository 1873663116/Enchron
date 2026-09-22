import sys
from pathlib import Path
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[3] / "Scripts" / "verification"))
import extract_visionpro_ui_recording as recording


class VisionProUIRecordingExtractionTests(unittest.TestCase):
    def test_finds_exported_and_pending_staging_recordings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result_bundle = root / "Result.xcresult"
            staging = result_bundle / "Staging"
            exported = root / "exported"
            staging.mkdir(parents=True)
            exported.mkdir()

            (exported / "recording.mp4").write_bytes(b"exported-video")
            (exported / "pending.txt").write_text(
                "Unexpected Error: Finished test run with pending attachment."
            )
            (staging / "pending-recording").write_bytes(b"staging-video")

            attachment_records = [
                {
                    "suggestedHumanReadableName": "Screen Recording 2026-08-04",
                    "exportedFileName": "recording.mp4",
                    "timestamp": 100.0,
                },
                {
                    "suggestedHumanReadableName": "Screen Recording 2026-08-04",
                    "exportedFileName": "pending.txt",
                    "timestamp": 200.0,
                },
            ]

            sources = recording.find_recording_sources(
                result_bundle=result_bundle,
                attachment_export_root=exported,
                attachment_records=attachment_records,
                probe_video=lambda path: (
                    {"duration": 12.0, "width": 2732, "height": 2048}
                    if path.read_bytes().endswith(b"video")
                    else None
                ),
            )

            self.assertEqual(
                [(source.origin, source.path.name) for source in sources],
                [
                    ("xcresult attachment", "recording.mp4"),
                    ("xcresult pending attachment", "pending-recording"),
                ],
            )
            self.assertEqual(sources[0].started_at, 100.0)
            self.assertIsNone(sources[1].started_at)

    def test_frame_times_align_operations_and_named_checkpoints_to_recording(self) -> None:
        attachment_records = [
            {
                "suggestedHumanReadableName": "Screen Recording 2026-08-04",
                "timestamp": 100.0,
            },
            {
                "suggestedHumanReadableName": "Synthesized Event 2026-08-04",
                "timestamp": 104.0,
            },
            {
                "suggestedHumanReadableName": "panorama-handoff-window.png",
                "timestamp": 107.2,
            },
            {
                "suggestedHumanReadableName": "UI Snapshot 2026-08-04",
                "timestamp": 108.0,
            },
            {
                "suggestedHumanReadableName": "event-after-recording",
                "timestamp": 114.0,
            },
        ]

        points = recording.plan_frame_points(
            duration=12.0,
            recording_started_at=100.0,
            attachment_records=attachment_records,
            fixed_interval=5.0,
        )

        by_time = {point.seconds: set(point.reasons) for point in points}
        self.assertEqual(
            sorted(by_time),
            [0.5, 3.75, 4.0, 4.5, 5.0, 5.5, 7.2, 10.0, 11.5],
        )
        self.assertEqual(by_time[4.0], {"XCUITest interaction"})
        self.assertEqual(by_time[3.75], {"before XCUITest interaction"})
        self.assertEqual(by_time[4.5], {"after XCUITest interaction"})
        self.assertEqual(by_time[5.5], {"settled after XCUITest interaction"})
        self.assertEqual(
            by_time[7.2],
            {"test checkpoint: panorama-handoff-window.png"},
        )
        self.assertNotIn(8.0, by_time)


if __name__ == "__main__":
    unittest.main()
