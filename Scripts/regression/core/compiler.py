from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Dict, FrozenSet, Iterable, List, Mapping, Optional, Sequence, Set, Tuple

from .applicability import (
    ReviewedFact,
    evaluate_applicability,
    referenced_facts,
    reviewed_facts_digest,
)
from .capability import AllowedOperationCall
from .contracts import (
    ArgumentValueKind,
    AutomationScope,
    BoundLane,
    ContractBlocker,
    ContractReadiness,
    DraftCatalog,
    EvidenceSchemaPair,
    FactDeclaration,
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
    StateRequirement,
)
from .errors import RegressionError
from .expression import validate_expression_semantics
from .ids import (
    Digest,
    FactID,
    JourneyID,
    NodeID,
    PreparationID,
    PromiseID,
    ScenarioID,
)
from .plan import (
    BothJoinNode,
    CatalogAnalysis,
    CatalogMainGate,
    CompileRequest,
    CompiledRunPlan,
    EvaluationBinding,
    FullSelector,
    LaneGateDependency,
    MainGateBinding,
    OracleEvaluationBinding,
    PreparationBinding,
    PreparationRequirementBinding,
    PreparationResolution,
    PreparationReadinessAnalysis,
    PromiseSelector,
    RunPlanNode,
    RubricEvaluationBinding,
    ScenarioAttemptNode,
    ScenarioDependency,
    ScenarioReadinessAnalysis,
    ScenarioSelector,
)
from .review import CompletedReview, ReviewClass, ReviewUnitKind
from .review_catalog import verify_completed_catalog_reviews
from .scheduler import CriticalCost, PlannedNode, compute_critical_costs


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


class ContractNotReadyError(RegressionError):
    def __init__(
        self,
        scenario_id: ScenarioID,
        readiness: ContractReadiness,
        blockers: Tuple[ContractBlocker, ...],
    ) -> None:
        self.scenario_id = scenario_id
        self.readiness = readiness
        self.blockers = tuple(blockers)
        super().__init__(
            "compiler.scenario.not.ready",
            str(scenario_id),
            f"selected Scenario is {readiness.value} with {len(blockers)} typed blocker(s)",
        )


class PreparationNotReadyError(RegressionError):
    def __init__(
        self,
        preparation_id: PreparationID,
        readiness: ContractReadiness,
        blockers: Tuple[ContractBlocker, ...],
    ) -> None:
        self.preparation_id = preparation_id
        self.readiness = readiness
        self.blockers = tuple(blockers)
        super().__init__(
            "compiler.preparation.not.ready",
            str(preparation_id),
            f"required Preparation is {readiness.value} with {len(blockers)} typed blocker(s)",
        )


def _lane_sort_key(lane: BoundLane) -> int:
    return 0 if lane is BoundLane.SIMULATOR else 1


def _contract_lanes(requirement: LaneRequirement) -> FrozenSet[BoundLane]:
    if requirement is LaneRequirement.SIMULATOR:
        return frozenset((BoundLane.SIMULATOR,))
    if requirement is LaneRequirement.DEVICE:
        return frozenset((BoundLane.DEVICE,))
    if requirement in (LaneRequirement.EITHER, LaneRequirement.BOTH):
        return frozenset((BoundLane.SIMULATOR, BoundLane.DEVICE))
    raise _error(
        "compiler.invalid.scenario.lane",
        "scenario.lane",
        "Scenario has an invalid lane requirement",
    )


_REVIEWED_TOKEN = object()


@dataclass(frozen=True, init=False)
class ReviewedCatalog:
    catalog: DraftCatalog
    completed_review: CompletedReview

    def __init__(
        self,
        catalog: DraftCatalog,
        completed_review: CompletedReview,
        token: object = None,
    ) -> None:
        if token is not _REVIEWED_TOKEN:
            raise _error(
                "compiler.review.required",
                "reviewedCatalog",
                "ReviewedCatalog values can be created only by accept_reviews",
            )
        object.__setattr__(self, "catalog", catalog)
        object.__setattr__(self, "completed_review", completed_review)

    @property
    def catalog_digest(self) -> Digest:
        return self.catalog.digest

    @property
    def catalog_gate_digest(self) -> Digest:
        return self.completed_review.digest

    @property
    def digest(self) -> Digest:
        return self.catalog.digest


@dataclass(frozen=True)
class _CatalogIndex:
    catalog: DraftCatalog
    promises: Mapping[PromiseID, PromiseContract]
    facts: Mapping[FactID, FactDeclaration]
    operations: Mapping[object, OperationContract]
    oracles: Mapping[object, OracleContract]
    rubrics: Mapping[object, RubricContract]
    preparations: Mapping[PreparationID, PreparationContract]
    journeys: Mapping[JourneyID, JourneyContract]
    scenarios: Mapping[ScenarioID, ScenarioContract]
    predecessors: Mapping[ScenarioID, Tuple[ScenarioID, ...]]
    shared_requirements: Mapping[JourneyID, Tuple[StateRequirement, ...]]


@dataclass(frozen=True)
class _AnalysisState:
    public: CatalogAnalysis
    index: _CatalogIndex
    selected: Tuple[ScenarioID, ...]
    candidate_lanes: Mapping[ScenarioID, Tuple[BoundLane, ...]]
    predecessors: Mapping[ScenarioID, Tuple[ScenarioID, ...]]
    gate_scenarios: Mapping[BoundLane, ScenarioID]
    preparation_by_resolution: Mapping[
        Tuple[str, BoundLane, object, object], PreparationID
    ]
    used_preparations: Tuple[PreparationID, ...]


def accept_reviews(
    catalog: DraftCatalog, completed: CompletedReview
) -> ReviewedCatalog:
    if not isinstance(catalog, DraftCatalog):
        raise _error(
            "compiler.invalid.catalog", "catalog", "expected DraftCatalog"
        )
    if not isinstance(completed, CompletedReview):
        raise _error(
            "compiler.invalid.review",
            "completedReview",
            "expected CompletedReview",
        )
    _catalog_index(catalog)
    verify_completed_catalog_reviews(catalog, completed)
    return ReviewedCatalog(catalog, completed, _REVIEWED_TOKEN)


