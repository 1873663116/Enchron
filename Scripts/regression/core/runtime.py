from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
import os
from pathlib import Path
import re
import secrets
import tempfile
import time
from typing import Any, Dict, Iterable, Mapping, Optional, Protocol, Sequence, Tuple

from .capability import (
    AllowedOperationCall,
    AssignmentCapability,
    InvocationCount,
    InvocationCounts,
    OperationGrant,
    OperationRequest,
    authorize_operation as decide_authorization,
)
from .contracts import BoundLane, StateRequirement
from .digest import canonical_bytes, canonical_digest, digest_bytes
from .errors import RegressionError
from .events import EventType, decode_json_bytes, now_rfc3339_millis
from .expression import OracleResult, evaluate_success
from .ids import (
    CallID,
    CaseKey,
    Digest,
    EvidenceSchema,
    EvidenceType,
    LeaseID,
    NodeID,
    ObligationID,
    OperationID,
    OracleID,
    RunID,
    SidekickID,
    StateKey,
    StateSchema,
    parse_call_id,
    parse_case_key,
    parse_evidence_schema,
    parse_evidence_type,
    parse_identifier,
    parse_state_key,
    parse_state_schema,
)
from .ledger import LedgerWriter
from .plan import (
    AgentEnvironment,
    BothJoinNode,
    CompiledRunPlan,
    EvaluationBinding,
    PreparationBinding,
    ScenarioAttemptNode,
    compiled_plan_payload,
    success_payload,
)
from .replay import read_event_log, replay
from .runview import (
    AcceptedArtifactView,
    CallPlanView,
    FrozenJSONObject,
    LeaseStatus,
    NodeStatus,
    RunOutcome,
    RunView,
    StateProductionView,
    TERMINAL_NODE_STATUSES,
    TRANSITION_FAULT_INTERRUPTION_PREFIX,
    _assigned_emergency_arm,
    aggregate_oracle_results,
    attempt_ended_on_the_harness,
    attempts_of,
    awaiting_adjudication,
    build_run_view,
    current_lease,
    derivable_verdict,
    nodes_awaiting_adjudication,
    resolve_call_arguments,
    settled_oracle_result,
)
from .scheduler import ReadyCandidate, choose_ready
from .state import capture_state_handle
from .store import ArtifactInput, ArtifactReceipt, ArtifactStore


PLAN_FILENAME = "plan.json"
DEFAULT_LEASE_DURATION_MILLIS = 60_000
CLOSED_AS_PASSED = (
    NodeStatus.PASSED,
    NodeStatus.BLOCKED_BY,
    NodeStatus.FAILED_KNOWN,
)
_TRANSITION_TRACE_DISARM = OperationID("operation:transition-trace.disarm@1")


@dataclass(frozen=True)
class AssignmentLease:
    id: LeaseID
    node_id: NodeID
    lane: BoundLane
    sidekick_id: SidekickID
    capability: AssignmentCapability
    assignment_directory: Path


@dataclass(frozen=True)
class StateFingerprint:
    key: StateKey
    schema: StateSchema
    digest: Digest

    def __post_init__(self) -> None:
        object.__setattr__(self, "key", parse_state_key(self.key, "stateFingerprint.key"))
        object.__setattr__(
            self,
            "schema",
            parse_state_schema(self.schema, "stateFingerprint.schema"),
        )
        object.__setattr__(
            self,
            "digest",
            Digest(parse_identifier("digest", self.digest, "stateFingerprint.digest")),
        )


@dataclass(frozen=True)
class OperationResult:
    succeeded: bool
    state_fingerprints: Tuple[StateFingerprint, ...] = ()
    detail: str = ""
    outputs: FrozenJSONObject = FrozenJSONObject()

    def __post_init__(self) -> None:
        if type(self.succeeded) is not bool:
            raise RegressionError(
                "runtime.invalid_operation_result",
                "succeeded",
                "operation result succeeded must be a boolean",
            )
        fingerprints = tuple(self.state_fingerprints)
        if any(not isinstance(item, StateFingerprint) for item in fingerprints):
            raise RegressionError(
                "runtime.invalid_operation_result",
                "stateFingerprints",
                "state fingerprints must contain StateFingerprint values",
            )
        identities = tuple((item.key, item.schema) for item in fingerprints)
        if len(identities) != len(set(identities)):
            raise RegressionError(
                "runtime.duplicate_state_fingerprint",
                "stateFingerprints",
                "an operation result cannot repeat a state fingerprint",
            )
        if not isinstance(self.detail, str):
            raise RegressionError(
                "runtime.invalid_operation_result",
                "detail",
                "operation result detail must be text",
            )
        outputs = self.outputs
        if not isinstance(outputs, FrozenJSONObject):
            if not isinstance(outputs, Mapping):
                raise RegressionError(
                    "runtime.invalid_operation_output",
                    "outputs",
                    "operation outputs must be a JSON object",
                )
            outputs = FrozenJSONObject.from_mapping(outputs)
        object.__setattr__(self, "state_fingerprints", fingerprints)
        object.__setattr__(self, "outputs", outputs)


@dataclass(frozen=True)
class EmergencyOperationResult:
    call_id: CallID
    arguments_bytes: bytes
    result: OperationResult
    trigger: str

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "call_id",
            parse_call_id(self.call_id, "emergencyOperation.callId"),
        )
        if not isinstance(self.arguments_bytes, bytes):
            raise RegressionError(
                "runtime.invalid_emergency_operation",
                str(self.call_id),
                "emergency Operation arguments must be canonical bytes",
            )
        if not isinstance(self.result, OperationResult):
            raise RegressionError(
                "runtime.invalid_emergency_operation",
                str(self.call_id),
                "emergency Operation result must be OperationResult",
            )
        if self.result.state_fingerprints:
            raise RegressionError(
                "runtime.invalid_emergency_operation",
                str(self.call_id),
                "emergency Operation cannot produce reusable state",
            )
        if self.trigger not in ("exception", "cancellation"):
            raise RegressionError(
                "runtime.invalid_emergency_operation",
                str(self.call_id),
                "emergency Operation trigger must be exception or cancellation",
            )


@dataclass(frozen=True)
class EvidenceArtifact:
    obligation_id: ObligationID
    evidence_type: EvidenceType
    evidence_schema: EvidenceSchema
    case_key: CaseKey
    produced_by_call: CallID
    captured_at: str
    producer_contract_digest: Digest
    relative_path: str
    byte_length: int
    digest: Digest

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "obligation_id",
            ObligationID(
                parse_identifier("obligation", self.obligation_id, "artifact.obligationId")
            ),
        )
        object.__setattr__(
            self,
            "evidence_type",
            parse_evidence_type(self.evidence_type, "artifact.evidenceType"),
        )
        object.__setattr__(
            self,
            "evidence_schema",
            parse_evidence_schema(self.evidence_schema, "artifact.evidenceSchema"),
        )
        object.__setattr__(
            self,
            "case_key",
            parse_case_key(self.case_key, "artifact.caseKey"),
        )
        object.__setattr__(
            self,
            "produced_by_call",
            parse_call_id(self.produced_by_call, "artifact.producedByCall"),
        )
        _rfc3339_millis(self.captured_at, "artifact.capturedAt")
        object.__setattr__(
            self,
            "producer_contract_digest",
            Digest(
                parse_identifier(
                    "digest",
                    self.producer_contract_digest,
                    "artifact.producerContractDigest",
                )
            ),
        )
        if not isinstance(self.relative_path, str) or not self.relative_path:
            raise RegressionError(
                "runtime.invalid_artifact_path",
                str(self.obligation_id),
                "artifact relative path must be non-empty text",
            )
        if type(self.byte_length) is not int or self.byte_length <= 0:
            raise RegressionError(
                "runtime.invalid_artifact_length",
                str(self.obligation_id),
                "artifact byte length must be a positive integer",
            )
        object.__setattr__(
            self,
            "digest",
            Digest(parse_identifier("digest", self.digest, "artifact.digest")),
        )

    def payload(self) -> Mapping[str, Any]:
        return {
            "obligationId": str(self.obligation_id),
            "evidenceType": str(self.evidence_type),
            "evidenceSchema": str(self.evidence_schema),
            "caseKey": str(self.case_key),
            "producedByCall": str(self.produced_by_call),
            "capturedAt": self.captured_at,
            "producerContractDigest": str(self.producer_contract_digest),
            "relativePath": self.relative_path,
            "byteLength": self.byte_length,
            "digest": str(self.digest),
        }


