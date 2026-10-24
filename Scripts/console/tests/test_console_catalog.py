import contextlib
import os
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
                    {"operation": "operation:navigation.select-tab@1", "arguments": {"tab": "emby"}},
                    {"operation": "operation:accessibility.activate@2", "arguments": {"labels": ["Enchron Regression Series, poster"]}},
                ]
            ),
            "folder",
        )
        tap = [step for step in steps if step["args"].get("labelPrefix")][0]
        self.assertEqual(tap["args"]["label"], "Enchron Regression Series, poster")
        self.assertEqual(tap["args"]["labelPrefix"], "Enchron Regression Series")

    def test_a_plain_label_carries_no_prefix(self) -> None:
        steps, _ = catalog_units.translate(
            payload([{"operation": "operation:accessibility.activate@2", "arguments": {"labels": ["Season 2"]}}]),
            "folder",
        )
        tap = [step for step in steps if step["args"].get("label")][0]
        self.assertNotIn("labelPrefix", tap["args"])

    def test_the_emby_tab_resets_the_navigation_first(self) -> None:
        steps, _ = catalog_units.translate(
            payload([{"operation": "operation:navigation.select-tab@1", "arguments": {"tab": "emby"}}]),
            "folder",
        )
        verbs = [step["args"].get("verb") for step in steps]
        self.assertEqual(verbs[0], "resetMediaNavigation")
        self.assertEqual(steps[1]["args"]["identifier"], "Emby-Navigation-Tab")


class ColdStartTests(unittest.TestCase):
    def scenario_payload(self, identifier: str) -> dict:
        for path in catalog_units.SCENARIOS.rglob("*.md"):
            payload = catalog_units.scenario(path)
            if payload is not None and payload.get("id") == identifier:
                return payload
        raise AssertionError(f"no scenario {identifier}")

    def test_the_audit_declares_every_scenario_relaunch(self) -> None:
        self.assertEqual(len(catalog_units.cold_start_declarations()), 91)

    def test_the_matrix_replaces_its_relaunches_with_resets(self) -> None:
        payload = self.scenario_payload(
            "scenario:dynamic-range-interpretation:dolby-vision-profile-matrix"
        )
        steps, _ = catalog_units.translate(
            payload, "scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
        )
        verbs = [step["verb"] for step in steps]
        self.assertNotIn("app.relaunch", verbs)
        resets = [
            step
            for step in steps
            if step["verb"] == "device.app-command"
            and step["args"].get("verb") == "resetState"
        ]
        self.assertEqual(len(resets), 4)
        opens = [
            step
            for step in steps
            if step["verb"] == "device.app-command"
            and step["args"].get("verb") == "playMedia"
        ]
        self.assertEqual(len(opens), 5)
        frames = [
            step["args"]["count"]
            for step in steps
            if step["verb"] == "device.capture-frames"
        ]
        self.assertEqual(frames, [1, 1, 1, 1, 1])

    def test_a_declared_cold_start_keeps_its_relaunch(self) -> None:
        payload = self.scenario_payload(
            "scenario:emby-server-lifecycle:artwork-by-image-tag"
        )
        steps, _ = catalog_units.translate(payload, "scenario-artwork-by-image-tag")
        self.assertIn("app.relaunch", [step["verb"] for step in steps])

    def test_a_generated_unit_starts_without_a_relaunch(self) -> None:
        unit = catalog_units.unit_for(
            next(
                path
                for path in catalog_units.SCENARIOS.rglob("*.md")
                if (catalog_units.scenario(path) or {}).get("id")
                == "scenario:dynamic-range-interpretation:dolby-vision-profile-matrix"
            )
        )
        verbs = [action["verb"] for action in unit["actions"]]
        self.assertNotIn("app.relaunch", verbs)
        self.assertEqual(unit["actions"][1]["args"].get("verb"), "leavePlayback")

    def test_the_restart_report_accepts_the_audit(self) -> None:
        with open(os.devnull, "w", encoding="utf-8") as sink:
            with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
                self.assertEqual(catalog_units.report_restarts(), 0)


if __name__ == "__main__":
    unittest.main()