def analyze_catalog(catalog: DraftCatalog, request: CompileRequest) -> CatalogAnalysis:
    return _analyze_catalog(catalog, request, require_ready=False).public


def compile_run(
    catalog: ReviewedCatalog, request: CompileRequest
) -> CompiledRunPlan:
    if not isinstance(catalog, ReviewedCatalog):
        raise _error(
            "compiler.review.required",
            "catalog",
            "compile_run accepts ReviewedCatalog only",
        )
    verify_completed_catalog_reviews(catalog.catalog, catalog.completed_review)
    state = _analyze_catalog(catalog.catalog, request, require_ready=True)
    _validate_reviewed_fact_receipts(
        request.reviewed_facts, catalog.completed_review
    )
    return _compile_plan(catalog, request, state)


def _catalog_index(catalog: DraftCatalog) -> _CatalogIndex:
    rebuilt = DraftCatalog(
        catalog.promises,
        catalog.facts,
        catalog.operations,
        catalog.oracles,
        catalog.rubrics,
        catalog.preparations,
        catalog.journeys,
        catalog.scenarios,
    )
    if rebuilt.digest != catalog.digest:
        raise _error(
            "compiler.catalog.digest.mismatch",
            "catalog.catalogDigest",
            "Catalog digest does not match its current contract leaves",
        )
    groups = (
        ("promise", catalog.promises, PromiseContract),
        ("fact", catalog.facts, FactDeclaration),
        ("operation", catalog.operations, OperationContract),
        ("oracle", catalog.oracles, OracleContract),
        ("rubric", catalog.rubrics, RubricContract),
        ("preparation", catalog.preparations, PreparationContract),
        ("journey", catalog.journeys, JourneyContract),
        ("scenario", catalog.scenarios, ScenarioContract),
    )
    indexes: Dict[str, Dict[object, object]] = {}
    all_ids: Set[object] = set()
    for name, values, expected_type in groups:
        by_id: Dict[object, object] = {}
        for index, value in enumerate(values):
            if not isinstance(value, expected_type):
                raise _error(
                    "compiler.invalid.catalog.contract",
                    f"catalog.{name}[{index}]",
                    f"expected {expected_type.__name__}",
                )
            if value.id in by_id or value.id in all_ids:
                raise _error(
                    "compiler.duplicate.catalog.id",
                    str(value.id),
                    "Catalog contract IDs must be globally unique",
                )
            by_id[value.id] = value
            all_ids.add(value.id)
        indexes[name] = by_id

    promises = indexes["promise"]
    facts = indexes["fact"]
    operations = indexes["operation"]
    oracles = indexes["oracle"]
    rubrics = indexes["rubric"]
    preparations = indexes["preparation"]
    journeys = indexes["journey"]
    scenarios = indexes["scenario"]
    if not promises:
        raise _error(
            "compiler.empty.catalog", "catalog.promises", "Catalog has no Promise"
        )
    if not scenarios:
        raise _error(
            "compiler.empty.catalog", "catalog.scenarios", "Catalog has no Scenario"
        )

    call_ids = set()
    for owner in tuple(preparations.values()) + tuple(scenarios.values()):
        for call in owner.operations:
            if call.call_id in call_ids:
                raise _error(
                    "compiler.duplicate.call",
                    str(call.call_id),
                    "CallID must be globally unique",
                )
            call_ids.add(call.call_id)
            if call.operation not in operations:
                raise _error(
                    "compiler.unknown.operation",
                    str(call.call_id),
                    f"unknown Operation {call.operation}",
                )

    for preparation in preparations.values():
        calls = {item.call_id: item for item in preparation.operations}
        produced_keys: Dict[object, object] = {}
        for declaration in preparation.produces:
            previous_schema = produced_keys.setdefault(
                declaration.key, declaration.schema
            )
            if previous_schema != declaration.schema:
                raise _error(
                    "compiler.state.schema.conflict",
                    str(preparation.id),
                    f"state key {declaration.key} has more than one schema",
                )
            if declaration.produced_by_call is not None:
                producer_call = calls.get(declaration.produced_by_call)
                if producer_call is None:
                    raise _error(
                        "compiler.preparation.producer.call.missing",
                        str(preparation.id),
                        f"unknown producer call {declaration.produced_by_call}",
                    )
                producer_operation = operations[producer_call.operation]
                if producer_operation.role is not OperationRole.SETUP:
                    raise _error(
                        "compiler.preparation.producer.role",
                        str(preparation.id),
                        "Preparation state must be produced by a setup Operation",
                    )
                if producer_call.call_id != preparation.operations[-1].call_id:
                    raise _error(
                        "compiler.preparation.producer.not_final",
                        str(preparation.id),
                        "Preparation state must be produced after its complete ordered call transcript",
                    )

    claimed: Dict[ScenarioID, JourneyID] = {}
    predecessors: Dict[ScenarioID, List[ScenarioID]] = {
        item: [] for item in scenarios
    }
    shared_requirements: Dict[JourneyID, Tuple[StateRequirement, ...]] = {}
    for journey in journeys.values():
        members = set(journey.scenario_refs)
        for scenario_id in journey.scenario_refs:
            scenario = scenarios.get(scenario_id)
            if scenario is None:
                raise _error(
                    "compiler.unknown.journey.scenario",
                    str(journey.id),
                    f"unknown Scenario {scenario_id}",
                )
            if scenario.journey != journey.id:
                raise _error(
                    "compiler.scenario.journey.mismatch",
                    str(scenario_id),
                    f"Scenario declares {scenario.journey}",
                )
            previous = claimed.get(scenario_id)
            if previous is not None:
                raise _error(
                    "compiler.duplicate.journey.membership",
                    str(scenario_id),
                    f"Scenario belongs to {previous} and {journey.id}",
                )
            claimed[scenario_id] = journey.id
        for before, after in journey.ordering:
            if before not in members or after not in members:
                raise _error(
                    "compiler.external.journey.edge",
                    str(journey.id),
                    "Journey ordering edges must stay within the Journey",
                )
            predecessors[after].append(before)
        shared_requirements[journey.id] = tuple(journey.shared_state)
    unclaimed = set(scenarios) - set(claimed)
    if unclaimed:
        raise _error(
            "compiler.unclaimed.scenario",
            str(sorted(unclaimed, key=str)[0]),
            "Scenario is absent from Journey grouping",
        )
    _validate_journey_acyclic(predecessors)

    obligation_ids = set()
    for scenario in scenarios.values():
        invalid_gate_lanes = scenario.main_gate_for - _contract_lanes(scenario.lane)
        if invalid_gate_lanes:
            raise _error(
                "compiler.main.gate.lane.mismatch",
                str(scenario.id),
                "MainGate claims a lane on which the Scenario cannot execute",
            )
        for promise_id in scenario.promise_refs:
            promise = promises.get(promise_id)
            if promise is None:
                raise _error(
                    "compiler.unknown.promise",
                    str(scenario.id),
                    f"unknown Promise {promise_id}",
                )
            if promise.scope is AutomationScope.EXCLUDED:
                raise _error(
                    "compiler.excluded.promise.in.scenario",
                    str(scenario.id),
                    f"Scenario references excluded Promise {promise_id}",
                )
        unknown_facts = referenced_facts(scenario.applicability) - frozenset(facts)
        if unknown_facts:
            raise _error(
                "compiler.unknown.catalog.fact",
                str(scenario.id),
                "unknown applicability Fact(s): "
                + ", ".join(sorted(unknown_facts, key=str)),
            )
        call_by_id = {item.call_id: item for item in scenario.operations}
        for obligation in scenario.obligations:
            if obligation.id in obligation_ids:
                raise _error(
                    "compiler.duplicate.obligation",
                    str(obligation.id),
                    "ObligationID must be globally unique",
                )
            obligation_ids.add(obligation.id)
            pair = EvidenceSchemaPair(
                obligation.evidence_type, obligation.evidence_schema
            )
            call = (
                None
                if obligation.produced_by_call is None
                else call_by_id.get(obligation.produced_by_call)
            )
            if scenario.readiness is ContractReadiness.READY and call is None:
                raise _error(
                    "compiler.obligation.producer.missing",
                    str(obligation.id),
                    "obligation producer is absent from Scenario calls",
                )
            if call is not None:
                producer = operations[call.operation]
                if producer.role in (
                    OperationRole.SETUP,
                    OperationRole.DIAGNOSTIC_BYPASS,
                ):
                    raise _error(
                        "compiler.obligation.producer.role",
                        str(obligation.id),
                        f"{producer.role.value} Operation cannot produce coverage",
                    )
                if pair not in producer.evidence_schemas:
                    raise _error(
                        "compiler.obligation.evidence.mismatch",
                        str(obligation.id),
                        "producer does not support the obligation evidence pair",
                    )
            oracle = oracles.get(obligation.oracle)
            if oracle is None:
                raise _error(
                    "compiler.unknown.oracle",
                    str(obligation.id),
                    f"unknown Oracle {obligation.oracle}",
                )
            if pair not in oracle.evidence_schemas:
                raise _error(
                    "compiler.oracle.evidence.mismatch",
                    str(obligation.id),
                    "Oracle does not support the obligation evidence pair",
                )
            if obligation.rubric not in rubrics:
                raise _error(
                    "compiler.unknown.rubric",
                    str(obligation.id),
                    f"unknown Rubric {obligation.rubric}",
                )

    return _CatalogIndex(
        catalog,
        promises,
        facts,
        operations,
        oracles,
        rubrics,
        preparations,
        journeys,
        scenarios,
        {key: tuple(sorted(value, key=str)) for key, value in predecessors.items()},
        shared_requirements,
    )


