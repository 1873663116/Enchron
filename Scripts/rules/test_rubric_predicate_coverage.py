#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPOSITORY_ROOT / "Scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.contracts import RubricContract
from regression.core.digest import canonical_digest
from regression.rubric_compiler import (
    FIELD_VALUES,
    CompiledRubric,
    FieldPredicate,
    RubricCompilerError,
    compile_rubric,
)


def load_checker():
    path = SCRIPTS / "rules" / "check_rubric_predicate_coverage.py"
    specification = importlib.util.spec_from_file_location("coverage_checker", path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


checker = load_checker()


def rubric(*criteria: str) -> RubricContract:
    return RubricContract(
        id="rubric:fixture.shape.o01@1",
        title="Fixture",
        criteria=tuple(criteria),
        negative_controls=("A reading that differs fails the bound case.",),
        body="body",
        source_digest=canonical_digest({"fixture": "rubric"}),
    )


class CompilerShapeTests(unittest.TestCase):
    """The compiler recognises registered field assertions and nothing else. A
    criterion it cannot reduce stays natural language and is listed, which is how
    `docs/CONTEXT.md` treats an evidence point no guard covers."""

    def test_a_registered_field_assertion_compiles(self) -> None:
        compiled = compile_rubric(
            rubric("The bound control-plane fields report lifecycle Playing.")
        )

        self.assertEqual(
            (FieldPredicate("lifecycle", "==", "Playing"),), compiled.predicates
        )
        self.assertEqual((), compiled.uncompiled)

    def test_an_equals_form_compiles_the_same_way(self) -> None:
        compiled = compile_rubric(rubric("The reading reports controls=shown."))

        self.assertEqual(
            (FieldPredicate("controls", "==", "shown"),), compiled.predicates
        )

    def test_a_boolean_literal_becomes_a_boolean(self) -> None:
        compiled = compile_rubric(rubric("The observation reports isEnabled false."))

        self.assertEqual(
            (FieldPredicate("isEnabled", "==", False),), compiled.predicates
        )

    def test_a_pixel_criterion_stays_natural_language(self) -> None:
        criterion = (
            "The first deviant frame shows the popover overlapping the top action "
            "row by more than a hairline."
        )

        compiled = compile_rubric(rubric(criterion))

        self.assertEqual((), compiled.predicates)
        self.assertEqual((criterion,), compiled.uncompiled)

    def test_an_unregistered_value_for_a_registered_field_is_not_compiled(
        self,
    ) -> None:
        criterion = "The reading reports lifecycle Buffering."

        compiled = compile_rubric(rubric(criterion))

        self.assertEqual((), compiled.predicates)
        self.assertEqual((criterion,), compiled.uncompiled)

    def test_a_negated_sentence_yields_no_predicate(self) -> None:
        criterion = "A reading with mediaKind video fails the bound case."

        compiled = compile_rubric(rubric(criterion))

        self.assertEqual((), compiled.predicates)
        self.assertEqual((criterion,), compiled.uncompiled)

    def test_a_negation_in_one_sentence_leaves_the_next_sentence_compilable(
        self,
    ) -> None:
        compiled = compile_rubric(
            rubric(
                "No reading of mediaKind video is admissible here. "
                "The bound fields report lifecycle Paused."
            )
        )

        self.assertEqual(
            (FieldPredicate("lifecycle", "==", "Paused"),), compiled.predicates
        )

    def test_repeated_assertions_are_recorded_once(self) -> None:
        compiled = compile_rubric(
            rubric(
                "The reading reports lifecycle Playing.",
                "The later reading also reports lifecycle Playing.",
            )
        )

        self.assertEqual(1, len(compiled.predicates))

    def test_anything_but_a_rubric_contract_is_refused(self) -> None:
        with self.assertRaisesRegex(RubricCompilerError, "one RubricContract"):
            compile_rubric({"criteria": ["lifecycle Playing"]})

    def test_every_registered_field_carries_at_least_one_value(self) -> None:
        for field, values in FIELD_VALUES.items():
            self.assertTrue(values, field)


class CoverageReportTests(unittest.TestCase):
    """The report is the record of what the deterministic layer does not cover.
    It must count criteria that yield a predicate, not call them covered: the
    predicate stands for the field assertion it names and no more."""

    def report(self) -> dict:
        return checker.coverage(REPOSITORY_ROOT / "Regression")

    def test_the_report_covers_the_whole_corpus(self) -> None:
        report = self.report()

        self.assertEqual(97, report["rubricCount"])
        self.assertEqual(len(report["byRubric"]), report["rubricCount"])
        self.assertEqual(
            report["criterionCount"],
            sum(item["criteria"] for item in report["byRubric"]),
        )

    def test_the_report_lists_every_criterion_that_yields_nothing(self) -> None:
        report = self.report()

        uncompiled = sum(len(item["uncompiled"]) for item in report["byRubric"])
        self.assertEqual(
            report["criterionCount"] - report["criteriaYieldingPredicates"],
            uncompiled,
        )

    def test_the_recorded_baseline_matches_the_corpus(self) -> None:
        report = self.report()
        baseline = checker.load_baseline(checker.BASELINE_PATH)

        self.assertEqual([], checker.regressions(report, baseline))
        self.assertEqual(
            baseline["criteriaYieldingPredicates"],
            report["criteriaYieldingPredicates"],
        )

    def test_a_drop_below_the_baseline_is_refused(self) -> None:
        report = dict(self.report())
        report["criteriaYieldingPredicates"] -= 1

        refusals = checker.regressions(
            report, checker.load_baseline(checker.BASELINE_PATH)
        )

        self.assertEqual(1, len(refusals))
        self.assertIn("fell from", refusals[0])

    def test_writing_a_baseline_that_lowers_coverage_is_refused(self) -> None:
        with TemporaryDirectory() as scratch:
            path = Path(scratch) / "baseline.json"
            path.write_text(
                json.dumps(
                    {"criteriaYieldingPredicates": 500, "predicateCount": 500}
                ),
                encoding="utf-8",
            )

            refusals = checker.write_baseline(self.report(), path)

            self.assertTrue(refusals)
            self.assertEqual(
                500, json.loads(path.read_text(encoding="utf-8"))[
                    "criteriaYieldingPredicates"
                ]
            )

    def test_writing_a_baseline_that_holds_coverage_is_accepted(self) -> None:
        with TemporaryDirectory() as scratch:
            path = Path(scratch) / "baseline.json"

            refusals = checker.write_baseline(self.report(), path)

            self.assertEqual([], refusals)
            recorded = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(
                self.report()["predicateCount"], recorded["predicateCount"]
            )

    def test_a_catalog_that_cannot_be_read_exits_non_zero(self) -> None:
        with TemporaryDirectory() as scratch:
            argv = sys.argv
            sys.argv = [
                "check_rubric_predicate_coverage.py",
                "--catalog-root",
                scratch,
            ]
            noise = io.StringIO()
            try:
                with contextlib.redirect_stderr(noise), contextlib.redirect_stdout(noise):
                    self.assertEqual(1, checker.main())
            finally:
                sys.argv = argv

            self.assertIn("could not be compiled", noise.getvalue())


if __name__ == "__main__":
    unittest.main()
