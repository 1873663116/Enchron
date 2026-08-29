from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import re
from typing import Any, FrozenSet, Mapping, Optional, Tuple, Union

from .applicability import Applicability
from .digest import canonical_bytes, canonical_digest, digest_bytes
from .errors import RegressionError
from .expression import SuccessExpression
from .ids import (
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
    parse_call_id,
    parse_case_key,
    parse_evidence_schema,
    parse_evidence_type,
    parse_identifier,
    parse_state_key,
    parse_state_schema,
)


class AutomationScope(Enum):
    INCLUDED = "included"
    EXCLUDED = "excluded"


class LaneRequirement(Enum):
    SIMULATOR = "simulator"
    DEVICE = "device"
    EITHER = "either"
    BOTH = "both"


class BoundLane(Enum):
    SIMULATOR = "simulator"
    DEVICE = "device"


class OperationRole(Enum):
    SETUP = "setup"
    PRODUCT_BEHAVIOR = "product-behavior"
    EVIDENCE = "evidence"
    DIAGNOSTIC_BYPASS = "diagnostic-bypass"


class ArtifactClass(Enum):
    COVERAGE = "coverage"
    PREPARATION = "preparation"
    DIAGNOSTIC = "diagnostic"


class OracleKind(Enum):
    DETERMINISTIC = "deterministic"
    AGENT = "agent"


class ArgumentValueKind(Enum):
    BOOLEAN = "boolean"
    INTEGER = "integer"
    STRING = "string"
    STRING_LIST = "string-list"


class NodeStateKind(Enum):
    PENDING = "pending"
    READY = "ready"
    LEASED = "leased"
    PASSED = "passed"
    FAILED = "failed"
    BLOCKED_BY = "blocked-by"


class ContractReadiness(Enum):
    READY = "ready"
    HUMAN_COVERAGE_BLOCKED = "human-coverage-blocked"
    IMPLEMENTATION_GAP = "implementation-gap"


_ARGUMENT_NAME = re.compile(r"[a-z][A-Za-z0-9]*")
_HUMAN_COVERAGE_QUESTION = re.compile(r"HC-[0-9]{3}")


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


