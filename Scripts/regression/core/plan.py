from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, FrozenSet, Optional, Tuple, Union

from .applicability import ReviewedFact, reviewed_facts_digest
from .capability import AllowedOperationCall
from .contracts import (
    ArtifactClass,
    BoundLane,
    ContractBlocker,
    ContractReadiness,
    OracleKind,
    StateDeclaration,
    StateRequirement,
)
from .digest import canonical_bytes, canonical_digest
from .errors import RegressionError
from .expression import AllOf, AnyOf, AtLeast, Not, ObservationRef, SuccessExpression
from .ids import (
    CallID,
    CaseKey,
    Digest,
    EvidenceSchema,
    EvidenceType,
    JourneyID,
    NodeID,
    ObligationID,
    OracleID,
    PreparationID,
    PromiseID,
    RubricID,
    ScenarioID,
    parse_call_id,
    parse_case_key,
    parse_evidence_schema,
    parse_evidence_type,
    parse_identifier,
)
from .scheduler import CriticalCost


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


def _non_empty(value: object, location: str, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise _error("plan.empty.value", location, f"{label} must not be empty")
    return value


def _digest(value: object, location: str) -> Digest:
    return Digest(parse_identifier("digest", value, location))


def _node_id(value: object, location: str) -> NodeID:
    return NodeID(parse_identifier("node", value, location))


def _lane_sort_key(lane: BoundLane) -> int:
    return 0 if lane is BoundLane.SIMULATOR else 1


def _lanes(values: Tuple[BoundLane, ...], location: str) -> Tuple[BoundLane, ...]:
    result = tuple(values)
    if not result:
        raise _error("plan.empty.lanes", location, "at least one lane is required")
    if any(not isinstance(item, BoundLane) for item in result):
        raise _error(
            "plan.invalid.lane", location, "lanes must contain concrete BoundLane values"
        )
    if len(result) != len(set(result)):
        raise _error("plan.duplicate.lane", location, "a lane may appear only once")
    return tuple(sorted(result, key=_lane_sort_key))


@dataclass(frozen=True)
class FullSelector:
    pass


@dataclass(frozen=True)
class PromiseSelector:
    promise_ids: Tuple[PromiseID, ...]

    def __post_init__(self) -> None:
        values = tuple(
            PromiseID(parse_identifier("promise", item, "selector.promiseIds"))
            for item in self.promise_ids
        )
        if not values:
            raise _error(
                "plan.empty.selector", "selector.promiseIds", "Promise selector must not be empty"
            )
        if len(values) != len(set(values)):
            raise _error(
                "plan.duplicate.selector",
                "selector.promiseIds",
                "Promise selector IDs must be unique",
            )
        object.__setattr__(self, "promise_ids", tuple(sorted(values, key=str)))

    @property
    def promises(self) -> Tuple[PromiseID, ...]:
        return self.promise_ids


@dataclass(frozen=True)
class ScenarioSelector:
    scenario_ids: Tuple[ScenarioID, ...]

    def __post_init__(self) -> None:
        values = tuple(
            ScenarioID(parse_identifier("scenario", item, "selector.scenarioIds"))
            for item in self.scenario_ids
        )
        if not values:
            raise _error(
                "plan.empty.selector", "selector.scenarioIds", "Scenario selector must not be empty"
            )
        if len(values) != len(set(values)):
            raise _error(
                "plan.duplicate.selector",
                "selector.scenarioIds",
                "Scenario selector IDs must be unique",
            )
        object.__setattr__(self, "scenario_ids", tuple(sorted(values, key=str)))

    @property
    def scenarios(self) -> Tuple[ScenarioID, ...]:
        return self.scenario_ids


Selector = Union[FullSelector, PromiseSelector, ScenarioSelector]


@dataclass(frozen=True)
class ToolchainIdentity:
    xcode_version: str
    xcode_build: str
    visionos_sdk_version: str
    visionos_sdk_build: str
    visionos_simulator_sdk_version: str
    visionos_simulator_sdk_build: str

    def __post_init__(self) -> None:
        for name, location, label in (
            ("xcode_version", "xcodeVersion", "Xcode version"),
            ("xcode_build", "xcodeBuild", "Xcode build"),
            ("visionos_sdk_version", "visionOSSDKVersion", "visionOS SDK version"),
            ("visionos_sdk_build", "visionOSSDKBuild", "visionOS SDK build"),
            (
                "visionos_simulator_sdk_version",
                "visionOSSimulatorSDKVersion",
                "visionOS Simulator SDK version",
            ),
            (
                "visionos_simulator_sdk_build",
                "visionOSSimulatorSDKBuild",
                "visionOS Simulator SDK build",
            ),
        ):
            _non_empty(
                getattr(self, name),
                f"toolchainIdentity.{location}",
                label,
            )


@dataclass(frozen=True)
class LaneBuildArtifact:
    lane: BoundLane
    xctestrun_digest: Digest
    test_products_digest: Digest
    application_code_digest: Digest

    def __post_init__(self) -> None:
        if not isinstance(self.lane, BoundLane):
            raise _error(
                "plan.invalid.build.lane",
                "laneBuildArtifact.lane",
                "build artifact lane must be concrete",
            )
        object.__setattr__(
            self,
            "xctestrun_digest",
            _digest(
                self.xctestrun_digest,
                f"laneBuildArtifact.{self.lane.value}.xctestrunDigest",
            ),
        )
        object.__setattr__(
            self,
            "test_products_digest",
            _digest(
                self.test_products_digest,
                f"laneBuildArtifact.{self.lane.value}.testProductsDigest",
            ),
        )
        object.__setattr__(
            self,
            "application_code_digest",
            _digest(
                self.application_code_digest,
                f"laneBuildArtifact.{self.lane.value}.applicationCodeDigest",
            ),
        )


@dataclass(frozen=True)
class BuildIdentity:
    bundle_identifier: str
    git_revision: str
    source_tree_digest: Digest
    configuration_digest: Digest
    toolchain: ToolchainIdentity
    lane_artifacts: Tuple[LaneBuildArtifact, ...]
    identity_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        for name, label in (
            ("bundle_identifier", "bundle identifier"),
            ("git_revision", "git revision"),
        ):
            _non_empty(getattr(self, name), f"buildIdentity.{name}", label)
        object.__setattr__(
            self,
            "source_tree_digest",
            _digest(self.source_tree_digest, "buildIdentity.sourceTreeDigest"),
        )
        object.__setattr__(
            self,
            "configuration_digest",
            _digest(self.configuration_digest, "buildIdentity.configurationDigest"),
        )
        if not isinstance(self.toolchain, ToolchainIdentity):
            raise _error(
                "plan.invalid.build.toolchain",
                "buildIdentity.toolchain",
                "expected ToolchainIdentity",
            )
        artifacts = tuple(self.lane_artifacts)
        if any(not isinstance(item, LaneBuildArtifact) for item in artifacts):
            raise _error(
                "plan.invalid.build.artifact",
                "buildIdentity.laneArtifacts",
                "lane artifacts must contain LaneBuildArtifact values",
            )
        artifact_lanes = tuple(item.lane for item in artifacts)
        if len(artifact_lanes) != len(set(artifact_lanes)):
            raise _error(
                "plan.duplicate.build.artifact",
                "buildIdentity.laneArtifacts",
                "a build identity may bind a lane only once",
            )
        artifacts = tuple(
            sorted(artifacts, key=lambda item: _lane_sort_key(item.lane))
        )
        required_lanes = (BoundLane.SIMULATOR, BoundLane.DEVICE)
        if tuple(item.lane for item in artifacts) != required_lanes:
            raise _error(
                "plan.missing.build.artifact",
                "buildIdentity.laneArtifacts",
                "BuildIdentity must bind exactly one simulator and one device artifact",
            )
        simulator, device = artifacts
        for name, location, label in (
            ("xctestrun_digest", "xctestrunDigest", ".xctestrun"),
            ("test_products_digest", "testProductsDigest", "test products"),
            ("application_code_digest", "applicationCodeDigest", "application code"),
        ):
            if getattr(simulator, name) == getattr(device, name):
                raise _error(
                    "plan.shared.build.artifact.digest",
                    f"buildIdentity.laneArtifacts.{location}",
                    f"simulator and device {label} digests must differ",
                )
        object.__setattr__(self, "lane_artifacts", artifacts)
        object.__setattr__(
            self,
            "identity_digest",
            canonical_digest(_build_identity_payload(self)),
        )

    @property
    def digest(self) -> Digest:
        return self.identity_digest

    @property
    def artifacts(self) -> Tuple[LaneBuildArtifact, ...]:
        return self.lane_artifacts


@dataclass(frozen=True)
class AgentEnvironment:
    model: str
    prompt_digest: Digest
    configuration_digest: Digest

    def __post_init__(self) -> None:
        _non_empty(self.model, "agentEnvironment.model", "agent model")
        object.__setattr__(
            self,
            "prompt_digest",
            _digest(self.prompt_digest, "agentEnvironment.promptDigest"),
        )
        object.__setattr__(
            self,
            "configuration_digest",
            _digest(
                self.configuration_digest, "agentEnvironment.configurationDigest"
            ),
        )


@dataclass(frozen=True)
class EvidenceEnvironmentIdentity:
    deterministic_runtime_digest: Digest
    agent_environment: Optional[AgentEnvironment] = None
    identity_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "deterministic_runtime_digest",
            _digest(
                self.deterministic_runtime_digest,
                "evidenceEnvironment.deterministicRuntimeDigest",
            ),
        )
        if self.agent_environment is not None and not isinstance(
            self.agent_environment, AgentEnvironment
        ):
            raise _error(
                "plan.invalid.agent.environment",
                "evidenceEnvironment.agentEnvironment",
                "expected AgentEnvironment or None",
            )
        object.__setattr__(
            self,
            "identity_digest",
            canonical_digest(_evidence_environment_payload(self)),
        )

    @property
    def digest(self) -> Digest:
        return self.identity_digest