@dataclass(frozen=True)
class EvidenceEnvelope:
    run_id: RunID
    plan_digest: Digest
    node_id: NodeID
    lease_id: LeaseID
    lane: BoundLane
    sidekick_id: SidekickID
    build_identity_digest: Digest
    evidence_environment_digest: Digest
    artifacts: Tuple[EvidenceArtifact, ...]

    def __post_init__(self) -> None:
        object.__setattr__(
            self, "run_id", RunID(parse_identifier("run", self.run_id, "envelope.runId"))
        )
        object.__setattr__(
            self,
            "plan_digest",
            Digest(parse_identifier("digest", self.plan_digest, "envelope.planDigest")),
        )
        object.__setattr__(
            self,
            "node_id",
            NodeID(parse_identifier("node", self.node_id, "envelope.nodeId")),
        )
        object.__setattr__(
            self,
            "lease_id",
            LeaseID(parse_identifier("lease", self.lease_id, "envelope.leaseId")),
        )
        if not isinstance(self.lane, BoundLane):
            raise RegressionError(
                "runtime.invalid_envelope_lane",
                str(self.lease_id),
                "evidence envelope lane must be concrete",
            )
        object.__setattr__(
            self,
            "sidekick_id",
            SidekickID(
                parse_identifier("sidekick", self.sidekick_id, "envelope.sidekickId")
            ),
        )
        for name in ("build_identity_digest", "evidence_environment_digest"):
            object.__setattr__(
                self,
                name,
                Digest(parse_identifier("digest", getattr(self, name), f"envelope.{name}")),
            )
        artifacts = tuple(self.artifacts)
        if not artifacts or any(not isinstance(item, EvidenceArtifact) for item in artifacts):
            raise RegressionError(
                "runtime.invalid_envelope_artifacts",
                str(self.lease_id),
                "an evidence envelope must contain typed artifacts",
            )
        obligation_ids = tuple(item.obligation_id for item in artifacts)
        if len(obligation_ids) != len(set(obligation_ids)):
            raise RegressionError(
                "runtime.duplicate_envelope_obligation",
                str(self.lease_id),
                "an evidence envelope cannot repeat an obligation",
            )
        object.__setattr__(
            self, "artifacts", tuple(sorted(artifacts, key=lambda item: str(item.obligation_id)))
        )

    @property
    def digest(self) -> Digest:
        return canonical_digest(self.payload())

    def payload(self) -> Mapping[str, Any]:
        return {
            "runId": str(self.run_id),
            "planDigest": str(self.plan_digest),
            "nodeId": str(self.node_id),
            "leaseId": str(self.lease_id),
            "lane": self.lane.value,
            "sidekickId": str(self.sidekick_id),
            "buildIdentityDigest": str(self.build_identity_digest),
            "evidenceEnvironmentDigest": str(self.evidence_environment_digest),
            "artifacts": [item.payload() for item in self.artifacts],
        }


@dataclass(frozen=True)
class OracleEvaluationRequest:
    binding: EvaluationBinding
    artifact: ArtifactReceipt


@dataclass(frozen=True)
class OracleEvaluatorIdentity:
    oracle_id: OracleID
    implementation_locator: str
    implementation_digest: Digest
    agent_environment: Optional[AgentEnvironment]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "oracle_id",
            OracleID(
                parse_identifier(
                    "oracle", self.oracle_id, "oracleEvaluatorIdentity.oracleId"
                )
            ),
        )
        if (
            not isinstance(self.implementation_locator, str)
            or not self.implementation_locator.strip()
        ):
            raise RegressionError(
                "runtime.invalid_oracle_evaluator_identity",
                str(self.oracle_id),
                "Oracle evaluator implementation locator must be non-empty text",
            )
        object.__setattr__(
            self,
            "implementation_digest",
            Digest(
                parse_identifier(
                    "digest",
                    self.implementation_digest,
                    "oracleEvaluatorIdentity.implementationDigest",
                )
            ),
        )
        if self.agent_environment is not None and not isinstance(
            self.agent_environment, AgentEnvironment
        ):
            raise RegressionError(
                "runtime.invalid_oracle_evaluator_identity",
                str(self.oracle_id),
                "Oracle evaluator agent environment must be AgentEnvironment or None",
            )


class OracleEvaluator(Protocol):
    def identity_for(self, oracle_id: OracleID) -> OracleEvaluatorIdentity: ...

    def evaluate(self, request: OracleEvaluationRequest) -> "OracleEvaluation": ...


@dataclass(frozen=True)
class CriterionEvaluation:
    criterion: str
    result: OracleResult

    def __post_init__(self) -> None:
        if not isinstance(self.criterion, str) or not self.criterion.strip():
            raise RegressionError(
                "runtime.invalid_oracle_evaluation",
                "criterion",
                "criterion must be non-empty text",
            )
        if not isinstance(self.result, OracleResult):
            raise RegressionError(
                "runtime.invalid_oracle_evaluation",
                "criterion.result",
                "criterion result must be an OracleResult",
            )


@dataclass(frozen=True)
class NegativeControlEvaluation:
    negative_control: str
    result: OracleResult

    def __post_init__(self) -> None:
        if not isinstance(self.negative_control, str) or not self.negative_control.strip():
            raise RegressionError(
                "runtime.invalid_oracle_evaluation",
                "negativeControl",
                "negative control must be non-empty text",
            )
        if not isinstance(self.result, OracleResult):
            raise RegressionError(
                "runtime.invalid_oracle_evaluation",
                "negativeControl.result",
                "negative-control result must be an OracleResult",
            )


def aggregate_oracle_evaluation(
    criteria: Sequence[CriterionEvaluation],
    negative_controls: Sequence[NegativeControlEvaluation],
) -> OracleResult:
    return aggregate_oracle_results(
        tuple(item.result for item in criteria)
        + tuple(item.result for item in negative_controls)
    )


@dataclass(frozen=True)
class EvidenceReference:
    receipt_digest: Digest

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "receipt_digest",
            Digest(
                parse_identifier(
                    "digest", self.receipt_digest, "evidenceRef.receiptDigest"
                )
            ),
        )


_DIAGNOSTIC_CODE = re.compile(r"[a-z0-9]+(?:[.-][a-z0-9]+)*")
_MAX_ORACLE_DIAGNOSTICS = 16
_MAX_ORACLE_DIAGNOSTIC_DETAIL = 1024


@dataclass(frozen=True)
class OracleDiagnostic:
    code: str
    detail: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, str) or _DIAGNOSTIC_CODE.fullmatch(self.code) is None:
            raise RegressionError(
                "runtime.invalid_oracle_diagnostic",
                "detail.code",
                "diagnostic code must be a lowercase dotted or dashed identifier",
            )
        if not isinstance(self.detail, str) or len(self.detail) > _MAX_ORACLE_DIAGNOSTIC_DETAIL:
            raise RegressionError(
                "runtime.invalid_oracle_diagnostic",
                "detail.detail",
                f"diagnostic detail must be text no longer than {_MAX_ORACLE_DIAGNOSTIC_DETAIL} characters",
            )


@dataclass(frozen=True)
class OracleEvaluation:
    overall: OracleResult
    criteria: Tuple[CriterionEvaluation, ...]
    negative_controls: Tuple[NegativeControlEvaluation, ...]
    evidence_refs: Tuple[EvidenceReference, ...]
    detail: Tuple[OracleDiagnostic, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.overall, OracleResult):
            raise RegressionError(
                "runtime.invalid_oracle_evaluation",
                "overall",
                "overall must be an OracleResult",
            )
        for name, expected in (
            ("criteria", CriterionEvaluation),
            ("negative_controls", NegativeControlEvaluation),
            ("evidence_refs", EvidenceReference),
            ("detail", OracleDiagnostic),
        ):
            values = tuple(getattr(self, name))
            if any(not isinstance(item, expected) for item in values):
                raise RegressionError(
                    "runtime.invalid_oracle_evaluation",
                    name,
                    f"{name} contains an invalid value",
                )
            object.__setattr__(self, name, values)
        if not self.evidence_refs:
            raise RegressionError(
                "runtime.invalid_oracle_evaluation",
                "evidenceRefs",
                "an Oracle evaluation must cite accepted evidence",
            )
        if len(self.detail) > _MAX_ORACLE_DIAGNOSTICS:
            raise RegressionError(
                "runtime.invalid_oracle_evaluation",
                "detail",
                f"an Oracle evaluation may contain at most {_MAX_ORACLE_DIAGNOSTICS} diagnostics",
            )


