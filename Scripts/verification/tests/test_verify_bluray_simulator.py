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
        self.shots = []
        for index, color in enumerate((40, 90, 140)):
            path = self.root / f"frame-{index}.png"
            path.write_bytes(encode_png(Raster(2, 2, 3, bytes([color, 100, 110] * 4))))
            self.shots.append(path)

    def _frames(self, playlist_id: int) -> dict:
        return {
            "succeeded": True,
            "operation": "operation:evidence.capture-frames@1",
            "fields": {
                "frames": [
                    {
                        "record": {"localScreenshotPath": str(path)},
                        "playbackState": {"fields": {
                            "bluRayPlaylistID": str(playlist_id),
                            "displayedPixel": "true",
                            "videoSamples": str(index + 1),
                            "position": str(index),
                        }},
                    }
                    for index, path in enumerate(self.shots)
                ]
            },
        }

    def _fel_outcomes(self) -> list[dict]:
        return [
            self._inspection("FileBrowsing-FilesScreen-itemCount", "1 items"),
            self._inspection(
                "FileBrowsing-grid-bluray-content-0",
                "FEL_test_for_AVS, Duration 2 min",
            ),
            {
                "succeeded": True,
                "operation": "operation:media.open@2",
                "arguments": {"identifier": "FileBrowsing-grid-bluray-content-0"},
                "fields": {},
            },
            {
                "succeeded": True,
                "operation": "operation:diagnostics.playback-state@1",
                "fields": {"fields": {"bluRayPlaylistID": "0"}},
            },
            self._frames(0),
        ]

    def _fel_directory_outcomes(self) -> list[dict]:
        outcomes = [
            self._inspection("FileBrowsing-FilesScreen-itemCount", "2 items"),
            {
                "succeeded": True,
                "operation": "operation:accessibility.activate@2",
                "arguments": {"identifiers": ["FileBrowsing-grid-bluray-browseFiles"]},
                "fields": {},
            },
            {
                "succeeded": True,
                "operation": "operation:accessibility.activate@2",
                "arguments": {"identifiers": ["FileBrowsing-grid-folder-BDMV"]},
                "fields": {},
            },
            self._inspection("FileBrowsing-FilesScreen-itemCount", "2 items"),
        ]
        outcomes.extend(self._fel_outcomes()[1:])
        return outcomes

    def _avs_outcomes(self) -> list[dict]:
        return [
            self._inspection("FileBrowsing-FilesScreen-itemCount", "3 items"),
            self._inspection("FileBrowsing-grid-bluray-group-videos", "Videos, 97 items"),
            self._inspection("FileBrowsing-grid-bluray-group-sequences", "Sequences, 2 items"),
            self._inspection("FileBrowsing-grid-bluray-group-stillImages", "Still images, 11 items"),
            {
                "succeeded": True,
                "operation": "operation:accessibility.activate@2",
                "arguments": {"identifiers": ["FileBrowsing-grid-bluray-group-sequences"]},
                "fields": {},
            },
            self._inspection("FileBrowsing-FilesScreen-itemCount", "2 items"),
            self._inspection(
                "FileBrowsing-grid-bluray-content-99",
                "Sequences · 30s · H.264 1080p, Duration 30 sec",
            ),
            self._inspection(
                "FileBrowsing-grid-bluray-content-43",
                "Sequences · 25m 00s · H.264 1080p, Duration 25 min",
            ),
            {
                "succeeded": True,
                "operation": "operation:media.open@2",
                "arguments": {"identifier": "FileBrowsing-grid-bluray-content-99"},
                "fields": {},
            },
            {
                "succeeded": True,
                "operation": "operation:diagnostics.playback-state@1",
                "fields": {"fields": {"bluRayPlaylistID": "99"}},
            },
            self._frames(99),
        ]

    def _sintel_outcomes(self) -> list[dict]:
        return [
            self._inspection("FileBrowsing-FilesScreen-itemCount", "2 items"),
            self._inspection(
                "FileBrowsing-grid-bluray-group-additional",
                "Additional content, 1 items",
            ),
            self._inspection(
                "FileBrowsing-grid-bluray-content-0",
                "Sintel-Bluray, Duration 14 min",
            ),
            {
                "succeeded": True,
                "operation": "operation:media.open@2",
                "arguments": {"identifier": "FileBrowsing-grid-bluray-content-0"},
                "fields": {},
            },
            {
                "succeeded": True,
                "operation": "operation:diagnostics.playback-state@1",
                "fields": {"fields": {"bluRayPlaylistID": "0"}},
            },
            self._frames(0),
        ]

    def _editions_outcomes(self) -> list[dict]:
        return [
            self._inspection("FileBrowsing-FilesScreen-itemCount", "3 items"),
            self._inspection(
                "FileBrowsing-grid-bluray-group-additional",
                "Additional content, 1 items",
            ),
            self._inspection(
                "FileBrowsing-grid-bluray-content-1",
                "1m 15s · Sintel – Edition tests, Duration 1 min",
            ),
            self._inspection(
                "FileBrowsing-grid-bluray-content-0",
                "1m 00s · Sintel – Edition tests, Duration 1 min",
            ),
            {
                "succeeded": True,
                "operation": "operation:media.open@2",
                "arguments": {"identifier": "FileBrowsing-grid-bluray-content-1"},
                "fields": {},
            },
            {
                "succeeded": True,
                "operation": "operation:diagnostics.playback-state@1",
                "fields": {"fields": {"bluRayPlaylistID": "1"}},
            },
            self._frames(1),
        ]

    @staticmethod
    def _inspection(identifier: str, label: str) -> dict:
        return {
            "succeeded": True,
            "operation": "operation:accessibility.inspect@2",
            "fields": {
                "requestedIdentifier": identifier,
                "matchedElement": {"label": label},
            },
        }

    def test_fel_content_card_duration_and_frames_pass_without_visible_playlist_id(self) -> None:
        transcript = {
            "scenario": "scenario:bluray-disc:fel-iso",
            "outcomes": self._fel_outcomes(),
        }
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            report = verifier.verify_transcript(transcript)
        self.assertEqual(report["playlistID"], 0)
        self.assertEqual(report["rootItemCounts"], [1])
        self.assertEqual(report["screenshotDimensions"], [[2, 2]] * 3)

    def test_avs_root_groups_then_sequence_content_and_selected_identity_pass(self) -> None:
        transcript = {
            "scenario": "scenario:bluray-disc:avs-iso",
            "outcomes": self._avs_outcomes(),
        }
        with mock.patch.object(
            verifier,
            "_oracle",
            return_value=(110, {99: "30 sec", 43: "25 min"}),
        ):
            report = verifier.verify_transcript(transcript)
        self.assertEqual(report["authoredTitleCount"], 110)
        self.assertEqual(report["rootItemCounts"], [3, 2])
        self.assertEqual(report["playlistID"], 99)

    def test_fel_directory_proves_parent_and_bdmv_self_content_counts(self) -> None:
        transcript = {
            "scenario": "scenario:bluray-disc:fel-directory",
            "outcomes": self._fel_directory_outcomes(),
        }
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            report = verifier.verify_transcript(transcript)
        self.assertEqual(report["rootItemCounts"], [2, 2])

    def test_official_sintel_root_has_feature_and_additional_group(self) -> None:
        transcript = {
            "scenario": "scenario:bluray-disc:sintel-iso",
            "outcomes": self._sintel_outcomes(),
        }
        with mock.patch.object(verifier, "_oracle", return_value=(2, {0: "14 min"})):
            report = verifier.verify_transcript(transcript)
        self.assertEqual(report["rootItemCounts"], [2])
        self.assertEqual(report["playlistID"], 0)

    def test_controlled_editions_root_has_both_versions_and_additional_group(self) -> None:
        transcript = {
            "scenario": "scenario:bluray-disc:sintel-editions-iso",
            "outcomes": self._editions_outcomes(),
        }
        with mock.patch.object(
            verifier, "_oracle", return_value=(3, {1: "1 min", 0: "1 min"})
        ):
            report = verifier.verify_transcript(transcript)
        self.assertEqual(report["rootItemCounts"], [3])
        self.assertEqual(report["playlistID"], 1)

    def test_controlled_editions_missing_sixty_second_version_is_rejected(self) -> None:
        outcomes = self._editions_outcomes()
        outcomes.pop(3)
        transcript = {
            "scenario": "scenario:bluray-disc:sintel-editions-iso",
            "outcomes": outcomes,
        }
        with mock.patch.object(
            verifier, "_oracle", return_value=(3, {1: "1 min", 0: "1 min"})
        ):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "Content 0"):
                verifier.verify_transcript(transcript)

    def test_controlled_editions_wrong_authored_name_is_rejected(self) -> None:
        outcomes = self._editions_outcomes()
        outcomes[2]["fields"]["matchedElement"]["label"] = (
            "Sintel Director Cut, Duration 1 min"
        )
        transcript = {
            "scenario": "scenario:bluray-disc:sintel-editions-iso",
            "outcomes": outcomes,
        }
        with mock.patch.object(
            verifier, "_oracle", return_value=(3, {1: "1 min", 0: "1 min"})
        ):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "Content 1"):
                verifier.verify_transcript(transcript)

    def test_old_110_card_root_is_rejected(self) -> None:
        outcomes = self._avs_outcomes()
        outcomes[0]["fields"]["matchedElement"]["label"] = "110 items"
        transcript = {"scenario": "scenario:bluray-disc:avs-iso", "outcomes": outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(110, {99: "30 sec", 43: "25 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "content count"):
                verifier.verify_transcript(transcript)

    def test_visible_playlist_id_is_rejected(self) -> None:
        outcomes = self._fel_outcomes()
        outcomes[1]["fields"]["matchedElement"]["label"] += ", Playlist ID 0"
        transcript = {"scenario": "scenario:bluray-disc:fel-iso", "outcomes": outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "visible Playlist ID"):
                verifier.verify_transcript(transcript)

    def test_old_playlist_card_identifier_is_rejected(self) -> None:
        outcomes = self._fel_outcomes()
        outcomes[1]["fields"]["requestedIdentifier"] = "FileBrowsing-grid-bluray-playlist-0"
        outcomes[2]["arguments"]["identifier"] = "FileBrowsing-grid-bluray-playlist-0"
        transcript = {"scenario": "scenario:bluray-disc:fel-iso", "outcomes": outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "playlist card identifier"):
                verifier.verify_transcript(transcript)

    def test_content_inspection_before_group_click_is_rejected(self) -> None:
        outcomes = self._avs_outcomes()
        content = outcomes.pop(6)
        outcomes.insert(1, content)
        transcript = {"scenario": "scenario:bluray-disc:avs-iso", "outcomes": outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(110, {99: "30 sec", 43: "25 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "before its content group"):
                verifier.verify_transcript(transcript)

    def test_screenshot_from_another_playlist_fails(self) -> None:
        outcomes = self._fel_outcomes()
        outcomes[-1]["fields"]["frames"][0]["playbackState"]["fields"]["bluRayPlaylistID"] = "43"
        transcript = {"scenario": "scenario:bluray-disc:fel-iso", "outcomes": outcomes}
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "another playlist"):
                verifier.verify_transcript(transcript)

    def test_one_by_one_capture_fails(self) -> None:
        self.shots[0].write_bytes(encode_png(Raster(1, 1, 3, bytes([90, 100, 110]))))
        transcript = {
            "scenario": "scenario:bluray-disc:fel-iso",
            "outcomes": self._fel_outcomes(),
        }
        with mock.patch.object(verifier, "_oracle", return_value=(1, {0: "2 min"})):
            with self.assertRaisesRegex(verifier.BluRayE2EError, "1x1"):
                verifier.verify_transcript(transcript)


if __name__ == "__main__":
    unittest.main()