@dataclass(frozen=True)
class CompileRequest:
    selector: Selector
    reviewed_facts: Tuple[ReviewedFact, ...]
    requested_lanes: Tuple[BoundLane, ...]
    build_identity: BuildIdentity
    evidence_environment_identity: EvidenceEnvironmentIdentity

    def __post_init__(self) -> None:
        if not isinstance(self.selector, (FullSelector, PromiseSelector, ScenarioSelector)):
            raise _error(
                "plan.invalid.selector",
                "compileRequest.selector",
                "expected a typed selector",
            )
        facts = tuple(self.reviewed_facts)
        if any(not isinstance(item, ReviewedFact) for item in facts):
            raise _error(
                "plan.invalid.reviewed.fact",
                "compileRequest.reviewedFacts",
                "expected ReviewedFact values",
            )
        fact_ids = tuple(item.id for item in facts)
        if len(fact_ids) != len(set(fact_ids)):
            raise _error(
                "plan.duplicate.reviewed.fact",
                "compileRequest.reviewedFacts",
                "a reviewed Fact may appear only once",
            )
        object.__setattr__(self, "reviewed_facts", tuple(sorted(facts, key=lambda item: str(item.id))))
        object.__setattr__(
            self,
            "requested_lanes",
            _lanes(tuple(self.requested_lanes), "compileRequest.requestedLanes"),
        )
        if not isinstance(self.build_identity, BuildIdentity):
            raise _error(
                "plan.invalid.build.identity",
                "compileRequest.buildIdentity",
                "expected BuildIdentity",
            )
        if not isinstance(
            self.evidence_environment_identity, EvidenceEnvironmentIdentity
        ):
            raise _error(
                "plan.invalid.evidence.environment",
                "compileRequest.evidenceEnvironmentIdentity",
                "expected EvidenceEnvironmentIdentity",
            )

    @property
    def evidence_environment(self) -> EvidenceEnvironmentIdentity:
        return self.evidence_environment_identity


@dataclass(frozen=True)
class ScenarioDependency:
    predecessor: ScenarioID
    successor: ScenarioID

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "predecessor",
            ScenarioID(
                parse_identifier("scenario", self.predecessor, "scenarioDependency.predecessor")
            ),
        )
        object.__setattr__(
            self,
            "successor",
            ScenarioID(
                parse_identifier("scenario", self.successor, "scenarioDependency.successor")
            ),
        )
        if self.predecessor == self.successor:
            raise _error(
                "plan.self.dependency",
                str(self.predecessor),
                "a Scenario cannot depend on itself",
            )