@dataclass(frozen=True)
class EvidenceReceipt:
    lease_id: LeaseID
    envelope_digest: Digest
    artifacts: Tuple[AcceptedArtifactView, ...]
    node_status: NodeStatus


class MainRun:
    def __init__(
        self,
        plan: CompiledRunPlan,
        directory: Path,
        ledger: LedgerWriter,
    ) -> None:
        self.plan = plan
        self.directory = Path(directory)
        self._ledger = ledger
        self._store = ArtifactStore(self.directory)
        self._closed = False
        self._nodes = {node.id: node for node in plan.nodes}
        self._preparations = {
            (binding.lane, binding.preparation_id): binding
            for binding in plan.preparation_bindings
        }

    @property
    def run_id(self) -> RunID:
        return RunID(self._ledger.run_id)

    @property
    def view(self) -> RunView:
        if self._closed:
            return replay(self.directory)
        return build_run_view(self._ledger.events)

    def bootstrap_and_recover(self) -> None:
        if not self._ledger.events:
            self._append(
                EventType.RUN_OPENED,
                {"nodes": [_node_open_payload(node) for node in self.plan.nodes]},
                "run-opened",
            )
        opened_view = self.view
        if not opened_view.closed:
            bootstrapped = frozenset(item.lane for item in opened_view.lanes)
            for lane in self.plan.requested_lanes:
                if lane in bootstrapped:
                    continue
                self._append(
                    EventType.LANE_BOOTSTRAPPED,
                    {"lane": lane.value},
                    f"lane-bootstrapped:{lane.value}",
                )
        self._recover_uncertain_invocations()
        self._settle_derivable_nodes()

    def claim(
        self,
        lane: BoundLane,
        sidekick_id: SidekickID,
        now_millis: Optional[int] = None,
        lease_duration_millis: int = DEFAULT_LEASE_DURATION_MILLIS,
    ) -> AssignmentLease:
        self._require_open()
        if not isinstance(lane, BoundLane):
            raise RegressionError(
                "runtime.invalid_lane", "lane", "claim lane must be concrete"
            )
        parsed_sidekick = SidekickID(
            parse_identifier("sidekick", sidekick_id, "claim.sidekickId")
        )
        now = _millis() if now_millis is None else _non_negative_millis(
            now_millis, "claim.nowMillis"
        )
        if type(lease_duration_millis) is not int or lease_duration_millis < 1:
            raise RegressionError(
                "runtime.invalid_lease_duration",
                lane.value,
                "lease duration must be a positive integer",
            )
        self._settle_derivable_nodes()
        current = self.view
        lane_view = current.lane(lane)
        if lane_view.interrupted:
            raise RegressionError(
                "runtime.lane_interrupted", lane.value, "lane cannot accept more work"
            )
        if lane_view.active_lease_id is not None:
            raise RegressionError(
                "runtime.lane_busy", lane.value, "lane already has an active lease"
            )

        candidates = []
        by_id = {}
        for node in self.plan.nodes:
            if not isinstance(node, ScenarioAttemptNode):
                continue
            node_view = current.node(node.id)
            if node_view.status is not NodeStatus.PENDING:
                continue
            available_lanes = self._available_lanes(node, current)
            if lane not in available_lanes or not self._strict_predecessors_passed(node, current):
                continue
            reusable = self._reusable_state_count(node, lane, current)
            candidate = ReadyCandidate(
                node.id,
                available_lanes,
                node.critical_remaining_millis,
                reusable,
                node.cost_millis,
            )
            candidates.append(candidate)
            by_id[node.id] = node
        selected = choose_ready(candidates, lane)
        node = by_id[selected.node_id]
        calls = self._call_sequence(node, lane, current)
        lease_id = _new_lease_id(self.run_id, node.id, lane, len(current.leases) + 1)
        deadline = now + lease_duration_millis
        capability = AssignmentCapability(
            self.run_id,
            self.plan.plan_digest,
            node.id,
            lease_id,
            lane,
            tuple(_allowed_call(call) for call in calls),
            deadline,
        )
        assignment_directory = self._assignment_directory(lease_id)
        self._append(
            EventType.NODE_CLAIMED,
            {
                "nodeId": str(node.id),
                "leaseId": str(lease_id),
                "lane": lane.value,
                "sidekickId": str(parsed_sidekick),
                "claimedAtMillis": now,
                "deadlineMillis": deadline,
                "calls": [_call_payload(call) for call in calls],
            },
            f"claim:{lease_id}",
        )
        return AssignmentLease(
            lease_id,
            node.id,
            lane,
            parsed_sidekick,
            capability,
            assignment_directory,
        )

    def authorize_operation(
        self,
        capability: AssignmentCapability,
        request: OperationRequest,
        now_millis: Optional[int] = None,
        *,
        defer_interruption: bool = False,
    ) -> OperationGrant:
        self._require_open()
        if not isinstance(capability, AssignmentCapability):
            raise RegressionError(
                "runtime.invalid_capability",
                "capability",
                "authorization needs an AssignmentCapability",
            )
        if not isinstance(request, OperationRequest):
            raise RegressionError(
                "runtime.invalid_operation_request",
                "request",
                "authorization needs an OperationRequest",
            )
        if type(defer_interruption) is not bool:
            raise RegressionError(
                "runtime.invalid_deferred_interruption",
                str(capability.lease_id),
                "defer_interruption must be a boolean",
            )
        current = self.view
        lease = current.lease(capability.lease_id)
        expected = self.capability_for_lease(lease)
        if capability != expected:
            raise RegressionError(
                "runtime.capability_mismatch",
                str(capability.lease_id),
                "capability does not exactly match the active run lease",
            )
        if lease.status is not LeaseStatus.ACTIVE:
            raise RegressionError(
                "runtime.lease_not_active", str(lease.lease_id), "lease is not active"
            )
        if lease.uncertain_invocations:
            raise RegressionError(
                "runtime.invocation_unresolved",
                str(lease.lease_id),
                "an authorized or invoked call is still unresolved",
            )
        call = lease.current_call
        if call is None or request.call_id != call.call_id:
            raise RegressionError(
                "runtime.call_out_of_order",
                str(request.call_id),
                "only the current planned call may be authorized",
            )
        entering_scenario = call.phase == "scenario" and (
            lease.cursor == 0 or lease.calls[lease.cursor - 1].phase == "preparation"
        )
        if entering_scenario:
            node = self._scenario_node(lease.node_id)
            if not self._scenario_prerequisites_valid(node, lease.lane, current):
                if not defer_interruption:
                    self.interrupt_lane(
                        lease.lane,
                        "scenario-prerequisite-invalid",
                        lease.lease_id,
                    )
                raise RegressionError(
                    "runtime.scenario_prerequisite_invalid",
                    str(lease.node_id),
                    "a prepared StateHandle became invalid before Scenario entry",
                )
        counts = _invocation_counts(lease.invocations)
        now = _millis() if now_millis is None else _non_negative_millis(
            now_millis, "authorization.nowMillis"
        )
        try:
            arguments_bytes = resolve_call_arguments(lease, call)
        except RegressionError:
            if not defer_interruption:
                self.interrupt_lane(
                    lease.lane,
                    "operation-result-reference-error",
                    lease.lease_id,
                )
            raise
        try:
            decision = decide_authorization(
                capability,
                request,
                counts,
                now,
                arguments_bytes,
            )
        except RegressionError as error:
            if error.code in (
                "capability.expired_lease",
                "capability.invocation_limit",
            ) and not defer_interruption:
                self.interrupt_lane(
                    lease.lane,
                    "lease-expired"
                    if error.code == "capability.expired_lease"
                    else "operation-retries-exhausted",
                    lease.lease_id,
                )
            raise
        grant = decision.grant
        self._append(
            EventType.OPERATION_AUTHORIZED,
            _grant_payload(grant),
            f"authorize:{grant.id}",
        )
        return grant

    def invoke_operation(
        self,
        grant: OperationGrant,
        arguments_bytes: bytes,
        adapter: Any,
        *,
        defer_interruption: bool = False,
    ) -> OperationResult:
        self._require_open()
        if not isinstance(grant, OperationGrant):
            raise RegressionError(
                "runtime.invalid_grant", "grant", "gateway needs an OperationGrant"
            )
        if not isinstance(arguments_bytes, bytes):
            raise RegressionError(
                "runtime.invalid_arguments",
                str(grant.call_id),
                "gateway arguments must be canonical bytes",
            )
        if type(defer_interruption) is not bool:
            raise RegressionError(
                "runtime.invalid_deferred_interruption",
                str(grant.lease_id),
                "defer_interruption must be a boolean",
            )
        if (
            arguments_bytes != grant.arguments_bytes
            or digest_bytes(arguments_bytes) != grant.arguments_digest
        ):
            raise RegressionError(
                "runtime.arguments_mismatch",
                str(grant.call_id),
                "gateway bytes differ from the exact authorized arguments",
            )
        current = self.view
        lease = current.lease(grant.lease_id)
        invocation = lease.invocation(grant.id)
        if invocation is None or not _grant_matches(invocation, grant):
            raise RegressionError(
                "runtime.grant_mismatch",
                str(grant.id),
                "grant does not exactly match its persisted authorization",
            )
        if lease.status is not LeaseStatus.ACTIVE or invocation.invoked or invocation.completed:
            raise RegressionError(
                "runtime.grant_not_invokable",
                str(grant.id),
                "grant is not an unused authorization on an active lease",
            )
        lane = current.lane(grant.lane)
        transition = lane.epochs.advance(grant.invalidates_tags)
        invoked_payload = dict(_grant_payload(grant))
        invoked_payload["epochAdvances"] = [
            {"tag": str(item.tag), "before": item.before, "after": item.after}
            for item in transition.advances
        ]
        self._append(
            EventType.OPERATION_INVOKED,
            invoked_payload,
            f"invoke:{grant.id}",
        )

        try:
            if hasattr(adapter, "invoke"):
                result = adapter.invoke(grant, arguments_bytes)
            elif callable(adapter):
                result = adapter(grant, arguments_bytes)
            else:
                raise TypeError("operation adapter is not callable")
        except Exception as error:
            if not defer_interruption:
                self.interrupt_lane(
                    grant.lane,
                    "operation-adapter-error",
                    grant.lease_id,
                )
            raise RegressionError(
                "runtime.operation_adapter_error",
                str(grant.call_id),
                f"operation adapter failed: {error}",
            ) from error

        if not isinstance(result, OperationResult):
            if not defer_interruption:
                self.interrupt_lane(
                    grant.lane,
                    "invalid-operation-result",
                    grant.lease_id,
                )
            raise RegressionError(
                "runtime.invalid_operation_result",
                str(grant.call_id),
                "operation adapter must return OperationResult",
            )
        self._complete_operation(
            grant,
            result,
            defer_interruption=defer_interruption,
        )
        return result

    def accept_evidence(
        self,
        envelope: EvidenceEnvelope,
        evaluator: OracleEvaluator,
    ) -> EvidenceReceipt:
        self._require_open()
        if not isinstance(envelope, EvidenceEnvelope):
            raise RegressionError(
                "runtime.invalid_envelope",
                "envelope",
                "evidence submission needs an EvidenceEnvelope",
            )
        current = self.view
        lease = current.lease(envelope.lease_id)
        node = self._scenario_node(lease.node_id)
        node_view = current.node(node.id)

        if lease.envelope_digest is not None and lease.envelope_digest != envelope.digest:
            raise RegressionError(
                "runtime.envelope_conflict",
                str(lease.lease_id),
                "the lease already received a different envelope digest",
            )
        if node_view.status in TERMINAL_NODE_STATUSES:
            if lease.evidence_accepted:
                return _evidence_receipt(lease, node_view.status)
            raise RegressionError(
                "runtime.node_already_terminal",
                str(node.id),
                "terminal node cannot accept new evidence",
            )

        try:
            self._validate_evaluator(node, evaluator)
        except RegressionError:
            self.interrupt_lane(
                lease.lane, "invalid-oracle-evaluator", lease.lease_id
            )
            raise

        try:
            self._validate_envelope(envelope, lease, node)
            accepted_payload = None
            if not lease.evidence_accepted:
                receipts = self._store.ingest_many(
                    lease.lease_id,
                    tuple(
                        ArtifactInput(
                            item.evidence_schema,
                            item.relative_path,
                            item.byte_length,
                            item.digest,
                        )
                        for item in envelope.artifacts
                    ),
                )
                accepted_payload = [
                    {
                        **artifact.payload(),
                        "objectPath": str(
                            receipt.object_path.relative_to(self.directory)
                        ),
                        "receiptDigest": str(receipt.receipt_digest),
                    }
                    for artifact, receipt in zip(envelope.artifacts, receipts)
                ]
        except RegressionError as error:
            if self.view.node(node.id).status is NodeStatus.LEASED:
                self.interrupt_lane(
                    lease.lane,
                    f"invalid-evidence-envelope:{error.code}",
                    lease.lease_id,
                )
            raise

        if lease.envelope_digest is None:
            self._append(
                EventType.ENVELOPE_RECEIVED,
                {
                    "leaseId": str(lease.lease_id),
                    "envelopeDigest": str(envelope.digest),
                },
                f"envelope:{lease.lease_id}:{envelope.digest}",
            )
            lease = self.view.lease(envelope.lease_id)

        if accepted_payload is not None:
            self._append(
                EventType.EVIDENCE_ACCEPTED,
                {
                    "leaseId": str(lease.lease_id),
                    "envelopeDigest": str(envelope.digest),
                    "artifacts": accepted_payload,
                },
                f"evidence-accepted:{lease.lease_id}:{envelope.digest}",
            )

        self._evaluate_and_record(node, lease.lease_id, evaluator)
        self._settle_derivable_nodes()
        final = self.view
        final_lease = final.lease(lease.lease_id)
        return _evidence_receipt(final_lease, final.node(node.id).status)

    def interrupt_lane(
        self,
        lane: BoundLane,
        reason: str,
        lease_id: Optional[LeaseID] = None,
        emergency_operation: Optional[EmergencyOperationResult] = None,
    ) -> RunView:
        self._require_open()
        if not isinstance(lane, BoundLane):
            raise RegressionError(
                "runtime.invalid_lane", "lane", "interruption lane must be concrete"
            )
        if not isinstance(reason, str) or not reason:
            raise RegressionError(
                "runtime.invalid_interruption_reason",
                lane.value,
                "interruption reason must be non-empty text",
            )
        current = self.view
        lane_view = current.lane(lane)
        target = lane_view.active_lease_id if lease_id is None else lease_id
        if target is not None:
            lease = current.lease(target)
            if lease.lane is not lane:
                raise RegressionError(
                    "runtime.lease_lane_mismatch",
                    str(target),
                    "interruption lease belongs to another lane",
                )
        if emergency_operation is not None:
            if target is None:
                raise RegressionError(
                    "runtime.emergency_operation_without_lease",
                    lane.value,
                    "emergency Operation must identify its affected lease",
                )
            if lane_view.interrupted:
                raise RegressionError(
                    "runtime.emergency_operation_after_interruption",
                    str(target),
                    "emergency Operation must be recorded by the first interruption event",
                )
            reason = self._emergency_interruption_reason(
                reason,
                current.lease(target),
                emergency_operation,
            )
        if not lane_view.interrupted:
            self._append(
                EventType.LANE_INTERRUPTED,
                {
                    "lane": lane.value,
                    "leaseId": None if target is None else str(target),
                    "reason": reason,
                },
                f"lane-interrupted:{lane.value}",
            )
        current = self.view
        if target is not None:
            lease = current.lease(target)
            node_view = current.node(lease.node_id)
            if node_view.status is NodeStatus.LEASED and not awaiting_adjudication(
                node_view, lease
            ):
                self._record_verdict(
                    lease.node_id,
                    NodeStatus.INDETERMINATE,
                    lease.lease_id,
                )
        self._settle_derivable_nodes()
        return self.view

    def _emergency_interruption_reason(
        self,
        reason: str,
        lease: Any,
        emergency: EmergencyOperationResult,
    ) -> str:
        if not isinstance(emergency, EmergencyOperationResult):
            raise RegressionError(
                "runtime.invalid_emergency_operation",
                str(lease.lease_id),
                "emergency Operation must be an EmergencyOperationResult",
            )
        call = next(
            (item for item in lease.calls if item.call_id == emergency.call_id),
            None,
        )
        if call is None or call.operation != _TRANSITION_TRACE_DISARM:
            raise RegressionError(
                "runtime.emergency_operation_not_assigned",
                str(emergency.call_id),
                "emergency disarm must reuse the lease's assigned transition-trace disarm",
            )
        if lease.call_succeeded(call.call_id):
            raise RegressionError(
                "runtime.emergency_operation_already_completed",
                str(call.call_id),
                "an already completed transition-trace disarm cannot run as cleanup",
            )
        arguments_value = decode_json_bytes(
            emergency.arguments_bytes,
            f"{call.call_id}.emergencyArguments",
        )
        arguments = FrozenJSONObject.from_mapping(
            arguments_value,
            f"{call.call_id}.emergencyArguments",
        )
        if canonical_bytes(arguments.payload()) != emergency.arguments_bytes:
            raise RegressionError(
                "runtime.emergency_operation_arguments_mismatch",
                str(call.call_id),
                "emergency disarm arguments must use canonical JSON bytes",
            )
        generation = arguments.payload().get("generationToken")
        _assigned_emergency_arm(
            lease,
            call,
            generation,
            "runtime.emergency_operation_generation_mismatch",
            str(call.call_id),
        )
        expected_arguments = canonical_bytes({"generationToken": generation})
        if (
            emergency.arguments_bytes != expected_arguments
            or digest_bytes(emergency.arguments_bytes) != digest_bytes(expected_arguments)
        ):
            raise RegressionError(
                "runtime.emergency_operation_arguments_mismatch",
                str(call.call_id),
                "emergency disarm arguments differ from the assigned generation reference",
            )
        record = {
            "schema": "enchron.regression.interruption",
            "schemaVersion": 1,
            "reason": reason,
            "affectedLeaseId": str(lease.lease_id),
            "emergencyOperation": {
                "callId": str(call.call_id),
                "operation": str(call.operation),
                "contractDigest": str(call.contract_digest),
                "argumentsBytes": emergency.arguments_bytes.decode("utf-8"),
                "argumentsDigest": str(digest_bytes(emergency.arguments_bytes)),
                "implementationLocator": call.implementation_locator,
                "implementationDigest": str(call.implementation_digest),
                "trigger": emergency.trigger,
                "result": {
                    "succeeded": emergency.result.succeeded,
                    "detail": emergency.result.detail,
                    "outputs": emergency.result.outputs.payload(),
                },
            },
        }
        return TRANSITION_FAULT_INTERRUPTION_PREFIX + canonical_bytes(record).decode(
            "utf-8"
        )

    def finalize(self) -> RunView:
        self._require_open()
        self._recover_uncertain_invocations()
        self._settle_derivable_nodes()
        current = self.view
        owed = nodes_awaiting_adjudication(current)
        if owed:
            raise RegressionError(
                "runtime.adjudication_owed",
                ", ".join(str(item.node_id) for item in owed),
                "a non-satisfied node needs its ledger verdict before the run closes",
            )
        for node in current.nodes:
            if node.status is not NodeStatus.LEASED:
                continue
            lease = current_lease(current, node)
            if lease is None:
                continue
            self.interrupt_lane(
                lease.lane,
                "run-finalized-with-active-lease",
                lease.lease_id,
            )
            current = self.view
        self._settle_derivable_nodes()
        current = self.view
        for node in current.nodes:
            if node.status is NodeStatus.PENDING:
                self._record_verdict(node.node_id, NodeStatus.INDETERMINATE, None)
        current = self.view
        statuses = tuple(node.status for node in current.nodes)
        if NodeStatus.INDETERMINATE in statuses:
            outcome = RunOutcome.INTERRUPTED
        elif NodeStatus.FAILED in statuses:
            outcome = RunOutcome.FAILED
        elif NodeStatus.DEFERRED_HUMAN in statuses:
            outcome = RunOutcome.DEFERRED
        elif all(status in CLOSED_AS_PASSED for status in statuses):
            outcome = RunOutcome.PASSED
        else:
            unclassified = sorted(
                {status.value for status in statuses if status not in CLOSED_AS_PASSED}
            )
            raise RegressionError(
                "runtime.unclassified_terminal_status",
                ", ".join(unclassified),
                "the outcome ladder classifies every terminal status it closes over",
            )
        self._append(
            EventType.RUN_CLOSED,
            {"outcome": outcome.value},
            "run-closed",
        )
        result = self.view
        self.close()
        return result

    def close(self) -> None:
        if self._closed:
            return
        self._ledger.close()
        self._closed = True

    def __enter__(self) -> "MainRun":
        self._require_open()
        return self

    def __exit__(self, exception_type: Any, exception: Any, traceback: Any) -> None:
        self.close()

    def _complete_operation(
        self,
        grant: OperationGrant,
        result: OperationResult,
        *,
        defer_interruption: bool = False,
    ) -> None:
        current = self.view
        lease = current.lease(grant.lease_id)
        invocation = lease.invocation(grant.id)
        if (
            lease.status is not LeaseStatus.ACTIVE
            or invocation is None
            or not _grant_matches(invocation, grant)
            or not invocation.invoked
            or invocation.completed
        ):
            raise RegressionError(
                "runtime.completion_mismatch",
                str(grant.id),
                "completion does not match one invoked grant",
            )
        call = lease.current_call
        if call is None or call.call_id != grant.call_id:
            raise RegressionError(
                "runtime.completion_out_of_order",
                str(grant.id),
                "completion is not for the current call",
            )

        fingerprints = {
            (item.key, item.schema): item.digest for item in result.state_fingerprints
        }
        expected = {(item.key, item.schema) for item in call.state_productions}
        if result.succeeded and set(fingerprints) != expected:
            if not defer_interruption:
                self.interrupt_lane(
                    grant.lane, "state-fingerprint-mismatch", grant.lease_id
                )
            raise RegressionError(
                "runtime.state_fingerprint_mismatch",
                str(grant.call_id),
                "successful preparation must return exactly its declared fingerprints",
            )
        if not result.succeeded and fingerprints:
            if not defer_interruption:
                self.interrupt_lane(
                    grant.lane, "failed-call-produced-state", grant.lease_id
                )
            raise RegressionError(
                "runtime.failed_call_produced_state",
                str(grant.call_id),
                "failed operation cannot produce reusable state",
            )

        handles = []
        epochs = current.lane(grant.lane).epochs
        if result.succeeded:
            for production in call.state_productions:
                handle = capture_state_handle(
                    production.key,
                    production.schema,
                    grant.lane,
                    grant.node_id,
                    epochs,
                    production.depends_on_tags,
                    fingerprints[(production.key, production.schema)],
                )
                handles.append(
                    {
                        "key": str(handle.key),
                        "schema": str(handle.schema),
                        "lane": handle.lane.value,
                        "producedByNode": str(handle.produced_by_node),
                        "preparationId": str(production.preparation_id),
                        "producedByCall": str(production.produced_by_call),
                        "dependencies": [
                            {"tag": str(item.tag), "value": item.value}
                            for item in handle.dependencies.entries
                        ],
                        "fingerprint": str(handle.fingerprint),
                    }
                )
        self._append(
            EventType.OPERATION_COMPLETED,
            {
                "grantId": str(grant.id),
                "leaseId": str(grant.lease_id),
                "succeeded": result.succeeded,
                "detail": result.detail,
                "outputs": result.outputs.payload(),
                "stateHandles": handles,
            },
            f"complete:{grant.id}",
        )
        updated = self.view.lease(grant.lease_id)
        if (
            not result.succeeded
            and updated.current_call is not None
            and updated.invocation_count(grant.call_id)
            >= updated.current_call.max_invocations
            and not attempt_ended_on_the_harness(updated)
        ):
            if not defer_interruption:
                self.interrupt_lane(
                    grant.lane, "operation-retries-exhausted", grant.lease_id
                )

    def _validate_envelope(
        self,
        envelope: EvidenceEnvelope,
        lease: Any,
        node: ScenarioAttemptNode,
    ) -> None:
        expected_identity = (
            self.run_id,
            self.plan.plan_digest,
            node.id,
            lease.lease_id,
            lease.lane,
            lease.sidekick_id,
            node.build_identity.digest,
            node.evidence_environment_identity.digest,
        )
        actual_identity = (
            envelope.run_id,
            envelope.plan_digest,
            envelope.node_id,
            envelope.lease_id,
            envelope.lane,
            envelope.sidekick_id,
            envelope.build_identity_digest,
            envelope.evidence_environment_digest,
        )
        if actual_identity != expected_identity:
            raise RegressionError(
                "runtime.envelope_identity_mismatch",
                str(lease.lease_id),
                "envelope identity does not exactly match the assignment",
            )
        if lease.status is not LeaseStatus.ACTIVE:
            raise RegressionError(
                "runtime.lease_not_active", str(lease.lease_id), "lease is not active"
            )
        if not lease.operations_complete:
            raise RegressionError(
                "runtime.evidence_before_operations",
                str(lease.lease_id),
                "evidence cannot be accepted before every planned call succeeds",
            )
        bindings = {item.id: item for item in node.evaluation_bindings}
        artifacts = {item.obligation_id: item for item in envelope.artifacts}
        if set(artifacts) != set(bindings):
            raise RegressionError(
                "runtime.envelope_obligation_mismatch",
                str(lease.lease_id),
                "envelope must cover every planned obligation exactly once",
            )
        for obligation_id, binding in bindings.items():
            artifact = artifacts[obligation_id]
            if (
                artifact.evidence_type != binding.evidence_type
                or artifact.evidence_schema != binding.evidence_schema
                or artifact.case_key != binding.case_key
                or artifact.produced_by_call != binding.produced_by_call
                or artifact.producer_contract_digest
                != binding.producer_contract_digest
            ):
                raise RegressionError(
                    "runtime.envelope_binding_mismatch",
                    str(obligation_id),
                    "artifact evidence pair, case, or producer differs from its plan binding",
                )
            captured_millis = _rfc3339_millis(
                artifact.captured_at, f"{obligation_id}.capturedAt"
            )
            if not lease.claimed_at_millis <= captured_millis <= lease.deadline_millis:
                raise RegressionError(
                    "runtime.artifact_capture_outside_lease",
                    str(obligation_id),
                    "artifact capturedAt is outside the lease attempt",
                )
            if not lease.call_succeeded(binding.produced_by_call):
                raise RegressionError(
                    "runtime.evidence_producer_incomplete",
                    str(obligation_id),
                    "artifact producer call did not complete successfully",
                )

    def _evaluate_and_record(
        self,
        node: ScenarioAttemptNode,
        lease_id: LeaseID,
        evaluator: OracleEvaluator,
    ) -> None:
        current = self.view
        lease = current.lease(lease_id)
        completed = {
            item.obligation_id: item.overall for item in lease.oracle_evaluations
        }
        receipts = {
            item.obligation_id: _artifact_receipt(self.directory, lease_id, item)
            for item in lease.evidence
        }
        for binding in node.evaluation_bindings:
            if binding.id in completed:
                continue
            request = OracleEvaluationRequest(binding, receipts[binding.id])
            try:
                self._validate_evaluator_binding(node, binding, evaluator)
            except RegressionError:
                self.interrupt_lane(
                    lease.lane, "invalid-oracle-evaluator", lease.lease_id
                )
                raise
            try:
                result = evaluator.evaluate(request)
            except Exception as error:
                self.interrupt_lane(
                    lease.lane, "oracle-evaluator-error", lease.lease_id
                )
                raise RegressionError(
                    "runtime.oracle_evaluator_error",
                    str(binding.id),
                    f"Oracle evaluator failed: {error}",
                ) from error
            if not isinstance(result, OracleEvaluation):
                self.interrupt_lane(
                    lease.lane, "invalid-oracle-result", lease.lease_id
                )
                raise RegressionError(
                    "runtime.invalid_oracle_result",
                    str(binding.id),
                    "Oracle evaluator must return a structured OracleEvaluation",
                )
            if tuple(item.criterion for item in result.criteria) != binding.rubric.criteria:
                self.interrupt_lane(
                    lease.lane, "invalid-oracle-result", lease.lease_id
                )
                raise RegressionError(
                    "runtime.incomplete_oracle_criteria",
                    str(binding.id),
                    "Oracle criteria must exactly match the ordered Rubric criteria",
                )
            if (
                tuple(item.negative_control for item in result.negative_controls)
                != binding.rubric.negative_controls
            ):
                self.interrupt_lane(
                    lease.lane, "invalid-oracle-result", lease.lease_id
                )
                raise RegressionError(
                    "runtime.incomplete_oracle_negative_controls",
                    str(binding.id),
                    "Oracle negative controls must exactly match the ordered Rubric negative controls",
                )
            canonical_overall = aggregate_oracle_evaluation(
                result.criteria,
                result.negative_controls,
            )
            if result.overall is not canonical_overall:
                self.interrupt_lane(
                    lease.lane, "invalid-oracle-result", lease.lease_id
                )
                raise RegressionError(
                    "runtime.oracle_overall_mismatch",
                    str(binding.id),
                    "Oracle overall differs from the canonical component aggregate",
                )
            expected_refs = (EvidenceReference(receipts[binding.id].receipt_digest),)
            if result.evidence_refs != expected_refs:
                self.interrupt_lane(
                    lease.lane, "invalid-oracle-result", lease.lease_id
                )
                raise RegressionError(
                    "runtime.oracle_evidence_ref_mismatch",
                    str(binding.id),
                    "Oracle evidence refs must exactly cite the accepted artifact receipt",
                )
            self._append(
                EventType.ORACLE_EVALUATED,
                {
                    "leaseId": str(lease.lease_id),
                    "obligationId": str(binding.id),
                    "overall": result.overall.value,
                    "criteria": [
                        {"criterion": item.criterion, "result": item.result.value}
                        for item in result.criteria
                    ],
                    "negativeControls": [
                        {
                            "negativeControl": item.negative_control,
                            "result": item.result.value,
                        }
                        for item in result.negative_controls
                    ],
                    "evidenceRefs": [
                        {"receiptDigest": str(item.receipt_digest)}
                        for item in result.evidence_refs
                    ],
                    "detail": [
                        {"code": item.code, "detail": item.detail}
                        for item in result.detail
                    ],
                    "oracleId": str(binding.oracle.id),
                    "oracleContractDigest": str(binding.oracle.contract_digest),
                    "oracleImplementationDigest": str(
                        binding.oracle.implementation_digest
                    ),
                    "oracleImplementationLocator": (
                        binding.oracle.implementation_locator
                    ),
                    "rubricId": str(binding.rubric.id),
                    "rubricContractDigest": str(binding.rubric.contract_digest),
                },
                f"oracle:{lease.lease_id}:{binding.id}",
            )

        current = self.view
        if (
            settled_oracle_result(current.node(node.id), current.lease(lease.lease_id))
            is OracleResult.SATISFIED
        ):
            self._record_verdict(node.id, NodeStatus.PASSED, lease.lease_id)

    def _validate_evaluator(
        self,
        node: ScenarioAttemptNode,
        evaluator: OracleEvaluator,
    ) -> None:
        if not callable(getattr(evaluator, "evaluate", None)) or not callable(
            getattr(evaluator, "identity_for", None)
        ):
            raise RegressionError(
                "runtime.invalid_oracle_evaluator",
                str(node.id),
                "Oracle evaluator must implement identity_for and evaluate",
            )
        for binding in node.evaluation_bindings:
            self._validate_evaluator_binding(node, binding, evaluator)

    def _validate_evaluator_binding(
        self,
        node: ScenarioAttemptNode,
        binding: EvaluationBinding,
        evaluator: OracleEvaluator,
    ) -> OracleEvaluatorIdentity:
        try:
            identity = evaluator.identity_for(binding.oracle.id)
        except RegressionError:
            raise
        except Exception as error:
            raise RegressionError(
                "runtime.invalid_oracle_evaluator",
                str(binding.oracle.id),
                f"Oracle evaluator identity lookup failed: {error}",
            ) from error
        if not isinstance(identity, OracleEvaluatorIdentity):
            raise RegressionError(
                "runtime.invalid_oracle_evaluator",
                str(binding.oracle.id),
                "identity_for must return OracleEvaluatorIdentity",
            )
        expected_implementation = (
            binding.oracle.id,
            binding.oracle.implementation_locator,
            binding.oracle.implementation_digest,
        )
        actual_implementation = (
            identity.oracle_id,
            identity.implementation_locator,
            identity.implementation_digest,
        )
        if actual_implementation != expected_implementation:
            raise RegressionError(
                "runtime.oracle_evaluator_identity_mismatch",
                str(binding.oracle.id),
                "Oracle evaluator implementation differs from the compiled binding",
            )
        expected_environment = node.evidence_environment_identity.agent_environment
        if identity.agent_environment != expected_environment:
            raise RegressionError(
                "runtime.oracle_agent_environment_mismatch",
                str(binding.oracle.id),
                "Oracle decision provider environment differs from the compiled node",
            )
        return identity

    def _settle_derivable_nodes(self) -> None:
        while True:
            current = self.view
            nodes = {item.node_id: item for item in current.nodes}
            decision = next(
                (
                    (node.node_id, derivable_verdict(node, nodes))
                    for node in current.nodes
                    if derivable_verdict(node, nodes) is not None
                ),
                None,
            )
            if decision is None:
                return
            node_id, (status, ancestors) = decision
            self._record_verdict(node_id, status, None, ancestors)

    def _record_verdict(
        self,
        node_id: NodeID,
        status: NodeStatus,
        lease_id: Optional[LeaseID],
        failure_ancestors: Tuple[NodeID, ...] = (),
    ) -> None:
        payload = {
            "nodeId": str(node_id),
            "leaseId": None if lease_id is None else str(lease_id),
            "status": status.value,
            "failureAncestors": [str(item) for item in failure_ancestors],
        }
        attempt = attempts_of(
            node_id, {item.lease_id: item for item in self.view.leases}
        )
        self._append(
            EventType.VERDICT_RECORDED,
            payload,
            f"verdict:{node_id}:{attempt}",
        )

    def _recover_uncertain_invocations(self) -> None:
        current = self.view
        for lease in current.leases:
            node = current.node(lease.node_id)
            if node.status is not NodeStatus.LEASED or node.lease_id != lease.lease_id:
                continue
            call = lease.current_call
            retries_exhausted = (
                call is not None
                and lease.invocation_count(call.call_id) >= call.max_invocations
                and any(
                    item.call_id == call.call_id
                    and item.completed
                    and item.succeeded is False
                    for item in lease.invocations
                )
            )
            recovery_reason = None
            if lease.uncertain_invocations or lease.status is LeaseStatus.INTERRUPTED:
                recovery_reason = "uncertain-operation-after-recovery"
            elif retries_exhausted and not attempt_ended_on_the_harness(lease):
                recovery_reason = "operation-retries-exhausted"
            if recovery_reason is not None:
                self.interrupt_lane(
                    lease.lane,
                    recovery_reason,
                    lease.lease_id,
                )
                current = self.view
                continue
            if settled_oracle_result(node, lease) is OracleResult.SATISFIED:
                self._record_verdict(node.node_id, NodeStatus.PASSED, lease.lease_id)
                current = self.view

    def _call_sequence(
        self,
        node: ScenarioAttemptNode,
        lane: BoundLane,
        view: RunView,
    ) -> Tuple[CallPlanView, ...]:
        preparations = []
        scheduled = set()
        active = set()

        def require(
            preparation_id: Any,
            requirement: StateRequirement,
        ) -> None:
            key = (lane, preparation_id)
            binding = self._preparations.get(key)
            if binding is None:
                raise RegressionError(
                    "runtime.missing_preparation_binding",
                    str(preparation_id),
                    "plan does not contain the lane-local Preparation binding",
                )
            if view.valid_state_handle(
                requirement.key, requirement.schema, lane, binding.preparation_id
            ) is not None:
                return
            if key in scheduled:
                return
            if key in active:
                raise RegressionError(
                    "runtime.preparation_cycle",
                    str(preparation_id),
                    "Preparation bindings contain a dependency cycle",
                )
            active.add(key)
            for dependency in binding.prerequisite_bindings:
                require(dependency.preparation_id, dependency.requirement)
            active.remove(key)
            scheduled.add(key)
            preparations.append(binding)

        for requirement in node.preparation_requirements:
            if requirement.lane is lane:
                require(requirement.preparation_id, requirement.requirement)

        result = []
        for binding in preparations:
            result.extend(_preparation_calls(binding))
        result.extend(_scenario_calls(node.calls))
        call_ids = tuple(item.call_id for item in result)
        if len(call_ids) != len(set(call_ids)):
            raise RegressionError(
                "runtime.duplicate_lease_call",
                str(node.id),
                "Preparation and Scenario calls must be unique within one lease",
            )
        return tuple(result)

    def _available_lanes(
        self, node: ScenarioAttemptNode, view: RunView
    ) -> Tuple[BoundLane, ...]:
        result = []
        for lane in node.lane_candidates:
            lane_view = view.lane(lane)
            if lane_view.interrupted:
                continue
            gate = next(
                (item for item in node.gate_dependencies if item.lane is lane), None
            )
            if gate is not None and view.node(gate.gate_node_id).status is not NodeStatus.PASSED:
                continue
            result.append(lane)
        return tuple(result)

    def _strict_predecessors(self, node: ScenarioAttemptNode) -> Tuple[NodeID, ...]:
        gates = frozenset(item.gate_node_id for item in node.gate_dependencies)
        return tuple(item for item in node.predecessors if item not in gates)

    def _strict_predecessors_passed(
        self, node: ScenarioAttemptNode, view: RunView
    ) -> bool:
        return all(
            view.node(item).status is NodeStatus.PASSED
            for item in self._strict_predecessors(node)
        )

    def _reusable_state_count(
        self, node: ScenarioAttemptNode, lane: BoundLane, view: RunView
    ) -> int:
        return sum(
            view.valid_state_handle(
                item.requirement.key,
                item.requirement.schema,
                lane,
                item.preparation_id,
            )
            is not None
            for item in node.preparation_requirements
            if item.lane is lane
        )

    def _scenario_prerequisites_valid(
        self, node: ScenarioAttemptNode, lane: BoundLane, view: RunView
    ) -> bool:
        return all(
            view.valid_state_handle(
                item.requirement.key,
                item.requirement.schema,
                lane,
                item.preparation_id,
            )
            is not None
            for item in node.preparation_requirements
            if item.lane is lane
        )

    def capability_for_lease(self, lease: Any) -> AssignmentCapability:
        return AssignmentCapability(
            self.run_id,
            self.plan.plan_digest,
            lease.node_id,
            lease.lease_id,
            lease.lane,
            tuple(_allowed_call(call) for call in lease.calls),
            lease.deadline_millis,
        )

    def _assignment_directory(self, lease_id: LeaseID) -> Path:
        assignments = self.directory / "assignments"
        assignments.mkdir(parents=True, exist_ok=True)
        if assignments.is_symlink() or not assignments.is_dir():
            raise RegressionError(
                "runtime.invalid_assignments_directory",
                str(assignments),
                "assignments must be a real directory",
            )
        destination = assignments / str(lease_id)
        destination.mkdir(exist_ok=True)
        if destination.is_symlink() or not destination.is_dir():
            raise RegressionError(
                "runtime.invalid_assignment_directory",
                str(destination),
                "lease assignment path must be a real directory",
            )
        return destination

    def _scenario_node(self, node_id: NodeID) -> ScenarioAttemptNode:
        node = self._nodes.get(node_id)
        if not isinstance(node, ScenarioAttemptNode):
            raise RegressionError(
                "runtime.node_not_scenario",
                str(node_id),
                "only Scenario nodes own leases and evidence",
            )
        return node

    def _append(
        self,
        event_type: EventType,
        payload: Mapping[str, Any],
        idempotency_key: Optional[str] = None,
    ) -> None:
        self._ledger.append(
            event_type,
            payload,
            now_rfc3339_millis(),
            idempotency_key,
        )

    def _require_open(self) -> None:
        if self._closed:
            raise RegressionError(
                "runtime.closed", str(self.directory), "MainRun is closed"
            )
        if self.view.closed:
            raise RegressionError(
                "runtime.already_finalized",
                str(self.directory),
                "run has already been finalized",
            )