def _validate_journey_acyclic(
    predecessors: Mapping[ScenarioID, Tuple[ScenarioID, ...]]
) -> None:
    complete: Set[ScenarioID] = set()
    active: List[ScenarioID] = []

    def visit(scenario_id: ScenarioID) -> None:
        if scenario_id in complete:
            return
        if scenario_id in active:
            start = active.index(scenario_id)
            cycle = active[start:] + [scenario_id]
            raise _error(
                "compiler.journey.cycle",
                str(scenario_id),
                "Journey dependency cycle: " + " -> ".join(map(str, cycle)),
            )
        active.append(scenario_id)
        for predecessor in predecessors[scenario_id]:
            visit(predecessor)
        active.pop()
        complete.add(scenario_id)

    for scenario_id in sorted(predecessors, key=str):
        visit(scenario_id)


def _analyze_catalog(
    catalog: DraftCatalog,
    request: CompileRequest,
    require_ready: bool,
) -> _AnalysisState:
    if not isinstance(catalog, DraftCatalog):
        raise _error(
            "compiler.invalid.catalog", "catalog", "expected DraftCatalog"
        )
    if not isinstance(request, CompileRequest):
        raise _error(
            "compiler.invalid.request", "request", "expected CompileRequest"
        )
    index = _catalog_index(catalog)
    _validate_reviewed_facts(index, request.reviewed_facts)

    applicable = {
        scenario.id: evaluate_applicability(
            scenario.applicability, request.reviewed_facts
        )
        for scenario in index.scenarios.values()
    }
    target_promises, target_scenarios = _select_targets(index, request, applicable)
    gate_scenarios = _select_main_gates(index, request, applicable)
    selected = set(target_scenarios) | set(gate_scenarios.values())

    def include_predecessors(scenario_id: ScenarioID) -> None:
        for predecessor in index.predecessors[scenario_id]:
            include_predecessors(predecessor)
            if applicable[predecessor]:
                selected.add(predecessor)

    for scenario_id in tuple(sorted(selected, key=str)):
        include_predecessors(scenario_id)

    if require_ready:
        for scenario_id in sorted(selected, key=str):
            scenario = index.scenarios[scenario_id]
            if scenario.readiness is not ContractReadiness.READY:
                raise ContractNotReadyError(
                    scenario.id, scenario.readiness, scenario.blockers
                )

    dependencies = _filtered_dependencies(index.predecessors, selected)
    candidate_lanes = {
        scenario_id: _scenario_candidate_lanes(
            index.scenarios[scenario_id], request.requested_lanes
        )
        for scenario_id in selected
    }
    _validate_main_gate_predecessors(
        index, applicable, gate_scenarios
    )
    _validate_scenarios(index, selected, candidate_lanes)

    (
        resolutions,
        preparation_by_resolution,
        used_preparations,
    ) = _resolve_preparations(
        index, selected, candidate_lanes, require_ready=require_ready
    )
    executable_selected = {
        item
        for item in selected
        if index.scenarios[item].readiness is ContractReadiness.READY
    }
    requires_agent = _requires_agent_environment(index, executable_selected)
    if requires_agent and request.evidence_environment_identity.agent_environment is None:
        raise _error(
            "compiler.agent.environment.missing",
            "request.evidenceEnvironmentIdentity.agentEnvironment",
            "selected Scenarios use an Agent Oracle",
        )

    public = CatalogAnalysis(
        catalog.digest,
        request.selector,
        reviewed_facts_digest(request.reviewed_facts),
        request.requested_lanes,
        tuple(target_promises),
        tuple(target_scenarios),
        tuple(
            sorted(
                (scenario_id for scenario_id, value in applicable.items() if value),
                key=str,
            )
        ),
        tuple(selected),
        tuple(ScenarioDependency(before, after) for before, after in dependencies),
        tuple(resolutions),
        tuple(
            CatalogMainGate(lane, scenario_id)
            for lane, scenario_id in sorted(
                gate_scenarios.items(), key=lambda item: _lane_sort_key(item[0])
            )
        ),
        tuple(
            ScenarioReadinessAnalysis(
                scenario.id, scenario.readiness, scenario.blockers
            )
            for scenario in catalog.scenarios
        ),
        tuple(
            PreparationReadinessAnalysis(
                preparation.id, preparation.readiness, preparation.blockers
            )
            for preparation in catalog.preparations
        ),
        requires_agent,
    )
    return _AnalysisState(
        public,
        index,
        tuple(sorted(selected, key=str)),
        candidate_lanes,
        _dependency_map(selected, dependencies),
        gate_scenarios,
        preparation_by_resolution,
        tuple(sorted(used_preparations, key=str)),
    )