@dataclass(frozen=True)
class PreparationResolution:
    consumer: str
    lane: BoundLane
    requirement: StateRequirement
    preparation_id: PreparationID

    def __post_init__(self) -> None:
        _non_empty(self.consumer, "preparationResolution.consumer", "consumer")
        if not isinstance(self.lane, BoundLane):
            raise _error(
                "plan.invalid.preparation.lane",
                self.consumer,
                "Preparation resolution lane must be concrete",
            )
        if not isinstance(self.requirement, StateRequirement):
            raise _error(
                "plan.invalid.state.requirement",
                self.consumer,
                "expected StateRequirement",
            )
        object.__setattr__(
            self,
            "preparation_id",
            PreparationID(
                parse_identifier(
                    "preparation", self.preparation_id, "preparationResolution.preparationId"
                )
            ),
        )


@dataclass(frozen=True)
class CatalogMainGate:
    lane: BoundLane
    scenario_id: ScenarioID

    def __post_init__(self) -> None:
        if not isinstance(self.lane, BoundLane):
            raise _error("plan.invalid.gate.lane", "catalogMainGate.lane", "gate lane must be concrete")
        object.__setattr__(
            self,
            "scenario_id",
            ScenarioID(parse_identifier("scenario", self.scenario_id, "catalogMainGate.scenarioId")),
        )


@dataclass(frozen=True)
class ScenarioReadinessAnalysis:
    scenario_id: ScenarioID
    readiness: ContractReadiness
    blockers: Tuple[ContractBlocker, ...]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "scenario_id",
            ScenarioID(
                parse_identifier(
                    "scenario", self.scenario_id, "scenarioReadiness.scenarioId"
                )
            ),
        )
        if not isinstance(self.readiness, ContractReadiness):
            raise _error(
                "plan.invalid.readiness",
                str(self.scenario_id),
                "readiness must be a ContractReadiness",
            )
        object.__setattr__(self, "blockers", tuple(self.blockers))


@dataclass(frozen=True)
class PreparationReadinessAnalysis:
    preparation_id: PreparationID
    readiness: ContractReadiness
    blockers: Tuple[ContractBlocker, ...]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "preparation_id",
            PreparationID(
                parse_identifier(
                    "preparation",
                    self.preparation_id,
                    "preparationReadiness.preparationId",
                )
            ),
        )
        if not isinstance(self.readiness, ContractReadiness):
            raise _error(
                "plan.invalid.readiness",
                str(self.preparation_id),
                "readiness must be a ContractReadiness",
            )
        object.__setattr__(self, "blockers", tuple(self.blockers))


@dataclass(frozen=True)
class CatalogAnalysis:
    catalog_digest: Digest
    selector: Selector
    reviewed_facts_digest: Digest
    requested_lanes: Tuple[BoundLane, ...]
    target_promises: Tuple[PromiseID, ...]
    target_scenarios: Tuple[ScenarioID, ...]
    applicable_scenarios: Tuple[ScenarioID, ...]
    selected_scenarios: Tuple[ScenarioID, ...]
    journey_dependencies: Tuple[ScenarioDependency, ...]
    preparation_resolutions: Tuple[PreparationResolution, ...]
    main_gates: Tuple[CatalogMainGate, ...]
    scenario_readiness: Tuple[ScenarioReadinessAnalysis, ...]
    preparation_readiness: Tuple[PreparationReadinessAnalysis, ...]
    requires_agent_environment: bool

    def __post_init__(self) -> None:
        object.__setattr__(self, "catalog_digest", _digest(self.catalog_digest, "catalogAnalysis.catalogDigest"))
        object.__setattr__(self, "reviewed_facts_digest", _digest(self.reviewed_facts_digest, "catalogAnalysis.reviewedFactsDigest"))
        if not isinstance(self.selector, (FullSelector, PromiseSelector, ScenarioSelector)):
            raise _error("plan.invalid.selector", "catalogAnalysis.selector", "expected a typed selector")
        object.__setattr__(self, "requested_lanes", _lanes(tuple(self.requested_lanes), "catalogAnalysis.requestedLanes"))
        for name in ("target_promises", "target_scenarios", "applicable_scenarios", "selected_scenarios"):
            values = tuple(getattr(self, name))
            if len(values) != len(set(values)):
                raise _error("plan.duplicate.analysis.item", f"catalogAnalysis.{name}", "analysis IDs must be unique")
            object.__setattr__(self, name, tuple(sorted(values, key=str)))
        object.__setattr__(
            self,
            "journey_dependencies",
            tuple(sorted(tuple(self.journey_dependencies), key=lambda item: (str(item.predecessor), str(item.successor)))),
        )
        object.__setattr__(
            self,
            "preparation_resolutions",
            tuple(
                sorted(
                    tuple(self.preparation_resolutions),
                    key=lambda item: (
                        item.consumer,
                        _lane_sort_key(item.lane),
                        str(item.requirement.key),
                        str(item.requirement.schema),
                    ),
                )
            ),
        )
        object.__setattr__(
            self,
            "main_gates",
            tuple(
                sorted(
                    tuple(self.main_gates),
                    key=lambda item: _lane_sort_key(item.lane),
                )
            ),
        )
        object.__setattr__(
            self,
            "scenario_readiness",
            tuple(
                sorted(
                    tuple(self.scenario_readiness),
                    key=lambda item: str(item.scenario_id),
                )
            ),
        )
        object.__setattr__(
            self,
            "preparation_readiness",
            tuple(
                sorted(
                    tuple(self.preparation_readiness),
                    key=lambda item: str(item.preparation_id),
                )
            ),
        )
        if type(self.requires_agent_environment) is not bool:
            raise _error(
                "plan.invalid.agent.requirement",
                "catalogAnalysis.requiresAgentEnvironment",
                "requiresAgentEnvironment must be a boolean",
            )


