import unittest
from pathlib import Path
class WindowEffectDeliveryTests(unittest.TestCase):
    def test_window_environment_delivers_effect(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def window_environment_scenario")
        snippet = text[idx: idx + 8000]
        self.assertIn("accessibility:EnvironmentCard-effect-", snippet)
        self.assertIn("accessibility:EnvironmentCard-card", snippet)
        self.assertIn("accessibility:EnvironmentCard-carousel", snippet)
        pos_effect = snippet.find("EnvironmentCard-effect-")
        pos_card = snippet.find("EnvironmentCard-card")
        self.assertLess(pos_effect, snippet.find("environmentCard effect delivered"))
        self.assertIn("for operation_id in (", snippet)
        self.assertIn("EnvironmentCard-effect", snippet[snippet.find("if effect_delivered"): snippet.find("if effect_delivered")+2000])

    def test_immersive_menu_more_marks_received_when_hittable(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def player_panel_menu_scenario")
        snippet = text[idx: idx + 9000]
        self.assertIn("is_hittable = matched.get(\"isHittable\") is True", snippet)
        self.assertIn("if is_hittable:", snippet)
        self.assertIn("accessibility:PlayerPanel-menu-more", snippet)
        self.assertIn("received=True", snippet)

class WindowPlaybackControlsNoRegressionTests(unittest.TestCase):
    def test_window_environment_still_delivers_effect_after_controls_fix(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def window_environment_scenario")
        snippet = text[idx: idx + 8000]
        self.assertIn("EnvironmentCard-effect-", snippet)
        self.assertIn("if effect_delivered:", snippet)
        self.assertIn("EnvironmentCard-effect", snippet[snippet.find("if effect_delivered"): snippet.find("if effect_delivered")+2000])

    def test_video_format_custom_angle_credits_without_a_menu_row_tap(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def video_format_editor_scenario")
        snippet = text[idx: idx + 12000]
        self.assertIn("CustomAngle", snippet)
        start = snippet.find("-CustomAngle")
        block = snippet[start: snippet.find("cancel_editor()", start)]
        self.assertIn("family=\"customAngle\"", block)
        self.assertIn("delivered_by_debug_menu_selection", block)
        self.assertNotIn("--label", block)
        self.assertNotIn("hold(\"pace\"", block)

    def test_window_scenario_still_observes_playback_controls(self) -> None:
        text = (Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def window_scenario")
        snippet = text[idx: idx + 6000]
        self.assertIn("observe(presentation, \"Window playback controls\")", snippet)
        self.assertIn("video_format_editor_scenario", snippet)

if __name__ == "__main__":
    unittest.main()
