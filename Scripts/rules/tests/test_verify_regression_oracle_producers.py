#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RULES = Path(__file__).resolve().parents[1]
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_regression_oracle_producers as checker


TREE = ("accessibility.tree", "accessibility-tree@1")
PROBE = ("playback.probe", "playback-probe@1")


class Spec:
    def __init__(self, identifier: str, outputs: tuple) -> None:
        self.identifier = identifier
        self.outputs = outputs


PRODUCERS = {
    "operation:accessibility.inspect@2": Spec("operation:accessibility.inspect@2", (TREE,)),
    "operation:diagnostics.playback-state@1": Spec("operation:diagnostics.playback-state@1", (PROBE,)),
    "operation:app.relaunch@1": Spec("operation:app.relaunch@1", ()),
}


def oracle(identifier: str, pairs: tuple) -> str:
    document = {
        "schema": "enchron.regression.oracle",
        "schemaVersion": 1,
        "id": identifier,
        "title": "Title",
        "kind": "agent",
        "evidenceSchemas": [
            {"evidenceType": pair[0], "evidenceSchema": pair[1]} for pair in pairs
        ],
    }
    return "---\n" + json.dumps(document, indent=2) + "\n---\n\n# Title\n"


def scenario(producer: str, pair: tuple, oracle_id: str, produced_by: str = "call:s:01") -> str:
    document = {
        "schema": "enchron.regression.scenario",
        "schemaVersion": 1,
        "id": "scenario:sample:one",
        "operations": [
            {"callId": "call:s:01", "operation": producer, "arguments": {}, "maxInvocations": 1}
        ],
        "obligations": [
            {
                "id": "obligation:sample:one:o01:default",
                "caseKey": "default",
                "artifactClass": "coverage",
                "evidenceType": pair[0],
                "evidenceSchema": pair[1],
                "oracle": oracle_id,
                "producedByCall": produced_by,
                "rubric": "rubric:sample.one.o01@1",
            }
        ],
    }
    return "---\n" + json.dumps(document, indent=2) + "\n---\n\n# Sample\n"


class OracleProducerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        for target, value in (("REPOSITORY_ROOT", self.repository),):
            patcher = patch.object(checker, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        producers = patch.object(
            checker,
            "produced_pairs",
            lambda: {
                pair: [spec.identifier for spec in PRODUCERS.values() if pair in spec.outputs]
                for spec in PRODUCERS.values()
                for pair in spec.outputs
            },
        )
        producers.start()
        self.addCleanup(producers.stop)
        self.write(f"{checker.ORACLES_ROOT}/tree.md", oracle("oracle:tree@1", (TREE,)))
        self.write(f"{checker.ORACLES_ROOT}/probe.md", oracle("oracle:probe@1", (PROBE,)))
        self.scenario(scenario("operation:accessibility.inspect@2", TREE, "oracle:tree@1"))

    def write(self, relative: str, contents: str) -> None:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def scenario(self, contents: str) -> None:
        self.write(f"{checker.JOURNEYS_ROOT}/sample/scenarios/one.md", contents)

    def test_an_oracle_whose_pair_has_a_producer_passes(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_an_oracle_whose_pair_nothing_emits_fails(self) -> None:
        self.write(
            f"{checker.ORACLES_ROOT}/orphan.md",
            oracle("oracle:orphan@1", (("emby.range-log", "emby-range-log@1"),)),
        )

        self.assertIn("which no Operation emits", " ".join(checker.failures()))

    def test_an_obligation_whose_oracle_refuses_its_pair_fails(self) -> None:
        self.scenario(scenario("operation:accessibility.inspect@2", TREE, "oracle:probe@1"))

        self.assertIn("but oracle:probe@1 accepts", " ".join(checker.failures()))

    def test_an_obligation_produced_by_a_call_that_emits_nothing_fails(self) -> None:
        self.scenario(scenario("operation:app.relaunch@1", TREE, "oracle:tree@1"))

        self.assertIn("which does not emit it", " ".join(checker.failures()))

    def test_an_obligation_produced_by_an_uncalled_call_fails(self) -> None:
        self.scenario(
            scenario("operation:accessibility.inspect@2", TREE, "oracle:tree@1", "call:s:99")
        )

        self.assertIn("which the Scenario does not call", " ".join(checker.failures()))

    def test_an_obligation_naming_an_unknown_oracle_fails(self) -> None:
        self.scenario(scenario("operation:accessibility.inspect@2", TREE, "oracle:absent@1"))

        self.assertIn("names unknown Oracle", " ".join(checker.failures()))


class RepositoryTests(unittest.TestCase):
    def test_every_obligation_binds_a_producer_that_emits_its_pair(self) -> None:
        obligations = [
            failure for failure in checker.failures() if failure.startswith(checker.JOURNEYS_ROOT)
        ]

        self.assertEqual(obligations, [])

    def test_every_catalog_oracle_has_a_producer(self) -> None:
        self.assertEqual(checker.failures(), [])


if __name__ == "__main__":
    unittest.main()