@dataclass(frozen=True)
class PreparationBinding:
    preparation_id: PreparationID
    lane: BoundLane
    contract_digest: Digest
    estimated_cost_millis: int
    prerequisites: Tuple[StateRequirement, ...]
    calls: Tuple[AllowedOperationCall, ...]
    produces: Tuple[StateDeclaration, ...]
    prerequisite_bindings: Tuple["PreparationRequirementBinding", ...] = ()

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "preparation_id",
            PreparationID(parse_identifier("preparation", self.preparation_id, "preparationBinding.preparationId")),
        )
        if not isinstance(self.lane, BoundLane):
            raise _error("plan.invalid.preparation.lane", str(self.preparation_id), "Preparation lane must be concrete")
        object.__setattr__(self, "contract_digest", _digest(self.contract_digest, f"{self.preparation_id}.contractDigest"))
        if type(self.estimated_cost_millis) is not int or self.estimated_cost_millis <= 0:
            raise _error("plan.invalid.cost", str(self.preparation_id), "Preparation cost must be positive integer milliseconds")
        prerequisites = tuple(self.prerequisites)
        calls = tuple(self.calls)
        produces = tuple(self.produces)
        prerequisite_bindings = tuple(self.prerequisite_bindings)
        if any(not isinstance(item, StateRequirement) for item in prerequisites):
            raise _error("plan.invalid.state.requirement", str(self.preparation_id), "expected StateRequirement values")
        if not calls or any(not isinstance(item, AllowedOperationCall) for item in calls):
            raise _error("plan.invalid.preparation.calls", str(self.preparation_id), "Preparation must contain exact allowed calls")
        if not produces or any(not isinstance(item, StateDeclaration) for item in produces):
            raise _error("plan.invalid.preparation.produces", str(self.preparation_id), "Preparation must declare produced state")
        if any(
            not isinstance(item, PreparationRequirementBinding)
            for item in prerequisite_bindings
        ):
            raise _error(
                "plan.invalid.preparation.requirement",
                str(self.preparation_id),
                "expected PreparationRequirementBinding values",
            )
        if any(item.lane is not self.lane for item in prerequisite_bindings):
            raise _error(
                "plan.preparation.lane.mismatch",
                str(self.preparation_id),
                "nested Preparation bindings must use the producer lane",
            )
        object.__setattr__(
            self,
            "prerequisites",
            tuple(
                sorted(
                    prerequisites,
                    key=lambda item: (str(item.key), str(item.schema)),
                )
            ),
        )
        object.__setattr__(self, "calls", calls)
        object.__setattr__(
            self,
            "produces",
            tuple(
                sorted(
                    produces,
                    key=lambda item: (
                        str(item.key),
                        str(item.schema),
                        str(item.produced_by_call),
                    ),
                )
            ),
        )
        object.__setattr__(
            self,
            "prerequisite_bindings",
            tuple(
                sorted(
                    prerequisite_bindings,
                    key=lambda item: (
                        str(item.requirement.key),
                        str(item.requirement.schema),
                        str(item.preparation_id),
                    ),
                )
            ),
        )


@dataclass(frozen=True)
class PreparationRequirementBinding:
    lane: BoundLane
    requirement: StateRequirement
    preparation_id: PreparationID

    def __post_init__(self) -> None:
        if not isinstance(self.lane, BoundLane):
            raise _error("plan.invalid.preparation.lane", "preparationRequirement.lane", "lane must be concrete")
        if not isinstance(self.requirement, StateRequirement):
            raise _error("plan.invalid.state.requirement", "preparationRequirement.requirement", "expected StateRequirement")
        object.__setattr__(
            self,
            "preparation_id",
            PreparationID(parse_identifier("preparation", self.preparation_id, "preparationRequirement.preparationId")),
        )


@dataclass(frozen=True)
class LaneGateDependency:
    lane: BoundLane
    gate_node_id: NodeID

    def __post_init__(self) -> None:
        if not isinstance(self.lane, BoundLane):
            raise _error("plan.invalid.gate.lane", "laneGateDependency.lane", "gate lane must be concrete")
        object.__setattr__(self, "gate_node_id", _node_id(self.gate_node_id, "laneGateDependency.gateNodeId"))


@dataclass(frozen=True)
class MainGateBinding:
    lane: BoundLane
    scenario_id: ScenarioID
    node_id: NodeID

    def __post_init__(self) -> None:
        if not isinstance(self.lane, BoundLane):
            raise _error("plan.invalid.gate.lane", "mainGateBinding.lane", "gate lane must be concrete")
        object.__setattr__(self, "scenario_id", ScenarioID(parse_identifier("scenario", self.scenario_id, "mainGateBinding.scenarioId")))
        object.__setattr__(self, "node_id", _node_id(self.node_id, "mainGateBinding.nodeId"))


@dataclass(frozen=True)
class OracleEvaluationBinding:
    id: OracleID
    kind: OracleKind
    contract_digest: Digest
    implementation_locator: str
    implementation_digest: Digest
    body: str

    def __post_init__(self) -> None:
        identifier = OracleID(
            parse_identifier("oracle", self.id, "oracleEvaluation.id")
        )
        object.__setattr__(self, "id", identifier)
        if not isinstance(self.kind, OracleKind):
            raise _error(
                "plan.invalid.oracle.kind",
                str(identifier),
                "Oracle evaluation kind must be an OracleKind",
            )
        object.__setattr__(
            self,
            "contract_digest",
            _digest(self.contract_digest, f"{identifier}.contractDigest"),
        )
        _non_empty(
            self.implementation_locator,
            f"{identifier}.implementationLocator",
            "Oracle implementation locator",
        )
        object.__setattr__(
            self,
            "implementation_digest",
            _digest(
                self.implementation_digest,
                f"{identifier}.implementationDigest",
            ),
        )
        if not isinstance(self.body, str):
            raise _error(
                "plan.invalid.oracle.body",
                str(identifier),
                "Oracle body must be text",
            )


