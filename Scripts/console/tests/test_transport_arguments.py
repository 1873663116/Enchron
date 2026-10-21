import sys
import unittest
from pathlib import Path

CONSOLE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CONSOLE_ROOT))

import transport


class ScreenshotDefaultTests(unittest.TestCase):
    def parse(self, *arguments: str):
        return transport.parse_arguments(list(arguments))

    def test_an_interaction_action_starts_without_a_screenshot(self) -> None:
        for action in ("tap", "typeText", "press", "coordinateTap"):
            parsed = self.parse(action, "--device", "SIM", "--identifier", "X")
            self.assertTrue(parsed.no_screenshot, action)

    def test_an_explicit_screenshot_wins_over_the_default(self) -> None:
        parsed = self.parse("tap", "--device", "SIM", "--screenshot")
        self.assertFalse(parsed.no_screenshot)

    def test_a_snapshot_still_carries_its_screenshot(self) -> None:
        parsed = self.parse("snapshot", "--device", "SIM")
        self.assertFalse(parsed.no_screenshot)

    def test_a_snapshot_can_still_ask_not_to(self) -> None:
        parsed = self.parse("snapshot", "--device", "SIM", "--no-screenshot")
        self.assertTrue(parsed.no_screenshot)
