from __future__ import annotations

import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
from typing import Iterable


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CATALOG_ROOT = REPOSITORY_ROOT / "Regression"
BLUEPRINT_PATH = REPOSITORY_ROOT / "Config/regression/catalog-v2.json"
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from regression.core.applicability import ReviewedFact
from regression.core.catalog import load_catalog
from regression.core.compiler import analyze_catalog
from regression.core.contracts import (
    AutomationScope,
    BoundLane,
    ContractReadiness,
    EvidenceSchemaPair,
    OperationRole,
)
from regression.core.digest import digest_text_file
from regression.core.expression import (
    AllOf,
    AnyOf,
    AtLeast,
    Not,
    ObservationRef,
    SuccessExpression,
)
from regression.core.plan import (
    AgentEnvironment,
    BuildIdentity,
    CompileRequest,
    EvidenceEnvironmentIdentity,
    FullSelector,
    LaneBuildArtifact,
    ToolchainIdentity,
)
from regression.materialize_catalog_v2 import materialize


EXPECTED_COUNTS = {
    "promises": 65,
    "facts": 10,
    "operations": 35,
    "oracles": 11,
    "rubrics": 107,
    "preparations": 18,
    "journeys": 14,
    "scenarios": 70,
}
EXPECTED_OPERATION_IDS = frozenset(
    {
        "operation:accessibility.activate@2",
        "operation:accessibility.inspect@2",
        "operation:accessibility.type@2",
        "operation:app.relaunch@1",
        "operation:diagnostics.browse-hierarchy@1",
        "operation:diagnostics.playback-state@1",
        "operation:diagnostics.surface-probe@1",
        "operation:evidence.capture-audio@2",
        "operation:evidence.capture-frames@1",
        "operation:evidence.structural-test@1",
        "operation:format.apply@2",
        "operation:harness.assert-channels@2",
        "operation:harness.ensure-session@1",
        "operation:harness.reset-product-state@2",
        "operation:host.preflight@1",
        "operation:input.device-hub-prepare@1",
        "operation:input.device-hub-pinch@2",
        "operation:issue.present@1",
        "operation:library.snapshot@1",
        "operation:media.import-staged@2",
        "operation:media.open@2",
        "operation:media.stage-fixture@2",
        "operation:navigation.select-tab@1",
        "operation:playback.await-window-state@1",
        "operation:playback.seek@2",
        "operation:playback.select-subtitle@1",
        "operation:playback.wait-position@2",
        "operation:preparation.local-directory-subtitle-source@1",
        "operation:presentation.enter-docked-skybox@1",
        "operation:presentation.enter-panorama@1",
        "operation:presentation.exit-spatial@1",
        "operation:storage.clear@1",
        "operation:transition-trace.arm@1",
        "operation:transition-trace.disarm@1",
        "operation:transition-trace.fetch@1",
    }
)
EXPECTED_ORACLE_IDS = frozenset(
    {
        "oracle:agent-audio@2",
        "oracle:agent-visual@2",
        "oracle:agent-structured-accessibility-tree@1",
        "oracle:agent-structured-emby-evidence@1",
        "oracle:agent-structured-interaction-trace@1",
        "oracle:agent-structured-library-command@1",
        "oracle:agent-structured-playback-probe@1",
        "oracle:agent-structured-spatial-input@1",
        "oracle:agent-structured-structural-test@2",
        "oracle:agent-structured-transition@1",
        "oracle:agent-structured-window-control-plane@1",
    }
)
EXPECTED_JOURNEY_EDGES = frozenset(
    {
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:artwork-captured-on-exit",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:audio-track-switch-same-session",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:external-subtitle-source-matrix",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:subtitle-switch-and-off",
        ),
    }
)
FORBIDDEN_ARGUMENT_KEYS = frozenset(
    {"query", "fields", "system", "mediaAlias", "semanticAlias", "fixtureSet"}
)
FORBIDDEN_RUNTIME_VALUES = frozenset(
    {"human", "wearer", "skipped", "voided", "notapplicable"}
)
RESULT_REFERENCE = re.compile(
    r"^result://(call:[a-z0-9:-]+)/([A-Za-z][A-Za-z0-9]*)$"
)