def _validate_reviewed_facts(
    index: _CatalogIndex, reviewed_facts: Tuple[ReviewedFact, ...]
) -> None:
    by_id = {item.id: item for item in reviewed_facts}
    unknown = set(by_id) - set(index.facts)
    if unknown:
        raise _error(
            "compiler.unknown.reviewed.fact",
            str(sorted(unknown, key=str)[0]),
            "reviewed Fact is absent from the Catalog",
        )
    for fact in by_id.values():
        declaration = index.facts[fact.id]
        if fact.review_receipt_digest is None:
            raise _error(
                "compiler.unreviewed.fact",
                str(fact.id),
                "Fact value has no review receipt",
            )
        if fact.source_digest != declaration.source_digest:
            raise _error(
                "compiler.fact.source.mismatch",
                str(fact.id),
                "Fact sourceDigest does not match the current Catalog declaration",
            )
        if not _fact_value_matches(declaration.value_type, fact.value):
            raise _error(
                "compiler.fact.type.mismatch",
                str(fact.id),
                f"Fact value does not match {declaration.value_type.value}",
            )
    referenced = set()
    for scenario in index.scenarios.values():
        referenced.update(referenced_facts(scenario.applicability))
    missing = referenced - set(by_id)
    if missing:
        raise _error(
            "compiler.reviewed.fact.missing",
            str(sorted(missing, key=str)[0]),
            "applicability Fact is absent from the reviewed Fact set",
        )


def _validate_reviewed_fact_receipts(
    reviewed_facts: Tuple[ReviewedFact, ...], completed: CompletedReview
) -> None:
    receipts_by_packet = {
        receipt.packet_digest: receipt
        for receipt in completed.receipts
        if receipt.reviewer is ReviewClass.HUMAN_COVERAGE and receipt.accepted
    }
    receipts_by_fact = {}
    for packet in completed.packets:
        if packet.reviewer is not ReviewClass.HUMAN_COVERAGE:
            continue
        receipt = receipts_by_packet.get(packet.packet_digest)
        if receipt is None:
            continue
        for unit in packet.units:
            if unit.kind is ReviewUnitKind.FACT:
                receipts_by_fact[unit.ref] = receipt.receipt_digest

    for fact in reviewed_facts:
        expected = receipts_by_fact.get(str(fact.id))
        if expected is None or fact.review_receipt_digest != expected:
            raise _error(
                "compiler.fact.review.receipt.mismatch",
                str(fact.id),
                "Fact reviewReceiptDigest does not match the accepted "
                "human-coverage receipt that covers this Fact",
            )


def _fact_value_matches(kind: ArgumentValueKind, value: object) -> bool:
    if kind is ArgumentValueKind.BOOLEAN:
        return type(value) is bool
    if kind is ArgumentValueKind.INTEGER:
        return type(value) is int
    if kind is ArgumentValueKind.STRING:
        return isinstance(value, str)
    return False


