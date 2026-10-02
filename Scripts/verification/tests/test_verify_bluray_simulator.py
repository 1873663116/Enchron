from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "Scripts"))
from Scripts.regression.tools.raster import Raster, encode_png
from Scripts.verification import verify_bluray_simulator as verifier


class BluRaySimulatorVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        image = encode_png(Raster(2, 2, 3, bytes([90, 100, 110] * 4)))
        self.shot = self.root / "frame.png"
        self.shot.write_bytes(image)
        self.outcomes = [
            {"succeeded": True, "operation": "operation:accessibility.inspect@2", "fields": {
                "requestedIdentifier": "FileBrowsing-FilesScreen-itemCount",
                "matchedElement": {"label": "1 items"},
            }},
            {"succeeded": True, "operation": "operation:accessibility.inspect@2", "fields": {
                "requestedIdentifier": "FileBrowsing-grid-bluray-playlist-0",
                "matchedElement": {"label": "Title 1, Playlist ID 0, Duration 2 min"},
            }},
            {"succeeded": True, "operation": "operation:media.open@2",
             "arguments": {"identifier": "FileBrowsing-grid-bluray-playlist-0"}, "fields": {}},
            {"succeeded": True, "operation": "operation:diagnostics.playback-state@1",
             "fields": {"fields": {"bluRayPlaylistID": "0"}}},
            {"succeeded": True, "operation": "operation:evidence.capture-frames@1", "fields": {
                "frames": [{
                    "record": {"localScreenshotPath": str(self.shot)},
                    "playbackState": {"fields": {
                        "bluRayPlaylistID": "0", "displayedPixel": "true",
                        "videoSamples": str(index + 1), "position": str(index),
                    }},
                } for index in range(3)]
            }},
        ]

    def test_literal_card_identity_duration_and_frames_pass(self) -> None:
        transcript = {"scenario": "scenario:bluray-disc:fel-iso", "outcomes": self.outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            report = verifier.verify_transcript(transcript)
        self.assertEqual(report["playlistID"], 0)
        self.assertEqual(report["screenshotDimensions"], [[2, 2]] * 3)

    def test_wrong_playback_playlist_fails(self) -> None:
        self.outcomes[3]["fields"]["fields"]["bluRayPlaylistID"] = "43"
        transcript = {"scenario": "scenario:bluray-disc:fel-iso", "outcomes": self.outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "different playlist"):
                verifier.verify_transcript(transcript)

    def test_one_by_one_capture_fails(self) -> None:
        self.shot.write_bytes(encode_png(Raster(1, 1, 3, bytes([90, 100, 110]))))
        transcript = {"scenario": "scenario:bluray-disc:fel-iso", "outcomes": self.outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "1x1"):
                verifier.verify_transcript(transcript)


if __name__ == "__main__":
    unittest.main()
