from __future__ import annotations

import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]


class EnvironmentHomeDismissalOwnerTests(unittest.TestCase):
    def test_environment_navigation_has_no_standalone_scene(self) -> None:
        app = (REPO / "Apps/Enchron/EnchronApp.swift").read_text()
        main = (REPO / "Apps/Enchron/MainView.swift").read_text()
        self.assertNotIn('Window("Environment"', app)
        self.assertIn("EnvironmentHomeView(isCompact:", main)
        self.assertIn(".onChange(of: playbackSession.environmentCardDismissalRequestRevision)", main)
        self.assertNotIn("dismissWindow(", main)

    def test_spatial_handoff_navigates_away_from_the_environment_page(self) -> None:
        executor = (REPO / "Modules/Playback/Platform/SpatialPlatformEffectExecutor.swift").read_text()
        self.assertIn("setEnvironmentHomeVisible(false)", executor)
        self.assertNotIn("senseZoneVolumeID", executor)


if __name__ == "__main__":
    unittest.main()
