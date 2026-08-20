#!/usr/bin/env python3
"""The rules that decide what a unit step proves."""

from __future__ import annotations

import re
import unittest

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


if __name__ == "__main__":
    unittest.main()