def open_run(plan: CompiledRunPlan, directory: Path) -> MainRun:
    if not isinstance(plan, CompiledRunPlan):
        raise RegressionError(
            "runtime.invalid_plan", "plan", "open_run needs a CompiledRunPlan"
        )
    run_directory = Path(directory)
    _write_plan_once(run_directory, plan)
    existing = read_event_log(run_directory)
    run_id = existing.run_id or RunID("run:" + secrets.token_hex(12))
    ledger = LedgerWriter(run_directory, run_id, plan.plan_digest, build_run_view)
    main = MainRun(plan, run_directory, ledger)
    try:
        main.bootstrap_and_recover()
        return main
    except BaseException:
        main.close()
        raise


def _write_plan_once(directory: Path, plan: CompiledRunPlan) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    if directory.is_symlink() or not directory.is_dir():
        raise RegressionError(
            "runtime.invalid_run_directory",
            str(directory),
            "run directory must be a real directory",
        )
    path = directory / PLAN_FILENAME
    encoded = canonical_bytes(compiled_plan_payload(plan)) + b"\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=".plan-", dir=str(directory))
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(encoded)
            output.flush()
            os.fsync(output.fileno())
        try:
            os.link(str(temporary), str(path))
        except FileExistsError:
            if path.is_symlink() or not path.is_file():
                raise RegressionError(
                    "runtime.invalid_plan_file",
                    str(path),
                    "plan.json must be a regular immutable file",
                )
            if path.read_bytes() != encoded:
                raise RegressionError(
                    "runtime.plan_conflict",
                    str(path),
                    "run directory already contains a different plan",
                )
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
    parent = os.open(str(directory), os.O_RDONLY)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)