def _non_empty(value: object, location: str, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise _error("contract.empty_string", location, f"{label} must not be empty")
    return value


def _argument_name(value: object, location: str) -> str:
    value = _non_empty(value, location, "argument name")
    if _ARGUMENT_NAME.fullmatch(value) is None:
        raise _error(
            "contract.invalid_argument_name",
            location,
            "argument name must use lowerCamelCase",
        )
    return value


def _enum(value: object, enum_type: Any, location: str) -> Any:
    if not isinstance(value, enum_type):
        raise _error("contract.invalid_enum", location, f"expected {enum_type.__name__}")
    return value


def _source_fields(instance: object, kind: str, identifier: str) -> None:
    body = getattr(instance, "body")
    source_digest = getattr(instance, "source_digest")
    if not isinstance(body, str):
        raise _error("contract.invalid_body", identifier, "body must be text")
    source_digest = Digest(
        parse_identifier("digest", source_digest, f"{identifier}.sourceDigest")
    )
    object.__setattr__(instance, "source_digest", source_digest)
    object.__setattr__(
        instance,
        "leaf_digest",
        canonical_digest(
            {"kind": kind, "id": identifier, "sourceDigest": str(source_digest)}
        ),
    )


def _strings(
    values: Tuple[str, ...],
    location: str,
    label: str,
    empty_code: str,
) -> Tuple[str, ...]:
    result = tuple(values)
    if not result:
        raise _error(empty_code, location, f"{label} must not be empty")
    for index, value in enumerate(result):
        _non_empty(value, f"{location}[{index}]", label)
    if len(result) != len(set(result)):
        raise _error(
            "contract.duplicate_item",
            location,
            f"{label} must not contain duplicates",
        )
    return result


@dataclass(frozen=True)
class PromiseContract:
    id: PromiseID
    title: str
    statement: str
    scope: AutomationScope
    reason: Optional[str]
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = PromiseID(parse_identifier("promise", self.id, "promise.id"))
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        _non_empty(self.statement, f"{identifier}.statement", "statement")
        _enum(self.scope, AutomationScope, f"{identifier}.automation.scope")
        if self.reason is not None:
            _non_empty(self.reason, f"{identifier}.automation.reason", "reason")
        if self.scope is AutomationScope.EXCLUDED and self.reason is None:
            raise _error(
                "contract.excluded_promise_without_reason",
                str(identifier),
                "an excluded Promise must state a reason",
            )
        _source_fields(self, "promise", str(identifier))


@dataclass(frozen=True)
class FactDeclaration:
    id: FactID
    title: str
    statement: str
    value_type: ArgumentValueKind
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = FactID(parse_identifier("fact", self.id, "fact.id"))
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        _non_empty(self.statement, f"{identifier}.statement", "statement")
        _enum(self.value_type, ArgumentValueKind, f"{identifier}.valueType")
        if self.value_type is ArgumentValueKind.STRING_LIST:
            raise _error(
                "contract.invalid_fact_value_type",
                f"{identifier}.valueType",
                "Facts support boolean, integer, or string values",
            )
        _source_fields(self, "fact", str(identifier))


@dataclass(frozen=True)
class ArgumentField:
    name: str
    value_type: ArgumentValueKind
    required: bool

    def __post_init__(self) -> None:
        _argument_name(self.name, "argument.name")
        _enum(self.value_type, ArgumentValueKind, f"argument.{self.name}.type")
        if type(self.required) is not bool:
            raise _error(
                "contract.invalid_argument_required",
                f"argument.{self.name}.required",
                "required must be a boolean",
            )

    def accepts(self, value: object) -> bool:
        if self.value_type is ArgumentValueKind.BOOLEAN:
            return type(value) is bool
        if self.value_type is ArgumentValueKind.INTEGER:
            return type(value) is int
        if self.value_type is ArgumentValueKind.STRING:
            return isinstance(value, str)
        return isinstance(value, list) and all(
            isinstance(item, str) for item in value
        )


@dataclass(frozen=True)
class ArgumentSchema:
    fields: Tuple[ArgumentField, ...]

    def __post_init__(self) -> None:
        fields = tuple(self.fields)
        if any(not isinstance(item, ArgumentField) for item in fields):
            raise _error(
                "contract.invalid_argument_field",
                "operation.argumentSchema.fields",
                "fields must contain ArgumentField values",
            )
        names = tuple(item.name for item in fields)
        if len(names) != len(set(names)):
            raise _error(
                "contract.duplicate_argument_field",
                "operation.argumentSchema.fields",
                "an argument field may be declared only once",
            )
        object.__setattr__(self, "fields", fields)

    def canonicalize(self, arguments: Mapping[str, Any], location: str) -> bytes:
        if not isinstance(arguments, Mapping):
            raise _error(
                "contract.arguments_not_object",
                location,
                "operation arguments must be a JSON object",
            )
        field_by_name = {item.name: item for item in self.fields}
        unknown = sorted(set(arguments) - set(field_by_name))
        if unknown:
            raise _error(
                "contract.unknown_argument",
                location,
                "unknown argument(s): " + ", ".join(unknown),
            )
        missing = sorted(
            item.name
            for item in self.fields
            if item.required and item.name not in arguments
        )
        if missing:
            raise _error(
                "contract.missing_argument",
                location,
                "missing required argument(s): " + ", ".join(missing),
            )
        for name, value in arguments.items():
            if not field_by_name[name].accepts(value):
                raise _error(
                    "contract.invalid_argument_type",
                    f"{location}.{name}",
                    f"expected {field_by_name[name].value_type.value}",
                )
        return canonical_bytes(dict(arguments))


@dataclass(frozen=True, order=True)
class EvidenceSchemaPair:
    evidence_type: EvidenceType
    evidence_schema: EvidenceSchema

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "evidence_type",
            parse_evidence_type(self.evidence_type, "evidenceSchemaPair.evidenceType"),
        )
        object.__setattr__(
            self,
            "evidence_schema",
            parse_evidence_schema(
                self.evidence_schema, "evidenceSchemaPair.evidenceSchema"
            ),
        )


