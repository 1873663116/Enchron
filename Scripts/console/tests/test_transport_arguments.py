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


class AppCommandLatencyTests(unittest.TestCase):
    def setUp(self) -> None:
        transport._AWAKE_APPS.clear()
        self.addCleanup(transport._AWAKE_APPS.clear)
        original_is_simulator = transport.is_simulator
        self.addCleanup(setattr, transport, "is_simulator", original_is_simulator)

    def test_a_recent_wake_is_reused(self) -> None:
        transport._AWAKE_APPS[("DEVICE", "bundle")] = float("inf")
        calls: list[str] = []

        def probe(device: str) -> bool:
            calls.append(device)
            raise AssertionError("a recent wake must not be revalidated")

        transport.is_simulator = probe
        transport.ensure_app_awake("DEVICE", "bundle")
        self.assertEqual(calls, [])

    def test_an_old_wake_is_revalidated(self) -> None:
        transport._AWAKE_APPS[("DEVICE", "bundle")] = float("-inf")

        def probe(device: str) -> bool:
            raise RuntimeError("the wake is stale")

        transport.is_simulator = probe
        with self.assertRaises(RuntimeError):
            transport.ensure_app_awake("DEVICE", "bundle")

    def test_the_response_poll_is_short(self) -> None:
        self.assertLessEqual(transport.APP_COMMAND_RESPONSE_POLL_SECONDS, 0.05)