def _node_open_payload(node: Any) -> Mapping[str, Any]:
    payload = {
        "nodeId": str(node.id),
        "kind": "bothJoin" if isinstance(node, BothJoinNode) else "scenarioAttempt",
        "predecessors": [str(item) for item in node.predecessors],
        "laneCandidates": [item.value for item in node.lane_candidates],
        "gateDependencies": []
        if isinstance(node, BothJoinNode)
        else [
            {"lane": item.lane.value, "nodeId": str(item.gate_node_id)}
            for item in node.gate_dependencies
        ],
    }
    if not isinstance(node, BothJoinNode):
        payload["success"] = success_payload(node.success)
        payload["scenarioId"] = str(node.scenario_id)
    return payload


def _preparation_calls(binding: PreparationBinding) -> Tuple[CallPlanView, ...]:
    declarations = {call.call_id: [] for call in binding.calls}
    for declaration in binding.produces:
        if declaration.produced_by_call not in declarations:
            raise RegressionError(
                "runtime.preparation_producer_missing",
                str(binding.preparation_id),
                "state declaration producer is absent from Preparation calls",
            )
        declarations[declaration.produced_by_call].append(
            StateProductionView(
                declaration.key,
                declaration.schema,
                binding.preparation_id,
                declaration.produced_by_call,
                tuple(sorted(declaration.depends_on_tags, key=str)),
            )
        )
    return tuple(
        CallPlanView(
            call.call_id,
            call.operation,
            call.contract_digest,
            call.arguments_bytes,
            call.arguments_digest,
            call.implementation_locator,
            call.implementation_digest,
            call.max_invocations,
            tuple(call.invalidates_tags),
            "preparation",
            binding.preparation_id,
            tuple(declarations[call.call_id]),
        )
        for call in binding.calls
    )


