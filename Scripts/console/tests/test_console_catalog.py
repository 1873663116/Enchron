import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import catalog_units


def payload(operations: list[dict]) -> dict:
    return {"id": "scenario:test:example", "operations": operations}


class TranslationTests(unittest.TestCase):
    def test_a_card_label_carries_its_prefix(self) -> None:
        steps, _ = catalog_units.translate(
            payload(
                [
                    {"operation": "navigation.select-tab@1", "arguments": {"tab": "emby"}},
                    {"operation": "accessibility.activate@2", "arguments": {"labels": ["Enchron Regression Series, poster"]}},
                ]
            ),
            "folder",
        )
        tap = [step for step in steps if step["args"].get("label")][0]
        self.assertEqual(tap["args"]["label"], "Enchron Regression Series, poster")
        self.assertEqual(tap["args"]["labelPrefix"], "Enchron Regression Series")

    def test_a_plain_label_carries_no_prefix(self) -> None:
        steps, _ = catalog_units.translate(
            payload([{"operation": "accessibility.activate@2", "arguments": {"labels": ["Season 2"]}}]),
            "folder",
        )
        tap = [step for step in steps if step["args"].get("label")][0]
        self.assertNotIn("labelPrefix", tap["args"])

    def test_the_emby_tab_resets_the_navigation_first(self) -> None:
        steps, _ = catalog_units.translate(
            payload([{"operation": "navigation.select-tab@1", "arguments": {"tab": "emby"}}]),
            "folder",
        )
        verbs = [step["args"].get("verb") for step in steps]
        self.assertEqual(verbs[0], "resetMediaNavigation")
        self.assertEqual(steps[1]["args"]["identifier"], "Emby-Navigation-Tab")


if __name__ == "__main__":
    unittest.main()
