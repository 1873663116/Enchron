import pathlib
import unittest


class PlaybackFailureIdentifierContractTests(unittest.TestCase):
    def _text(self):
        return (pathlib.Path(__file__).resolve().parents[2] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")

    def test_broken_clip_fixture_still_registered(self):
        text = self._text()
        self.assertIn('"broken-clip.mp4"', text)
        self.assertIn('TestVectors/Enchron/PlaybackBehavior/broken-clip.mp4', text)
        self.assertIn('SCENARIO_FIXTURES', text)
        idx = text.find('SCENARIO_FIXTURES')
        self.assertIn('broken-clip.mp4', text[idx: idx + 3000])
        self.assertIn('"window-playback"', text)

    def test_playback_failure_marks_known_defect_when_identifier_absent(self):
        text = self._text()
        idx = text.find('def playback_failure_scenario')
        snippet = text[idx: idx + 9000]
        self.assertIn('PlayerUI-loadFailure-primary', snippet)
        self.assertIn('PlayerUI-loadFailure-secondary', snippet)
        self.assertIn("label: 'Retry'", snippet)
        self.assertIn("label: 'Close'", snippet)
        self.assertIn('mark_observation', snippet)
        self.assertIn('snapshot', snippet)
        self.assertIn('PlayerUI-loadFailure-primary assigned in MainView.swift', snippet)
        self.assertIn('PlayerUI-loadFailure-secondary assigned in MainView.swift', snippet)
        self.assertIn('identifier contract', snippet)

    def test_playback_failure_reachable_only_via_identifier(self):
        text = self._text()
        idx = text.find('def playback_failure_scenario')
        snippet = text[idx: idx + 9000]
        self.assertIn('if primary is not None:', snippet)
        self.assertIn('self.tap(presentation, primary)', snippet)
        self.assertIn('self.delivered', snippet)
        self.assertIn('reachability playback issue delivered', snippet)
        self.assertIn('action=retry', snippet)

    def test_playback_failure_uses_label_only_as_recovery(self):
        text = self._text()
        idx = text.find('def playback_failure_scenario')
        snippet = text[idx: idx + 9000]
        self.assertIn('controller("tap", "--label", "Retry"', snippet)
        self.assertIn('controller("tap", "--label", "Close"', snippet)
        self.assertNotIn('"matchedElement": {"isHittable": True}', snippet)
        secondary_else = snippet.count('else:')
        self.assertGreaterEqual(secondary_else, 2)

    def test_no_fabricated_matched_element(self):
        text = self._text()
        idx = text.find('def playback_failure_scenario')
        snippet = text[idx: idx + 9000]
        self.assertNotIn('Retry" in hierarchy', snippet)
        self.assertNotIn("primary_doc = {\"matchedElement\"", snippet)
        self.assertNotIn("secondary_doc = {\"matchedElement\"", snippet)


if __name__ == "__main__":
    unittest.main()
