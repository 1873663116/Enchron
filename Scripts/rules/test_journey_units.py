#!/usr/bin/env python3
"""The rules that decide what a unit step proves."""

from __future__ import annotations

import re
import unittest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import journey_units as units


class TemplateMatchingTests(unittest.TestCase):
    PATTERNS = [
        (units.template_pattern(template), f"accessibility:{template}")
        for template in (
            "Emby-Detail-Version",
            "Emby-Detail-{action}",
            "Settings-action-{id}",
        )
    ]

    def sorted_patterns(self) -> list[tuple[re.Pattern[str], str]]:
        entries = sorted(
            self.PATTERNS,
            key=lambda entry: -len(re.sub(r"\{.*?\}", "", entry[1])),
        )
        return entries

    def test_an_exact_template_beats_a_wildcard_that_swallows_it(self) -> None:
        found = units.match_operation("Emby-Detail-Version", self.sorted_patterns())

        self.assertEqual(found, "accessibility:Emby-Detail-Version")

    def test_a_wildcard_still_matches_its_own_instances(self) -> None:
        found = units.match_operation("Emby-Detail-Resume", self.sorted_patterns())

        self.assertEqual(found, "accessibility:Emby-Detail-{action}")

    def test_an_unknown_identifier_matches_nothing(self) -> None:
        self.assertIsNone(units.match_operation("Nothing-Here", self.sorted_patterns()))


class DerivedCoverageTests(unittest.TestCase):
    PATTERNS = [(units.template_pattern("Grid-card-{id}"), "accessibility:Grid-card-{id}")]

    def test_a_real_tap_covers_the_operation_it_taps(self) -> None:
        step = units.real("tap", "Grid-card-one", expect="Card opens.")

        self.assertEqual(
            units.derived_claims(step, ("window",), self.PATTERNS),
            [("window", "accessibility:Grid-card-{id}")],
        )

    def test_setup_and_evidence_steps_cover_nothing(self) -> None:
        """Reaching a screen and reading it back are not the operation. Crediting
        them would let a unit claim coverage it never drove."""
        for build in (units.setup, units.evidence):
            step = build("tap", "Grid-card-one", expect="Card opens.")

            self.assertEqual(units.derived_claims(step, ("window",), self.PATTERNS), [])

    def test_a_step_is_credited_in_the_context_it_crosses_into(self) -> None:
        step = units.real(
            "tap", "Grid-card-one", context="panorama", expect="Card opens."
        )

        self.assertEqual(
            units.derived_claims(step, ("portal",), self.PATTERNS),
            [("panorama", "accessibility:Grid-card-{id}")],
        )

    def test_an_app_command_covers_its_command_operation(self) -> None:
        step = units.injected(
            "app",
            "seekNormalized",
            why="w",
            skips="s",
            blind="b",
            expect="Position lands.",
        )

        self.assertIn(("window", "command:seekNormalized"), units.derived_claims(step, ("window",), []))


class RegistryTests(unittest.TestCase):
    def test_the_registry_passes_its_own_check(self) -> None:
        self.assertEqual(units.check(), 0)

    def test_every_cell_is_covered_or_exempt_and_never_both(self) -> None:
        cells = set(units.matrix_cells())
        assignment = units.covered_by(units.identifier_operations())
        covered = {cell for cell in assignment if cell in cells}
        exempt = set(units.EXEMPTIONS)

        self.assertEqual(covered | exempt, cells)
        self.assertEqual(covered & exempt, set())

    def test_the_committed_ledger_matches_the_registry(self) -> None:
        self.assertEqual(
            units.LEDGER_PATH.read_text(encoding="utf-8"), units.ledger_text()
        )

    CREDENTIAL_FIELD = re.compile(
        r"Password|Username|User\b|Address|Host|Token|Secret|Share", re.IGNORECASE
    )

    def test_credentials_are_named_by_placeholder_never_by_value(self) -> None:
        """A step's text reaches the device log and the committed ledger, so a
        field that carries a secret names it and the runner supplies it."""
        for unit in units.UNITS:
            for step in unit.steps:
                if step.text is None or not self.CREDENTIAL_FIELD.search(step.target):
                    continue
                self.assertRegex(
                    step.text,
                    r"^\$\{[A-Z_]+\}$",
                    f"{unit.id} types a literal into {step.target}",
                )



class DeviceHubVocabularyTests(unittest.TestCase):
    SURFACE = "PlayerUI-window-playback-surface"
    ENTITY = "EnchronWindowInput.surface"
    PROBE = "spatialTap entity=EnchronWindowInput.surface accepted=true"

    def complaints(self, step: units.Step) -> list[str]:
        return units.entity_input_complaints(
            step, units.identifier_operations(), units.entity_input_operations()
        )

    def test_a_synthetic_tap_on_an_entity_input_target_is_rejected(self) -> None:
        step = units.real("tap", self.SURFACE, expect="Controls appear.")
        self.assertTrue(any("RealityKit" in item for item in self.complaints(step)))

    def test_an_injection_cannot_claim_an_entity_input_target(self) -> None:
        step = units.injected(
            "tap", self.SURFACE, why="w", skips="s", blind="b", expect="Shown."
        )
        self.assertTrue(self.complaints(step))

    def test_a_device_hub_pinch_with_the_probe_contract_passes(self) -> None:
        step = units.device_hub(
            "pinch", self.SURFACE, entity=self.ENTITY, probe=self.PROBE, expect="Shown."
        )
        self.assertEqual([], self.complaints(step))

    def test_a_channel_style_probe_is_rejected(self) -> None:
        step = units.device_hub(
            "pinch",
            self.SURFACE,
            entity=self.ENTITY,
            probe="toggle source=channel showControls=true",
            expect="Shown.",
        )
        self.assertTrue(any("spatialTap" in item for item in self.complaints(step)))

    def test_a_device_hub_step_cannot_launder_an_ordinary_control(self) -> None:
        step = units.device_hub(
            "pinch",
            "PlayerPanel-button-play",
            entity=self.ENTITY,
            probe=self.PROBE,
            expect="Pauses.",
        )
        self.assertTrue(self.complaints(step))

    def test_evidence_fields_are_rejected_outside_device_hub(self) -> None:
        step = units.Step(
            verb="tap",
            target=self.SURFACE,
            drive=units.REAL,
            entity=self.ENTITY,
            expect="Shown.",
        )
        self.assertTrue(
            any("only a device-hub" in item for item in self.complaints(step))
        )

    def test_a_device_hub_pinch_covers_the_operation_it_pinches(self) -> None:
        patterns = [
            (units.template_pattern(self.SURFACE), f"accessibility:{self.SURFACE}")
        ]
        step = units.device_hub(
            "pinch", self.SURFACE, entity=self.ENTITY, probe=self.PROBE, expect="Shown."
        )
        self.assertEqual(
            units.derived_claims(step, ("window",), patterns),
            [("window", f"accessibility:{self.SURFACE}")],
        )

    def test_the_surface_cells_record_the_device_hub_drive_and_probe(self) -> None:
        assignment = units.covered_by(units.identifier_operations())
        for context in ("window", "portal"):
            entry = assignment[(context, f"accessibility:{self.SURFACE}")]
            self.assertEqual(units.DEVICE_HUB, entry["drive"])
            self.assertIn("accepted=true", str(entry["probe"]))


if __name__ == "__main__":
    unittest.main()
