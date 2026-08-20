import sys
from pathlib import Path
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import verify_media_discovery_capability_matrix as capability


class MediaDiscoveryCapabilityMatrixTests(unittest.TestCase):
    def test_audio_only_entries_use_audio_reader_stages(self) -> None:
        self.assertEqual(
            capability.stages_for("audioOnly"),
            (("streams", "tracks"), ("open", "audio-reader")),
        )

    def test_first_frame_expectation_uses_a_minimum_not_an_exact_count(self) -> None:
        recorded = {
            "exitCode": 0,
            "expectation": {
                "codec": "avc1",
                "decode": "ok",
                "decodedFrames": "positive",
            },
        }
        actual = capability.ProbeResult(
            0,
            "stage=decode codec=avc1 decoded_frames=1 decode=ok",
            "",
        )

        self.assertEqual(
            capability.compare_stage("mp4", "local", "firstFrame", "decode", recorded, actual),
            [],
        )

    def test_proven_negative_result_requires_the_recorded_failure(self) -> None:
        recorded = {
            "exitCode": 2,
            "expectation": {"error": "Unsupported codec: mpeg4"},
        }
        actual = capability.ProbeResult(2, "", "Unsupported codec: mpeg4")

        self.assertEqual(
            capability.compare_stage("avi", "http", "open", "video-reader", recorded, actual),
            [],
        )

    def test_iso_transport_scopes_keep_local_udf_separate_from_http(self) -> None:
        self.assertEqual(
            capability.expected_source_scope("iso", "local"),
            "local-udf-image",
        )
        self.assertEqual(
            capability.expected_source_scope("iso", "http"),
            "http-byte-range-without-local-udf-detection",
        )


if __name__ == "__main__":
    unittest.main()
