#!/usr/bin/env python3

from __future__ import annotations

import csv
import hashlib
import io
import json
from pathlib import Path
import sys
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SCRIPTS_ROOT = REPOSITORY_ROOT / "Scripts"
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

import regression.review_stage as review_stage


AUTHORITY_PATH = (
    REPOSITORY_ROOT / "Config/regression/catalog-root/semantic-authority.json"
)
DECISIONS_PATH = REPOSITORY_ROOT / "Config/regression/semantic-authority-decisions.tsv"


class SemanticAuthorityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.encoded = AUTHORITY_PATH.read_bytes()
        cls.payload = json.loads(cls.encoded)

    def test_all_questions_have_one_closed_decision(self) -> None:
        self.assertEqual(self.payload["version"], 1)
        decisions = self.payload["decisions"]
        self.assertEqual(
            [entry["id"] for entry in decisions],
            [f"HC-{index:03d}" for index in range(24)],
        )
        self.assertTrue(all(entry["status"] == "decided" for entry in decisions))

    def test_runtime_human_actor_is_structurally_forbidden(self) -> None:
        self.assertIs(self.payload["authority"]["runtimeHumanActorAllowed"], False)
        self.assertIs(
            self.payload["authority"][
                "equivalentDerivedHumanCoverageAuthorized"
            ],
            True,
        )
        encoded = self.encoded.decode("utf-8")
        for forbidden in ('"status": "pending"', '"status": "skipped"', '"status": "notApplicable"', '"status": "voided"'):
            self.assertNotIn(forbidden, encoded)

    def test_every_decision_has_policy_boundary_evidence_and_work_list(self) -> None:
        for entry in self.payload["decisions"]:
            with self.subTest(decision=entry["id"]):
                self.assertIsInstance(entry["policy"], str)
                self.assertTrue(entry["policy"].strip())
                self.assertIsInstance(entry["applicability"], str)
                self.assertTrue(entry["applicability"].strip())
                self.assertIsInstance(entry["evidence"], list)
                self.assertTrue(entry["evidence"])
                self.assertTrue(all(isinstance(item, str) and item for item in entry["evidence"]))
                self.assertIsInstance(entry["requiredWork"], list)

    def test_every_evidence_locator_resolves_to_current_repository_content(self) -> None:
        for entry in self.payload["decisions"]:
            for index, locator in enumerate(entry["evidence"]):
                with self.subTest(decision=entry["id"], locator=locator):
                    review_stage._semantic_authority_evidence_locator(
                        REPOSITORY_ROOT,
                        locator,
                        f"{AUTHORITY_PATH}.decisions[{entry['id']}].evidence[{index}]",
                    )

    def test_persistent_decision_source_is_exactly_the_24_approved_rows(self) -> None:
        source = self.payload["authority"]["source"]
        self.assertEqual(source, "Config/regression/semantic-authority-decisions.tsv")
        self.assertNotIn(".scratch", source)
        self.assertEqual(REPOSITORY_ROOT / source, DECISIONS_PATH)
        encoded = DECISIONS_PATH.read_bytes()
        self.assertEqual(
            self.payload["authority"]["sourceDigest"],
            "sha256:" + hashlib.sha256(encoded).hexdigest(),
        )

        reader = csv.DictReader(
            io.StringIO(encoded.decode("utf-8")), delimiter="\t"
        )
        self.assertEqual(
            reader.fieldnames,
            [
                "id",
                "status",
                "policy",
                "applicability",
                "evidence",
                "requiredWork",
            ],
        )
        rows = list(reader)
        expected_ids = [f"HC-{index:03d}" for index in range(24)]
        self.assertEqual([row["id"] for row in rows], expected_ids)
        self.assertEqual(len({row["id"] for row in rows}), 24)
        for row, decision in zip(rows, self.payload["decisions"]):
            with self.subTest(decision=decision["id"]):
                self.assertEqual(row["id"], decision["id"])
                self.assertEqual(row["status"], decision["status"])
                self.assertEqual(row["policy"], decision["policy"])
                self.assertEqual(row["applicability"], decision["applicability"])
                self.assertEqual(json.loads(row["evidence"]), decision["evidence"])
                self.assertEqual(
                    json.loads(row["requiredWork"]), decision["requiredWork"]
                )

    def test_bundle_records_the_digest_of_the_decisions_it_was_built_from(self) -> None:
        self.assertEqual(
            self.payload["authority"]["sourceDigest"],
            "sha256:" + hashlib.sha256(DECISIONS_PATH.read_bytes()).hexdigest(),
            "semantic-authority.json names a sourceDigest that no longer matches "
            + DECISIONS_PATH.relative_to(REPOSITORY_ROOT).as_posix()
            + "; update the recorded digest with the decisions it was built from.",
        )


if __name__ == "__main__":
    unittest.main()
