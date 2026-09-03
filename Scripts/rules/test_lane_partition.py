#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "verification"))

from harness import lane_partition as lp

INVENTORY = json.loads(
    (ROOT.parent / "Config" / "reachability_operation_inventory.json").read_text(encoding="utf-8")
)
OPERATIONS = INVENTORY["operations"]
BY_ID = {op["id"]: op for op in OPERATIONS}
PLAYER_PRESENTATIONS = {"window", "portal", "panorama", "docked"}
BOUNDARY_OPENS = {
    "accessibility:MediaLibrary-grid-video-{reference.name}",
    "accessibility:FileBrowsing-grid-video-{file.name}",
}


class RealInventoryPartition(unittest.TestCase):
    def setUp(self) -> None:
        self.lanes = lp.partition(OPERATIONS)
        self.sim = self.lanes[lp.SIMULATOR]
        self.device = self.lanes[lp.DEVICE]

    def test_every_operation_lands_in_exactly_one_lane(self) -> None:
        self.assertEqual(len(self.sim) + len(self.device), len(OPERATIONS))
        self.assertEqual(set(self.sim) & set(self.device), set())
        self.assertEqual(set(self.sim) | set(self.device), set(BY_ID))

    def test_no_simulator_cell_needs_a_player_presentation(self) -> None:
        leaking = [
            op_id
            for op_id in self.sim
            if set(BY_ID[op_id].get("proofContexts", [])) & PLAYER_PRESENTATIONS
        ]
        self.assertEqual(leaking, [], f"simulator would starve driving {leaking}")

    def test_no_simulator_cell_opens_playback(self) -> None:
        opening = [op_id for op_id in self.sim if lp.opens_playback(BY_ID[op_id])]
        self.assertEqual(opening, [], f"opening media on the simulator hangs the app: {opening}")

    def test_simulator_cells_are_browser_only(self) -> None:
        for op_id in self.sim:
            self.assertEqual(
                BY_ID[op_id].get("proofContexts"),
                ["main-window-browser"],
                f"{op_id} is not a browse-only cell",
            )

    def test_every_playback_domain_operation_runs_on_device(self) -> None:
        for op in OPERATIONS:
            if op.get("proofDomain") == "playback":
                self.assertEqual(lp.lane_for(op), lp.DEVICE, op["id"])

    def test_media_opening_activations_run_on_device(self) -> None:
        for op_id in BOUNDARY_OPENS:
            self.assertIn(op_id, self.device)


class RejectsMisclassification(unittest.TestCase):
    def test_playback_opening_on_browse_surface_is_device(self) -> None:
        op = {
            "id": "x",
            "kind": "activate",
            "identifierTemplate": "MediaLibrary-grid-video-{name}",
            "proofContextDerivation": {"host": "browserWindowSurface"},
        }
        self.assertEqual(lp.lane_for(op), lp.DEVICE)

    def test_pure_browse_surface_is_simulator(self) -> None:
        op = {
            "id": "y",
            "kind": "activate",
            "identifierTemplate": "MediaLibrary-Manage-newFolder",
            "proofContextDerivation": {"host": "browserWindowSurface"},
        }
        self.assertEqual(lp.lane_for(op), lp.SIMULATOR)

    def test_player_host_is_device(self) -> None:
        op = {
            "id": "z",
            "kind": "activate",
            "identifierTemplate": "PlayerPanel-button-play",
            "proofContextDerivation": {"host": "fusedPlayerPanelSharedContent"},
        }
        self.assertEqual(lp.lane_for(op), lp.DEVICE)



HUNG_IDENTIFIER = "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"


class OpeningIdentifierDecision(unittest.TestCase):
    def test_the_identifier_that_hung_the_simulator_is_recognised(self) -> None:
        self.assertTrue(lp.identifier_opens_playback(HUNG_IDENTIFIER))

    def test_file_browser_and_emby_openers_are_recognised(self) -> None:
        self.assertTrue(lp.identifier_opens_playback("FileBrowsing-grid-video-clip.mkv"))
        self.assertTrue(lp.identifier_opens_playback("Emby-Detail-Resume"))
        self.assertTrue(lp.identifier_opens_playback("Emby-Detail-PlayFromBeginning"))

    def test_browse_controls_do_not_open_playback(self) -> None:
        for identifier in ("MediaLibrary-Manage-newFolder", "MediaLibrary-Breadcrumb-current", "Emby-Detail-Version"):
            self.assertFalse(lp.identifier_opens_playback(identifier), identifier)

    def test_only_the_simulator_defers_the_open(self) -> None:
        self.assertTrue(lp.tap_deferred_to_device(lp.SIMULATOR, HUNG_IDENTIFIER))
        self.assertFalse(lp.tap_deferred_to_device(lp.DEVICE, HUNG_IDENTIFIER))
        self.assertFalse(lp.tap_deferred_to_device(lp.SIMULATOR, "MediaLibrary-Manage-newFolder"))


if __name__ == "__main__":
    unittest.main()
