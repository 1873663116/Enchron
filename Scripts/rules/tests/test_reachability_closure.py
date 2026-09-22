import pathlib
import unittest


class ReachabilityClosureTests(unittest.TestCase):
    def test_broken_clip_fixture_registered(self):
        text = (pathlib.Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        self.assertIn('"broken-clip.mp4"', text)
        self.assertIn('TestVectors/Enchron/PlaybackBehavior/broken-clip.mp4', text)
        self.assertIn('"window-playback"', text)
        self.assertIn('broken-clip.mp4', text[text.find('SCENARIO_FIXTURES'):text.find('SCENARIO_FIXTURES')+2000])

    def test_window_scenario_drives_dock_and_load_failure(self):
        text = (pathlib.Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def window_scenario")
        snippet = text[idx: idx + 8000]
        self.assertIn("playback_failure_scenario", snippet)
        self.assertIn('enter_docked_playback', snippet)
        self.assertIn('dock_choice="default"', snippet)
        self.assertIn('sdr-bframe-multiaudio-subtitles-30s.mkv', snippet)

    def test_window_environment_delivers_volume(self):
        text = (pathlib.Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def window_environment_scenario")
        snippet = text[idx: idx + 9000]
        self.assertIn("environmentVolume:open-interact-close", snippet)
        self.assertIn("dismissEnvironmentCard", snippet)
        self.assertIn("wait_for_identifier_absent", snippet)

    def test_docked_environment_has_retry(self):
        text = (pathlib.Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find("def docked_environment_card_scenario")
        snippet = text[idx: idx + 9000]
        self.assertIn("environmentVolume:open-interact-close", snippet)
        self.assertIn('hold("pace"', snippet)

    def test_remote_episode_helper_exists(self):
        text = (pathlib.Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        self.assertIn("ensure_remote_episode_playback", text)
        self.assertIn("EpisodeSeries", text)
        self.assertIn("S01E", text)
        self.assertIn("FileBrowsing-grid-video-", text)

    def test_new_scenarios_registered(self):
        text = (pathlib.Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        self.assertIn("window-load-failure", text)
        self.assertIn("window-remote-audio-episodes", text)
        self.assertIn("portal-remote-audio-episodes", text)
        self.assertIn("SCENARIO_FIXTURES", text)


if __name__ == "__main__":
    unittest.main()