def _select_targets(
    index: _CatalogIndex,
    request: CompileRequest,
    applicable: Mapping[ScenarioID, bool],
) -> Tuple[Tuple[PromiseID, ...], Tuple[ScenarioID, ...]]:
    selector = request.selector
    if isinstance(selector, FullSelector):
        target_promises = tuple(
            sorted(
                (
                    promise.id
                    for promise in index.promises.values()
                    if promise.scope is AutomationScope.INCLUDED
                ),
                key=str,
            )
        )
    elif isinstance(selector, PromiseSelector):
        target_promises = selector.promise_ids
        for promise_id in target_promises:
            promise = index.promises.get(promise_id)
            if promise is None:
                raise _error(
                    "compiler.unknown.target.promise",
                    str(promise_id),
                    "selector names an unknown Promise",
                )
            if promise.scope is AutomationScope.EXCLUDED:
                raise _error(
                    "compiler.excluded.target.promise",
                    str(promise_id),
                    "excluded Promise cannot enter a RunPlan",
                )
    elif isinstance(selector, ScenarioSelector):
        for scenario_id in selector.scenario_ids:
            scenario = index.scenarios.get(scenario_id)
            if scenario is None:
                raise _error(
                    "compiler.unknown.target.scenario",
                    str(scenario_id),
                    "selector names an unknown Scenario",
                )
            if not applicable[scenario_id]:
                raise _error(
                    "compiler.inapplicable.target.scenario",
                    str(scenario_id),
                    "an explicitly selected Scenario is not applicable",
                )
        return (), selector.scenario_ids
    else:
        raise TypeError(f"unsupported selector: {type(selector).__name__}")

    target_scenarios = []
    for promise_id in target_promises:
        covering = tuple(
            scenario.id
            for scenario in index.scenarios.values()
            if promise_id in scenario.promise_refs and applicable[scenario.id]
        )
        if not covering:
            raise _error(
                "compiler.uncovered.target.promise",
                str(promise_id),
                "target Promise has no applicable Scenario",
            )
        target_scenarios.extend(covering)
    return target_promises, tuple(sorted(set(target_scenarios), key=str))


def _select_main_gates(
    index: _CatalogIndex,
    request: CompileRequest,
    applicable: Mapping[ScenarioID, bool],
) -> Dict[BoundLane, ScenarioID]:
    result: Dict[BoundLane, ScenarioID] = {}
    for lane in request.requested_lanes:
        candidates = tuple(
            sorted(
                (
                    scenario.id
                    for scenario in index.scenarios.values()
                    if applicable[scenario.id] and lane in scenario.main_gate_for
                ),
                key=str,
            )
        )
        if not candidates:
            raise _error(
                "compiler.main.gate.missing",
                lane.value,
                "requested lane has no applicable MainGate",
            )
        if len(candidates) != 1:
            raise _error(
                "compiler.main.gate.duplicate",
                lane.value,
                "requested lane has more than one applicable MainGate: "
                + ", ".join(map(str, candidates)),
            )
        result[lane] = candidates[0]
    return result


def _validate_main_gate_predecessors(
    index: _CatalogIndex,
    applicable: Mapping[ScenarioID, bool],
    gates: Mapping[BoundLane, ScenarioID],
) -> None:
    for lane, scenario_id in gates.items():
        found: Set[ScenarioID] = set()

        def collect(item: ScenarioID) -> None:
            for predecessor in index.predecessors[item]:
                collect(predecessor)
                if applicable[predecessor]:
                    found.add(predecessor)

        collect(scenario_id)
        if found:
            raise _error(
                "compiler.main.gate.has.predecessor",
                lane.value,
                f"MainGate {scenario_id} has applicable Journey predecessor "
                + str(sorted(found, key=str)[0]),
            )


def _filtered_dependencies(
    raw: Mapping[ScenarioID, Tuple[ScenarioID, ...]],
    selected: Set[ScenarioID],
) -> Tuple[Tuple[ScenarioID, ScenarioID], ...]:
    edges: Set[Tuple[ScenarioID, ScenarioID]] = set()

    def nearest(item: ScenarioID) -> Set[ScenarioID]:
        result: Set[ScenarioID] = set()
        for predecessor in raw[item]:
            if predecessor in selected:
                result.add(predecessor)
            else:
                result.update(nearest(predecessor))
        return result

    for successor in selected:
        for predecessor in nearest(successor):
            edges.add((predecessor, successor))
    return tuple(sorted(edges, key=lambda item: (str(item[0]), str(item[1]))))


def _dependency_map(
    selected: Set[ScenarioID],
    dependencies: Tuple[Tuple[ScenarioID, ScenarioID], ...],
) -> Dict[ScenarioID, Tuple[ScenarioID, ...]]:
    result: Dict[ScenarioID, List[ScenarioID]] = {item: [] for item in selected}
    for predecessor, successor in dependencies:
        result[successor].append(predecessor)
    return {
        key: tuple(sorted(value, key=str)) for key, value in result.items()
    }


def _scenario_candidate_lanes(
    scenario: ScenarioContract, requested_lanes: Tuple[BoundLane, ...]
) -> Tuple[BoundLane, ...]:
    requested = set(requested_lanes)
    if scenario.lane is LaneRequirement.SIMULATOR:
        candidates = (BoundLane.SIMULATOR,)
    elif scenario.lane is LaneRequirement.DEVICE:
        candidates = (BoundLane.DEVICE,)
    elif scenario.lane is LaneRequirement.EITHER:
        candidates = requested_lanes
    elif scenario.lane is LaneRequirement.BOTH:
        candidates = (BoundLane.SIMULATOR, BoundLane.DEVICE)
    else:
        raise _error(
            "compiler.invalid.scenario.lane",
            str(scenario.id),
            "Scenario has an invalid lane requirement",
        )
    if scenario.lane is LaneRequirement.BOTH:
        if set(candidates) - requested:
            raise _error(
                "compiler.scenario.lane.unavailable",
                str(scenario.id),
                "both Scenario requires requested simulator and device lanes",
            )
    elif not candidates or candidates[0] not in requested:
        raise _error(
            "compiler.scenario.lane.unavailable",
            str(scenario.id),
            f"Scenario cannot execute on requested lane set {sorted(item.value for item in requested)!r}",
        )
    return tuple(sorted(candidates, key=_lane_sort_key))


