import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_episode_switch_captures_frames as checker


def scenario(*operations: tuple[str, dict]) -> dict:
    return {
        "id": "scenario:t:s",
        "operations": [
            {"callId": f"call:t:s:{index:02d}", "operation": operation, "arguments": arguments}
            for index, (operation, arguments) in enumerate(operations, start=1)
        ],
    }


EPISODE = ("operation:accessibility.activate@2", {"identifiers": ["PlayerPanel-menu-more", "PlayerPanel-menu-episodes"]})
FRAMES = ("operation:evidence.capture-frames@1", {"context": "portal"})
INSPECT = ("operation:accessibility.inspect@2", {"identifier": "PlayerUI-spatial-state"})


class EpisodeSwitchCapturesFramesTests(unittest.TestCase):
    def test_frames_after_the_switch_satisfy_the_rule(self) -> None:
        self.assertEqual(checker.violations({"scenarios": [scenario(EPISODE, INSPECT, FRAMES)]}), [])

    def test_a_switch_without_frames_is_reported(self) -> None:
        found = checker.violations({"scenarios": [scenario(EPISODE, INSPECT)]})
        self.assertEqual(len(found), 1)
        self.assertIn("call:t:s:01", found[0])

    def test_frames_before_the_switch_do_not_count(self) -> None:
        self.assertEqual(len(checker.violations({"scenarios": [scenario(FRAMES, EPISODE)]})), 1)

    def test_other_activations_are_ignored(self) -> None:
        other = ("operation:accessibility.activate@2", {"identifiers": ["PlayerUI-TopAction-more", "PlayerUI-menu-audio"]})
        self.assertEqual(checker.violations({"scenarios": [scenario(other)]}), [])

    def test_real_blueprint_has_no_violations(self) -> None:
        catalog = json.loads(checker.BLUEPRINT.read_text(encoding="utf-8"))
        self.assertEqual(checker.violations(catalog), [])


if __name__ == "__main__":
    unittest.main()
