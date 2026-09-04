#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_regression_related_results_arity as checker


def catalog(criteria, inlined, *, bound=True):
    call = {
        "callId": "call:probe:01",
        "operation": "operation:diagnostics.playback-state@1",
        "arguments": {"relatedResults": [f"result://call:probe:0{n}/fields" for n in range(inlined)]},
    }
    scenario = {
        "id": "scenario:probe",
        "operations": [call],
        "obligations": (
            [{"id": "o01", "rubric": "rubric:probe.o01@1", "producedByCall": "call:probe:01"}]
            if bound
            else []
        ),
    }
    return {
        "scenarios": [scenario],
        "rubrics": [{"id": "rubric:probe.o01@1", "criteria": criteria, "negativeControls": []}],
    }


class RelatedResultsArityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, document) -> None:
        path = self.repository / checker.BLUEPRINT
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(document, ensure_ascii=False) + "\n", encoding="utf-8")

    def test_a_criterion_within_the_inlined_count_passes(self) -> None:
        self.write(catalog(["relatedResults[1] is the response."], inlined=2))

        self.assertEqual(checker.failures(), [])

    def test_a_criterion_past_the_inlined_count_fails(self) -> None:
        self.write(catalog(["relatedResults[1] is the response."], inlined=1))

        self.assertIn("inlines 1", " ".join(checker.failures()))

    def test_a_criterion_reading_nothing_is_not_policed(self) -> None:
        self.write(catalog(["The bound artifact reports lifecycle Playing."], inlined=0))

        self.assertEqual(checker.failures(), [])

    def test_the_highest_index_decides(self) -> None:
        self.write(
            catalog(["relatedResults[0] is the route.", "relatedResults[2] is the trace."], inlined=2)
        )

        self.assertIn("relatedResults[2]", " ".join(checker.failures()))

    def test_a_negative_control_counts_too(self) -> None:
        document = catalog(["The bound artifact reports lifecycle Playing."], inlined=1)
        document["rubrics"][0]["negativeControls"] = ["A relatedResults[3] mismatch fails."]
        self.write(document)

        self.assertIn("relatedResults[3]", " ".join(checker.failures()))

    def test_a_rubric_nothing_binds_is_reported(self) -> None:
        self.write(catalog(["relatedResults[0] is the route."], inlined=1, bound=False))

        self.assertIn("no obligation binds it", " ".join(checker.failures()))


class RepositoryTests(unittest.TestCase):
    def test_the_live_catalog_has_no_arity_drift(self) -> None:
        self.assertEqual(checker.failures(), [])


if __name__ == "__main__":
    unittest.main()


class CaseGuardedSlotTests(unittest.TestCase):
    """A criterion that names its case only speaks for that case's producer."""

    def catalog(self, criterion: str) -> dict:
        def call(number: str, inlined: int) -> dict:
            return {
                "callId": f"call:j:s:{number}",
                "operation": "operation:accessibility.activate@2",
                "arguments": {"relatedResults": [f"result://x/{i}" for i in range(inlined)]},
            }

        return {
            "scenarios": [
                {
                    "id": "scenario:j:s",
                    "operations": [call("06", 2), call("15", 4)],
                    "obligations": [
                        {"caseKey": "window", "producedByCall": "call:j:s:06", "rubric": "rubric:r@1"},
                        {"caseKey": "portal", "producedByCall": "call:j:s:15", "rubric": "rubric:r@1"},
                    ],
                }
            ],
            "rubrics": [{"id": "rubric:r@1", "criteria": [criterion], "negativeControls": []}],
        }

    def test_a_case_named_sentence_spares_the_other_cases_producer(self) -> None:
        criterion = (
            "The window case reads relatedResults[1]. "
            "Portal inlines relatedResults[0], relatedResults[1..2], and relatedResults[3]."
        )
        with patch.object(checker, "blueprint", return_value=self.catalog(criterion)):
            self.assertEqual(checker.failures(), [])

    def test_an_unguarded_sentence_still_binds_every_producer(self) -> None:
        criterion = "Each bound artifact reads relatedResults[3]."
        with patch.object(checker, "blueprint", return_value=self.catalog(criterion)):
            self.assertEqual(
                checker.failures(),
                ["rubric:r@1: reads relatedResults[3] while call:j:s:06 inlines 2"],
            )

    def test_a_case_named_sentence_still_binds_its_own_producer(self) -> None:
        criterion = "The window case reads relatedResults[2]."
        with patch.object(checker, "blueprint", return_value=self.catalog(criterion)):
            self.assertEqual(
                checker.failures(),
                ["rubric:r@1: reads relatedResults[2] while call:j:s:06 inlines 2"],
            )
