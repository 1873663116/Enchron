import sys
from pathlib import Path
import unittest
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).parents[3] / "Scripts" / "verification"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
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

    def test_iso_transport_scopes_name_selected_bluray_playlist(self) -> None:
        self.assertEqual(
            capability.expected_source_scope("iso", "local"),
            "local-selected-bluray-playlist",
        )
        self.assertEqual(
            capability.expected_source_scope("iso", "http"),
            "http-byte-range-selected-bluray-playlist",
        )
        self.assertEqual(
            capability.expected_selection("iso"),
            {"kind": "bluRayPlaylist", "playlistID": 0},
        )

    def test_iso_probe_passes_literal_playlist_zero_and_preserves_auth_url(self) -> None:
        source = "http://enchron-probe:media-discovery@127.0.0.1:9000/disc.iso"
        with patch.object(capability.subprocess, "run") as run:
            run.return_value = capability.subprocess.CompletedProcess(
                args=[], returncode=0, stdout="", stderr=""
            )
            capability.run_probe(Path("/probe"), "decode", source, 30, playlist_id=0)

        command = run.call_args.args[0]
        self.assertEqual(command[:5], ["/probe", "--stage", "decode", "--url", source])
        self.assertEqual(command[5:], ["--playlist", "0", "--seconds", "1"])

    def test_replay_rejects_output_from_another_playlist(self) -> None:
        recorded = {
            "exitCode": 0,
            "expectation": {
                "video_stream": "0",
                "duration": "positive",
                "playlist_id": "0",
            },
        }
        actual = capability.ProbeResult(
            0,
            "stage=video-reader playlist_id=1 video_stream=0 duration_seconds=120",
            "",
        )

        failures = capability.compare_stage(
            "iso", "local", "open", "video-reader", recorded, actual
        )

        self.assertEqual(
            failures,
            ["iso/local/open: playlist_id='1', expected '0'"],
        )


if __name__ == "__main__":
    unittest.main()