@dataclass(frozen=True)
class RubricEvaluationBinding:
    id: RubricID
    contract_digest: Digest
    criteria: Tuple[str, ...]
    negative_controls: Tuple[str, ...]
    body: str

    def __post_init__(self) -> None:
        identifier = RubricID(
            parse_identifier("rubric", self.id, "rubricEvaluation.id")
        )
        object.__setattr__(self, "id", identifier)
        object.__setattr__(
            self,
            "contract_digest",
            _digest(self.contract_digest, f"{identifier}.contractDigest"),
        )
        for field_name, label in (
            ("criteria", "Rubric criteria"),
            ("negative_controls", "Rubric negative controls"),
        ):
            values = tuple(getattr(self, field_name))
            if not values:
                raise _error(
                    "plan.empty.rubric.rule",
                    f"{identifier}.{field_name}",
                    f"{label} must not be empty",
                )
            if any(not isinstance(item, str) or not item.strip() for item in values):
                raise _error(
                    "plan.invalid.rubric.rule",
                    f"{identifier}.{field_name}",
                    f"{label} must contain non-empty text",
                )
            if len(values) != len(set(values)):
                raise _error(
                    "plan.duplicate.rubric.rule",
                    f"{identifier}.{field_name}",
                    f"{label} must not contain duplicates",
                )
            object.__setattr__(self, field_name, values)
        if not isinstance(self.body, str):
            raise _error(
                "plan.invalid.rubric.body",
                str(identifier),
                "Rubric body must be text",
            )


@dataclass(frozen=True)
class EvaluationBinding:
    id: ObligationID
    artifact_class: ArtifactClass
    evidence_type: EvidenceType
    evidence_schema: EvidenceSchema
    case_key: CaseKey
    produced_by_call: CallID
    producer_contract_digest: Digest
    oracle: OracleEvaluationBinding
    rubric: RubricEvaluationBinding

    def __post_init__(self) -> None:
        identifier = ObligationID(
            parse_identifier("obligation", self.id, "evaluationBinding.id")
        )
        object.__setattr__(self, "id", identifier)
        if self.artifact_class is not ArtifactClass.COVERAGE:
            raise _error(
                "plan.invalid.evaluation.artifact.class",
                str(identifier),
                "Scenario evaluation bindings must produce coverage",
            )
        object.__setattr__(
            self,
            "evidence_type",
            parse_evidence_type(
                self.evidence_type, f"{identifier}.evidenceType"
            ),
        )
        object.__setattr__(
            self,
            "evidence_schema",
            parse_evidence_schema(
                self.evidence_schema, f"{identifier}.evidenceSchema"
            ),
        )
        object.__setattr__(
            self,
            "case_key",
            parse_case_key(self.case_key, f"{identifier}.caseKey"),
        )
        object.__setattr__(
            self,
            "produced_by_call",
            parse_call_id(
                self.produced_by_call, f"{identifier}.producedByCall"
            ),
        )
        object.__setattr__(
            self,
            "producer_contract_digest",
            _digest(
                self.producer_contract_digest,
                f"{identifier}.producerContractDigest",
            ),
        )
        if not isinstance(self.oracle, OracleEvaluationBinding):
            raise _error(
                "plan.invalid.evaluation.oracle",
                str(identifier),
                "evaluation must bind an OracleEvaluationBinding",
            )
        if not isinstance(self.rubric, RubricEvaluationBinding):
            raise _error(
                "plan.invalid.evaluation.rubric",
                str(identifier),
                "evaluation must bind a RubricEvaluationBinding",
            )


@dataclass(frozen=True)
class ScenarioAttemptNode:
    id: NodeID
    scenario_id: ScenarioID
    journey_id: JourneyID
    scenario_digest: Digest
    lane_candidates: Tuple[BoundLane, ...]
    binds_lane_on_claim: bool
    cost_millis: int
    predecessors: Tuple[NodeID, ...]
    gate_dependencies: Tuple[LaneGateDependency, ...]
    preparation_requirements: Tuple[PreparationRequirementBinding, ...]
    calls: Tuple[AllowedOperationCall, ...]
    evaluation_bindings: Tuple[EvaluationBinding, ...]
    success: SuccessExpression
    build_identity: BuildIdentity
    evidence_environment_identity: EvidenceEnvironmentIdentity
    critical_remaining_millis: int

    def __post_init__(self) -> None:
        object.__setattr__(self, "id", _node_id(self.id, "scenarioAttempt.id"))
        object.__setattr__(self, "scenario_id", ScenarioID(parse_identifier("scenario", self.scenario_id, f"{self.id}.scenarioId")))
        object.__setattr__(self, "journey_id", JourneyID(parse_identifier("journey", self.journey_id, f"{self.id}.journeyId")))
        object.__setattr__(self, "scenario_digest", _digest(self.scenario_digest, f"{self.id}.scenarioDigest"))
        object.__setattr__(self, "lane_candidates", _lanes(tuple(self.lane_candidates), f"{self.id}.laneCandidates"))
        if type(self.binds_lane_on_claim) is not bool:
            raise _error("plan.invalid.claim.binding", str(self.id), "bindsLaneOnClaim must be a boolean")
        if type(self.cost_millis) is not int or self.cost_millis <= 0:
            raise _error("plan.invalid.cost", str(self.id), "Scenario cost must be positive integer milliseconds")
        predecessors = tuple(_node_id(item, f"{self.id}.predecessors") for item in self.predecessors)
        if len(predecessors) != len(set(predecessors)):
            raise _error("plan.duplicate.predecessor", str(self.id), "a node cannot repeat a predecessor")
        object.__setattr__(self, "predecessors", tuple(sorted(predecessors, key=str)))
        gate_dependencies = tuple(self.gate_dependencies)
        if any(not isinstance(item, LaneGateDependency) for item in gate_dependencies):
            raise _error("plan.invalid.gate.dependency", str(self.id), "expected LaneGateDependency values")
        if len(tuple(item.lane for item in gate_dependencies)) != len(set(item.lane for item in gate_dependencies)):
            raise _error("plan.duplicate.gate.dependency", str(self.id), "a node may bind one gate per lane")
        if any(item.lane not in self.lane_candidates for item in gate_dependencies):
            raise _error("plan.gate.lane.mismatch", str(self.id), "gate dependencies must match candidate lanes")
        object.__setattr__(
            self,
            "gate_dependencies",
            tuple(
                sorted(
                    gate_dependencies,
                    key=lambda item: _lane_sort_key(item.lane),
                )
            ),
        )
        preparation_requirements = tuple(self.preparation_requirements)
        if any(not isinstance(item, PreparationRequirementBinding) for item in preparation_requirements):
            raise _error("plan.invalid.preparation.requirement", str(self.id), "expected PreparationRequirementBinding values")
        object.__setattr__(
            self,
            "preparation_requirements",
            tuple(
                sorted(
                    preparation_requirements,
                    key=lambda item: (
                        _lane_sort_key(item.lane),
                        str(item.requirement.key),
                        str(item.requirement.schema),
                    ),
                )
            ),
        )
        calls = tuple(self.calls)
        evaluation_bindings = tuple(self.evaluation_bindings)
        if not calls or any(not isinstance(item, AllowedOperationCall) for item in calls):
            raise _error("plan.invalid.scenario.calls", str(self.id), "Scenario must contain exact allowed calls")
        if not evaluation_bindings or any(
            not isinstance(item, EvaluationBinding)
            for item in evaluation_bindings
        ):
            raise _error(
                "plan.invalid.evaluation.bindings",
                str(self.id),
                "Scenario must contain complete evaluation bindings",
            )
        evaluation_ids = tuple(item.id for item in evaluation_bindings)
        if len(evaluation_ids) != len(set(evaluation_ids)):
            raise _error(
                "plan.duplicate.evaluation.binding",
                str(self.id),
                "Scenario cannot repeat an evaluation binding",
            )
        call_ids = frozenset(item.call_id for item in calls)
        missing_producer = next(
            (
                item.produced_by_call
                for item in evaluation_bindings
                if item.produced_by_call not in call_ids
            ),
            None,
        )
        if missing_producer is not None:
            raise _error(
                "plan.evaluation.producer.missing",
                str(self.id),
                f"evaluation producer {missing_producer} is absent from Scenario calls",
            )
        object.__setattr__(self, "calls", calls)
        object.__setattr__(
            self,
            "evaluation_bindings",
            tuple(sorted(evaluation_bindings, key=lambda item: str(item.id))),
        )
        if not isinstance(self.build_identity, BuildIdentity):
            raise _error("plan.invalid.build.identity", str(self.id), "attempt must bind BuildIdentity")
        if not isinstance(self.evidence_environment_identity, EvidenceEnvironmentIdentity):
            raise _error("plan.invalid.evidence.environment", str(self.id), "attempt must bind EvidenceEnvironmentIdentity")
        if type(self.critical_remaining_millis) is not int or self.critical_remaining_millis < 0:
            raise _error("plan.invalid.critical.cost", str(self.id), "critical remaining cost must be non-negative")

    @property
    def runnable(self) -> bool:
        return True


