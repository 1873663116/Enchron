#!/usr/bin/env python3

from __future__ import annotations

import ast
from dataclasses import replace
import json
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.applicability import Constant, FactEquals, ReviewedFact
from regression.core.compiler import (
    ContractNotReadyError,
    PreparationNotReadyError,
    accept_reviews,
    analyze_catalog,
    compile_run,
)
from regression.core.contracts import (
    ArgumentSchema,
    ArgumentValueKind,
    ArtifactClass,
    AutomationScope,
    BoundLane,
    ContractReadiness,
    DraftCatalog,
    EvidenceSchemaPair,
    EvidenceObligation,
    FactDeclaration,
    ImplementationGapBlocker,
    JourneyContract,
    LaneRequirement,
    OperationCall,
    OperationContract,
    OperationRole,
    OracleContract,
    OracleKind,
    PreparationContract,
    PromiseContract,
    RubricContract,
    ScenarioContract,
    StateDeclaration,
    StateRequirement,
)
from regression.core.errors import RegressionError
from regression.core.digest import canonical_digest
from regression.core.expression import ObservationRef
from regression.core.ids import (
    CallID,
    CaseKey,
    Digest,
    EvidenceSchema,
    EvidenceType,
    FactID,
    JourneyID,
    ObligationID,
    OperationID,
    OracleID,
    PreparationID,
    PromiseID,
    RubricID,
    ScenarioID,
    StateKey,
    StateSchema,
    StateTag,
)
from regression.core.plan import (
    AgentEnvironment,
    BothJoinNode,
    BuildIdentity,
    CompileRequest,
    EvidenceEnvironmentIdentity,
    FullSelector,
    LaneBuildArtifact,
    PromiseSelector,
    ScenarioAttemptNode,
    ScenarioSelector,
    ToolchainIdentity,
    compiled_plan_bytes,
    compiled_plan_payload,
)
from regression.core.review import (
    BudgetAmount,
    BudgetUnit,
    CompletedReview,
    ReviewActorIdentity,
    ReviewBudget,
    ReviewClass,
    ReviewPacket,
    ReviewPolicy,
    ReviewReceipt,
    ReviewUnitKind,
    ReviewUsage,
    approve_review_budgets,
    complete_reviews,
)
from regression.core.review_catalog import (
    build_catalog_review_units,
    plan_catalog_reviews,
)


def digest(character: str) -> Digest:
    return Digest("sha256:" + character * 64)


def toolchain_identity() -> ToolchainIdentity:
    return ToolchainIdentity(
        "26.0",
        "17A5305f",
        "26.0",
        "23A5308g",
        "26.0",
        "23A5308g",
    )


def lane_build_artifact(
    lane: BoundLane,
    xctestrun: str,
    test_products: str,
    application_code: str,
) -> LaneBuildArtifact:
    return LaneBuildArtifact(
        lane,
        digest(xctestrun),
        digest(test_products),
        digest(application_code),
    )


def promise(
    identifier: str,
    source: str,
    scope: AutomationScope = AutomationScope.INCLUDED,
) -> PromiseContract:
    return PromiseContract(
        PromiseID(identifier),
        identifier,
        f"Statement for {identifier}",
        scope,
        "subjective only" if scope is AutomationScope.EXCLUDED else None,
        "body",
        digest(source),
    )


def operation_call(
    identifier: str, operation_id: OperationID
) -> OperationCall:
    return OperationCall(CallID(identifier), operation_id, b"{}", 2)


