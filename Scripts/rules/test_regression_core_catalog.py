from __future__ import annotations

from copy import deepcopy
from dataclasses import FrozenInstanceError
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from regression.core.catalog import load_catalog
from regression.core.contracts import (
    ArtifactClass,
    AutomationScope,
    BoundLane,
    ContractReadiness,
    EvidenceSchemaPair,
    HumanCoverageBlocker,
    LaneRequirement,
    OracleKind,
    StateDeclaration,
    StateRequirement,
)
from regression.core.errors import RegressionError
from regression.core.ids import CallID, CaseKey, EvidenceSchema, EvidenceType


PROMISE_FEATURES = (
    "accessibility",
    "audio",
    "browsing",
    "history",
    "immersive-video",
    "playback",
    "reliability",
    "search",
    "settings",
    "sources",
    "subtitles",
    "windows",
)


class CatalogFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.documents = {}
        for feature in PROMISE_FEATURES:
            automation = {"scope": "included"}
            if feature != "playback":
                automation = {
                    "scope": "excluded",
                    "reason": "This fixture exercises only playback.",
                }
            self.documents[f"promises/{feature}.md"] = {
                "schema": "enchron.regression.promises",
                "schemaVersion": 1,
                "feature": feature,
                "title": feature.replace("-", " ").title(),
                "promises": [
                    {
                        "id": f"promise:{feature}:c01",
                        "title": f"{feature.replace('-', ' ').title()} commitment",
                        "statement": f"The {feature} commitment is upheld.",
                        "automation": automation,
                    }
                ],
            }

        self.documents.update(
            {
                "facts/library.md": {
                    "schema": "enchron.regression.fact",
                    "schemaVersion": 1,
                    "id": "fact:library.available",
                    "title": "Fixture library availability",
                    "statement": "The fixture library is reachable.",
                    "valueType": "boolean",
                    "value": True,
                    "provenance": {"kind": "decision", "decision": "HC-000"},
                },
                "operations/prepare.md": {
                    "schema": "enchron.regression.operation",
                    "schemaVersion": 1,
                    "id": "operation:playback.prepare-library@1",
                    "title": "Prepare the fixture library",
                    "role": "setup",
                    "lanes": ["simulator", "device"],
                    "argumentSchema": {
                        "fields": [],
                        "additionalProperties": False,
                    },
                    "invalidatesTags": ["playback.session"],
                    "evidenceSchemas": [],
                    "implementation": {
                        "locator": "Scripts/regression/operations/playback/prepare.py",
                        "digest": "sha256:" + "0" * 64,
                    },
                },
                "operations/observe.md": {
                    "schema": "enchron.regression.operation",
                    "schemaVersion": 1,
                    "id": "operation:playback.observe@1",
                    "title": "Observe the selected title",
                    "role": "evidence",
                    "lanes": ["simulator", "device"],
                    "argumentSchema": {
                        "fields": [
                            {"name": "title", "type": "string", "required": True}
                        ],
                        "additionalProperties": False,
                    },
                    "invalidatesTags": ["playback.session"],
                    "evidenceSchemas": [
                        {
                            "evidenceType": "ui.screenshot",
                            "evidenceSchema": "ui.screenshot@1",
                        }
                    ],
                    "implementation": {
                        "locator": "Scripts/regression/operations/playback/observe.py",
                        "digest": "sha256:" + "1" * 64,
                    },
                },
                "oracles/visible.md": {
                    "schema": "enchron.regression.oracle",
                    "schemaVersion": 1,
                    "id": "oracle:playback.visible@1",
                    "title": "Visible playback oracle",
                    "kind": "agent",
                    "evidenceSchemas": [
                        {
                            "evidenceType": "ui.screenshot",
                            "evidenceSchema": "ui.screenshot@1",
                        }
                    ],
                    "implementation": {
                        "locator": "Scripts/regression/oracles/visible.py",
                        "digest": "sha256:" + "2" * 64,
                    },
                },
                "rubrics/visible.md": {
                    "schema": "enchron.regression.rubric",
                    "schemaVersion": 1,
                    "id": "rubric:playback.visible@1",
                    "title": "Visible playback rubric",
                    "criteria": ["The rendered frame visibly contains the title."],
                    "negativeControls": [
                        "A frame showing only loading chrome does not satisfy the rubric."
                    ],
                },
                "preparations/library-simulator.md": {
                    "schema": "enchron.regression.preparation",
                    "schemaVersion": 1,
                    "id": "preparation:library-ready:simulator",
                    "title": "Prepare the simulator library",
                    "lane": "simulator",
                    "estimatedCostMillis": 500,
                    "readiness": "ready",
                    "blockers": [],
                    "prerequisites": [],
                    "operations": [
                        {
                            "callId": "call:preparation:library-ready:simulator",
                            "operation": "operation:playback.prepare-library@1",
                            "arguments": {},
                            "maxInvocations": 2,
                        }
                    ],
                    "produces": [
                        {
                            "key": "library-ready",
                            "schema": "enchron.state.library-ready@1",
                            "producedByCall": "call:preparation:library-ready:simulator",
                            "dependsOnTags": ["playback.session"],
                        }
                    ],
                },
                "preparations/library-device.md": {
                    "schema": "enchron.regression.preparation",
                    "schemaVersion": 1,
                    "id": "preparation:library-ready:device",
                    "title": "Prepare the device library",
                    "lane": "device",
                    "estimatedCostMillis": 700,
                    "readiness": "ready",
                    "blockers": [],
                    "prerequisites": [],
                    "operations": [
                        {
                            "callId": "call:preparation:library-ready:device",
                            "operation": "operation:playback.prepare-library@1",
                            "arguments": {},
                            "maxInvocations": 2,
                        }
                    ],
                    "produces": [
                        {
                            "key": "library-ready",
                            "schema": "enchron.state.library-ready@1",
                            "producedByCall": "call:preparation:library-ready:device",
                            "dependsOnTags": ["playback.session"],
                        }
                    ],
                },
                "journeys/playback/journey.md": {
                    "schema": "enchron.regression.journey",
                    "schemaVersion": 1,
                    "id": "journey:playback",
                    "title": "Playback journey",
                    "scenarioRefs": ["scenario:playback:start"],
                    "ordering": [],
                    "sharedState": [
                        {
                            "key": "library-ready",
                            "schema": "enchron.state.library-ready@1",
                        }
                    ],
                },
                "journeys/playback/scenarios/start.md": {
                    "schema": "enchron.regression.scenario",
                    "schemaVersion": 1,
                    "id": "scenario:playback:start",
                    "title": "Start playback",
                    "journey": "journey:playback",
                    "promiseRefs": ["promise:playback:c01"],
                    "applicability": {
                        "factEquals": {
                            "fact": "fact:library.available",
                            "value": True,
                        }
                    },
                    "lane": "either",
                    "estimatedCostMillis": 1200,
                    "staticCases": ["default"],
                    "readiness": "ready",
                    "blockers": [],
                    "prerequisites": [
                        {
                            "key": "library-ready",
                            "schema": "enchron.state.library-ready@1",
                        }
                    ],
                    "operations": [
                        {
                            "callId": "call:playback:start:observe",
                            "operation": "operation:playback.observe@1",
                            "arguments": {"title": "Fixture Movie"},
                            "maxInvocations": 1,
                        }
                    ],
                    "obligations": [
                        {
                            "id": "obligation:playback:visible",
                            "artifactClass": "coverage",
                            "evidenceType": "ui.screenshot",
                            "evidenceSchema": "ui.screenshot@1",
                            "caseKey": "default",
                            "producedByCall": "call:playback:start:observe",
                            "oracle": "oracle:playback.visible@1",
                            "rubric": "rubric:playback.visible@1",
                        }
                    ],
                    "success": {"observation": "obligation:playback:visible"},
                    "mainGateFor": ["simulator"],
                },
            }
        )

    @property
    def playback_promises(self):
        return self.documents["promises/playback.md"]["promises"]

    @property
    def scenario(self):
        return self.documents["journeys/playback/scenarios/start.md"]

    def add_second_scenario(self) -> None:
        scenario = deepcopy(self.scenario)
        scenario["id"] = "scenario:playback:finish"
        scenario["title"] = "Finish playback"
        scenario["operations"][0]["callId"] = "call:playback:finish:observe"
        scenario["obligations"][0]["id"] = "obligation:playback:finish:visible"
        scenario["obligations"][0]["producedByCall"] = (
            "call:playback:finish:observe"
        )
        scenario["success"] = {
            "observation": "obligation:playback:finish:visible"
        }
        self.documents["journeys/playback/scenarios/finish.md"] = scenario
        self.documents["journeys/playback/journey.md"]["scenarioRefs"].append(
            "scenario:playback:finish"
        )

    def write(self) -> None:
        for relative, metadata in self.documents.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            heading = metadata.get("id", metadata.get("feature", "Catalog"))
            path.write_text(
                "---\n"
                + json.dumps(metadata, sort_keys=True)
                + "\n---\n"
                + "# "
                + heading
                + "\n\nReview body.\n",
                encoding="utf-8",
            )


class CatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "Regression"
        self.fixture = CatalogFixture(self.root)

    def load(self):
        self.fixture.write()
        return load_catalog(self.root)

    def assert_catalog_error(self, code: str) -> RegressionError:
        with self.assertRaises(RegressionError) as raised:
            self.load()
        self.assertEqual(raised.exception.code, code)
        return raised.exception

    def test_loads_catalog_v2_into_fully_frozen_contracts(self) -> None:
        catalog = self.load()

        self.assertEqual(len(catalog.promises), 12)
        playback = next(
            item for item in catalog.promises if item.id == "promise:playback:c01"
        )
        self.assertEqual(playback.scope, AutomationScope.INCLUDED)
        self.assertEqual(playback.title, "Playback commitment")
        self.assertIn("Review body.", playback.body)
        self.assertEqual(len(catalog.preparations), 2)
        self.assertEqual(catalog.preparations[0].lane, BoundLane.DEVICE)
        self.assertIsInstance(catalog.preparations[0].produces[0], StateDeclaration)
        self.assertIsInstance(catalog.scenarios[0].prerequisites[0], StateRequirement)
        self.assertEqual(catalog.oracles[0].kind, OracleKind.AGENT)
        self.assertEqual(catalog.scenarios[0].lane, LaneRequirement.EITHER)
        self.assertEqual(
            catalog.scenarios[0].operations[0].arguments_bytes,
            b'{"title":"Fixture Movie"}',
        )
        self.assertEqual(
            catalog.scenarios[0].operations[0].call_id,
            CallID("call:playback:start:observe"),
        )
        self.assertEqual(
            catalog.scenarios[0].obligations[0].evidence_type,
            EvidenceType("ui.screenshot"),
        )
        self.assertEqual(
            catalog.scenarios[0].obligations[0].evidence_schema,
            EvidenceSchema("ui.screenshot@1"),
        )
        self.assertEqual(catalog.scenarios[0].static_cases, (CaseKey("default"),))
        self.assertIs(catalog.scenarios[0].readiness, ContractReadiness.READY)
        self.assertTrue(catalog.catalog_digest.startswith("sha256:"))
        with self.assertRaises(FrozenInstanceError):
            catalog.promises = ()
        with self.assertRaises(AttributeError):
            catalog.operations[0].evidence_schemas.add(
                EvidenceSchemaPair(
                    EvidenceType("ui.video"), EvidenceSchema("ui.video@1")
                )
            )

    def test_promise_documents_group_commitment_level_contracts(self) -> None:
        self.fixture.playback_promises.append(
            {
                "id": "promise:playback:c02",
                "title": "Playback continuity",
                "statement": "Playback continues after controls disappear.",
                "automation": {"scope": "included"},
            }
        )
        self.fixture.scenario["promiseRefs"].append("promise:playback:c02")

        catalog = self.load()

        playback = tuple(
            promise
            for promise in catalog.promises
            if promise.id.startswith("promise:playback:")
        )
        self.assertEqual(
            tuple(promise.id for promise in playback),
            ("promise:playback:c01", "promise:playback:c02"),
        )
        self.assertEqual(playback[0].source_digest, playback[1].source_digest)

    def test_promise_feature_document_count_can_evolve(self) -> None:
        for feature in PROMISE_FEATURES:
            if feature != "playback":
                del self.fixture.documents[f"promises/{feature}.md"]

        catalog = self.load()

        self.assertEqual(
            tuple(item.id for item in catalog.promises),
            ("promise:playback:c01",),
        )

    def test_requires_at_least_one_promise_feature_document(self) -> None:
        for feature in PROMISE_FEATURES:
            del self.fixture.documents[f"promises/{feature}.md"]
        self.assert_catalog_error("catalog.empty_promise_features")

    def test_rejects_promise_feature_mismatches(self) -> None:
        promise_document = self.fixture.documents["promises/playback.md"]
        promise_document["promises"][0]["id"] = "promise:audio:c02"
        self.assert_catalog_error("catalog.promise_feature_mismatch")

    def test_preparation_state_producer_must_exist_and_be_setup(self) -> None:
        preparation = self.fixture.documents["preparations/library-simulator.md"]
        preparation["produces"][0]["producedByCall"] = "call:missing:producer"
        self.assert_catalog_error("catalog.unknown_state_producer")

        preparation["produces"][0]["producedByCall"] = (
            "call:preparation:library-ready:simulator"
        )
        self.fixture.documents["operations/prepare.md"]["role"] = "product-behavior"
        self.assert_catalog_error("catalog.non_setup_state_producer")

    def test_state_declarations_require_invalidation_tags(self) -> None:
        preparation = self.fixture.documents["preparations/library-simulator.md"]
        preparation["produces"][0]["dependsOnTags"] = []
        self.assert_catalog_error("contract.empty_state_tags")

        preparation["produces"][0]["dependsOnTags"] = [
            "playback.session",
            "playback.session",
        ]
        self.assert_catalog_error("catalog.duplicate_state_tag")

    def test_state_requirements_are_key_and_schema_only_and_need_a_producer(self) -> None:
        self.fixture.scenario["prerequisites"][0]["producedByCall"] = (
            "call:playback:start:observe"
        )
        self.assert_catalog_error("catalog.unknown_key")

        del self.fixture.scenario["prerequisites"][0]["producedByCall"]
        self.fixture.scenario["prerequisites"][0]["schema"] = (
            "enchron.state.unknown@1"
        )
        self.assert_catalog_error("catalog.unknown_state_requirement")

    def test_evidence_pair_must_match_producer_and_oracle(self) -> None:
        self.fixture.documents["operations/observe.md"]["evidenceSchemas"] = []
        self.assert_catalog_error("catalog.unsupported_producer_evidence_schema")

        self.fixture.documents["operations/observe.md"]["evidenceSchemas"] = [
            {"evidenceType": "ui.screenshot", "evidenceSchema": "ui.screenshot@1"}
        ]
        self.fixture.documents["oracles/visible.md"]["evidenceSchemas"] = [
            {
                "evidenceType": "ui.screenshot",
                "evidenceSchema": "ui.screenshot@2",
            }
        ]
        self.assert_catalog_error("catalog.unsupported_oracle_evidence_schema")

    def test_oracles_require_at_least_one_evidence_schema_pair(self) -> None:
        self.fixture.documents["oracles/visible.md"]["evidenceSchemas"] = []
        self.assert_catalog_error("contract.empty_oracle_evidence_schemas")

    def test_parses_non_ready_contracts_with_typed_blockers(self) -> None:
        scenario = self.fixture.scenario
        scenario["readiness"] = "human-coverage-blocked"
        scenario["blockers"] = [
            {
                "kind": "human-coverage",
                "questionId": "HC-020",
                "detail": "A wearer decision is still required.",
            }
        ]
        scenario["operations"] = []
        scenario["obligations"][0]["producedByCall"] = None
        preparation = self.fixture.documents[
            "preparations/library-simulator.md"
        ]
        preparation["readiness"] = "implementation-gap"
        preparation["blockers"] = [
            {
                "kind": "implementation-gap",
                "capability": "fixture-stage",
                "detail": "The lane-local fixture stager is not implemented.",
            }
        ]
        preparation["produces"][0]["producedByCall"] = None

        catalog = self.load()

        self.assertIs(
            catalog.scenarios[0].readiness,
            ContractReadiness.HUMAN_COVERAGE_BLOCKED,
        )
        self.assertIsInstance(
            catalog.scenarios[0].blockers[0], HumanCoverageBlocker
        )
        unavailable_preparation = next(
            item
            for item in catalog.preparations
            if item.id == "preparation:library-ready:simulator"
        )
        self.assertIs(
            unavailable_preparation.readiness,
            ContractReadiness.IMPLEMENTATION_GAP,
        )
        self.assertEqual(len(unavailable_preparation.operations), 1)
        self.assertEqual(len(unavailable_preparation.produces), 1)
        self.assertIsNone(
            unavailable_preparation.produces[0].produced_by_call
        )

    def test_readiness_blockers_and_static_cases_fail_closed(self) -> None:
        self.fixture.scenario["blockers"] = [
            {
                "kind": "implementation-gap",
                "capability": "capture",
                "detail": "Unexpected blocker on ready contract.",
            }
        ]
        self.assert_catalog_error("contract.ready_with_blockers")

        self.fixture.scenario["blockers"] = []
        self.fixture.scenario["staticCases"] = ["other"]
        self.assert_catalog_error("contract.unknown_obligation_case")

        self.fixture.scenario["staticCases"] = ["default"]
        self.fixture.scenario["readiness"] = "implementation-gap"
        self.fixture.scenario["blockers"] = [
            {
                "kind": "human-coverage",
                "questionId": "HC-020",
                "detail": "Wrong typed blocker.",
            }
        ]
        self.fixture.scenario["operations"] = []
        self.fixture.scenario["obligations"][0]["producedByCall"] = None
        self.assert_catalog_error("contract.blocker_readiness_mismatch")

    def test_rubrics_require_criteria_and_negative_controls(self) -> None:
        rubric = self.fixture.documents["rubrics/visible.md"]
        rubric["negativeControls"] = []
        self.assert_catalog_error("contract.empty_negative_controls")

        rubric["negativeControls"] = ["A blank frame is insufficient."]
        rubric["criteria"] = []
        self.assert_catalog_error("contract.empty_rubric")

    def test_call_ids_are_nominal_and_unique(self) -> None:
        self.fixture.scenario["operations"][0]["callId"] = "observe-title"
        self.assert_catalog_error("identifier.invalid_format")

        self.fixture.scenario["operations"][0]["callId"] = (
            "call:playback:start:observe"
        )
        self.fixture.scenario["operations"].append(
            deepcopy(self.fixture.scenario["operations"][0])
        )
        self.assert_catalog_error("catalog.duplicate_call")

    def test_call_ids_are_unique_across_scenarios_and_preparations(self) -> None:
        self.fixture.scenario["operations"][0]["callId"] = (
            "call:preparation:library-ready:simulator"
        )
        self.assert_catalog_error("catalog.duplicate_call")

    def test_main_gate_lanes_must_be_executable_and_unique(self) -> None:
        self.fixture.scenario["lane"] = "simulator"
        self.fixture.scenario["mainGateFor"] = ["device"]
        self.assert_catalog_error("catalog.invalid_main_gate_lane")

        self.fixture.scenario["lane"] = "either"
        self.fixture.scenario["mainGateFor"] = ["simulator"]
        self.fixture.add_second_scenario()
        self.assert_catalog_error("catalog.duplicate_main_gate")

    def test_rejects_unknown_keys_and_missing_references(self) -> None:
        self.fixture.documents["operations/observe.md"]["status"] = "passed"
        self.assert_catalog_error("catalog.unknown_key")

        del self.fixture.documents["operations/observe.md"]["status"]
        self.fixture.scenario["promiseRefs"] = ["promise:playback:c99"]
        self.assert_catalog_error("catalog.unknown_promise")

    def test_rejects_unknown_operation_oracle_and_rubric_references(self) -> None:
        self.fixture.scenario["operations"][0]["operation"] = (
            "operation:missing.action@1"
        )
        self.assert_catalog_error("catalog.unknown_operation")

        self.fixture.scenario["operations"][0]["operation"] = (
            "operation:playback.observe@1"
        )
        self.fixture.scenario["obligations"][0]["oracle"] = (
            "oracle:missing.visible@1"
        )
        self.assert_catalog_error("catalog.unknown_oracle")

        self.fixture.scenario["obligations"][0]["oracle"] = (
            "oracle:playback.visible@1"
        )
        self.fixture.scenario["obligations"][0]["rubric"] = (
            "rubric:missing.visible@1"
        )
        self.assert_catalog_error("catalog.unknown_rubric")

    def test_rejects_unknown_and_unused_success_obligations(self) -> None:
        self.fixture.scenario["success"] = {"observation": "obligation:missing:item"}
        self.assert_catalog_error("expression.unknown_obligation")

        self.fixture.scenario["success"] = {
            "observation": "obligation:playback:visible"
        }
        extra = deepcopy(self.fixture.scenario["obligations"][0])
        extra["id"] = "obligation:playback:unused"
        self.fixture.scenario["obligations"].append(extra)
        self.assert_catalog_error("expression.unused_obligation")

    def test_rejects_uncovered_included_and_referenced_excluded_promises(self) -> None:
        self.fixture.scenario["promiseRefs"] = []
        self.assert_catalog_error("catalog.empty_promises")

        self.fixture.scenario["promiseRefs"] = ["promise:playback:c01"]
        automation = self.fixture.playback_promises[0]["automation"]
        automation["scope"] = "excluded"
        automation["reason"] = "A supported automated path is unavailable."
        self.assert_catalog_error("catalog.excluded_promise_referenced")

    def test_excluded_promises_require_a_reason(self) -> None:
        promise = self.fixture.playback_promises[0]
        promise["automation"] = {"scope": "excluded"}
        self.assert_catalog_error("contract.excluded_promise_without_reason")

    def test_rejects_external_and_cyclic_journey_ordering(self) -> None:
        journey = self.fixture.documents["journeys/playback/journey.md"]
        journey["ordering"] = [
            {
                "before": "scenario:playback:start",
                "after": "scenario:other:end",
            }
        ]
        self.assert_catalog_error("catalog.external_ordering_reference")

        journey["ordering"] = [
            {
                "before": "scenario:playback:start",
                "after": "scenario:playback:start",
            }
        ]
        self.assert_catalog_error("catalog.journey_cycle")

    def test_rejects_preparation_cycles(self) -> None:
        preparation = self.fixture.documents["preparations/library-simulator.md"]
        preparation["prerequisites"] = [
            {
                "key": "library-ready",
                "schema": "enchron.state.library-ready@1",
            }
        ]
        self.assert_catalog_error("catalog.preparation_cycle")

    def test_rejects_duplicate_items_and_unknown_arguments(self) -> None:
        operation = self.fixture.documents["operations/observe.md"]
        pair = {"evidenceType": "ui.screenshot", "evidenceSchema": "ui.screenshot@1"}
        operation["evidenceSchemas"] = [pair, deepcopy(pair)]
        self.assert_catalog_error("catalog.duplicate_evidence_schema_pair")

        operation["evidenceSchemas"] = [pair]
        self.fixture.scenario["operations"][0]["arguments"]["unexpected"] = True
        self.assert_catalog_error("contract.unknown_argument")

    def test_operation_arguments_support_lower_camel_case_string_lists(self) -> None:
        operation = self.fixture.documents["operations/observe.md"]
        operation["argumentSchema"]["fields"] = [
            {"name": "sourceKind", "type": "string", "required": True},
            {"name": "subtitleTracks", "type": "string-list", "required": True},
        ]
        arguments = {
            "sourceKind": "local",
            "subtitleTracks": ["English", "Japanese"],
        }
        self.fixture.scenario["operations"][0]["arguments"] = arguments

        catalog = self.load()
        arguments["subtitleTracks"].append("French")

        self.assertEqual(
            catalog.scenarios[0].operations[0].arguments_bytes,
            b'{"sourceKind":"local","subtitleTracks":["English","Japanese"]}',
        )

    def test_rejects_invalid_argument_names_and_string_list_values(self) -> None:
        operation = self.fixture.documents["operations/observe.md"]
        operation["argumentSchema"]["fields"] = [
            {"name": "SourceKind", "type": "string", "required": True}
        ]
        self.fixture.scenario["operations"][0]["arguments"] = {
            "SourceKind": "local"
        }
        self.assert_catalog_error("contract.invalid_argument_name")

        operation["argumentSchema"]["fields"] = [
            {"name": "sourceKinds", "type": "string-list", "required": True}
        ]
        self.fixture.scenario["operations"][0]["arguments"] = {
            "sourceKinds": ["local", 1]
        }
        self.assert_catalog_error("contract.invalid_argument_type")

    def test_argument_schema_requires_additional_properties_false(self) -> None:
        operation = self.fixture.documents["operations/observe.md"]
        operation["argumentSchema"]["additionalProperties"] = True
        self.assert_catalog_error("catalog.argument_additional_properties")

    def test_facts_do_not_accept_operation_only_string_lists(self) -> None:
        self.fixture.documents["facts/library.md"]["valueType"] = "string-list"
        self.assert_catalog_error("contract.invalid_fact_value_type")

    def test_rejects_unsupported_lanes_and_non_coverage_producers(self) -> None:
        operation = self.fixture.documents["operations/observe.md"]
        operation["lanes"] = ["simulator"]
        self.assert_catalog_error("catalog.operation_lane_mismatch")

        operation["lanes"] = ["simulator", "device"]
        operation["role"] = "diagnostic-bypass"
        self.assert_catalog_error("catalog.non_evidence_coverage_producer")

    def test_rejects_non_integer_costs_and_non_coverage_obligations(self) -> None:
        self.fixture.scenario["estimatedCostMillis"] = 1.5
        self.assert_catalog_error("contract.invalid_estimated_cost")

        self.fixture.scenario["estimatedCostMillis"] = 1200
        self.fixture.scenario["obligations"][0]["artifactClass"] = "preparation"
        self.assert_catalog_error("catalog.invalid_artifact_class")

    def test_scenario_and_preparation_costs_must_be_positive(self) -> None:
        self.fixture.scenario["estimatedCostMillis"] = 0
        self.assert_catalog_error("contract.invalid_estimated_cost")

        self.fixture.scenario["estimatedCostMillis"] = 1200
        self.fixture.documents["preparations/library-device.md"][
            "estimatedCostMillis"
        ] = 0
        self.assert_catalog_error("contract.invalid_estimated_cost")

    def test_artifact_class_keeps_non_coverage_runtime_types(self) -> None:
        self.assertEqual(
            {item.value for item in ArtifactClass},
            {"coverage", "preparation", "diagnostic"},
        )

    def test_rejects_contracts_at_wrong_paths(self) -> None:
        document = self.fixture.documents.pop("preparations/library-device.md")
        self.fixture.documents["preparations/nested/library-device.md"] = document
        self.assert_catalog_error("catalog.invalid_path")

    def test_rejects_regression_schema_below_an_unknown_directory(self) -> None:
        self.fixture.documents["misc/observe.md"] = deepcopy(
            self.fixture.documents["operations/observe.md"]
        )
        self.assert_catalog_error("catalog.invalid_path")

    def test_catalog_digest_changes_with_source_and_is_path_independent(self) -> None:
        first = self.load().catalog_digest
        scenario = self.root / "journeys/playback/scenarios/start.md"
        scenario.write_text(
            scenario.read_text(encoding="utf-8").replace(
                "Review body.", "Changed review body."
            ),
            encoding="utf-8",
        )
        second = load_catalog(self.root).catalog_digest
        self.assertNotEqual(first, second)

        with TemporaryDirectory() as other_directory:
            other = CatalogFixture(Path(other_directory) / "Regression")
            other.write()
            self.assertEqual(first, load_catalog(other.root).catalog_digest)


if __name__ == "__main__":
    unittest.main()