@dataclass(frozen=True)
class BothJoinNode:
    id: NodeID
    scenario_id: ScenarioID
    journey_id: JourneyID
    predecessors: Tuple[NodeID, ...]
    critical_remaining_millis: int

    def __post_init__(self) -> None:
        object.__setattr__(self, "id", _node_id(self.id, "bothJoin.id"))
        object.__setattr__(self, "scenario_id", ScenarioID(parse_identifier("scenario", self.scenario_id, f"{self.id}.scenarioId")))
        object.__setattr__(self, "journey_id", JourneyID(parse_identifier("journey", self.journey_id, f"{self.id}.journeyId")))
        predecessors = tuple(_node_id(item, f"{self.id}.predecessors") for item in self.predecessors)
        if len(predecessors) != 2 or len(set(predecessors)) != 2:
            raise _error("plan.invalid.both.join", str(self.id), "both join must depend on two distinct attempts")
        object.__setattr__(self, "predecessors", tuple(sorted(predecessors, key=str)))
        if type(self.critical_remaining_millis) is not int or self.critical_remaining_millis < 0:
            raise _error("plan.invalid.critical.cost", str(self.id), "critical remaining cost must be non-negative")

    @property
    def cost_millis(self) -> int:
        return 0

    @property
    def lane_candidates(self) -> Tuple[BoundLane, ...]:
        return ()

    @property
    def runnable(self) -> bool:
        return False


RunPlanNode = Union[ScenarioAttemptNode, BothJoinNode]