@dataclass(frozen=True)
class HumanCoverageBlocker:
    question_id: str
    detail: str

    def __post_init__(self) -> None:
        question_id = _non_empty(
            self.question_id, "humanCoverageBlocker.questionId", "questionId"
        )
        if _HUMAN_COVERAGE_QUESTION.fullmatch(question_id) is None:
            raise _error(
                "contract.invalid_human_coverage_question",
                "humanCoverageBlocker.questionId",
                "questionId must use HC-NNN",
            )
        _non_empty(self.detail, "humanCoverageBlocker.detail", "blocker detail")


@dataclass(frozen=True)
class ImplementationGapBlocker:
    capability: str
    detail: str

    def __post_init__(self) -> None:
        _non_empty(
            self.capability,
            "implementationGapBlocker.capability",
            "capability",
        )
        _non_empty(self.detail, "implementationGapBlocker.detail", "blocker detail")


ContractBlocker = Union[HumanCoverageBlocker, ImplementationGapBlocker]


def _readiness(
    readiness: ContractReadiness,
    blockers: Tuple[ContractBlocker, ...],
    location: str,
) -> Tuple[ContractBlocker, ...]:
    _enum(readiness, ContractReadiness, f"{location}.readiness")
    values = tuple(blockers)
    if any(
        not isinstance(item, (HumanCoverageBlocker, ImplementationGapBlocker))
        for item in values
    ):
        raise _error(
            "contract.invalid_blocker",
            f"{location}.blockers",
            "blockers must contain typed blocker values",
        )
    if readiness is ContractReadiness.READY:
        if values:
            raise _error(
                "contract.ready_with_blockers",
                f"{location}.blockers",
                "a ready contract cannot declare blockers",
            )
        return values
    if not values:
        raise _error(
            "contract.non_ready_without_blocker",
            f"{location}.blockers",
            "a non-ready contract must declare a blocker",
        )
    expected = (
        HumanCoverageBlocker
        if readiness is ContractReadiness.HUMAN_COVERAGE_BLOCKED
        else ImplementationGapBlocker
    )
    if any(not isinstance(item, expected) for item in values):
        raise _error(
            "contract.blocker_readiness_mismatch",
            f"{location}.blockers",
            f"{readiness.value} requires {expected.__name__} values",
        )
    if len(values) != len(set(values)):
        raise _error(
            "contract.duplicate_blocker",
            f"{location}.blockers",
            "a blocker may appear only once",
        )
    return values


@dataclass(frozen=True)
class OperationContract:
    id: OperationID
    title: str
    role: OperationRole
    lanes: FrozenSet[BoundLane]
    argument_schema: ArgumentSchema
    invalidates_tags: FrozenSet[StateTag]
    evidence_schemas: FrozenSet[EvidenceSchemaPair]
    implementation_locator: str
    implementation_digest: Digest
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = OperationID(parse_identifier("operation", self.id, "operation.id"))
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        _enum(self.role, OperationRole, f"{identifier}.role")
        lanes = frozenset(self.lanes)
        if not lanes or any(not isinstance(lane, BoundLane) for lane in lanes):
            raise _error(
                "contract.invalid_operation_lanes",
                f"{identifier}.lanes",
                "lanes must contain simulator or device",
            )
        object.__setattr__(self, "lanes", lanes)
        if not isinstance(self.argument_schema, ArgumentSchema):
            raise _error(
                "contract.invalid_argument_schema",
                f"{identifier}.argumentSchema",
                "expected an ArgumentSchema",
            )
        invalidates_tags = frozenset(
            StateTag(
                parse_identifier(
                    "state_tag", tag, f"{identifier}.invalidatesTags"
                )
            )
            for tag in self.invalidates_tags
        )
        evidence_schemas = frozenset(self.evidence_schemas)
        if any(
            not isinstance(item, EvidenceSchemaPair) for item in evidence_schemas
        ):
            raise _error(
                "contract.invalid_evidence_schema_pair",
                f"{identifier}.evidenceSchemas",
                "evidenceSchemas must contain EvidenceSchemaPair values",
            )
        object.__setattr__(self, "invalidates_tags", invalidates_tags)
        object.__setattr__(self, "evidence_schemas", evidence_schemas)
        _non_empty(
            self.implementation_locator,
            f"{identifier}.implementation.locator",
            "implementation locator",
        )
        object.__setattr__(
            self,
            "implementation_digest",
            Digest(
                parse_identifier(
                    "digest",
                    self.implementation_digest,
                    f"{identifier}.implementation.digest",
                )
            ),
        )
        _source_fields(self, "operation", str(identifier))