def string_values(value: object) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from string_values(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from string_values(item)


def success_references(expression: SuccessExpression) -> tuple[str, ...]:
    if isinstance(expression, ObservationRef):
        return (str(expression.ref),)
    if isinstance(expression, Not):
        return success_references(expression.term)
    if isinstance(expression, (AllOf, AnyOf, AtLeast)):
        return tuple(
            reference
            for term in expression.terms
            for reference in success_references(term)
        )
    raise TypeError(f"unsupported SuccessExpression {type(expression).__name__}")


def has_forced_two_of_three(expression: SuccessExpression) -> bool:
    if isinstance(expression, ObservationRef):
        return False
    if isinstance(expression, Not):
        return has_forced_two_of_three(expression.term)
    if isinstance(expression, (AllOf, AnyOf, AtLeast)):
        if (
            isinstance(expression, AtLeast)
            and expression.count == 2
            and len(expression.terms) == 3
        ):
            return True
        return any(has_forced_two_of_three(term) for term in expression.terms)
    raise TypeError(f"unsupported SuccessExpression {type(expression).__name__}")


class MaterializedCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = load_catalog(CATALOG_ROOT)

    def assert_closed_calls(self, owner: str, calls, global_call_ids: set[str]):
        self.assertTrue(calls)
        call_ids = [str(call.call_id) for call in calls]
        self.assertEqual(len(call_ids), len(set(call_ids)))
        self.assertFalse(global_call_ids & set(call_ids))
        global_call_ids.update(call_ids)

        prefix = (
            "call:" + owner.removeprefix("scenario:") + ":"
            if owner.startswith("scenario:")
            else f"call:{owner}:"
        )
        seen = set()
        for index, call in enumerate(calls, 1):
            self.assertEqual(str(call.call_id), f"{prefix}{index:02d}")
            self.assertEqual(call.max_invocations, 1)
            arguments = json.loads(call.arguments_bytes.decode("utf-8"))
            for value in string_values(arguments):
                if not value.startswith("result://"):
                    continue
                match = RESULT_REFERENCE.fullmatch(value)
                self.assertIsNotNone(match, call.call_id)
                assert match is not None
                self.assertIn(match.group(1), seen, call.call_id)
            seen.add(str(call.call_id))
        return {call.call_id: call for call in calls}

    def test_live_catalog_matches_a_fresh_v2_materialization(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report = materialize(
                BLUEPRINT_PATH,
                root / "Catalog",
                root / "report.json",
                CATALOG_ROOT,
            )

        self.assertEqual(report["check"], "matched")
        self.assertEqual(
            report["counts"],
            {
                "promises": 65,
                "operations": 35,
                "oracles": 11,
                "rubrics": 107,
                "preparations": 18,
                "journeys": 14,
                "scenarios": 70,
                "staticCases": 120,
            },
        )
        self.assertEqual(report["scenarioReadiness"], {"ready": 70})
        self.assertEqual(
            report["preparationReadiness"],
            {"ready": 18},
        )
        self.assertFalse(report["scenarioReadinessGaps"])
        self.assertFalse(report["preparationReadinessGaps"])

    def test_catalog_has_the_complete_v2_population(self) -> None:
        catalog = self.catalog
        self.assertEqual(
            {name: len(getattr(catalog, name)) for name in EXPECTED_COUNTS},
            EXPECTED_COUNTS,
        )
        self.assertEqual(
            sum(len(scenario.static_cases) for scenario in catalog.scenarios),
            120,
        )
        self.assertEqual(
            sum(len(scenario.obligations) for scenario in catalog.scenarios),
            159,
        )
        self.assertTrue(
            all(
                promise.scope is AutomationScope.INCLUDED
                for promise in catalog.promises
            )
        )
        self.assertTrue(
            all(
                scenario.readiness is ContractReadiness.READY
                and not scenario.blockers
                for scenario in catalog.scenarios
            )
        )
        self.assertTrue(
            all(
                preparation.readiness is ContractReadiness.READY
                and not preparation.blockers
                for preparation in catalog.preparations
            )
        )
        covered = {
            promise_id
            for scenario in catalog.scenarios
            for promise_id in scenario.promise_refs
        }
        self.assertEqual(covered, {promise.id for promise in catalog.promises})

    def test_operation_and_oracle_sets_exclude_retired_contracts(self) -> None:
        operations = {
            str(operation.id): operation for operation in self.catalog.operations
        }
        self.assertEqual(
            set(operations),
            EXPECTED_OPERATION_IDS,
        )
        self.assertIs(
            operations["operation:playback.select-subtitle@1"].role,
            OperationRole.PRODUCT_BEHAVIOR,
        )
        local_directory = operations[
            "operation:preparation.local-directory-subtitle-source@1"
        ]
        self.assertIs(local_directory.role, OperationRole.SETUP)
        self.assertEqual(
            tuple(
                (field.name, field.value_type.value, field.required)
                for field in local_directory.argument_schema.fields
            ),
            (
                ("directoryName", "string", True),
                ("mediaFileName", "string", True),
                ("memberFileNames", "string-list", True),
            ),
        )
        self.assertEqual(
            local_directory.evidence_schemas,
            frozenset(
                {EvidenceSchemaPair("library.command", "library-command@1")}
            ),
        )
        self.assertNotIn("operation:diagnostics.emby-range-log@1", operations)
        self.assertEqual(
            {str(oracle.id) for oracle in self.catalog.oracles},
            EXPECTED_ORACLE_IDS,
        )
        self.assertTrue(
            all(len(oracle.evidence_schemas) == 1 for oracle in self.catalog.oracles)
        )

        evidence_types = {
            str(pair.evidence_type)
            for contract in (*self.catalog.operations, *self.catalog.oracles)
            for pair in contract.evidence_schemas
        }
        evidence_types.update(
            str(obligation.evidence_type)
            for scenario in self.catalog.scenarios
            for obligation in scenario.obligations
        )
        self.assertNotIn("evidence-bundle", evidence_types)

        for node in (*self.catalog.preparations, *self.catalog.scenarios):
            for call in node.operations:
                arguments = json.loads(call.arguments_bytes.decode("utf-8"))
                self.assertFalse(set(arguments) & FORBIDDEN_ARGUMENT_KEYS, call.call_id)
                for value in string_values(arguments):
                    self.assertNotIn(
                        value.lower(), FORBIDDEN_RUNTIME_VALUES, call.call_id
                    )
                    self.assertFalse(value.startswith("fixture:"), call.call_id)
        self.assertTrue(
            all(
                not has_forced_two_of_three(scenario.success)
                for scenario in self.catalog.scenarios
            )
        )

    def test_every_scenario_closes_producer_oracle_rubric_and_success(self) -> None:
        operations = {operation.id: operation for operation in self.catalog.operations}
        oracles = {oracle.id: oracle for oracle in self.catalog.oracles}
        rubrics = {rubric.id: rubric for rubric in self.catalog.rubrics}
        referenced_rubrics = set()
        global_call_ids = set()

        for scenario in self.catalog.scenarios:
            with self.subTest(scenario=scenario.id):
                calls = list(scenario.operations)
                call_by_id = self.assert_closed_calls(
                    str(scenario.id), calls, global_call_ids
                )
                producer_ids = []
                for obligation in scenario.obligations:
                    producer_id = obligation.produced_by_call
                    self.assertIsNotNone(producer_id)
                    self.assertIn(producer_id, call_by_id)
                    assert producer_id is not None
                    producer_ids.append(producer_id)
                    producer = operations[call_by_id[producer_id].operation]
                    self.assertIn(
                        producer.role,
                        {OperationRole.PRODUCT_BEHAVIOR, OperationRole.EVIDENCE},
                    )
                    pair = EvidenceSchemaPair(
                        obligation.evidence_type,
                        obligation.evidence_schema,
                    )
                    self.assertIn(pair, producer.evidence_schemas)
                    self.assertIn(pair, oracles[obligation.oracle].evidence_schemas)
                    self.assertIn(obligation.rubric, rubrics)
                    referenced_rubrics.add(obligation.rubric)

                self.assertEqual(len(producer_ids), len(set(producer_ids)))
                self.assertEqual(
                    {str(obligation.case_key) for obligation in scenario.obligations},
                    {str(case) for case in scenario.static_cases},
                )
                declared = [str(obligation.id) for obligation in scenario.obligations]
                referenced = list(success_references(scenario.success))
                self.assertEqual(len(referenced), len(set(referenced)))
                self.assertCountEqual(referenced, declared)

        self.assertEqual(referenced_rubrics, set(rubrics))

    def test_preparations_have_exact_setup_producers_and_closed_calls(self) -> None:
        operations = {operation.id: operation for operation in self.catalog.operations}
        global_call_ids = set()

        for preparation in self.catalog.preparations:
            with self.subTest(preparation=preparation.id):
                calls = list(preparation.operations)
                call_by_id = self.assert_closed_calls(
                    str(preparation.id), calls, global_call_ids
                )
                self.assertEqual(len(preparation.produces), 1)
                for state in preparation.produces:
                    if state.produced_by_call is None:
                        self.assertEqual(
                            str(preparation.id),
                            "preparation:emby-test-library",
                        )
                        self.assertIs(
                            preparation.readiness,
                            ContractReadiness.IMPLEMENTATION_GAP,
                        )
                        continue
                    self.assertIn(state.produced_by_call, call_by_id)
                    producer = call_by_id[state.produced_by_call]
                    self.assertIs(
                        operations[producer.operation].role, OperationRole.SETUP
                    )

        local_directory = next(
            preparation
            for preparation in self.catalog.preparations
            if str(preparation.id) == "preparation:local-directory-subtitle-source"
        )
        producer_id = local_directory.produces[0].produced_by_call
        self.assertIsNotNone(producer_id)
        call_by_id = {call.call_id: call for call in local_directory.operations}
        assert producer_id is not None
        self.assertEqual(
            str(call_by_id[producer_id].operation),
            "operation:preparation.local-directory-subtitle-source@1",
        )

    def test_journeys_have_the_reviewed_edges_and_one_main_gate(self) -> None:
        edges = {
            (str(before), str(after))
            for journey in self.catalog.journeys
            for before, after in journey.ordering
        }
        self.assertEqual(edges, EXPECTED_JOURNEY_EDGES)

        gates = [
            scenario for scenario in self.catalog.scenarios if scenario.main_gate_for
        ]
        self.assertEqual(len(gates), 1)
        self.assertEqual(
            gates[0].id,
            "scenario:local-media-lifecycle:clean-flat-playback-main-gate",
        )
        self.assertEqual(
            gates[0].main_gate_for,
            frozenset((BoundLane.SIMULATOR, BoundLane.DEVICE)),
        )
        self.assertTrue(
            all(
                gates[0].id not in edge
                for journey in self.catalog.journeys
                for edge in journey.ordering
            )
        )

    def test_full_catalog_analysis_selects_all_scenarios_and_edges(self) -> None:
        digest_a = "sha256:" + "a" * 64
        digest_b = "sha256:" + "b" * 64
        digest_c = "sha256:" + "c" * 64
        digest_d = "sha256:" + "d" * 64
        digest_e = "sha256:" + "e" * 64
        digest_f = "sha256:" + "f" * 64
        digest_0 = "sha256:" + "0" * 64
        digest_1 = "sha256:" + "1" * 64
        scope_fact = next(
            fact
            for fact in self.catalog.facts
            if fact.id == "fact:runtime.catalog-scope-included"
        )
        request = CompileRequest(
            FullSelector(),
            (
                ReviewedFact(
                    scope_fact.id,
                    True,
                    scope_fact.source_digest,
                    digest_a,
                ),
            ),
            (BoundLane.SIMULATOR, BoundLane.DEVICE),
            BuildIdentity(
                "com.xiongzhipeng.XrPlayer",
                "catalog-materialization-test",
                digest_a,
                digest_b,
                ToolchainIdentity(
                    "27.0",
                    "18A5301h",
                    "27.0",
                    "24A5298h",
                    "27.0",
                    "24A5298h",
                ),
                (
                    LaneBuildArtifact(
                        BoundLane.SIMULATOR,
                        digest_c,
                        digest_d,
                        digest_e,
                    ),
                    LaneBuildArtifact(
                        BoundLane.DEVICE,
                        digest_f,
                        digest_0,
                        digest_1,
                    ),
                ),
            ),
            EvidenceEnvironmentIdentity(
                {operation.id: digest_a for operation in self.catalog.operations},
                AgentEnvironment("catalog-test-agent", digest_a, digest_b),
            ),
        )

        analysis = analyze_catalog(self.catalog, request)

        gate_id = "scenario:local-media-lifecycle:clean-flat-playback-main-gate"
        self.assertEqual(len(analysis.target_promises), 65)
        self.assertEqual(len(analysis.target_scenarios), 70)
        self.assertEqual(len(analysis.selected_scenarios), 70)
        self.assertEqual(
            {(gate.lane, str(gate.scenario_id)) for gate in analysis.main_gates},
            {
                (BoundLane.SIMULATOR, gate_id),
                (BoundLane.DEVICE, gate_id),
            },
        )
        self.assertEqual(
            {
                (str(dependency.predecessor), str(dependency.successor))
                for dependency in analysis.journey_dependencies
            },
            EXPECTED_JOURNEY_EDGES,
        )

    def test_implementation_locators_exist_and_match_their_sha256(self) -> None:
        implementations = list(self.catalog.operations) + list(self.catalog.oracles)
        for contract in implementations:
            with self.subTest(contract=contract.id):
                locator = Path(contract.implementation_locator)
                self.assertFalse(locator.is_absolute())
                path = (REPOSITORY_ROOT / locator).resolve()
                path.relative_to(REPOSITORY_ROOT.resolve())
                self.assertTrue(path.is_file())
                self.assertEqual(contract.implementation_digest, digest_text_file(path))

    def test_identifiers_and_materialized_arguments_are_normalized(self) -> None:
        for preparation in self.catalog.preparations:
            for state in preparation.prerequisites:
                self.assertNotIn(":", str(state.key))
            for state in preparation.produces:
                self.assertNotIn(":", str(state.key))
        for journey in self.catalog.journeys:
            for state in journey.shared_state:
                self.assertNotIn(":", str(state.key))
        for scenario in self.catalog.scenarios:
            for state in scenario.prerequisites:
                self.assertNotIn(":", str(state.key))

        contract_roots = (
            CATALOG_ROOT / "promises",
            CATALOG_ROOT / "facts",
            CATALOG_ROOT / "operations",
            CATALOG_ROOT / "oracles",
            CATALOG_ROOT / "rubrics",
            CATALOG_ROOT / "preparations",
            CATALOG_ROOT / "journeys",
        )
        for root in contract_roots:
            for path in root.rglob("*.md"):
                with self.subTest(path=path):
                    self.assertNotIn("${", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
