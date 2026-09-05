#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "verification"))

from harness import scenario_lanes
from harness.lane_partition import DEVICE, SIMULATOR
import reachability_matrix as matrix

SYNTHETIC = '''
class ReachabilityRun:
    def open_media(self, identifier):
        self.tap("main-window-browser", identifier)

    def open_first(self):
        name = self.primary()
        self.open_media(f"MediaLibrary-grid-video-{name}")

    def browse_only(self):
        self.tap("main-window-browser", "MediaLibrary-Manage-newFolder")

    def resume_from_emby(self):
        self.tap("main-window-browser", "Emby-Detail-Play")

    def nested(self):
        self.open_first()

    def connect_webdav(self):
        self.tap("main-window-browser", "FileBrowsing-SourceConnection-webDAV-connect")

    def run_named_segment_scenario(self, name):
        scenarios = {
            "browse": self.browse_only,
            "open": self.open_first,
            "nested": self.nested,
            "emby": self.resume_from_emby,
            "lambda-browse": lambda: self.browse_only(),
            "lambda-open": lambda: self.nested(),
            "connect": self.connect_webdav,
        }
        scenarios[name]()
'''

BROWSER_DEVICE_SCENARIOS = {
    "breadcrumbs",
    "emby-content-round11",
    "library-conditions",
    "library-editing-round11",
    "playback-failures",
    "player-ui-candidates",
    "remote-browser-round11",
    "resume-decision",
    "source-connection-smb",
    "source-connection-webdav",
}
BROWSER_SIMULATOR_SCENARIOS = {
    "browser-core",
    "emby-session-recovery",
    "emby-version-season",
    "file-browser-errors",
    "library-reference-move",
    "manage-add",
    "settings-category-round13",
    "settings-menus",
    "source-sidebar",
}


class SyntheticSource(unittest.TestCase):
    def setUp(self) -> None:
        self.lanes = scenario_lanes.classify(SYNTHETIC)

    def test_a_scenario_that_only_browses_stays_on_the_simulator(self) -> None:
        self.assertEqual(self.lanes["browse"], SIMULATOR)
        self.assertEqual(self.lanes["lambda-browse"], SIMULATOR)

    def test_an_f_string_opener_is_seen_through_its_prefix(self) -> None:
        self.assertEqual(self.lanes["open"], DEVICE)

    def test_the_opener_is_found_through_nested_calls(self) -> None:
        self.assertEqual(self.lanes["nested"], DEVICE)
        self.assertEqual(self.lanes["lambda-open"], DEVICE)

    def test_an_exact_emby_opener_is_recognised(self) -> None:
        self.assertEqual(self.lanes["emby"], DEVICE)

    def test_a_credential_submit_needs_the_device(self) -> None:
        self.assertEqual(self.lanes["connect"], DEVICE)

    def test_a_source_without_the_run_class_is_refused(self) -> None:
        with self.assertRaises(scenario_lanes.ScenarioTableMissing):
            scenario_lanes.classify("class Other:\n    pass\n")

    def test_a_run_class_without_the_table_is_refused(self) -> None:
        with self.assertRaises(scenario_lanes.ScenarioTableMissing):
            scenario_lanes.classify("class ReachabilityRun:\n    def tap(self):\n        pass\n")


class HarnessSource(unittest.TestCase):
    def test_every_planned_scenario_has_a_lane(self) -> None:
        missing = sorted(matrix.SEGMENT_SCENARIO_NAMES - set(matrix.SCENARIO_LANES))
        self.assertEqual(missing, [])

    def test_browser_scenarios_split_as_reviewed(self) -> None:
        browser = BROWSER_DEVICE_SCENARIOS | BROWSER_SIMULATOR_SCENARIOS
        device = {name for name in browser if matrix.SCENARIO_LANES[name] == DEVICE}
        self.assertEqual(device, BROWSER_DEVICE_SCENARIOS)

    def test_a_presentation_context_is_device_regardless_of_its_scenarios(self) -> None:
        self.assertEqual(matrix.segment_lane("window", ["window-environment-round11"]), DEVICE)

    def test_a_browser_segment_follows_its_most_demanding_scenario(self) -> None:
        self.assertEqual(
            matrix.segment_lane("main-window-browser", ["browser-core", "manage-add"]),
            SIMULATOR,
        )
        self.assertEqual(
            matrix.segment_lane("main-window-browser", ["browser-core", "resume-decision"]),
            DEVICE,
        )


if __name__ == "__main__":
    unittest.main()
