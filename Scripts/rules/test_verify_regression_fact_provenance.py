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

import verify_regression_fact_provenance as checker  # noqa: E402


CONSTANT_SOURCE = """static const double SOME_TARGET_SECONDS = 1.0;
static const long SOME_BACKOFF[] = {250, 500, 1000};
    public static let someThreshold: Double = 15 * 60
"""

DECISIONS = "id\tstatus\tpolicy\nHC-000\tdecided\tsomething\nHC-900\tproposal\tnot yet\n"


def fact(identifier: str, value_type: str, value, provenance=None) -> str:
    document = {
        "schema": checker.FACT_SCHEMA,
        "schemaVersion": 1,
        "id": identifier,
        "title": "Title",
        "statement": "Statement.",
        "valueType": value_type,
        "value": value,
    }
    if provenance is not None:
        document["provenance"] = provenance
    return "---\n" + json.dumps(document, ensure_ascii=False, indent=2) + "\n---\n\n# Title\n"


class FactProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.write("Source/constants.c", CONSTANT_SOURCE)
        self.write(checker.DECISIONS, DECISIONS)
        self.blueprint({})

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def blueprint(self, values: dict) -> None:
        self.write(checker.BLUEPRINT, json.dumps({"analysisFactValues": values}) + "\n")

    def declare(self, name: str, identifier: str, value_type: str, value, provenance=None) -> None:
        self.write(f"{checker.FACTS_ROOT}/{name}.md", fact(identifier, value_type, value, provenance))
        self.blueprint({identifier: value})

    def seconds_provenance(self, transform: str = "integer") -> dict:
        return {
            "kind": "product-constant",
            "path": "Source/constants.c",
            "pattern": r"SOME_TARGET_SECONDS\s*=\s*([0-9.]+)\s*;",
            "transform": transform,
        }

    def test_a_value_matching_its_constant_passes(self) -> None:
        self.declare("seconds", "fact:seconds", "integer", 1, self.seconds_provenance())

        self.assertEqual(checker.failures(), [])

    def test_a_value_that_contradicts_its_constant_fails(self) -> None:
        self.declare("seconds", "fact:seconds", "integer", 6, self.seconds_provenance())

        self.assertIn("declares 6 but", " ".join(checker.failures()))

    def test_a_constant_that_drifts_under_a_pinned_value_fails(self) -> None:
        self.declare("seconds", "fact:seconds", "integer", 1, self.seconds_provenance())
        self.write("Source/constants.c", CONSTANT_SOURCE.replace("= 1.0;", "= 6.0;"))

        self.assertIn("says 6", " ".join(checker.failures()))

    def test_a_multiplied_constant_is_evaluated(self) -> None:
        self.declare(
            "threshold",
            "fact:threshold",
            "integer",
            900,
            {
                "kind": "product-constant",
                "path": "Source/constants.c",
                "pattern": r"someThreshold:\s*Double\s*=\s*(.+)$",
                "transform": "integer",
            },
        )

        self.assertEqual(checker.failures(), [])

    def test_a_number_list_constant_is_read_as_canonical_json_text(self) -> None:
        self.declare(
            "backoff",
            "fact:backoff",
            "string",
            '["250","500","1000"]',
            {
                "kind": "product-constant",
                "path": "Source/constants.c",
                "pattern": r"SOME_BACKOFF\[\]\s*=\s*\{([^}]*)\}",
                "transform": "number-list",
            },
        )

        self.assertEqual(checker.failures(), [])

    def test_a_negated_boolean_authority_is_read_with_its_polarity_flipped(self) -> None:
        self.write("Source/authority.json", '{"runtimeHumanActorAllowed": false}\n')
        self.declare(
            "no-human",
            "fact:no-human",
            "boolean",
            True,
            {
                "kind": "product-constant",
                "path": "Source/authority.json",
                "pattern": r'"runtimeHumanActorAllowed":\s*(true|false)',
                "transform": "boolean-negated",
            },
        )

        self.assertEqual(checker.failures(), [])

    def test_a_fact_with_no_provenance_fails(self) -> None:
        self.declare("orphan", "fact:orphan", "boolean", True)

        self.assertIn("needs a provenance", " ".join(checker.failures()))

    def test_a_decision_that_is_decided_passes(self) -> None:
        self.declare(
            "decided", "fact:decided", "boolean", True,
            {"kind": "decision", "decision": "HC-000"},
        )

        self.assertEqual(checker.failures(), [])

    def test_a_decision_that_is_only_proposed_fails(self) -> None:
        self.declare(
            "proposed", "fact:proposed", "boolean", True,
            {"kind": "decision", "decision": "HC-900"},
        )

        self.assertIn("not a decided entry", " ".join(checker.failures()))

    def test_an_unknown_decision_fails(self) -> None:
        self.declare(
            "unknown", "fact:unknown", "boolean", True,
            {"kind": "decision", "decision": "HC-777"},
        )

        self.assertIn("not a decided entry", " ".join(checker.failures()))

    def test_a_missing_source_file_fails(self) -> None:
        provenance = self.seconds_provenance()
        provenance["path"] = "Source/absent.c"
        self.declare("seconds", "fact:seconds", "integer", 1, provenance)

        self.assertIn("does not exist", " ".join(checker.failures()))

    def test_a_pattern_that_matches_nothing_fails(self) -> None:
        provenance = self.seconds_provenance()
        provenance["pattern"] = r"NOT_PRESENT\s*=\s*([0-9]+)"
        self.declare("seconds", "fact:seconds", "integer", 1, provenance)

        self.assertIn("pattern found nothing", " ".join(checker.failures()))

    def test_an_unknown_transform_fails(self) -> None:
        self.declare(
            "seconds", "fact:seconds", "integer", 1, self.seconds_provenance("guesswork")
        )

        self.assertIn("transform must be one of", " ".join(checker.failures()))

    def test_a_blueprint_that_disagrees_with_the_declaration_fails(self) -> None:
        self.declare("seconds", "fact:seconds", "integer", 1, self.seconds_provenance())
        self.blueprint({"fact:seconds": 6})

        self.assertIn("in its declaration", " ".join(checker.failures()))

    def test_a_blueprint_that_omits_a_declared_fact_fails(self) -> None:
        self.declare("seconds", "fact:seconds", "integer", 1, self.seconds_provenance())
        self.blueprint({})

        self.assertIn("does not carry declared Fact", " ".join(checker.failures()))

    def test_a_blueprint_that_invents_a_fact_fails(self) -> None:
        self.declare("seconds", "fact:seconds", "integer", 1, self.seconds_provenance())
        self.blueprint({"fact:seconds": 1, "fact:invented": True})

        self.assertIn("names unknown Fact", " ".join(checker.failures()))

    def test_an_expression_with_a_function_call_is_refused(self) -> None:
        self.write("Source/constants.c", "static const double SOME_TARGET_SECONDS = pow(2,3);\n")
        provenance = self.seconds_provenance()
        provenance["pattern"] = r"SOME_TARGET_SECONDS\s*=\s*(.+);"
        self.declare("seconds", "fact:seconds", "integer", 8, provenance)

        self.assertIn("cannot read", " ".join(checker.failures()))


class RepositoryTests(unittest.TestCase):
    def test_the_prefetch_fact_no_longer_claims_six_seconds(self) -> None:
        path = (
            checker.REPOSITORY_ROOT
            / checker.FACTS_ROOT
            / "network-prefetch-target-seconds.md"
        )
        document = checker.frontmatter(path)

        self.assertNotEqual(document["value"], 6)
        self.assertEqual(document["provenance"]["kind"], "product-constant")


if __name__ == "__main__":
    unittest.main()
