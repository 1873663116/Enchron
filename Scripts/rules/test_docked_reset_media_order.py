import unittest
from pathlib import Path

class DockedResetMediaOrderTests(unittest.TestCase):
    def test_docked_reset_media_is_last_in_docked_scenario(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        marker = "def docked_scenario"
        idx = text.find(marker)
        self.assertNotEqual(idx, -1)
        snippet = text[idx: idx + 9000]
        pos_settings = snippet.find("self.docked_settings_scenario()")
        pos_media = snippet.find("self.docked_media_information_scenario()")
        pos_environment = snippet.find("self.docked_environment_card_scenario()")
        pos_menu = snippet.find("self.player_panel_menu_scenario(")
        pos_transport = snippet.find("self.transport_scenario(")
        pos_issue = snippet.find("self.docked_issue_scenario()")
        pos_exit = snippet.find("self.docked_exit_scenario()")
        pos_exercise = snippet.find('self.exercise_playback_issue(')
        pos_observe_post = snippet.find('Docked playback post-reset-media')
        self.assertNotEqual(pos_settings, -1)
        self.assertNotEqual(pos_media, -1)
        self.assertNotEqual(pos_environment, -1)
        self.assertNotEqual(pos_menu, -1)
        self.assertNotEqual(pos_transport, -1)
        self.assertNotEqual(pos_issue, -1)
        self.assertNotEqual(pos_exit, -1)
        self.assertNotEqual(pos_exercise, -1)
        self.assertNotEqual(pos_observe_post, -1)
        self.assertLess(pos_environment, pos_settings)
        self.assertLess(pos_menu, pos_settings)
        self.assertLess(pos_transport, pos_settings)
        self.assertLess(pos_issue, pos_settings)
        self.assertLess(pos_exit, pos_settings)
        self.assertLess(pos_exercise, pos_settings)
        self.assertLess(pos_settings, pos_media)
        self.assertLess(pos_media, pos_observe_post)
        tail = snippet[pos_observe_post - 200: pos_observe_post + 800]
        self.assertIn("self.observe", tail)
        after_media = snippet[pos_media + len("self.docked_media_information_scenario()"): pos_observe_post + 1500]
        self.assertNotIn("self.docked_environment_card_scenario()", after_media)
        self.assertNotIn("self.player_panel_menu_scenario(", after_media)
        self.assertNotIn("self.transport_scenario(", after_media)
        self.assertNotIn("self.docked_issue_scenario()", after_media)
        self.assertNotIn("self.docked_exit_scenario()", after_media)

    def test_docked_settings_precedes_media_without_intervening_scenario(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def docked_scenario")
        snippet = text[idx: idx + 9000]
        pos_settings = snippet.find("self.docked_settings_scenario()")
        pos_media = snippet.find("self.docked_media_information_scenario()")
        between = snippet[pos_settings: pos_media]
        self.assertIn("self.docked_settings_scenario()", between)
        self.assertIn("self.docked_media_information_scenario()", snippet[pos_settings: pos_media + 50])
        self.assertNotIn("self.player_panel_menu_scenario", between)
        self.assertNotIn("self.transport_scenario", between)
        self.assertNotIn("self.docked_exit_scenario", between)

if __name__ == "__main__":
    unittest.main()
