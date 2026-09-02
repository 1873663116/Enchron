import unittest
from pathlib import Path

class SettingsMenuPlaybackGuardTests(unittest.TestCase):
    def test_settings_menu_scenario_selects_playback_category_before_menu(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        marker = 'def settings_menu_scenario'
        idx = text.find(marker)
        self.assertNotEqual(idx, -1)
        snippet = text[idx: idx + 2000]
        relaunch = snippet.find('self.relaunch()')
        menu = snippet.find('Settings-menu-resume-strategy')
        self.assertNotEqual(relaunch, -1)
        self.assertNotEqual(menu, -1)
        self.assertLess(relaunch, menu)

    def test_playback_selection_uses_reset_to_tab(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find('def settings_menu_scenario')
        snippet = text[idx: idx + 3000]
        self.assertIn('self.relaunch()', snippet)
        self.assertIn('Navigation-Ornament-tab-settings', snippet)
        self.assertNotIn('reset_to_tab', snippet)

    def test_menu_residue_is_cleared_before_final_category(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find('def settings_menu_scenario')
        snippet = text[idx: idx + 3000]
        menu_option = snippet.find('Settings-menuOption-')
        final_category = snippet.find('select_settings_category', menu_option)
        self.assertNotEqual(menu_option, -1)
        self.assertNotEqual(final_category, -1)
        self.assertLess(menu_option, final_category)
        self.assertNotIn('reset_to_tab', snippet[menu_option:final_category+100])

if __name__ == "__main__":
    unittest.main()