def _validate_scenarios(
    index: _CatalogIndex,
    selected: Set[ScenarioID],
    candidate_lanes: Mapping[ScenarioID, Tuple[BoundLane, ...]],
) -> None:
    oracle_ids = {item.id for item in index.catalog.oracles}
    rubric_ids = {item.id for item in index.catalog.rubrics}
    for scenario_id in selected:
        scenario = index.scenarios[scenario_id]
        if scenario.readiness is not ContractReadiness.READY:
            continue
        if type(scenario.estimated_cost_millis) is not int or scenario.estimated_cost_millis <= 0:
            raise _error(
                "compiler.invalid.scenario.cost",
                str(scenario_id),
                "Scenario cost must be positive integer milliseconds",
            )
        validate_expression_semantics(
            scenario.success,
            tuple(item.id for item in scenario.obligations),
            f"{scenario_id}.success",
        )
        call_by_id = {item.call_id: item for item in scenario.operations}
        for call in scenario.operations:
            operation = index.operations[call.operation]
            unsupported = set(candidate_lanes[scenario_id]) - set(operation.lanes)
            if unsupported:
                raise _error(
                    "compiler.operation.lane.mismatch",
                    str(call.call_id),
                    f"Operation does not support {sorted(item.value for item in unsupported)[0]}",
                )
        for obligation in scenario.obligations:
            if obligation.produced_by_call is None:
                raise _error(
                    "compiler.obligation.producer.missing",
                    str(obligation.id),
                    "ready obligation does not name a producer call",
                )
            call = call_by_id.get(obligation.produced_by_call)
            if call is None:
                raise _error(
                    "compiler.obligation.producer.missing",
                    str(obligation.id),
                    "obligation producer is absent from Scenario calls",
                )
            producer = index.operations[call.operation]
            pair = EvidenceSchemaPair(
                obligation.evidence_type, obligation.evidence_schema
            )
            if pair not in producer.evidence_schemas:
                raise _error(
                    "compiler.obligation.evidence.mismatch",
                    str(obligation.id),
                    "producer does not support the obligation evidence pair",
                )
            if obligation.oracle not in oracle_ids:
                raise _error(
                    "compiler.unknown.oracle",
                    str(obligation.id),
                    f"unknown Oracle {obligation.oracle}",
                )
            if obligation.rubric not in rubric_ids:
                raise _error(
                    "compiler.unknown.rubric",
                    str(obligation.id),
                    f"unknown Rubric {obligation.rubric}",
                )


def _resolve_preparations(
    index: _CatalogIndex,
    selected: Set[ScenarioID],
    candidate_lanes: Mapping[ScenarioID, Tuple[BoundLane, ...]],
    require_ready: bool,
) -> Tuple[
    Tuple[PreparationResolution, ...],
    Dict[Tuple[str, BoundLane, object, object], PreparationID],
    Set[PreparationID],
]:
    producers: Dict[Tuple[BoundLane, object, object], List[PreparationContract]] = {}
    producers_by_key: Dict[Tuple[BoundLane, object], List[PreparationContract]] = {}
    for preparation in index.preparations.values():
        _validate_requirement_schemas(
            preparation.prerequisites, str(preparation.id)
        )
        if type(preparation.estimated_cost_millis) is not int or preparation.estimated_cost_millis <= 0:
            raise _error(
                "compiler.invalid.preparation.cost",
                str(preparation.id),
                "Preparation cost must be positive integer milliseconds",
            )
        for call in preparation.operations:
            operation = index.operations[call.operation]
            if preparation.lane not in operation.lanes:
                raise _error(
                    "compiler.operation.lane.mismatch",
                    str(call.call_id),
                    f"Operation does not support {preparation.lane.value}",
                )
        for declaration in preparation.produces:
            producers.setdefault(
                (preparation.lane, declaration.key, declaration.schema), []
            ).append(preparation)
            producers_by_key.setdefault(
                (preparation.lane, declaration.key), []
            ).append(preparation)

    resolution_by_key: Dict[
        Tuple[str, BoundLane, object, object], PreparationID
    ] = {}
    resolutions: Dict[
        Tuple[str, BoundLane, object, object], PreparationResolution
    ] = {}
    used: Set[PreparationID] = set()
    active: List[Tuple[PreparationID, BoundLane]] = []
    complete: Set[Tuple[PreparationID, BoundLane]] = set()

    def producer_for(
        consumer: str, lane: BoundLane, requirement: StateRequirement
    ) -> PreparationContract:
        values = tuple(
            producers.get((lane, requirement.key, requirement.schema), ())
        )
        if not values:
            if producers_by_key.get((lane, requirement.key)):
                raise _error(
                    "compiler.preparation.schema.mismatch",
                    consumer,
                    f"no {lane.value} Preparation produces {requirement.key} as {requirement.schema}",
                )
            raise _error(
                "compiler.preparation.producer.missing",
                consumer,
                f"no {lane.value} Preparation produces {requirement.key} as {requirement.schema}",
            )
        if len(values) != 1:
            raise _error(
                "compiler.preparation.producer.ambiguous",
                consumer,
                f"{len(values)} {lane.value} Preparations produce {requirement.key} as {requirement.schema}",
            )
        return values[0]

    def resolve(
        consumer: str, lane: BoundLane, requirement: StateRequirement, retain: bool
    ) -> PreparationContract:
        preparation = producer_for(consumer, lane, requirement)
        if (
            require_ready
            and retain
            and preparation.readiness is not ContractReadiness.READY
        ):
            raise PreparationNotReadyError(
                preparation.id, preparation.readiness, preparation.blockers
            )
        key = (consumer, lane, requirement.key, requirement.schema)
        if retain:
            resolution_by_key[key] = preparation.id
            resolutions[key] = PreparationResolution(
                consumer, lane, requirement, preparation.id
            )
            used.add(preparation.id)
        visit(preparation, lane, retain)
        return preparation

    def visit(
        preparation: PreparationContract, lane: BoundLane, retain: bool
    ) -> None:
        identity = (preparation.id, lane)
        if identity in complete and not retain:
            return
        if identity in active:
            start = active.index(identity)
            cycle = active[start:] + [identity]
            raise _error(
                "compiler.preparation.cycle",
                str(preparation.id),
                "Preparation cycle: "
                + " -> ".join(str(item[0]) for item in cycle),
            )
        active.append(identity)
        if retain:
            used.add(preparation.id)
        for requirement in preparation.prerequisites:
            resolve(str(preparation.id), lane, requirement, retain)
        active.pop()
        complete.add(identity)

    for preparation in sorted(index.preparations.values(), key=lambda item: str(item.id)):
        visit(preparation, preparation.lane, False)

    for scenario_id in sorted(selected, key=str):
        scenario = index.scenarios[scenario_id]
        if scenario.readiness is not ContractReadiness.READY:
            continue
        requirements = _scenario_requirements(index, scenario)
        for lane in candidate_lanes[scenario_id]:
            for requirement in requirements:
                resolve(str(scenario_id), lane, requirement, True)

    return (
        tuple(resolutions[key] for key in sorted(resolutions, key=_resolution_key)),
        resolution_by_key,
        used,
    )


