#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "verification"))

from harness import lane_partition as lp

INVENTORY = json.loads(
    (ROOT.parent / "Config" / "reachability_operation_inventory.json").read_text(encoding="utf-8")
)
OPERATIONS = INVENTORY["operations"]
MEDIA_OPENERS = [
    "accessibility:Emby-Detail-Play",
    "accessibility:FileBrowsing-grid-video-{file.name}",
    "accessibility:MediaLibrary-grid-video-{reference.name}",
]
HUNG_IDENTIFIER = "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"


class OpeningOperations(unittest.TestCase):
    def test_exactly_the_media_openers_open_playback(self) -> None:
        opening = sorted(op["id"] for op in OPERATIONS if lp.opens_playback(op))
        self.assertEqual(opening, MEDIA_OPENERS)

    def test_only_activations_open_playback(self) -> None:
        scroll = {
            "id": "scroll:x",
            "kind": "scroll",
            "identifierTemplate": "MediaLibrary-grid-video-{name}",
        }
        self.assertFalse(lp.opens_playback(scroll))

    def test_browse_activation_does_not_open_playback(self) -> None:
        folder = {
            "id": "accessibility:MediaLibrary-Manage-newFolder",
            "kind": "activate",
            "identifierTemplate": "MediaLibrary-Manage-newFolder",
        }
        self.assertFalse(lp.opens_playback(folder))


class OpeningIdentifierDecision(unittest.TestCase):
    def test_the_identifier_that_hung_the_simulator_is_recognised(self) -> None:
        self.assertTrue(lp.identifier_opens_playback(HUNG_IDENTIFIER))

    def test_file_browser_and_emby_openers_are_recognised(self) -> None:
        self.assertTrue(lp.identifier_opens_playback("FileBrowsing-grid-video-clip.mkv"))
        self.assertTrue(lp.identifier_opens_playback("Emby-Detail-Play"))

    def test_a_credential_submit_needs_the_device_without_opening_playback(self) -> None:
        self.assertTrue(lp.identifier_submits_credentials("FileBrowsing-SourceConnection-smb-connect"))
        self.assertTrue(lp.identifier_needs_device("FileBrowsing-SourceConnection-webDAV-connect"))
        self.assertFalse(lp.identifier_opens_playback("FileBrowsing-SourceConnection-webDAV-connect"))
        self.assertFalse(lp.identifier_submits_credentials("FileBrowsing-SourceConnection-webDAV-cancel"))

    def test_browse_controls_do_not_open_playback(self) -> None:
        for identifier in (
            "MediaLibrary-Manage-newFolder",
            "MediaLibrary-Breadcrumb-current",
            "Emby-Detail-Version",
        ):
            self.assertFalse(lp.identifier_opens_playback(identifier), identifier)

    def test_only_the_simulator_refuses_the_open(self) -> None:
        self.assertTrue(lp.simulator_refuses_tap(lp.SIMULATOR, HUNG_IDENTIFIER))
        self.assertFalse(lp.simulator_refuses_tap(lp.DEVICE, HUNG_IDENTIFIER))
        self.assertFalse(
            lp.simulator_refuses_tap(lp.SIMULATOR, "MediaLibrary-Manage-newFolder")
        )


if __name__ == "__main__":
    unittest.main()