def _scenario_calls(calls: Sequence[AllowedOperationCall]) -> Tuple[CallPlanView, ...]:
    return tuple(
        CallPlanView(
            call.call_id,
            call.operation,
            call.contract_digest,
            call.arguments_bytes,
            call.arguments_digest,
            call.implementation_locator,
            call.implementation_digest,
            call.max_invocations,
            tuple(call.invalidates_tags),
            "scenario",
            None,
            (),
        )
        for call in calls
    )


def _allowed_call(call: CallPlanView) -> AllowedOperationCall:
    return AllowedOperationCall(
        call_id=call.call_id,
        operation=call.operation,
        contract_digest=call.contract_digest,
        arguments_bytes=call.arguments_bytes,
        arguments_digest=call.arguments_digest,
        implementation_locator=call.implementation_locator,
        implementation_digest=call.implementation_digest,
        max_invocations=call.max_invocations,
        invalidates_tags=call.invalidates_tags,
    )


def _call_payload(call: CallPlanView) -> Mapping[str, Any]:
    return {
        "callId": str(call.call_id),
        "operation": str(call.operation),
        "contractDigest": str(call.contract_digest),
        "argumentsBytes": call.arguments_bytes.decode("utf-8"),
        "argumentsDigest": str(call.arguments_digest),
        "implementationLocator": call.implementation_locator,
        "implementationDigest": str(call.implementation_digest),
        "maxInvocations": call.max_invocations,
        "invalidatesTags": [str(item) for item in call.invalidates_tags],
        "phase": call.phase,
        "preparationId": None
        if call.preparation_id is None
        else str(call.preparation_id),
        "stateProductions": [
            {
                "key": str(item.key),
                "schema": str(item.schema),
                "producedByCall": str(item.produced_by_call),
                "dependsOnTags": [str(tag) for tag in item.depends_on_tags],
            }
            for item in call.state_productions
        ],
    }