class Fixture:
    def __init__(self) -> None:
        evidence_type = EvidenceType("image.snapshot")
        evidence_schema = EvidenceSchema("image.snapshot@1")
        evidence_pair = EvidenceSchemaPair(evidence_type, evidence_schema)
        self.evidence_schema = evidence_schema
        self.state = StateRequirement(
            StateKey("session"), StateSchema("session.ready@1")
        )
        self.fact = FactDeclaration(
            FactID("fact:feature.enabled"),
            "Feature enabled",
            "Whether the feature is enabled",
            ArgumentValueKind.BOOLEAN,
            "body",
            digest("3"),
        )
        self.promises = (
            promise("promise:baseline:c01", "1"),
            promise("promise:playback:c01", "2"),
        )
        self.setup_operation = OperationContract(
            OperationID("operation:setup.session@1"),
            "Prepare session",
            OperationRole.SETUP,
            frozenset((BoundLane.SIMULATOR, BoundLane.DEVICE)),
            ArgumentSchema(()),
            frozenset(),
            frozenset(),
            "adapter.setup",
            digest("4"),
            "body",
            digest("5"),
        )
        self.evidence_operation = OperationContract(
            OperationID("operation:evidence.capture@1"),
            "Capture evidence",
            OperationRole.EVIDENCE,
            frozenset((BoundLane.SIMULATOR, BoundLane.DEVICE)),
            ArgumentSchema(()),
            frozenset(),
            frozenset((evidence_pair,)),
            "adapter.capture",
            digest("6"),
            "body",
            digest("7"),
        )
        self.deterministic_oracle = OracleContract(
            OracleID("oracle:deterministic.image@1"),
            "Deterministic image oracle",
            OracleKind.DETERMINISTIC,
            frozenset((evidence_pair,)),
            "oracle.deterministic",
            digest("8"),
            "body",
            digest("9"),
        )
        self.agent_oracle = OracleContract(
            OracleID("oracle:agent.image@1"),
            "Agent image oracle",
            OracleKind.AGENT,
            frozenset((evidence_pair,)),
            "oracle.agent",
            digest("a"),
            "body",
            digest("b"),
        )
        self.rubric = RubricContract(
            RubricID("rubric:image.quality@1"),
            "Image quality",
            ("The expected control is visible",),
            ("A blank frame must fail",),
            "body",
            digest("c"),
        )
        self.preparations = (
            self._preparation(BoundLane.SIMULATOR, "sim", "d"),
            self._preparation(BoundLane.DEVICE, "device", "e"),
        )
        self.gate = self._scenario(
            "scenario:bootstrap:gate",
            "journey:bootstrap",
            self.promises[0].id,
            LaneRequirement.BOTH,
            "call:bootstrap:gate",
            "obligation:bootstrap:gate",
            self.deterministic_oracle.id,
            Constant(True),
            frozenset((BoundLane.SIMULATOR, BoundLane.DEVICE)),
            (),
            "f",
        )
        self.either = self._scenario(
            "scenario:product:either",
            "journey:product",
            self.promises[1].id,
            LaneRequirement.EITHER,
            "call:product:either",
            "obligation:product:either",
            self.deterministic_oracle.id,
            FactEquals(self.fact.id, True),
            frozenset(),
            (),
            "0",
        )
        self.both = self._scenario(
            "scenario:product:both",
            "journey:product",
            self.promises[1].id,
            LaneRequirement.BOTH,
            "call:product:both",
            "obligation:product:both",
            self.agent_oracle.id,
            Constant(True),
            frozenset(),
            (),
            "1",
        )
        self.journeys = (
            JourneyContract(
                JourneyID("journey:bootstrap"),
                "Bootstrap",
                (self.gate.id,),
                (),
                (),
                "body",
                digest("2"),
            ),
            JourneyContract(
                JourneyID("journey:product"),
                "Product",
                (self.either.id, self.both.id),
                ((self.either.id, self.both.id),),
                (self.state,),
                "body",
                digest("3"),
            ),
        )
        self.catalog = DraftCatalog(
            self.promises,
            (self.fact,),
            (self.setup_operation, self.evidence_operation),
            (self.deterministic_oracle, self.agent_oracle),
            (self.rubric,),
            self.preparations,
            self.journeys,
            (self.gate, self.either, self.both),
        )

    def _preparation(
        self, lane: BoundLane, suffix: str, source: str
    ) -> PreparationContract:
        call = operation_call(f"call:prepare:{suffix}", self.setup_operation.id)
        return PreparationContract(
            PreparationID(f"preparation:session:{suffix}"),
            f"Prepare {suffix}",
            lane,
            20,
            ContractReadiness.READY,
            (),
            (),
            (call,),
            (
                StateDeclaration(
                    self.state.key,
                    self.state.schema,
                    call.call_id,
                    (StateTag("session.fixture"),),
                ),
            ),
            "body",
            digest(source),
        )

    def _scenario(
        self,
        identifier: str,
        journey: str,
        promise_id: PromiseID,
        lane: LaneRequirement,
        call_id: str,
        obligation_id: str,
        oracle_id: OracleID,
        applicability: object,
        main_gate_for: frozenset[BoundLane],
        prerequisites: tuple[StateRequirement, ...],
        source: str,
    ) -> ScenarioContract:
        call = operation_call(call_id, self.evidence_operation.id)
        obligation = EvidenceObligation(
            ObligationID(obligation_id),
            ArtifactClass.COVERAGE,
            EvidenceType("image.snapshot"),
            self.evidence_schema,
            CaseKey("default"),
            call.call_id,
            oracle_id,
            self.rubric.id,
        )
        return ScenarioContract(
            ScenarioID(identifier),
            identifier,
            JourneyID(journey),
            (promise_id,),
            applicability,
            lane,
            100,
            (CaseKey("default"),),
            ContractReadiness.READY,
            (),
            prerequisites,
            (call,),
            (obligation,),
            ObservationRef(obligation.id),
            main_gate_for,
            "body",
            digest(source),
        )

    def with_catalog(self, **changes: object) -> DraftCatalog:
        values = {
            "promises": self.catalog.promises,
            "facts": self.catalog.facts,
            "operations": self.catalog.operations,
            "oracles": self.catalog.oracles,
            "rubrics": self.catalog.rubrics,
            "preparations": self.catalog.preparations,
            "journeys": self.catalog.journeys,
            "scenarios": self.catalog.scenarios,
        }
        values.update(changes)
        return DraftCatalog(**values)

    def request(
        self,
        selector: object = None,
        reviewed_facts: tuple[ReviewedFact, ...] = (),
        lanes: tuple[BoundLane, ...] = (
            BoundLane.SIMULATOR,
            BoundLane.DEVICE,
        ),
        artifacts: tuple[LaneBuildArtifact, ...] = (),
        include_agent: bool = True,
    ) -> CompileRequest:
        if selector is None:
            selector = FullSelector()
        if not reviewed_facts:
            receipt_digest = fact_review_receipt_digest(
                completed_review(self.catalog), self.fact.id
            )
            reviewed_facts = (
                ReviewedFact(
                    self.fact.id,
                    True,
                    self.fact.source_digest,
                    receipt_digest,
                ),
            )
        if not artifacts:
            artifacts = (
                lane_build_artifact(BoundLane.SIMULATOR, "5", "6", "7"),
                lane_build_artifact(BoundLane.DEVICE, "8", "9", "a"),
            )
        build = BuildIdentity(
            "com.example.Enchron",
            "abc123",
            digest("b"),
            digest("c"),
            toolchain_identity(),
            artifacts,
        )
        agent = (
            AgentEnvironment("gpt-test", digest("d"), digest("e"))
            if include_agent
            else None
        )
        environment = EvidenceEnvironmentIdentity(_catalog_operation_digests(), agent)
        return CompileRequest(
            selector,
            reviewed_facts,
            lanes,
            build,
            environment,
        )


def _catalog_operation_digests():
    return {
        OperationID("operation:setup.session@1"): digest("8"),
        OperationID("operation:evidence.capture@1"): digest("9"),
    }


def completed_review(catalog: DraftCatalog) -> CompletedReview:
    units = build_catalog_review_units(catalog)
    budget = ReviewBudget(
        (
            BudgetAmount(BudgetUnit.INPUT_TOKENS, 1_000_000),
            BudgetAmount(BudgetUnit.REVIEW_ITEMS, 1_000_000),
        )
    )
    planned = plan_catalog_reviews(catalog, ReviewPolicy(budget, budget))
    approved = approve_review_budgets(planned)
    actor = ReviewActorIdentity("test-reviewer", digest("c"))
    receipts = tuple(
        ReviewReceipt(
            packet.packet_digest,
            packet.reviewer,
            actor,
            digest("d"),
            True,
            ReviewUsage(tuple(packet.approved_budget.amounts)),
            "2026-08-29T00:00:00Z",
            _assessment_digest(packet.reviewer, packet.packet_digest),
        )
        for packet in approved.packets
    )
    return complete_reviews(units, approved, receipts, catalog.digest)


def _assessment_digest(reviewer, packet_digest):
    if reviewer is not ReviewClass.AGENT_OPERABILITY:
        return None
    return canonical_digest({"assessmentFor": str(packet_digest)})


def fact_review_receipt_digest(
    completed: CompletedReview, fact_id: FactID
) -> Digest:
    packet = next(
        packet
        for packet in completed.packets
        if packet.reviewer is ReviewClass.HUMAN_COVERAGE
        and any(
            unit.kind is ReviewUnitKind.FACT and unit.ref == str(fact_id)
            for unit in packet.units
        )
    )
    return next(
        receipt.receipt_digest
        for receipt in completed.receipts
        if receipt.packet_digest == packet.packet_digest
    )


class CompilerPositiveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()

    def compile(self, request: CompileRequest = None, catalog: DraftCatalog = None):
        current = catalog or self.fixture.catalog
        completed = completed_review(current)
        reviewed = accept_reviews(current, completed)
        if request is None:
            declaration = next(
                fact for fact in current.facts if fact.id == self.fixture.fact.id
            )
            request = self.fixture.request(
                reviewed_facts=(
                    ReviewedFact(
                        declaration.id,
                        True,
                        declaration.source_digest,
                        fact_review_receipt_digest(completed, declaration.id),
                    ),
                )
            )
        return compile_run(reviewed, request)

    def test_two_lanes_either_both_and_shared_preparation_compile(self) -> None:
        plan = self.compile()
        attempts = tuple(
            item for item in plan.nodes if isinstance(item, ScenarioAttemptNode)
        )
        joins = tuple(item for item in plan.nodes if isinstance(item, BothJoinNode))
        self.assertEqual(5, len(attempts))
        self.assertEqual(2, len(joins))

        either = next(
            item for item in attempts if item.scenario_id == self.fixture.either.id
        )
        self.assertEqual(
            (BoundLane.SIMULATOR, BoundLane.DEVICE), either.lane_candidates
        )
        self.assertTrue(either.binds_lane_on_claim)
        self.assertEqual(2, len(either.preparation_requirements))

        both_attempts = tuple(
            item for item in attempts if item.scenario_id == self.fixture.both.id
        )
        both_join = next(
            item for item in joins if item.scenario_id == self.fixture.both.id
        )
        self.assertEqual(2, len(both_attempts))
        self.assertEqual(
            {item.id for item in both_attempts}, set(both_join.predecessors)
        )
        self.assertEqual(
            both_attempts[0].evaluation_bindings,
            both_attempts[1].evaluation_bindings,
        )
        obligation = self.fixture.both.obligations[0]
        evaluation = both_attempts[0].evaluation_bindings[0]
        self.assertEqual(obligation.id, evaluation.id)
        self.assertEqual(obligation.artifact_class, evaluation.artifact_class)
        self.assertEqual(obligation.evidence_type, evaluation.evidence_type)
        self.assertEqual(obligation.evidence_schema, evaluation.evidence_schema)
        self.assertEqual(obligation.case_key, evaluation.case_key)
        self.assertEqual(obligation.produced_by_call, evaluation.produced_by_call)
        self.assertEqual(
            self.fixture.evidence_operation.leaf_digest,
            evaluation.producer_contract_digest,
        )
        self.assertEqual(self.fixture.agent_oracle.id, evaluation.oracle.id)
        self.assertEqual(self.fixture.agent_oracle.kind, evaluation.oracle.kind)
        self.assertEqual(
            self.fixture.agent_oracle.leaf_digest,
            evaluation.oracle.contract_digest,
        )
        self.assertEqual(
            self.fixture.agent_oracle.implementation_locator,
            evaluation.oracle.implementation_locator,
        )
        self.assertEqual(
            self.fixture.agent_oracle.implementation_digest,
            evaluation.oracle.implementation_digest,
        )
        self.assertEqual(self.fixture.agent_oracle.body, evaluation.oracle.body)
        self.assertEqual(self.fixture.rubric.id, evaluation.rubric.id)
        self.assertEqual(
            self.fixture.rubric.leaf_digest,
            evaluation.rubric.contract_digest,
        )
        self.assertEqual(self.fixture.rubric.criteria, evaluation.rubric.criteria)
        self.assertEqual(
            self.fixture.rubric.negative_controls,
            evaluation.rubric.negative_controls,
        )
        self.assertEqual(self.fixture.rubric.body, evaluation.rubric.body)
        self.assertIs(
            both_attempts[0].build_identity, both_attempts[1].build_identity
        )

        self.assertEqual(2, len(plan.preparation_bindings))
        self.assertEqual(
            {BoundLane.SIMULATOR, BoundLane.DEVICE},
            {item.lane for item in plan.preparation_bindings},
        )
        self.assertTrue(
            all(binding.calls[0].contract_digest == self.fixture.setup_operation.leaf_digest for binding in plan.preparation_bindings)
        )
        self.assertEqual(set(item.id for item in plan.nodes), {item.node_id for item in plan.critical_costs})
        self.assertTrue(all(item.critical_remaining_millis >= item.cost_millis for item in attempts))

    def test_both_main_gate_attempts_unlock_lanes_without_join(self) -> None:
        plan = self.compile()
        gates = {item.lane: item.node_id for item in plan.main_gates}
        self.assertNotEqual(gates[BoundLane.SIMULATOR], gates[BoundLane.DEVICE])
        self.assertTrue(str(gates[BoundLane.SIMULATOR]).endswith(":simulator"))
        self.assertTrue(str(gates[BoundLane.DEVICE]).endswith(":device"))
        gate_join = next(
            item
            for item in plan.nodes
            if isinstance(item, BothJoinNode)
            and item.scenario_id == self.fixture.gate.id
        )
        self.assertNotIn(gate_join.id, set(gates.values()))

    def test_selector_adds_journey_predecessor_closure(self) -> None:
        request = self.fixture.request(
            selector=ScenarioSelector((self.fixture.both.id,))
        )
        analysis = analyze_catalog(self.fixture.catalog, request)
        self.assertIn(self.fixture.both.id, analysis.selected_scenarios)
        self.assertIn(self.fixture.either.id, analysis.selected_scenarios)
        self.assertIn(self.fixture.gate.id, analysis.selected_scenarios)
        self.assertIn(
            (self.fixture.either.id, self.fixture.both.id),
            {
                (item.predecessor, item.successor)
                for item in analysis.journey_dependencies
            },
        )

        promise_request = self.fixture.request(
            selector=PromiseSelector((self.fixture.promises[1].id,))
        )
        promise_analysis = analyze_catalog(self.fixture.catalog, promise_request)
        self.assertEqual(
            (self.fixture.promises[1].id,), promise_analysis.target_promises
        )

    def test_inapplicable_middle_is_removed_without_losing_order(self) -> None:
        middle = self.fixture._scenario(
            "scenario:product:middle",
            "journey:product",
            self.fixture.promises[1].id,
            LaneRequirement.EITHER,
            "call:product:middle",
            "obligation:product:middle",
            self.fixture.deterministic_oracle.id,
            Constant(False),
            frozenset(),
            (),
            "e",
        )
        journey = replace(
            self.fixture.journeys[1],
            scenario_refs=(self.fixture.either.id, middle.id, self.fixture.both.id),
            ordering=(
                (self.fixture.either.id, middle.id),
                (middle.id, self.fixture.both.id),
            ),
            source_digest=digest("f"),
        )
        catalog = self.fixture.with_catalog(
            journeys=(self.fixture.journeys[0], journey),
            scenarios=(self.fixture.gate, self.fixture.either, middle, self.fixture.both),
        )
        request = self.fixture.request(
            selector=ScenarioSelector((self.fixture.both.id,))
        )
        analysis = analyze_catalog(catalog, request)
        self.assertNotIn(middle.id, analysis.selected_scenarios)
        self.assertIn(
            (self.fixture.either.id, self.fixture.both.id),
            {
                (item.predecessor, item.successor)
                for item in analysis.journey_dependencies
            },
        )

    def test_plan_digest_is_independent_of_input_collection_order(self) -> None:
        first = self.compile()
        request = self.fixture.request(
            lanes=(BoundLane.DEVICE, BoundLane.SIMULATOR),
            artifacts=(
                lane_build_artifact(BoundLane.DEVICE, "8", "9", "a"),
                lane_build_artifact(BoundLane.SIMULATOR, "5", "6", "7"),
            ),
        )
        second = self.compile(request)
        self.assertEqual(first.plan_digest, second.plan_digest)
        self.assertEqual(
            (BoundLane.SIMULATOR, BoundLane.DEVICE), second.requested_lanes
        )

    def test_recursive_preparation_closure_is_frozen_into_rules(self) -> None:
        library = StateRequirement(
            StateKey("library"), StateSchema("library.ready@1")
        )

        def chained(lane: BoundLane, suffix: str, source: str):
            call = operation_call(
                f"call:prepare:library:{suffix}",
                self.fixture.setup_operation.id,
            )
            return PreparationContract(
                PreparationID(f"preparation:library:{suffix}"),
                f"Prepare library {suffix}",
                lane,
                30,
                ContractReadiness.READY,
                (),
                (self.fixture.state,),
                (call,),
                (
                    StateDeclaration(
                        library.key,
                        library.schema,
                        call.call_id,
                        (StateTag("library.fixture"),),
                    ),
                ),
                "body",
                digest(source),
            )

        chained_preparations = (
            chained(BoundLane.SIMULATOR, "sim", "4"),
            chained(BoundLane.DEVICE, "device", "5"),
        )
        journey = replace(
            self.fixture.journeys[1],
            shared_state=(library,),
            source_digest=digest("6"),
        )
        catalog = self.fixture.with_catalog(
            preparations=self.fixture.preparations + chained_preparations,
            journeys=(self.fixture.journeys[0], journey),
        )
        plan = self.compile(catalog=catalog)
        self.assertEqual(4, len(plan.preparation_bindings))
        by_id = {item.preparation_id: item for item in plan.preparation_bindings}
        for preparation in chained_preparations:
            binding = by_id[preparation.id]
            self.assertEqual(1, len(binding.prerequisite_bindings))
            expected = next(
                item.id
                for item in self.fixture.preparations
                if item.lane is preparation.lane
            )
            self.assertEqual(
                expected, binding.prerequisite_bindings[0].preparation_id
            )

    def test_a_node_carries_only_the_operation_digests_its_calls_use(self) -> None:
        plan = self.compile()
        attempts = tuple(
            item for item in plan.nodes if isinstance(item, ScenarioAttemptNode)
        )

        self.assertTrue(attempts)
        narrowed = 0
        for node in attempts:
            used = {item.operation for item in node.calls}
            carried = set(node.evidence_environment_identity.operation_digests)
            with self.subTest(node=str(node.id)):
                self.assertEqual(used, carried)
            if carried < set(plan.evidence_environment_identity.operation_digests):
                narrowed += 1

        self.assertTrue(
            narrowed,
            "no node used a strict subset, so narrowing proves nothing here",
        )

    def test_allowed_calls_preserve_strict_catalog_order(self) -> None:
        extra = operation_call(
            "call:product:both:preflight", self.fixture.evidence_operation.id
        )
        both = replace(
            self.fixture.both,
            operations=(extra,) + self.fixture.both.operations,
            source_digest=digest("4"),
        )
        catalog = self.fixture.with_catalog(
            scenarios=(self.fixture.gate, self.fixture.either, both)
        )
        plan = self.compile(catalog=catalog)
        attempts = tuple(
            item
            for item in plan.nodes
            if isinstance(item, ScenarioAttemptNode)
            and item.scenario_id == both.id
        )
        expected = tuple(item.call_id for item in both.operations)
        self.assertEqual(2, len(attempts))
        self.assertTrue(
            all(tuple(item.call_id for item in node.calls) == expected for node in attempts)
        )

    def test_operation_invalidates_tags_are_sorted_and_change_plan_digest(self) -> None:
        baseline = self.compile()
        changed_operation = replace(
            self.fixture.evidence_operation,
            invalidates_tags=frozenset(
                (StateTag("session.fixture"), StateTag("evidence.cache"))
            ),
        )
        changed_catalog = self.fixture.with_catalog(
            operations=(self.fixture.setup_operation, changed_operation)
        )
        changed = self.compile(catalog=changed_catalog)
        changed_payload = compiled_plan_payload(changed)
        attempt_payload = next(
            item
            for item in changed_payload["nodes"]
            if item["kind"] == "scenarioAttempt"
        )
        self.assertEqual(
            ["evidence.cache", "session.fixture"],
            attempt_payload["calls"][0]["invalidatesTags"],
        )
        self.assertEqual(baseline.catalog_digest, changed.catalog_digest)
        self.assertNotEqual(baseline.plan_digest, changed.plan_digest)

    def test_evaluation_contract_changes_change_plan_digest_and_payload(self) -> None:
        baseline = self.compile()

        changed_oracle = replace(
            self.fixture.agent_oracle,
            implementation_digest=digest("e"),
        )
        oracle_catalog = self.fixture.with_catalog(
            oracles=(self.fixture.deterministic_oracle, changed_oracle)
        )
        oracle_plan = self.compile(catalog=oracle_catalog)
        oracle_attempt = next(
            item
            for item in oracle_plan.nodes
            if isinstance(item, ScenarioAttemptNode)
            and item.scenario_id == self.fixture.both.id
        )
        self.assertEqual(
            changed_oracle.implementation_digest,
            oracle_attempt.evaluation_bindings[0].oracle.implementation_digest,
        )
        oracle_payload = next(
            item
            for item in compiled_plan_payload(oracle_plan)["nodes"]
            if item["kind"] == "scenarioAttempt"
            and item["scenarioId"] == str(self.fixture.both.id)
        )["evaluationBindings"][0]
        self.assertEqual(
            str(changed_oracle.implementation_digest),
            oracle_payload["oracle"]["implementationDigest"],
        )
        self.assertEqual(baseline.catalog_digest, oracle_plan.catalog_digest)
        self.assertNotEqual(baseline.plan_digest, oracle_plan.plan_digest)

        changed_rubric = replace(
            self.fixture.rubric,
            criteria=("The expected control is visible", "Motion is stable"),
        )
        rubric_catalog = self.fixture.with_catalog(rubrics=(changed_rubric,))
        rubric_plan = self.compile(catalog=rubric_catalog)
        rubric_payload = next(
            item
            for item in compiled_plan_payload(rubric_plan)["nodes"]
            if item["kind"] == "scenarioAttempt"
            and item["scenarioId"] == str(self.fixture.both.id)
        )["evaluationBindings"][0]
        self.assertEqual(
            ["The expected control is visible", "Motion is stable"],
            rubric_payload["rubric"]["criteria"],
        )
        self.assertEqual(baseline.catalog_digest, rubric_plan.catalog_digest)
        self.assertNotEqual(baseline.plan_digest, rubric_plan.plan_digest)

    def test_evaluation_payload_is_self_contained_without_catalog(self) -> None:
        plan = self.compile()
        attempt = next(
            item
            for item in plan.nodes
            if isinstance(item, ScenarioAttemptNode)
            and item.scenario_id == self.fixture.both.id
        )
        self.assertFalse(hasattr(plan, "catalog"))
        self.assertFalse(hasattr(attempt, "obligations"))
        evaluation = attempt.evaluation_bindings[0]
        payload = next(
            item
            for item in compiled_plan_payload(plan)["nodes"]
            if item["id"] == str(attempt.id)
        )["evaluationBindings"][0]
        self.assertEqual(str(evaluation.id), payload["id"])
        self.assertEqual(evaluation.artifact_class.value, payload["artifactClass"])
        self.assertEqual(str(evaluation.evidence_type), payload["evidenceType"])
        self.assertEqual(str(evaluation.evidence_schema), payload["evidenceSchema"])
        self.assertEqual(str(evaluation.case_key), payload["caseKey"])
        self.assertEqual(
            str(evaluation.producer_contract_digest),
            payload["producerContractDigest"],
        )
        self.assertEqual(str(evaluation.produced_by_call), payload["producedByCall"])
        self.assertEqual(str(evaluation.oracle.id), payload["oracle"]["id"])
        self.assertEqual(evaluation.oracle.kind.value, payload["oracle"]["kind"])
        self.assertEqual(
            str(evaluation.oracle.contract_digest),
            payload["oracle"]["contractDigest"],
        )
        self.assertEqual(
            evaluation.oracle.implementation_locator,
            payload["oracle"]["implementationLocator"],
        )
        self.assertEqual(
            str(evaluation.oracle.implementation_digest),
            payload["oracle"]["implementationDigest"],
        )
        self.assertEqual(evaluation.oracle.body, payload["oracle"]["body"])
        self.assertEqual(str(evaluation.rubric.id), payload["rubric"]["id"])
        self.assertEqual(
            str(evaluation.rubric.contract_digest),
            payload["rubric"]["contractDigest"],
        )
        self.assertEqual(
            list(evaluation.rubric.criteria),
            payload["rubric"]["criteria"],
        )
        self.assertEqual(
            list(evaluation.rubric.negative_controls),
            payload["rubric"]["negativeControls"],
        )
        self.assertEqual(evaluation.rubric.body, payload["rubric"]["body"])

    def test_operation_payload_is_self_contained_and_binds_argument_and_implementation_changes(self) -> None:
        baseline = self.compile()
        attempt = next(
            item
            for item in baseline.nodes
            if isinstance(item, ScenarioAttemptNode)
            and item.scenario_id == self.fixture.both.id
        )
        call = attempt.calls[0]
        payload = next(
            item
            for item in compiled_plan_payload(baseline)["nodes"]
            if item["id"] == str(attempt.id)
        )["calls"][0]

        self.assertFalse(hasattr(baseline, "catalog"))
        self.assertEqual(call.arguments_bytes.decode("utf-8"), payload["argumentsBytes"])
        self.assertEqual(str(call.arguments_digest), payload["argumentsDigest"])
        self.assertEqual(call.implementation_locator, payload["implementationLocator"])
        self.assertEqual(
            str(call.implementation_digest), payload["implementationDigest"]
        )

        catalog_call = self.fixture.both.operations[0]
        changed_call = OperationCall(
            catalog_call.call_id,
            catalog_call.operation,
            b'{"mode":"alternate"}',
            catalog_call.max_invocations,
        )
        changed_scenario = replace(
            self.fixture.both,
            operations=(changed_call,),
        )
        argument_catalog = self.fixture.with_catalog(
            scenarios=(self.fixture.gate, self.fixture.either, changed_scenario)
        )
        argument_plan = self.compile(catalog=argument_catalog)
        self.assertEqual(baseline.catalog_digest, argument_plan.catalog_digest)
        self.assertNotEqual(baseline.plan_digest, argument_plan.plan_digest)

        changed_operation = replace(
            self.fixture.evidence_operation,
            implementation_locator="adapter.capture.v2",
        )
        implementation_catalog = self.fixture.with_catalog(
            operations=(self.fixture.setup_operation, changed_operation)
        )
        implementation_plan = self.compile(catalog=implementation_catalog)
        self.assertEqual(baseline.catalog_digest, implementation_plan.catalog_digest)
        self.assertNotEqual(
            baseline.plan_digest, implementation_plan.plan_digest
        )

        changed_implementation_digest = replace(
            self.fixture.evidence_operation,
            implementation_digest=digest("e"),
        )
        digest_catalog = self.fixture.with_catalog(
            operations=(
                self.fixture.setup_operation,
                changed_implementation_digest,
            )
        )
        digest_plan = self.compile(catalog=digest_catalog)
        self.assertEqual(baseline.catalog_digest, digest_plan.catalog_digest)
        self.assertNotEqual(baseline.plan_digest, digest_plan.plan_digest)

    def test_analysis_has_no_runnable_capability(self) -> None:
        analysis = analyze_catalog(self.fixture.catalog, self.fixture.request())
        self.assertFalse(hasattr(analysis, "nodes"))
        self.assertFalse(hasattr(analysis, "calls"))

    def test_build_identity_digest_binds_toolchain_and_every_lane_digest(self) -> None:
        baseline = self.fixture.request().build_identity
        for index, artifact in enumerate(baseline.lane_artifacts):
            for field_name in (
                "xctestrun_digest",
                "test_products_digest",
                "application_code_digest",
            ):
                with self.subTest(lane=artifact.lane.value, field=field_name):
                    changed_artifacts = list(baseline.lane_artifacts)
                    changed_artifacts[index] = replace(
                        artifact,
                        **{field_name: digest("0")},
                    )
                    changed = replace(
                        baseline,
                        lane_artifacts=tuple(changed_artifacts),
                    )
                    self.assertNotEqual(baseline.digest, changed.digest)

        changed_toolchain = replace(
            baseline,
            toolchain=replace(baseline.toolchain, xcode_build="17A5305g"),
        )
        self.assertNotEqual(baseline.digest, changed_toolchain.digest)

    def test_public_serialization_is_canonical_and_detached(self) -> None:
        plan = self.compile()
        payload = compiled_plan_payload(plan)
        encoded = compiled_plan_bytes(plan)
        self.assertEqual(plan.plan_digest, canonical_digest(payload))
        self.assertEqual(payload, json.loads(encoded.decode("utf-8")))
        self.assertEqual(
            {
                "bundleIdentifier": "com.example.Enchron",
                "gitRevision": "abc123",
                "sourceTreeDigest": str(digest("b")),
                "configurationDigest": str(digest("c")),
                "toolchain": {
                    "xcodeVersion": "26.0",
                    "xcodeBuild": "17A5305f",
                    "visionOSSDKVersion": "26.0",
                    "visionOSSDKBuild": "23A5308g",
                    "visionOSSimulatorSDKVersion": "26.0",
                    "visionOSSimulatorSDKBuild": "23A5308g",
                },
                "laneArtifacts": [
                    {
                        "lane": "simulator",
                        "xctestrunDigest": str(digest("5")),
                        "testProductsDigest": str(digest("6")),
                        "applicationCodeDigest": str(digest("7")),
                    },
                    {
                        "lane": "device",
                        "xctestrunDigest": str(digest("8")),
                        "testProductsDigest": str(digest("9")),
                        "applicationCodeDigest": str(digest("a")),
                    },
                ],
            },
            payload["buildIdentity"],
        )
        self.assertFalse(hasattr(plan.build_identity, "worktree_clean"))
        self.assertFalse(hasattr(plan.build_identity, "xcode_version"))
        self.assertFalse(hasattr(plan.build_identity, "sdk_identity"))
        self.assertFalse(
            hasattr(plan.build_identity.lane_artifacts[0], "product_binary_digest")
        )
        payload["nodes"].clear()
        self.assertTrue(compiled_plan_payload(plan)["nodes"])
        self.assertEqual(plan.plan_digest, canonical_digest(compiled_plan_payload(plan)))


class CompilerFailureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()

    def assert_code(self, code: str, action) -> RegressionError:
        with self.assertRaises(RegressionError) as found:
            action()
        self.assertEqual(code, found.exception.code)
        return found.exception

    def test_preparation_state_is_produced_only_after_its_full_call_sequence(self) -> None:
        simulator, device = self.fixture.preparations
        trailing = operation_call(
            "call:prepare:sim:trailing",
            self.fixture.setup_operation.id,
        )
        malformed = replace(
            simulator,
            operations=simulator.operations + (trailing,),
            source_digest=digest("d"),
        )
        catalog = self.fixture.with_catalog(preparations=(malformed, device))

        self.assert_code(
            "compiler.preparation.producer.not_final",
            lambda: analyze_catalog(catalog, self.fixture.request()),
        )

    def test_selected_non_ready_scenario_reports_and_fails_with_typed_blockers(self) -> None:
        blocker = ImplementationGapBlocker(
            "playback-capture", "The exact capture producer is not implemented."
        )
        obligation = replace(
            self.fixture.either.obligations[0], produced_by_call=None
        )
        unavailable = replace(
            self.fixture.either,
            readiness=ContractReadiness.IMPLEMENTATION_GAP,
            blockers=(blocker,),
            operations=(),
            obligations=(obligation,),
            source_digest=digest("d"),
        )
        catalog = self.fixture.with_catalog(
            scenarios=(self.fixture.gate, unavailable, self.fixture.both)
        )
        request = self.fixture.request(
            selector=ScenarioSelector((unavailable.id,))
        )

        analysis = analyze_catalog(catalog, request)
        report = next(
            item
            for item in analysis.scenario_readiness
            if item.scenario_id == unavailable.id
        )
        self.assertIs(report.readiness, ContractReadiness.IMPLEMENTATION_GAP)
        self.assertEqual((blocker,), report.blockers)

        reviewed = accept_reviews(catalog, completed_review(catalog))
        with self.assertRaises(ContractNotReadyError) as raised:
            compile_run(reviewed, request)
        self.assertEqual((blocker,), raised.exception.blockers)
        self.assertIs(
            raised.exception.readiness, ContractReadiness.IMPLEMENTATION_GAP
        )

    def test_ready_scenario_resolves_non_ready_preparation_but_cannot_compile(self) -> None:
        blocker = ImplementationGapBlocker(
            "fixture-stage", "The simulator fixture stager is not implemented."
        )
        simulator = self.fixture.preparations[0]
        unavailable = replace(
            simulator,
            readiness=ContractReadiness.IMPLEMENTATION_GAP,
            blockers=(blocker,),
            produces=(
                replace(simulator.produces[0], produced_by_call=None),
            ),
            source_digest=digest("d"),
        )
        catalog = self.fixture.with_catalog(
            preparations=(unavailable, self.fixture.preparations[1])
        )
        request = self.fixture.request(
            selector=ScenarioSelector((self.fixture.either.id,)),
        )

        analysis = analyze_catalog(catalog, request)
        resolution = next(
            item
            for item in analysis.preparation_resolutions
            if item.preparation_id == unavailable.id
        )
        self.assertEqual(unavailable.id, resolution.preparation_id)
        report = next(
            item
            for item in analysis.preparation_readiness
            if item.preparation_id == unavailable.id
        )
        self.assertIs(report.readiness, ContractReadiness.IMPLEMENTATION_GAP)
        self.assertEqual((blocker,), report.blockers)

        reviewed = accept_reviews(catalog, completed_review(catalog))
        with self.assertRaises(PreparationNotReadyError) as raised:
            compile_run(reviewed, request)
        self.assertEqual(unavailable.id, raised.exception.preparation_id)
        self.assertEqual((blocker,), raised.exception.blockers)
        self.assertIs(
            raised.exception.readiness, ContractReadiness.IMPLEMENTATION_GAP
        )

    def test_evidence_schema_mismatch_and_cross_case_substitution_fail(self) -> None:
        wrong_schema = replace(
            self.fixture.either.obligations[0],
            evidence_schema=EvidenceSchema("image.snapshot@2"),
        )
        scenario = replace(
            self.fixture.either,
            obligations=(wrong_schema,),
            source_digest=digest("d"),
        )
        catalog = self.fixture.with_catalog(
            scenarios=(self.fixture.gate, scenario, self.fixture.both)
        )
        self.assert_code(
            "compiler.obligation.evidence.mismatch",
            lambda: analyze_catalog(catalog, self.fixture.request()),
        )

        wrong_oracle = replace(
            self.fixture.deterministic_oracle,
            evidence_schemas=frozenset(
                (
                    EvidenceSchemaPair(
                        EvidenceType("image.snapshot"),
                        EvidenceSchema("image.snapshot@2"),
                    ),
                )
            ),
            source_digest=digest("e"),
        )
        oracle_catalog = self.fixture.with_catalog(
            oracles=(wrong_oracle, self.fixture.agent_oracle)
        )
        self.assert_code(
            "compiler.oracle.evidence.mismatch",
            lambda: analyze_catalog(oracle_catalog, self.fixture.request()),
        )

        with self.assertRaises(RegressionError) as raised:
            replace(
                self.fixture.either,
                obligations=(
                    replace(
                        self.fixture.either.obligations[0],
                        case_key=CaseKey("undeclared"),
                    ),
                ),
            )
        self.assertEqual("contract.unknown_obligation_case", raised.exception.code)

    def test_missing_and_duplicate_main_gate_fail(self) -> None:
        no_gate = replace(
            self.fixture.gate,
            main_gate_for=frozenset(),
            source_digest=digest("d"),
        )
        missing_catalog = self.fixture.with_catalog(
            scenarios=(no_gate, self.fixture.either, self.fixture.both)
        )
        self.assert_code(
            "compiler.main.gate.missing",
            lambda: analyze_catalog(missing_catalog, self.fixture.request()),
        )

        duplicate = replace(
            self.fixture.either,
            main_gate_for=frozenset((BoundLane.SIMULATOR,)),
            source_digest=digest("e"),
        )
        duplicate_catalog = self.fixture.with_catalog(
            scenarios=(self.fixture.gate, duplicate, self.fixture.both)
        )
        self.assert_code(
            "compiler.main.gate.duplicate",
            lambda: analyze_catalog(duplicate_catalog, self.fixture.request()),
        )

    def test_main_gate_with_applicable_predecessor_fails(self) -> None:
        before = self.fixture._scenario(
            "scenario:bootstrap:before",
            "journey:bootstrap",
            self.fixture.promises[0].id,
            LaneRequirement.BOTH,
            "call:bootstrap:before",
            "obligation:bootstrap:before",
            self.fixture.deterministic_oracle.id,
            Constant(True),
            frozenset(),
            (),
            "d",
        )
        journey = replace(
            self.fixture.journeys[0],
            scenario_refs=(before.id, self.fixture.gate.id),
            ordering=((before.id, self.fixture.gate.id),),
            source_digest=digest("e"),
        )
        catalog = self.fixture.with_catalog(
            journeys=(journey, self.fixture.journeys[1]),
            scenarios=(before, self.fixture.gate, self.fixture.either, self.fixture.both),
        )
        self.assert_code(
            "compiler.main.gate.has.predecessor",
            lambda: analyze_catalog(catalog, self.fixture.request()),
        )

    def test_uncovered_and_excluded_target_promises_fail(self) -> None:
        uncovered = promise("promise:orphan:c01", "d")
        catalog = self.fixture.with_catalog(
            promises=self.fixture.promises + (uncovered,)
        )
        self.assert_code(
            "compiler.uncovered.target.promise",
            lambda: analyze_catalog(catalog, self.fixture.request()),
        )

        excluded = promise(
            "promise:subjective:c01", "e", AutomationScope.EXCLUDED
        )
        excluded_catalog = self.fixture.with_catalog(
            promises=self.fixture.promises + (excluded,)
        )
        full_analysis = analyze_catalog(
            excluded_catalog, self.fixture.request()
        )
        self.assertNotIn(excluded.id, full_analysis.target_promises)
        request = self.fixture.request(
            selector=PromiseSelector((excluded.id,))
        )
        self.assert_code(
            "compiler.excluded.target.promise",
            lambda: analyze_catalog(excluded_catalog, request),
        )

    def test_unknown_unreviewed_stale_and_wrong_type_facts_fail(self) -> None:
        cases = (
            (
                "compiler.unknown.reviewed.fact",
                ReviewedFact(
                    FactID("fact:unknown.value"), True, digest("1"), digest("2")
                ),
            ),
            (
                "compiler.unreviewed.fact",
                ReviewedFact(
                    self.fixture.fact.id,
                    True,
                    self.fixture.fact.source_digest,
                    None,
                ),
            ),
            (
                "compiler.fact.source.mismatch",
                ReviewedFact(
                    self.fixture.fact.id, True, digest("1"), digest("2")
                ),
            ),
            (
                "compiler.fact.type.mismatch",
                ReviewedFact(
                    self.fixture.fact.id,
                    1,
                    self.fixture.fact.source_digest,
                    digest("2"),
                ),
            ),
        )
        for code, fact in cases:
            with self.subTest(code=code):
                request = self.fixture.request(reviewed_facts=(fact,))
                self.assert_code(
                    code,
                    lambda request=request: analyze_catalog(
                        self.fixture.catalog, request
                    ),
                )

    def test_zero_and_two_preparation_producers_fail(self) -> None:
        missing_catalog = self.fixture.with_catalog(
            preparations=(self.fixture.preparations[0],)
        )
        self.assert_code(
            "compiler.preparation.producer.missing",
            lambda: analyze_catalog(missing_catalog, self.fixture.request()),
        )

        duplicate = self.fixture._preparation(BoundLane.DEVICE, "duplicate", "f")
        duplicate_catalog = self.fixture.with_catalog(
            preparations=self.fixture.preparations + (duplicate,)
        )
        self.assert_code(
            "compiler.preparation.producer.ambiguous",
            lambda: analyze_catalog(duplicate_catalog, self.fixture.request()),
        )

    def test_preparation_cycle_and_schema_mismatch_fail(self) -> None:
        cyclic = replace(
            self.fixture.preparations[0],
            prerequisites=(self.fixture.state,),
            source_digest=digest("f"),
        )
        cycle_catalog = self.fixture.with_catalog(
            preparations=(cyclic, self.fixture.preparations[1])
        )
        self.assert_code(
            "compiler.preparation.cycle",
            lambda: analyze_catalog(cycle_catalog, self.fixture.request()),
        )

        mismatched = StateRequirement(
            self.fixture.state.key, StateSchema("session.other@1")
        )
        journey = replace(
            self.fixture.journeys[1],
            shared_state=(mismatched,),
            source_digest=digest("f"),
        )
        mismatch_catalog = self.fixture.with_catalog(
            journeys=(self.fixture.journeys[0], journey)
        )
        self.assert_code(
            "compiler.preparation.schema.mismatch",
            lambda: analyze_catalog(mismatch_catalog, self.fixture.request()),
        )

    def test_operation_lane_and_requested_lane_mismatch_fail(self) -> None:
        simulator_only = replace(
            self.fixture.evidence_operation,
            lanes=frozenset((BoundLane.SIMULATOR,)),
            source_digest=digest("f"),
        )
        catalog = self.fixture.with_catalog(
            operations=(self.fixture.setup_operation, simulator_only)
        )
        self.assert_code(
            "compiler.operation.lane.mismatch",
            lambda: analyze_catalog(catalog, self.fixture.request()),
        )

        single_lane = self.fixture.request(lanes=(BoundLane.SIMULATOR,))
        self.assert_code(
            "compiler.scenario.lane.unavailable",
            lambda: analyze_catalog(self.fixture.catalog, single_lane),
        )

    def test_journey_cycle_is_defended_during_analysis(self) -> None:
        journey = replace(
            self.fixture.journeys[1],
            ordering=(
                (self.fixture.either.id, self.fixture.both.id),
                (self.fixture.both.id, self.fixture.either.id),
            ),
            source_digest=digest("f"),
        )
        catalog = self.fixture.with_catalog(
            journeys=(self.fixture.journeys[0], journey)
        )
        self.assert_code(
            "compiler.journey.cycle",
            lambda: analyze_catalog(catalog, self.fixture.request()),
        )

    def test_agent_environment_is_required_only_for_selected_agent_oracle(self) -> None:
        missing = self.fixture.request(include_agent=False)
        self.assert_code(
            "compiler.agent.environment.missing",
            lambda: analyze_catalog(self.fixture.catalog, missing),
        )
        deterministic_only = self.fixture.request(
            selector=ScenarioSelector((self.fixture.either.id,)),
            include_agent=False,
        )
        analysis = analyze_catalog(self.fixture.catalog, deterministic_only)
        self.assertFalse(analysis.requires_agent_environment)

    def test_toolchain_identity_requires_every_version_and_build_value(self) -> None:
        for field_name in (
            "xcode_version",
            "xcode_build",
            "visionos_sdk_version",
            "visionos_sdk_build",
            "visionos_simulator_sdk_version",
            "visionos_simulator_sdk_build",
        ):
            with self.subTest(field=field_name):
                self.assert_code(
                    "plan.empty.value",
                    lambda: replace(
                        toolchain_identity(),
                        **{field_name: ""},
                    ),
                )

    def test_build_identity_requires_dual_lane_noncolliding_artifacts(self) -> None:
        def identity(artifacts: tuple[LaneBuildArtifact, ...]) -> BuildIdentity:
            return BuildIdentity(
                "com.example.Enchron",
                "abc",
                digest("1"),
                digest("2"),
                toolchain_identity(),
                artifacts,
            )

        simulator = lane_build_artifact(BoundLane.SIMULATOR, "3", "4", "5")
        self.assert_code(
            "plan.missing.build.artifact",
            lambda: identity((simulator,)),
        )
        self.assert_code(
            "plan.duplicate.build.artifact",
            lambda: identity(
                (
                    simulator,
                    lane_build_artifact(BoundLane.SIMULATOR, "6", "7", "8"),
                ),
            ),
        )
        collisions = (
            (
                "xctestrunDigest",
                lane_build_artifact(BoundLane.DEVICE, "3", "7", "8"),
            ),
            (
                "testProductsDigest",
                lane_build_artifact(BoundLane.DEVICE, "6", "4", "8"),
            ),
            (
                "applicationCodeDigest",
                lane_build_artifact(BoundLane.DEVICE, "6", "7", "5"),
            ),
        )
        for location, device in collisions:
            with self.subTest(location=location):
                error = self.assert_code(
                    "plan.shared.build.artifact.digest",
                    lambda: identity((simulator, device)),
                )
                self.assertEqual(
                    f"buildIdentity.laneArtifacts.{location}", error.location
                )

    def test_old_or_incomplete_reviews_cannot_create_capability(self) -> None:
        completed = completed_review(self.fixture.catalog)
        changed_promise = replace(
            self.fixture.promises[0], source_digest=digest("f")
        )
        changed = self.fixture.with_catalog(
            promises=(changed_promise, self.fixture.promises[1])
        )
        self.assert_code(
            "review.catalog.digest.mismatch",
            lambda: accept_reviews(changed, completed),
        )

        incomplete = CompletedReview(
            self.fixture.catalog.digest,
            completed.packets[:-1],
            tuple(
                item
                for item in completed.receipts
                if item.packet_digest
                in {packet.packet_digest for packet in completed.packets[:-1]}
            ),
        )
        self.assert_code(
            "review.catalog.coverage.missing",
            lambda: accept_reviews(self.fixture.catalog, incomplete),
        )

    def test_compile_rejects_forged_review_receipt_digest_for_fact(self) -> None:
        completed = completed_review(self.fixture.catalog)
        reviewed = accept_reviews(self.fixture.catalog, completed)
        forged = self.fixture.request(
            reviewed_facts=(
                ReviewedFact(
                    self.fixture.fact.id,
                    True,
                    self.fixture.fact.source_digest,
                    digest("f"),
                ),
            )
        )

        analyze_catalog(self.fixture.catalog, forged)
        self.assert_code(
            "compiler.fact.review.receipt.mismatch",
            lambda: compile_run(reviewed, forged),
        )

    def test_review_scope_and_estimated_usage_are_rechecked(self) -> None:
        completed = completed_review(self.fixture.catalog)
        first = completed.packets[0]
        wrong_scope_units = tuple(
            replace(unit, scope="wrong") for unit in first.units
        )
        wrong_scope_packet = ReviewPacket(
            first.reviewer,
            "wrong",
            wrong_scope_units,
            first.approved_budget,
            first.policy_digest,
        )
        old_receipt = next(
            item
            for item in completed.receipts
            if item.packet_digest == first.packet_digest
        )
        wrong_scope_receipt = ReviewReceipt(
            wrong_scope_packet.packet_digest,
            wrong_scope_packet.reviewer,
            old_receipt.actor,
            old_receipt.report_digest,
            True,
            old_receipt.usage,
            old_receipt.issued_at,
            _assessment_digest(
                wrong_scope_packet.reviewer, wrong_scope_packet.packet_digest
            ),
        )
        wrong_scope = CompletedReview(
            self.fixture.catalog.digest,
            (wrong_scope_packet,) + completed.packets[1:],
            (wrong_scope_receipt,)
            + tuple(
                item
                for item in completed.receipts
                if item.packet_digest != first.packet_digest
            ),
        )
        self.assert_code(
            "review.catalog.unit.mismatch",
            lambda: accept_reviews(self.fixture.catalog, wrong_scope),
        )

        lowered_usage = ReviewUsage(
            (
                BudgetAmount(BudgetUnit.INPUT_TOKENS, 1),
                BudgetAmount(BudgetUnit.REVIEW_ITEMS, 1),
            )
        )
        lowered_packet = ReviewPacket(
            first.reviewer,
            first.scope,
            tuple(
                replace(unit, estimated_usage=lowered_usage)
                for unit in first.units
            ),
            first.approved_budget,
            first.policy_digest,
        )
        lowered = CompletedReview(
            self.fixture.catalog.digest,
            (lowered_packet,) + completed.packets[1:],
            completed.receipts,
        )
        self.assertEqual(first.packet_digest, lowered_packet.packet_digest)
        self.assert_code(
            "review.catalog.unit.mismatch",
            lambda: accept_reviews(self.fixture.catalog, lowered),
        )

    def test_compile_run_rejects_draft_catalog(self) -> None:
        self.assert_code(
            "compiler.review.required",
            lambda: compile_run(self.fixture.catalog, self.fixture.request()),
        )

    def test_selector_and_request_collections_reject_duplicates(self) -> None:
        self.assert_code(
            "plan.duplicate.selector",
            lambda: PromiseSelector(
                (self.fixture.promises[0].id, self.fixture.promises[0].id)
            ),
        )
        self.assert_code(
            "plan.duplicate.lane",
            lambda: self.fixture.request(
                lanes=(BoundLane.SIMULATOR, BoundLane.SIMULATOR),
            ),
        )


class CompilerCompatibilityTests(unittest.TestCase):
    def test_plan_and_compiler_parse_as_python_39(self) -> None:
        for relative in (
            "regression/core/plan.py",
            "regression/core/compiler.py",
            "rules/tests/test_regression_core_compiler.py",
        ):
            with self.subTest(path=relative):
                path = SCRIPTS / relative
                ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