@dataclass(frozen=True)
class CompiledRunPlan:
    catalog_digest: Digest
    catalog_gate_digest: Digest
    selector: Selector
    reviewed_facts: Tuple[ReviewedFact, ...]
    build_identity: BuildIdentity
    evidence_environment_identity: EvidenceEnvironmentIdentity
    requested_lanes: Tuple[BoundLane, ...]
    preparation_bindings: Tuple[PreparationBinding, ...]
    nodes: Tuple[RunPlanNode, ...]
    main_gates: Tuple[MainGateBinding, ...]
    critical_costs: Tuple[CriticalCost, ...]
    reviewed_facts_digest: Digest = field(init=False)
    plan_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "catalog_digest", _digest(self.catalog_digest, "compiledPlan.catalogDigest"))
        object.__setattr__(self, "catalog_gate_digest", _digest(self.catalog_gate_digest, "compiledPlan.catalogGateDigest"))
        if not isinstance(self.selector, (FullSelector, PromiseSelector, ScenarioSelector)):
            raise _error("plan.invalid.selector", "compiledPlan.selector", "expected a typed selector")
        facts = tuple(self.reviewed_facts)
        if any(not isinstance(item, ReviewedFact) for item in facts):
            raise _error("plan.invalid.reviewed.fact", "compiledPlan.reviewedFacts", "expected ReviewedFact values")
        object.__setattr__(self, "reviewed_facts", tuple(sorted(facts, key=lambda item: str(item.id))))
        object.__setattr__(self, "reviewed_facts_digest", reviewed_facts_digest(self.reviewed_facts))
        if not isinstance(self.build_identity, BuildIdentity):
            raise _error("plan.invalid.build.identity", "compiledPlan.buildIdentity", "expected BuildIdentity")
        if not isinstance(self.evidence_environment_identity, EvidenceEnvironmentIdentity):
            raise _error("plan.invalid.evidence.environment", "compiledPlan.evidenceEnvironment", "expected EvidenceEnvironmentIdentity")
        object.__setattr__(self, "requested_lanes", _lanes(tuple(self.requested_lanes), "compiledPlan.requestedLanes"))
        preparations = tuple(self.preparation_bindings)
        nodes = tuple(self.nodes)
        gates = tuple(self.main_gates)
        costs = tuple(self.critical_costs)
        if any(not isinstance(item, PreparationBinding) for item in preparations):
            raise _error("plan.invalid.preparation.binding", "compiledPlan.preparations", "expected PreparationBinding values")
        if not nodes or any(not isinstance(item, (ScenarioAttemptNode, BothJoinNode)) for item in nodes):
            raise _error("plan.invalid.nodes", "compiledPlan.nodes", "plan must contain run nodes")
        node_ids = tuple(item.id for item in nodes)
        if len(node_ids) != len(set(node_ids)):
            raise _error("plan.duplicate.node", "compiledPlan.nodes", "node IDs must be unique")
        if any(not isinstance(item, MainGateBinding) for item in gates):
            raise _error("plan.invalid.main.gate", "compiledPlan.mainGates", "expected MainGateBinding values")
        if tuple(item.lane for item in gates) != self.requested_lanes:
            raise _error("plan.main.gate.coverage", "compiledPlan.mainGates", "main gates must cover requested lanes exactly once")
        cost_ids = tuple(item.node_id for item in costs)
        if set(cost_ids) != set(node_ids) or len(cost_ids) != len(set(cost_ids)):
            raise _error("plan.critical.cost.coverage", "compiledPlan.criticalCosts", "critical costs must cover every node exactly once")
        by_cost = {item.node_id: item.remaining_millis for item in costs}
        if any(by_cost[item.id] != item.critical_remaining_millis for item in nodes):
            raise _error("plan.critical.cost.mismatch", "compiledPlan.criticalCosts", "node critical costs must match the scheduler result")
        object.__setattr__(
            self,
            "preparation_bindings",
            tuple(
                sorted(
                    preparations,
                    key=lambda item: (
                        _lane_sort_key(item.lane),
                        str(item.preparation_id),
                    ),
                )
            ),
        )
        object.__setattr__(self, "nodes", tuple(sorted(nodes, key=lambda item: str(item.id))))
        object.__setattr__(
            self,
            "main_gates",
            tuple(sorted(gates, key=lambda item: _lane_sort_key(item.lane))),
        )
        object.__setattr__(self, "critical_costs", tuple(sorted(costs, key=lambda item: str(item.node_id))))
        object.__setattr__(
            self, "plan_digest", canonical_digest(compiled_plan_payload(self))
        )

    @property
    def digest(self) -> Digest:
        return self.plan_digest

    @property
    def preparation_rules(self) -> Tuple[PreparationBinding, ...]:
        return self.preparation_bindings

    @property
    def evidence_environment(self) -> EvidenceEnvironmentIdentity:
        return self.evidence_environment_identity


def _selector_payload(selector: Selector) -> object:
    if isinstance(selector, FullSelector):
        return {"kind": "full"}
    if isinstance(selector, PromiseSelector):
        return {"kind": "promise", "promiseIds": [str(item) for item in selector.promise_ids]}
    if isinstance(selector, ScenarioSelector):
        return {"kind": "scenario", "scenarioIds": [str(item) for item in selector.scenario_ids]}
    raise TypeError(f"unsupported selector: {type(selector).__name__}")


def _build_identity_payload(identity: BuildIdentity) -> object:
    toolchain = identity.toolchain
    return {
        "bundleIdentifier": identity.bundle_identifier,
        "gitRevision": identity.git_revision,
        "sourceTreeDigest": str(identity.source_tree_digest),
        "configurationDigest": str(identity.configuration_digest),
        "toolchain": {
            "xcodeVersion": toolchain.xcode_version,
            "xcodeBuild": toolchain.xcode_build,
            "visionOSSDKVersion": toolchain.visionos_sdk_version,
            "visionOSSDKBuild": toolchain.visionos_sdk_build,
            "visionOSSimulatorSDKVersion": toolchain.visionos_simulator_sdk_version,
            "visionOSSimulatorSDKBuild": toolchain.visionos_simulator_sdk_build,
        },
        "laneArtifacts": [
            {
                "lane": item.lane.value,
                "xctestrunDigest": str(item.xctestrun_digest),
                "testProductsDigest": str(item.test_products_digest),
                "applicationCodeDigest": str(item.application_code_digest),
            }
            for item in identity.lane_artifacts
        ],
    }


def _evidence_environment_payload(identity: EvidenceEnvironmentIdentity) -> object:
    agent = identity.agent_environment
    return {
        "deterministicRuntimeDigest": str(identity.deterministic_runtime_digest),
        "agentEnvironment": None
        if agent is None
        else {
            "model": agent.model,
            "promptDigest": str(agent.prompt_digest),
            "configurationDigest": str(agent.configuration_digest),
        },
    }


def _state_requirement_payload(requirement: StateRequirement) -> object:
    return {"key": str(requirement.key), "schema": str(requirement.schema)}


def _state_declaration_payload(declaration: StateDeclaration) -> object:
    return {
        "key": str(declaration.key),
        "schema": str(declaration.schema),
        "producedByCall": str(declaration.produced_by_call),
        "dependsOnTags": [
            str(item) for item in sorted(declaration.depends_on_tags, key=str)
        ],
    }


def _allowed_call_payload(call: AllowedOperationCall) -> object:
    return {
        "callId": str(call.call_id),
        "operation": str(call.operation),
        "operationDigest": str(call.contract_digest),
        "argumentsBytes": call.arguments_bytes.decode("utf-8"),
        "argumentsDigest": str(call.arguments_digest),
        "implementationLocator": call.implementation_locator,
        "implementationDigest": str(call.implementation_digest),
        "maxInvocations": call.max_invocations,
        "invalidatesTags": [
            str(item) for item in sorted(call.invalidates_tags, key=str)
        ],
    }


def _evaluation_payload(binding: EvaluationBinding) -> object:
    return {
        "id": str(binding.id),
        "artifactClass": binding.artifact_class.value,
        "evidenceType": str(binding.evidence_type),
        "evidenceSchema": str(binding.evidence_schema),
        "caseKey": str(binding.case_key),
        "producedByCall": str(binding.produced_by_call),
        "producerContractDigest": str(binding.producer_contract_digest),
        "oracle": {
            "id": str(binding.oracle.id),
            "kind": binding.oracle.kind.value,
            "contractDigest": str(binding.oracle.contract_digest),
            "implementationLocator": binding.oracle.implementation_locator,
            "implementationDigest": str(binding.oracle.implementation_digest),
            "body": binding.oracle.body,
        },
        "rubric": {
            "id": str(binding.rubric.id),
            "contractDigest": str(binding.rubric.contract_digest),
            "criteria": list(binding.rubric.criteria),
            "negativeControls": list(binding.rubric.negative_controls),
            "body": binding.rubric.body,
        },
    }