def _resolution_key(
    value: Tuple[str, BoundLane, object, object]
) -> Tuple[str, str, str, str]:
    return value[0], value[1].value, str(value[2]), str(value[3])


def _scenario_requirements(
    index: _CatalogIndex, scenario: ScenarioContract
) -> Tuple[StateRequirement, ...]:
    values = tuple(scenario.prerequisites) + tuple(
        index.shared_requirements[scenario.journey]
    )
    _validate_requirement_schemas(values, str(scenario.id))
    result = []
    seen = set()
    for item in values:
        identity = (item.key, item.schema)
        if identity not in seen:
            seen.add(identity)
            result.append(item)
    return tuple(result)


def _validate_requirement_schemas(
    requirements: Sequence[StateRequirement], owner: str
) -> None:
    schemas = {}
    for requirement in requirements:
        previous = schemas.setdefault(requirement.key, requirement.schema)
        if previous != requirement.schema:
            raise _error(
                "compiler.state.schema.conflict",
                owner,
                f"state key {requirement.key} requires more than one schema",
            )


def _requires_agent_environment(
    index: _CatalogIndex, selected: Set[ScenarioID]
) -> bool:
    oracles = {item.id: item for item in index.catalog.oracles}
    return any(
        oracles[obligation.oracle].kind is OracleKind.AGENT
        for scenario_id in selected
        for obligation in index.scenarios[scenario_id].obligations
    )


def _compile_plan(
    reviewed: ReviewedCatalog,
    request: CompileRequest,
    state: _AnalysisState,
) -> CompiledRunPlan:
    index = state.index
    node_ids: Dict[ScenarioID, Dict[str, NodeID]] = {}
    terminal_by_scenario: Dict[ScenarioID, NodeID] = {}
    for scenario_id in state.selected:
        scenario = index.scenarios[scenario_id]
        base = "node:" + str(scenario_id).removeprefix("scenario:")
        if scenario.lane is LaneRequirement.BOTH:
            values = {
                BoundLane.SIMULATOR.value: NodeID(base + ":simulator"),
                BoundLane.DEVICE.value: NodeID(base + ":device"),
                "join": NodeID(base + ":join"),
            }
            terminal_by_scenario[scenario_id] = values["join"]
        else:
            suffix = scenario.lane.value
            values = {"attempt": NodeID(base + ":" + suffix)}
            terminal_by_scenario[scenario_id] = values["attempt"]
        node_ids[scenario_id] = values

    main_gate_nodes: Dict[BoundLane, NodeID] = {}
    for lane, scenario_id in state.gate_scenarios.items():
        scenario = index.scenarios[scenario_id]
        if scenario.lane is LaneRequirement.BOTH:
            main_gate_nodes[lane] = node_ids[scenario_id][lane.value]
        else:
            main_gate_nodes[lane] = node_ids[scenario_id]["attempt"]

    nodes: List[RunPlanNode] = []
    for scenario_id in state.selected:
        scenario = index.scenarios[scenario_id]
        predecessor_nodes = tuple(
            terminal_by_scenario[item]
            for item in state.predecessors[scenario_id]
        )
        allowed_calls = _allowed_calls(index, scenario.operations)
        if scenario.lane is LaneRequirement.BOTH:
            attempt_ids = []
            for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE):
                attempt_id = node_ids[scenario_id][lane.value]
                attempt_ids.append(attempt_id)
                nodes.append(
                    _attempt_node(
                        request,
                        state,
                        scenario,
                        attempt_id,
                        (lane,),
                        False,
                        predecessor_nodes,
                        allowed_calls,
                        main_gate_nodes,
                    )
                )
            nodes.append(
                BothJoinNode(
                    node_ids[scenario_id]["join"],
                    scenario_id,
                    scenario.journey,
                    tuple(attempt_ids),
                    0,
                )
            )
        else:
            nodes.append(
                _attempt_node(
                    request,
                    state,
                    scenario,
                    node_ids[scenario_id]["attempt"],
                    state.candidate_lanes[scenario_id],
                    scenario.lane is LaneRequirement.EITHER,
                    predecessor_nodes,
                    allowed_calls,
                    main_gate_nodes,
                )
            )

    scheduled = tuple(
        PlannedNode(
            item.id,
            item.cost_millis,
            item.predecessors,
            item.lane_candidates,
            item.runnable,
        )
        for item in nodes
    )
    critical_costs = compute_critical_costs(scheduled)
    remaining = {item.node_id: item.remaining_millis for item in critical_costs}
    nodes = [
        replace(item, critical_remaining_millis=remaining[item.id])
        for item in nodes
    ]

    preparation_bindings = tuple(
        _preparation_binding(state, index.preparations[item])
        for item in state.used_preparations
    )
    main_gates = tuple(
        MainGateBinding(lane, state.gate_scenarios[lane], main_gate_nodes[lane])
        for lane in request.requested_lanes
    )
    return CompiledRunPlan(
        reviewed.catalog.digest,
        reviewed.completed_review.digest,
        request.selector,
        request.reviewed_facts,
        request.build_identity,
        request.evidence_environment_identity,
        request.requested_lanes,
        preparation_bindings,
        tuple(nodes),
        main_gates,
        critical_costs,
    )


