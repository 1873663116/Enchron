#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.ids import ScenarioID
from regression.core.runview import Attribution, NodeStatus
from regression.tools import known_defects
from regression.tools.known_defects import (
    DEFECTS_PATH,
    DEFECTS_SCHEMA,
    KnownDefectError,
    classify,
    load,
)
from regression.tools.signatures import ALL_BLACK, CAPTURE_FAILED
from regression.tools.verdict import Verdict

SCENARIO = ScenarioID("scenario:playback:seek")
OTHER = ScenarioID("scenario:menu:open")


def document(*defects) -> dict:
    return {"schema": DEFECTS_SCHEMA, "schemaVersion": 1, "defects": list(defects)}


def record(**changes) -> dict:
    base = {
        "scenario": str(SCENARIO),
        "description": "the seek indicator lags one frame behind the scrubber",
        "match": {"signature": str(ALL_BLACK)},
        "recorded": "2026-09-01",
        "expiresWhen": "the renderer stops presenting the pre-seek frame",
    }
    base.update(changes)
    return base


def verdict(signature=ALL_BLACK) -> Verdict:
    return Verdict(
        "node:playback:seek", None, "the frame carried no content", Attribution.PRODUCT, signature
    )


class LoadTests(unittest.TestCase):
    """A record with no condition for revisiting it never gets revisited, so the
    ledger refuses to hold one."""

    def written(self, payload) -> Path:
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "known_defects.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_the_repository_ledger_parses(self) -> None:
        self.assertIsInstance(load(DEFECTS_PATH), tuple)

    def test_a_record_without_an_expiry_condition_is_refused(self) -> None:
        path = self.written(document(record(expiresWhen="   ")))

        with self.assertRaisesRegex(KnownDefectError, "expiresWhen"):
            load(path)

    def test_a_record_missing_a_field_is_refused_by_name(self) -> None:
        incomplete = record()
        del incomplete["recorded"]
        path = self.written(document(incomplete))

        with self.assertRaisesRegex(KnownDefectError, "omits recorded"):
            load(path)

    def test_an_unrecognised_field_is_refused(self) -> None:
        path = self.written(document(record(owner="someone")))

        with self.assertRaisesRegex(KnownDefectError, "owner"):
            load(path)

    def test_a_date_that_is_not_iso_is_refused(self) -> None:
        path = self.written(document(record(recorded="1 September 2026")))

        with self.assertRaisesRegex(KnownDefectError, "ISO 8601"):
            load(path)

    def test_an_unregistered_signature_is_refused(self) -> None:
        path = self.written(document(record(match={"signature": "signature:invented"})))

        with self.assertRaises(KnownDefectError) as raised:
            load(path)

        self.assertIn("signature:invented", str(raised.exception))

    def test_a_record_naming_both_match_forms_is_refused(self) -> None:
        path = self.written(
            document(
                record(
                    match={
                        "signature": str(ALL_BLACK),
                        "field": "lifecycle",
                        "operator": "==",
                        "value": "Paused",
                    }
                )
            )
        )

        with self.assertRaisesRegex(KnownDefectError, "matches on one of them"):
            load(path)

    def test_a_field_match_compares_only_with_equality(self) -> None:
        path = self.written(
            document(
                record(
                    match={"field": "lifecycle", "operator": "!=", "value": "Paused"}
                )
            )
        )

        with self.assertRaisesRegex(KnownDefectError, "matches on"):
            load(path)

    def test_a_document_of_another_schema_is_refused(self) -> None:
        path = self.written({"schema": "something.else", "defects": []})

        with self.assertRaisesRegex(KnownDefectError, "known-defects"):
            load(path)

    def test_a_missing_ledger_is_refused(self) -> None:
        with self.assertRaisesRegex(KnownDefectError, "no known defect ledger"):
            load(Path("/nonexistent/known_defects.json"))


class ClassifyTests(unittest.TestCase):
    """A known defect and an ordinary failure are two terminal states, not one
    state with an exemption note. Matching is by registered signature or by a
    field predicate, never by free text."""

    def defects(self, *records):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "known_defects.json"
        path.write_text(json.dumps(document(*records)), encoding="utf-8")
        return load(path)

    def test_a_matching_signature_records_a_known_failure(self) -> None:
        self.assertIs(
            NodeStatus.FAILED_KNOWN,
            classify(SCENARIO, verdict(), {}, self.defects(record())),
        )

    def test_a_different_signature_records_an_ordinary_failure(self) -> None:
        self.assertIs(
            NodeStatus.FAILED,
            classify(SCENARIO, verdict(CAPTURE_FAILED), {}, self.defects(record())),
        )

    def test_a_record_for_another_scenario_does_not_excuse_this_one(self) -> None:
        self.assertIs(
            NodeStatus.FAILED,
            classify(OTHER, verdict(), {}, self.defects(record())),
        )

    def test_a_field_predicate_match_records_a_known_failure(self) -> None:
        defects = self.defects(
            record(
                match={"field": "lifecycle", "operator": "==", "value": "Paused"}
            )
        )

        self.assertIs(
            NodeStatus.FAILED_KNOWN,
            classify(SCENARIO, verdict(None), {"lifecycle": "Paused"}, defects),
        )

    def test_a_field_predicate_that_reads_differently_does_not_match(self) -> None:
        defects = self.defects(
            record(
                match={"field": "lifecycle", "operator": "==", "value": "Paused"}
            )
        )

        self.assertIs(
            NodeStatus.FAILED,
            classify(SCENARIO, verdict(None), {"lifecycle": "Playing"}, defects),
        )

    def test_a_field_the_call_never_reported_does_not_match(self) -> None:
        defects = self.defects(
            record(
                match={"field": "lifecycle", "operator": "==", "value": "Paused"}
            )
        )

        self.assertIs(
            NodeStatus.FAILED, classify(SCENARIO, verdict(None), {}, defects)
        )

    def test_a_verdict_with_no_scenario_fails_closed_without_reading_the_ledger(
        self,
    ) -> None:
        def refuse(path=None):
            raise AssertionError("the ledger was read for a verdict with no Scenario")

        original = known_defects.load
        known_defects.load = refuse
        try:
            self.assertIs(NodeStatus.FAILED, classify(None, verdict(), {}))
        finally:
            known_defects.load = original

    def test_anything_but_a_verdict_is_refused(self) -> None:
        with self.assertRaisesRegex(KnownDefectError, "from a Verdict"):
            classify(SCENARIO, {"signature": str(ALL_BLACK)}, {}, self.defects())


if __name__ == "__main__":
    unittest.main()