def _success_payload(expression: SuccessExpression) -> object:
    if isinstance(expression, ObservationRef):
        return {"observation": str(expression.ref)}
    if isinstance(expression, AllOf):
        return {"all": [_success_payload(item) for item in expression.terms]}
    if isinstance(expression, AnyOf):
        return {"any": [_success_payload(item) for item in expression.terms]}
    if isinstance(expression, Not):
        return {"not": _success_payload(expression.term)}
    if isinstance(expression, AtLeast):
        return {
            "atLeast": {
                "count": expression.count,
                "of": [_success_payload(item) for item in expression.terms],
            }
        }
    raise TypeError(f"unsupported success expression: {type(expression).__name__}")


def _reviewed_fact_payload(fact: ReviewedFact) -> object:
    return {
        "fact": str(fact.id),
        "value": fact.value,
        "sourceDigest": str(fact.source_digest),
        "reviewReceiptDigest": str(fact.review_receipt_digest),
    }


def _preparation_payload(binding: PreparationBinding) -> object:
    return {
        "preparationId": str(binding.preparation_id),
        "lane": binding.lane.value,
        "contractDigest": str(binding.contract_digest),
        "estimatedCostMillis": binding.estimated_cost_millis,
        "prerequisites": [_state_requirement_payload(item) for item in binding.prerequisites],
        "calls": [_allowed_call_payload(item) for item in binding.calls],
        "produces": [_state_declaration_payload(item) for item in binding.produces],
        "prerequisiteBindings": [
            {
                "lane": item.lane.value,
                "requirement": _state_requirement_payload(item.requirement),
                "preparationId": str(item.preparation_id),
            }
            for item in binding.prerequisite_bindings
        ],
    }


def _node_payload(node: RunPlanNode) -> object:
    if isinstance(node, BothJoinNode):
        return {
            "kind": "bothJoin",
            "id": str(node.id),
            "scenarioId": str(node.scenario_id),
            "journeyId": str(node.journey_id),
            "predecessors": [str(item) for item in node.predecessors],
            "costMillis": 0,
            "runnable": False,
            "criticalRemainingMillis": node.critical_remaining_millis,
        }
    return {
        "kind": "scenarioAttempt",
        "id": str(node.id),
        "scenarioId": str(node.scenario_id),
        "journeyId": str(node.journey_id),
        "scenarioDigest": str(node.scenario_digest),
        "laneCandidates": [item.value for item in node.lane_candidates],
        "bindsLaneOnClaim": node.binds_lane_on_claim,
        "costMillis": node.cost_millis,
        "predecessors": [str(item) for item in node.predecessors],
        "gateDependencies": [
            {"lane": item.lane.value, "nodeId": str(item.gate_node_id)}
            for item in node.gate_dependencies
        ],
        "preparationRequirements": [
            {
                "lane": item.lane.value,
                "requirement": _state_requirement_payload(item.requirement),
                "preparationId": str(item.preparation_id),
            }
            for item in node.preparation_requirements
        ],
        "calls": [_allowed_call_payload(item) for item in node.calls],
        "evaluationBindings": [
            _evaluation_payload(item) for item in node.evaluation_bindings
        ],
        "success": _success_payload(node.success),
        "buildIdentityDigest": str(node.build_identity.digest),
        "evidenceEnvironmentDigest": str(node.evidence_environment_identity.digest),
        "criticalRemainingMillis": node.critical_remaining_millis,
    }


def compiled_plan_payload(plan: CompiledRunPlan) -> Dict[str, Any]:
    if not isinstance(plan, CompiledRunPlan):
        raise _error(
            "plan.invalid.compiled.plan",
            "plan",
            "expected CompiledRunPlan",
        )
    return {
        "catalogDigest": str(plan.catalog_digest),
        "catalogGateDigest": str(plan.catalog_gate_digest),
        "selector": _selector_payload(plan.selector),
        "reviewedFacts": [_reviewed_fact_payload(item) for item in plan.reviewed_facts],
        "reviewedFactsDigest": str(plan.reviewed_facts_digest),
        "buildIdentity": _build_identity_payload(plan.build_identity),
        "evidenceEnvironmentIdentity": _evidence_environment_payload(plan.evidence_environment_identity),
        "requestedLanes": [item.value for item in plan.requested_lanes],
        "preparationRules": [_preparation_payload(item) for item in plan.preparation_bindings],
        "nodes": [_node_payload(item) for item in plan.nodes],
        "mainGates": [
            {"lane": item.lane.value, "scenarioId": str(item.scenario_id), "nodeId": str(item.node_id)}
            for item in plan.main_gates
        ],
        "criticalCosts": [
            {"nodeId": str(item.node_id), "remainingMillis": item.remaining_millis}
            for item in plan.critical_costs
        ],
    }


def compiled_plan_bytes(plan: CompiledRunPlan) -> bytes:
    return canonical_bytes(compiled_plan_payload(plan))


__all__ = (
    "AgentEnvironment",
    "BothJoinNode",
    "BuildIdentity",
    "CatalogAnalysis",
    "CatalogMainGate",
    "CompileRequest",
    "CompiledRunPlan",
    "EvaluationBinding",
    "EvidenceEnvironmentIdentity",
    "FullSelector",
    "LaneBuildArtifact",
    "LaneGateDependency",
    "MainGateBinding",
    "OracleEvaluationBinding",
    "PreparationBinding",
    "PreparationReadinessAnalysis",
    "PreparationRequirementBinding",
    "PreparationResolution",
    "PromiseSelector",
    "RunPlanNode",
    "RubricEvaluationBinding",
    "ScenarioAttemptNode",
    "ScenarioDependency",
    "ScenarioReadinessAnalysis",
    "ScenarioSelector",
    "Selector",
    "ToolchainIdentity",
    "compiled_plan_bytes",
    "compiled_plan_payload",
)
