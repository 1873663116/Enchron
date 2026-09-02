import pathlib
import unittest


class HonestMenuAudioEpisodesTests(unittest.TestCase):
    def _text(self):
        return (pathlib.Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")

    def test_audio_episodes_guard_requires_identifier(self):
        text = self._text()
        idx = text.find("def top_menu_scenario")
        snippet = text[idx: idx + 9000]
        self.assertIn('family in ("audio", "episodes")', snippet)
        self.assertIn('hierarchy_identifiers', snippet)
        self.assertIn('PlayerUI-menu-audio', snippet)
        self.assertIn('PlayerUI-menu-episodes', snippet)
        self.assertIn('The More menu did not expose', snippet)
        self.assertIn('remains unmeasured', snippet)

    def test_audio_episodes_not_inferred_from_parent(self):
        text = self._text()
        idx = text.find("def top_menu_scenario")
        snippet = text[idx: idx + 9000]
        self.assertNotIn('reportsHittable") is True', snippet)
        self.assertNotIn('The More parent was hittable and the sdr file provides', snippet)
        self.assertNotIn('The dock TopAction was hittable', snippet)

    def test_sdr_fixture_registered(self):
        text = self._text()
        self.assertIn('sdr-bframe-multiaudio-subtitles-30s.mkv', text)
        self.assertIn('TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-subtitles-30s.mkv', text)
        self.assertIn('"window-remote-audio-episodes"', text)
        self.assertIn('"portal-remote-audio-episodes"', text)
        self.assertIn('EpisodeSeries', text)
        self.assertIn('S01E', text)
        self.assertIn('ensure_remote_episode_playback', text)

    def test_no_fabricated_audio_delivery(self):
        text = self._text()
        self.assertNotIn('The DEBUG open and dismiss verbs bracketed a probed product interaction; the volume close was not observed but the interaction itself is considered delivered', text)
        self.assertNotIn('The named More parent supplied hierarchy and hittability evidence; the DEBUG equivalent for audio was hittable', text)


if __name__ == "__main__":
    unittest.main()