def _attempt_node(
    request: CompileRequest,
    state: _AnalysisState,
    scenario: ScenarioContract,
    node_id: NodeID,
    lanes: Tuple[BoundLane, ...],
    binds_lane_on_claim: bool,
    predecessors: Tuple[NodeID, ...],
    calls: Tuple[AllowedOperationCall, ...],
    main_gate_nodes: Mapping[BoundLane, NodeID],
) -> ScenarioAttemptNode:
    requirements = _scenario_requirements(state.index, scenario)
    preparation_requirements = []
    for lane in lanes:
        for requirement in requirements:
            preparation_id = state.preparation_by_resolution[
                (str(scenario.id), lane, requirement.key, requirement.schema)
            ]
            preparation_requirements.append(
                PreparationRequirementBinding(lane, requirement, preparation_id)
            )
    gate_dependencies = tuple(
        LaneGateDependency(lane, main_gate_nodes[lane])
        for lane in lanes
        if main_gate_nodes[lane] != node_id
    )
    static_predecessors = set(predecessors)
    if len(lanes) == 1:
        static_predecessors.update(
            item.gate_node_id for item in gate_dependencies
        )
    return ScenarioAttemptNode(
        node_id,
        scenario.id,
        scenario.journey,
        scenario.leaf_digest,
        lanes,
        binds_lane_on_claim,
        scenario.estimated_cost_millis,
        tuple(sorted(static_predecessors, key=str)),
        gate_dependencies,
        tuple(preparation_requirements),
        calls,
        _evaluation_bindings(state.index, request, scenario),
        scenario.success,
        request.build_identity,
        request.evidence_environment_identity.narrowed(
            item.operation for item in calls
        ),
        0,
    )


def _evaluation_bindings(
    index: _CatalogIndex,
    request: CompileRequest,
    scenario: ScenarioContract,
) -> Tuple[EvaluationBinding, ...]:
    call_by_id = {item.call_id: item for item in scenario.operations}
    bindings = []
    for obligation in scenario.obligations:
        if obligation.produced_by_call is None:
            raise _error(
                "compiler.obligation.producer.missing",
                str(obligation.id),
                "ready obligation does not name a producer call",
            )
        producer_call = call_by_id.get(obligation.produced_by_call)
        if producer_call is None:
            raise _error(
                "compiler.obligation.producer.missing",
                str(obligation.id),
                "obligation producer is absent from Scenario calls",
            )
        producer = index.operations[producer_call.operation]
        pair = EvidenceSchemaPair(
            obligation.evidence_type, obligation.evidence_schema
        )
        if pair not in producer.evidence_schemas:
            raise _error(
                "compiler.obligation.evidence.mismatch",
                str(obligation.id),
                "producer does not support the obligation evidence pair",
            )
        oracle = index.oracles.get(obligation.oracle)
        if oracle is None:
            raise _error(
                "compiler.unknown.oracle",
                str(obligation.id),
                f"unknown Oracle {obligation.oracle}",
            )
        if oracle.id != obligation.oracle:
            raise _error(
                "compiler.oracle.binding.mismatch",
                str(obligation.id),
                "resolved Oracle does not match the obligation reference",
            )
        if pair not in oracle.evidence_schemas:
            raise _error(
                "compiler.oracle.evidence.mismatch",
                str(obligation.id),
                "Oracle does not support the obligation evidence pair",
            )
        if (
            oracle.kind is OracleKind.AGENT
            and request.evidence_environment_identity.agent_environment is None
        ):
            raise _error(
                "compiler.agent.environment.missing",
                "request.evidenceEnvironmentIdentity.agentEnvironment",
                "selected Scenarios use an Agent Oracle",
            )
        rubric = index.rubrics.get(obligation.rubric)
        if rubric is None:
            raise _error(
                "compiler.unknown.rubric",
                str(obligation.id),
                f"unknown Rubric {obligation.rubric}",
            )
        if rubric.id != obligation.rubric:
            raise _error(
                "compiler.rubric.binding.mismatch",
                str(obligation.id),
                "resolved Rubric does not match the obligation reference",
            )
        bindings.append(
            EvaluationBinding(
                obligation.id,
                obligation.artifact_class,
                obligation.evidence_type,
                obligation.evidence_schema,
                obligation.case_key,
                obligation.produced_by_call,
                producer.leaf_digest,
                OracleEvaluationBinding(
                    oracle.id,
                    oracle.kind,
                    oracle.leaf_digest,
                    oracle.implementation_locator,
                    oracle.implementation_digest,
                    oracle.body,
                ),
                RubricEvaluationBinding(
                    rubric.id,
                    rubric.leaf_digest,
                    rubric.criteria,
                    rubric.negative_controls,
                    rubric.body,
                ),
            )
        )
    return tuple(sorted(bindings, key=lambda item: str(item.id)))


def _allowed_calls(
    index: _CatalogIndex, calls: Tuple[OperationCall, ...]
) -> Tuple[AllowedOperationCall, ...]:
    return tuple(
        AllowedOperationCall(
            call_id=call.call_id,
            operation=call.operation,
            contract_digest=index.operations[call.operation].leaf_digest,
            arguments_bytes=call.arguments_bytes,
            arguments_digest=call.arguments_digest,
            implementation_locator=index.operations[
                call.operation
            ].implementation_locator,
            implementation_digest=index.operations[
                call.operation
            ].implementation_digest,
            max_invocations=call.max_invocations,
            invalidates_tags=index.operations[call.operation].invalidates_tags,
        )
        for call in calls
    )


def _preparation_binding(
    state: _AnalysisState, preparation: PreparationContract
) -> PreparationBinding:
    prerequisites = tuple(
        PreparationRequirementBinding(
            preparation.lane,
            requirement,
            state.preparation_by_resolution[
                (
                    str(preparation.id),
                    preparation.lane,
                    requirement.key,
                    requirement.schema,
                )
            ],
        )
        for requirement in preparation.prerequisites
    )
    return PreparationBinding(
        preparation.id,
        preparation.lane,
        preparation.leaf_digest,
        preparation.estimated_cost_millis,
        preparation.prerequisites,
        _allowed_calls(state.index, preparation.operations),
        preparation.produces,
        prerequisites,
    )


__all__ = (
    "ContractNotReadyError",
    "PreparationNotReadyError",
    "ReviewedCatalog",
    "accept_reviews",
    "analyze_catalog",
    "compile_run",
)