@dataclass(frozen=True)
class OracleContract:
    id: OracleID
    title: str
    kind: OracleKind
    evidence_schemas: FrozenSet[EvidenceSchemaPair]
    implementation_locator: str
    implementation_digest: Digest
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = OracleID(parse_identifier("oracle", self.id, "oracle.id"))
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        _enum(self.kind, OracleKind, f"{identifier}.kind")
        evidence_schemas = frozenset(self.evidence_schemas)
        if any(
            not isinstance(item, EvidenceSchemaPair) for item in evidence_schemas
        ):
            raise _error(
                "contract.invalid_evidence_schema_pair",
                f"{identifier}.evidenceSchemas",
                "evidenceSchemas must contain EvidenceSchemaPair values",
            )
        if not evidence_schemas:
            raise _error(
                "contract.empty_oracle_evidence_schemas",
                f"{identifier}.evidenceSchemas",
                "an Oracle must accept at least one evidence type and schema pair",
            )
        object.__setattr__(self, "evidence_schemas", evidence_schemas)
        _non_empty(
            self.implementation_locator,
            f"{identifier}.implementation.locator",
            "implementation locator",
        )
        object.__setattr__(
            self,
            "implementation_digest",
            Digest(
                parse_identifier(
                    "digest",
                    self.implementation_digest,
                    f"{identifier}.implementation.digest",
                )
            ),
        )
        _source_fields(self, "oracle", str(identifier))


@dataclass(frozen=True)
class RubricContract:
    id: RubricID
    title: str
    criteria: Tuple[str, ...]
    negative_controls: Tuple[str, ...]
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = RubricID(parse_identifier("rubric", self.id, "rubric.id"))
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        object.__setattr__(
            self,
            "criteria",
            _strings(
                tuple(self.criteria),
                f"{identifier}.criteria",
                "rubric criteria",
                "contract.empty_rubric",
            ),
        )
        object.__setattr__(
            self,
            "negative_controls",
            _strings(
                tuple(self.negative_controls),
                f"{identifier}.negativeControls",
                "rubric negative controls",
                "contract.empty_negative_controls",
            ),
        )
        _source_fields(self, "rubric", str(identifier))


@dataclass(frozen=True)
class StateRequirement:
    key: StateKey
    schema: StateSchema

    def __post_init__(self) -> None:
        key = parse_state_key(self.key, "stateRequirement.key")
        schema = parse_state_schema(
            self.schema, f"stateRequirement.{key}.schema"
        )
        object.__setattr__(self, "key", key)
        object.__setattr__(self, "schema", schema)


@dataclass(frozen=True)
class StateDeclaration:
    key: StateKey
    schema: StateSchema
    produced_by_call: Optional[CallID]
    depends_on_tags: Tuple[StateTag, ...]

    def __post_init__(self) -> None:
        key = parse_state_key(self.key, "stateDeclaration.key")
        schema = parse_state_schema(
            self.schema, f"stateDeclaration.{key}.schema"
        )
        object.__setattr__(self, "key", key)
        object.__setattr__(self, "schema", schema)
        if self.produced_by_call is not None:
            object.__setattr__(
                self,
                "produced_by_call",
                parse_call_id(
                    self.produced_by_call,
                    f"stateDeclaration.{key}.producedByCall",
                ),
            )
        tags = tuple(
            StateTag(
                parse_identifier(
                    "state_tag",
                    tag,
                    f"stateDeclaration.{key}.dependsOnTags",
                )
            )
            for tag in self.depends_on_tags
        )
        if not tags:
            raise _error(
                "contract.empty_state_tags",
                f"stateDeclaration.{key}.dependsOnTags",
                "a state declaration needs an invalidation tag",
            )
        if len(tags) != len(set(tags)):
            raise _error(
                "contract.duplicate_state_tag",
                f"stateDeclaration.{key}.dependsOnTags",
                "a state declaration cannot repeat a tag",
            )
        object.__setattr__(self, "depends_on_tags", tags)