def _grant_payload(grant: OperationGrant) -> Dict[str, Any]:
    return grant.payload()


def _grant_matches(invocation: Any, grant: OperationGrant) -> bool:
    return (
        invocation.grant_id,
        invocation.run_id,
        invocation.plan_digest,
        invocation.node_id,
        invocation.lease_id,
        invocation.lane,
        invocation.call_id,
        invocation.operation,
        invocation.contract_digest,
        invocation.arguments_template_digest,
        invocation.arguments_bytes,
        invocation.arguments_digest,
        invocation.implementation_locator,
        invocation.implementation_digest,
        invocation.invocation_index,
        invocation.invalidates_tags,
    ) == (
        grant.id,
        grant.run_id,
        grant.plan_digest,
        grant.node_id,
        grant.lease_id,
        grant.lane,
        grant.call_id,
        grant.operation,
        grant.contract_digest,
        grant.arguments_template_digest,
        grant.arguments_bytes,
        grant.arguments_digest,
        grant.implementation_locator,
        grant.implementation_digest,
        grant.invocation_index,
        grant.invalidates_tags,
    )


def _invocation_counts(invocations: Iterable[Any]) -> InvocationCounts:
    values: Dict[CallID, int] = {}
    for invocation in invocations:
        values[invocation.call_id] = values.get(invocation.call_id, 0) + 1
    return InvocationCounts(
        tuple(InvocationCount(call_id, values[call_id]) for call_id in sorted(values))
    )