@dataclass(frozen=True)
class OperationCall:
    call_id: CallID
    operation: OperationID
    arguments_bytes: bytes
    max_invocations: int
    arguments_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        call_id = parse_call_id(self.call_id, "operationCall.callId")
        object.__setattr__(self, "call_id", call_id)
        object.__setattr__(
            self,
            "operation",
            OperationID(
                parse_identifier(
                    "operation", self.operation, f"operationCall.{call_id}.operation"
                )
            ),
        )
        if not isinstance(self.arguments_bytes, bytes):
            raise _error(
                "contract.arguments_not_bytes",
                f"operationCall.{call_id}.arguments",
                "canonical arguments must be bytes",
            )
        if type(self.max_invocations) is not int or self.max_invocations < 1:
            raise _error(
                "contract.invalid_max_invocations",
                f"operationCall.{call_id}.maxInvocations",
                "maxInvocations must be a positive integer",
            )
        object.__setattr__(self, "arguments_digest", digest_bytes(self.arguments_bytes))


@dataclass(frozen=True)
class EvidenceObligation:
    id: ObligationID
    artifact_class: ArtifactClass
    evidence_type: EvidenceType
    evidence_schema: EvidenceSchema
    case_key: CaseKey
    produced_by_call: Optional[CallID]
    oracle: OracleID
    rubric: RubricID

    def __post_init__(self) -> None:
        identifier = ObligationID(parse_identifier("obligation", self.id, "obligation.id"))
        object.__setattr__(self, "id", identifier)
        _enum(self.artifact_class, ArtifactClass, f"{identifier}.artifactClass")
        if self.artifact_class is not ArtifactClass.COVERAGE:
            raise _error(
                "contract.non_coverage_obligation",
                str(identifier),
                "an EvidenceObligation may produce coverage only",
            )
        object.__setattr__(
            self,
            "evidence_type",
            parse_evidence_type(self.evidence_type, f"{identifier}.evidenceType"),
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
        if self.produced_by_call is not None:
            object.__setattr__(
                self,
                "produced_by_call",
                parse_call_id(self.produced_by_call, f"{identifier}.producedByCall"),
            )
        object.__setattr__(
            self,
            "oracle",
            OracleID(parse_identifier("oracle", self.oracle, f"{identifier}.oracle")),
        )
        object.__setattr__(
            self,
            "rubric",
            RubricID(parse_identifier("rubric", self.rubric, f"{identifier}.rubric")),
        )


def _requirements(
    values: Tuple[StateRequirement, ...], location: str
) -> Tuple[StateRequirement, ...]:
    result = tuple(values)
    if any(not isinstance(item, StateRequirement) for item in result):
        raise _error(
            "contract.invalid_state_requirement",
            location,
            "expected StateRequirement values",
        )
    identities = tuple((item.key, item.schema) for item in result)
    if len(identities) != len(set(identities)):
        raise _error(
            "contract.duplicate_state_requirement",
            location,
            "a state requirement may appear only once",
        )
    return result


def _calls(
    values: Tuple[OperationCall, ...], location: str, require_non_empty: bool = True
) -> Tuple[OperationCall, ...]:
    result = tuple(values)
    if require_non_empty and not result:
        raise _error(
            "catalog.empty_operations",
            location,
            "a runnable Catalog node must contain an Operation",
        )
    if any(not isinstance(item, OperationCall) for item in result):
        raise _error(
            "contract.invalid_operation_call",
            location,
            "expected OperationCall values",
        )
    call_ids = tuple(item.call_id for item in result)
    if len(call_ids) != len(set(call_ids)):
        raise _error(
            "catalog.duplicate_call",
            location,
            "a runnable Catalog node cannot repeat a callId",
        )
    return result


@dataclass(frozen=True)
class PreparationContract:
    id: PreparationID
    title: str
    lane: BoundLane
    estimated_cost_millis: int
    readiness: ContractReadiness
    blockers: Tuple[ContractBlocker, ...]
    prerequisites: Tuple[StateRequirement, ...]
    operations: Tuple[OperationCall, ...]
    produces: Tuple[StateDeclaration, ...]
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = PreparationID(
            parse_identifier("preparation", self.id, "preparation.id")
        )
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        _enum(self.lane, BoundLane, f"{identifier}.lane")
        if type(self.estimated_cost_millis) is not int or self.estimated_cost_millis <= 0:
            raise _error(
                "contract.invalid_estimated_cost",
                f"{identifier}.estimatedCostMillis",
                "estimatedCostMillis must be a positive integer",
            )
        prerequisites = _requirements(
            tuple(self.prerequisites), f"{identifier}.prerequisites"
        )
        blockers = _readiness(self.readiness, tuple(self.blockers), str(identifier))
        operations = _calls(
            tuple(self.operations),
            str(identifier),
            require_non_empty=self.readiness is ContractReadiness.READY,
        )
        produces = tuple(self.produces)
        if not produces:
            raise _error(
                "catalog.empty_produces",
                str(identifier),
                "a Preparation must declare produced state",
            )
        if any(not isinstance(item, StateDeclaration) for item in produces):
            raise _error(
                "contract.invalid_state_declaration",
                f"{identifier}.produces",
                "expected StateDeclaration values",
            )
        if self.readiness is ContractReadiness.READY and any(
            item.produced_by_call is None for item in produces
        ):
            raise _error(
                "contract.ready_preparation_without_producer",
                str(identifier),
                "a ready Preparation must name every state producer call",
            )
        if self.readiness is not ContractReadiness.READY and any(
            item.produced_by_call is not None for item in produces
        ):
            raise _error(
                "contract.non_ready_preparation_claims_producer",
                str(identifier),
                "a non-ready Preparation cannot claim that a planned call produces state",
            )
        identities = tuple((item.key, item.schema) for item in produces)
        if len(identities) != len(set(identities)):
            raise _error(
                "contract.duplicate_state_declaration",
                f"{identifier}.produces",
                "a Preparation cannot declare the same state twice",
            )
        object.__setattr__(self, "prerequisites", prerequisites)
        object.__setattr__(self, "blockers", blockers)
        object.__setattr__(self, "operations", operations)
        object.__setattr__(self, "produces", produces)
        _source_fields(self, "preparation", str(identifier))


@dataclass(frozen=True)
class ScenarioContract:
    id: ScenarioID
    title: str
    journey: JourneyID
    promise_refs: Tuple[PromiseID, ...]
    applicability: Applicability
    lane: LaneRequirement
    estimated_cost_millis: int
    static_cases: Tuple[CaseKey, ...]
    readiness: ContractReadiness
    blockers: Tuple[ContractBlocker, ...]
    prerequisites: Tuple[StateRequirement, ...]
    operations: Tuple[OperationCall, ...]
    obligations: Tuple[EvidenceObligation, ...]
    success: SuccessExpression
    main_gate_for: FrozenSet[BoundLane]
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = ScenarioID(parse_identifier("scenario", self.id, "scenario.id"))
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        object.__setattr__(
            self,
            "journey",
            JourneyID(parse_identifier("journey", self.journey, f"{identifier}.journey")),
        )
        promise_refs = tuple(
            PromiseID(parse_identifier("promise", item, f"{identifier}.promiseRefs"))
            for item in self.promise_refs
        )
        if not promise_refs:
            raise _error(
                "catalog.empty_promises",
                str(identifier),
                "a Scenario must reference a Promise",
            )
        if len(promise_refs) != len(set(promise_refs)):
            raise _error(
                "contract.duplicate_promise_reference",
                f"{identifier}.promiseRefs",
                "a Scenario cannot repeat a Promise reference",
            )
        prerequisites = _requirements(
            tuple(self.prerequisites), f"{identifier}.prerequisites"
        )
        static_cases = tuple(
            parse_case_key(item, f"{identifier}.staticCases[{index}]")
            for index, item in enumerate(self.static_cases)
        )
        if not static_cases:
            raise _error(
                "catalog.empty_static_cases",
                f"{identifier}.staticCases",
                "a Scenario must declare an ordered static case",
            )
        if len(static_cases) != len(set(static_cases)):
            raise _error(
                "catalog.duplicate_static_case",
                f"{identifier}.staticCases",
                "a Scenario cannot repeat a static case",
            )
        blockers = _readiness(self.readiness, tuple(self.blockers), str(identifier))
        operations = _calls(
            tuple(self.operations),
            str(identifier),
            require_non_empty=self.readiness is ContractReadiness.READY,
        )
        obligations = tuple(self.obligations)
        if not obligations:
            raise _error(
                "catalog.empty_obligations",
                str(identifier),
                "a Scenario must contain an obligation",
            )
        if any(not isinstance(item, EvidenceObligation) for item in obligations):
            raise _error(
                "contract.invalid_obligation",
                f"{identifier}.obligations",
                "expected EvidenceObligation values",
            )
        obligation_ids = tuple(item.id for item in obligations)
        if len(obligation_ids) != len(set(obligation_ids)):
            raise _error(
                "catalog.duplicate_obligation",
                str(identifier),
                "a Scenario cannot repeat an obligation ID",
            )
        unknown_cases = tuple(
            item.case_key for item in obligations if item.case_key not in static_cases
        )
        if unknown_cases:
            raise _error(
                "contract.unknown_obligation_case",
                str(identifier),
                f"obligation names undeclared case {unknown_cases[0]}",
            )
        if self.readiness is ContractReadiness.READY and any(
            item.produced_by_call is None for item in obligations
        ):
            raise _error(
                "contract.ready_obligation_without_producer",
                str(identifier),
                "every ready obligation must name a producer call",
            )
        if self.readiness is not ContractReadiness.READY and operations:
            raise _error(
                "contract.non_ready_with_operations",
                str(identifier),
                "a non-ready Scenario cannot declare executable calls",
            )
        if self.readiness is not ContractReadiness.READY and any(
            item.produced_by_call is not None for item in obligations
        ):
            raise _error(
                "contract.non_ready_with_producer",
                str(identifier),
                "a non-ready Scenario cannot declare evidence producers",
            )
        _enum(self.lane, LaneRequirement, f"{identifier}.lane")
        if type(self.estimated_cost_millis) is not int or self.estimated_cost_millis <= 0:
            raise _error(
                "contract.invalid_estimated_cost",
                f"{identifier}.estimatedCostMillis",
                "estimatedCostMillis must be a positive integer",
            )
        main_gate_for = frozenset(self.main_gate_for)
        if any(not isinstance(item, BoundLane) for item in main_gate_for):
            raise _error(
                "contract.invalid_main_gate_lane",
                f"{identifier}.mainGateFor",
                "mainGateFor must contain concrete lanes",
            )
        object.__setattr__(self, "promise_refs", promise_refs)
        object.__setattr__(self, "static_cases", static_cases)
        object.__setattr__(self, "blockers", blockers)
        object.__setattr__(self, "prerequisites", prerequisites)
        object.__setattr__(self, "operations", operations)
        object.__setattr__(self, "obligations", obligations)
        object.__setattr__(self, "main_gate_for", main_gate_for)
        _source_fields(self, "scenario", str(identifier))


@dataclass(frozen=True)
class JourneyContract:
    id: JourneyID
    title: str
    scenario_refs: Tuple[ScenarioID, ...]
    ordering: Tuple[Tuple[ScenarioID, ScenarioID], ...]
    shared_state: Tuple[StateRequirement, ...]
    body: str
    source_digest: Digest
    leaf_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        identifier = JourneyID(parse_identifier("journey", self.id, "journey.id"))
        object.__setattr__(self, "id", identifier)
        _non_empty(self.title, f"{identifier}.title", "title")
        scenario_refs = tuple(
            ScenarioID(parse_identifier("scenario", item, f"{identifier}.scenarioRefs"))
            for item in self.scenario_refs
        )
        if not scenario_refs:
            raise _error(
                "catalog.empty_journey",
                str(identifier),
                "a Journey must group a Scenario",
            )
        if len(scenario_refs) != len(set(scenario_refs)):
            raise _error(
                "catalog.duplicate_journey_scenario",
                str(identifier),
                "a Journey cannot list a Scenario twice",
            )
        ordering = tuple(
            (
                ScenarioID(
                    parse_identifier(
                        "scenario", edge[0], f"{identifier}.ordering.before"
                    )
                ),
                ScenarioID(
                    parse_identifier(
                        "scenario", edge[1], f"{identifier}.ordering.after"
                    )
                ),
            )
            for edge in self.ordering
        )
        if len(ordering) != len(set(ordering)):
            raise _error(
                "contract.duplicate_ordering_edge",
                f"{identifier}.ordering",
                "a Journey cannot repeat an ordering edge",
            )
        shared_state = _requirements(
            tuple(self.shared_state), f"{identifier}.sharedState"
        )
        object.__setattr__(self, "scenario_refs", scenario_refs)
        object.__setattr__(self, "ordering", ordering)
        object.__setattr__(self, "shared_state", shared_state)
        _source_fields(self, "journey", str(identifier))


CatalogContract = Union[
    PromiseContract,
    FactDeclaration,
    OperationContract,
    OracleContract,
    RubricContract,
    PreparationContract,
    JourneyContract,
    ScenarioContract,
]


def _contract_kind(contract: CatalogContract) -> str:
    if isinstance(contract, PromiseContract):
        return "promise"
    if isinstance(contract, FactDeclaration):
        return "fact"
    if isinstance(contract, OperationContract):
        return "operation"
    if isinstance(contract, OracleContract):
        return "oracle"
    if isinstance(contract, RubricContract):
        return "rubric"
    if isinstance(contract, PreparationContract):
        return "preparation"
    if isinstance(contract, JourneyContract):
        return "journey"
    if isinstance(contract, ScenarioContract):
        return "scenario"
    raise TypeError(f"unsupported Catalog contract: {type(contract).__name__}")


@dataclass(frozen=True)
class DraftCatalog:
    promises: Tuple[PromiseContract, ...]
    facts: Tuple[FactDeclaration, ...]
    operations: Tuple[OperationContract, ...]
    oracles: Tuple[OracleContract, ...]
    rubrics: Tuple[RubricContract, ...]
    preparations: Tuple[PreparationContract, ...]
    journeys: Tuple[JourneyContract, ...]
    scenarios: Tuple[ScenarioContract, ...]
    catalog_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        field_names = (
            "promises",
            "facts",
            "operations",
            "oracles",
            "rubrics",
            "preparations",
            "journeys",
            "scenarios",
        )
        for name in field_names:
            values = tuple(getattr(self, name))
            object.__setattr__(
                self, name, tuple(sorted(values, key=lambda item: str(item.id)))
            )
        leaves = tuple(
            sorted(
                (
                    (_contract_kind(contract), str(contract.id), str(contract.leaf_digest))
                    for contract in self.contracts
                ),
                key=lambda item: (item[0], item[1]),
            )
        )
        object.__setattr__(
            self,
            "catalog_digest",
            canonical_digest(
                [
                    {"kind": kind, "id": identifier, "digest": digest}
                    for kind, identifier, digest in leaves
                ]
            ),
        )

    @property
    def contracts(self) -> Tuple[CatalogContract, ...]:
        return (
            self.promises
            + self.facts
            + self.operations
            + self.oracles
            + self.rubrics
            + self.preparations
            + self.journeys
            + self.scenarios
        )

    @property
    def digest(self) -> Digest:
        return self.catalog_digest


__all__ = (
    "ArgumentField",
    "ArgumentSchema",
    "ArgumentValueKind",
    "ArtifactClass",
    "AutomationScope",
    "BoundLane",
    "CatalogContract",
    "ContractBlocker",
    "ContractReadiness",
    "DraftCatalog",
    "EvidenceSchemaPair",
    "EvidenceObligation",
    "FactDeclaration",
    "JourneyContract",
    "HumanCoverageBlocker",
    "ImplementationGapBlocker",
    "LaneRequirement",
    "NodeStateKind",
    "OperationCall",
    "OperationContract",
    "OperationRole",
    "OracleContract",
    "OracleKind",
    "PreparationContract",
    "PromiseContract",
    "RubricContract",
    "ScenarioContract",
    "StateDeclaration",
    "StateRequirement",
)