def _artifact_receipt(
    directory: Path, lease_id: LeaseID, artifact: AcceptedArtifactView
) -> ArtifactReceipt:
    object_path = directory / artifact.object_path
    receipt_path = (
        directory
        / "receipts"
        / "artifacts"
        / (str(artifact.receipt_digest)[7:] + ".json")
    )
    return ArtifactReceipt(
        lease_id,
        artifact.evidence_schema,
        artifact.relative_path,
        artifact.byte_length,
        artifact.digest,
        object_path,
        artifact.receipt_digest,
        receipt_path,
    )


def _evidence_receipt(lease: Any, status: NodeStatus) -> EvidenceReceipt:
    if lease.envelope_digest is None or not lease.evidence_accepted:
        raise RegressionError(
            "runtime.evidence_not_accepted",
            str(lease.lease_id),
            "lease has no accepted evidence receipt",
        )
    return EvidenceReceipt(
        lease.lease_id, lease.envelope_digest, lease.evidence, status
    )


def _new_lease_id(
    run_id: RunID, node_id: NodeID, lane: BoundLane, ordinal: int
) -> LeaseID:
    digest = canonical_digest(
        {
            "runId": str(run_id),
            "nodeId": str(node_id),
            "lane": lane.value,
            "ordinal": ordinal,
        }
    )
    return LeaseID("lease:" + str(digest)[7:31])


def _millis() -> int:
    return int(time.time() * 1000)


def _non_negative_millis(value: Any, location: str) -> int:
    if type(value) is not int or value < 0:
        raise RegressionError(
            "runtime.invalid_clock", location, "clock value must be a non-negative integer"
        )
    return value


_RFC3339_INSTANT = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})"
)


def _rfc3339_millis(value: object, location: str) -> int:
    if not isinstance(value, str) or _RFC3339_INSTANT.fullmatch(value) is None:
        raise RegressionError(
            "runtime.invalid_captured_at",
            location,
            "capturedAt must be an RFC 3339 instant with an explicit offset",
        )
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise RegressionError(
            "runtime.invalid_captured_at",
            location,
            "capturedAt must be a valid RFC 3339 instant",
        ) from error
    return int(parsed.timestamp() * 1000)


__all__ = (
    "AssignmentLease",
    "CriterionEvaluation",
    "DEFAULT_LEASE_DURATION_MILLIS",
    "EvidenceArtifact",
    "EvidenceEnvelope",
    "EvidenceReference",
    "EvidenceReceipt",
    "EmergencyOperationResult",
    "MainRun",
    "OperationResult",
    "NegativeControlEvaluation",
    "OracleDiagnostic",
    "OracleEvaluation",
    "OracleEvaluationRequest",
    "OracleEvaluator",
    "OracleEvaluatorIdentity",
    "PLAN_FILENAME",
    "TRANSITION_FAULT_INTERRUPTION_PREFIX",
    "StateFingerprint",
    "aggregate_oracle_evaluation",
    "open_run",
    "replay",
)
