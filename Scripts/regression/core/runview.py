from __future__ import annotations

from collections.abc import Mapping as MappingABC
from dataclasses import dataclass, replace
from datetime import datetime
from enum import Enum
import json
import math
import re
from typing import Any, Dict, Iterable, Iterator, Mapping, Optional, Tuple

from .capability import AllowedOperationCall, OperationGrant
from .contracts import BoundLane
from .digest import canonical_bytes, digest_bytes
from .errors import RegressionError
from .events import EventType, LedgerEvent, decode_json_bytes, payload_value
from .expression import (
    OracleResult,
    SuccessExpression,
    evaluate_success,
    parse_success_expression,
    referenced_obligations,
)
from .ids import (
    CallID,
    CaseKey,
    Digest,
    EvidenceSchema,
    EvidenceType,
    GrantID,
    LeaseID,
    NodeID,
    ObligationID,
    OperationID,
    PreparationID,
    RunID,
    SidekickID,
    SignatureID,
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
from .state import EpochTable, StateHandle, TagEpoch


class NodeStatus(Enum):
    PENDING = "pending"
    LEASED = "leased"
    PASSED = "passed"
    FAILED = "failed"
    FAILED_KNOWN = "failed(known)"
    BLOCKED_BY = "blockedBy"
    DEFERRED_HUMAN = "deferred(human)"
    INDETERMINATE = "indeterminate"


TERMINAL_NODE_STATUSES = (
    NodeStatus.PASSED,
    NodeStatus.FAILED,
    NodeStatus.FAILED_KNOWN,
    NodeStatus.BLOCKED_BY,
    NodeStatus.DEFERRED_HUMAN,
    NodeStatus.INDETERMINATE,
)

PRODUCT_NODE_STATUSES = (
    NodeStatus.PASSED,
    NodeStatus.FAILED,
    NodeStatus.FAILED_KNOWN,
)

PRODUCT_FAILURE_NODE_STATUSES = (
    NodeStatus.FAILED,
    NodeStatus.FAILED_KNOWN,
)


class Attribution(Enum):
    PRODUCT = "product"
    HARNESS = "harness"
    SPEC = "spec"


MAX_NODE_ATTEMPTS = 2

HARNESS_TIMEOUT_KINDS = frozenset(
    {"transport-timeout", "wait-expired", "provisional-budget-expired"}
)

ADJUDICATED_NODE_STATUSES = {
    OracleResult.SATISFIED: (NodeStatus.PASSED,),
    OracleResult.VIOLATED: (NodeStatus.FAILED, NodeStatus.FAILED_KNOWN),
    OracleResult.INDETERMINATE: (
        NodeStatus.INDETERMINATE,
        NodeStatus.DEFERRED_HUMAN,
    ),
}


class LeaseStatus(Enum):
    ACTIVE = "active"
    COMPLETED = "completed"
    INTERRUPTED = "interrupted"


class RunOutcome(Enum):
    PASSED = "passed"
    FAILED = "failed"
    INTERRUPTED = "interrupted"


TRANSITION_FAULT_INTERRUPTION_PREFIX = "enchron.regression.interruption@1:"
_TRANSITION_TRACE_ARM = OperationID("operation:transition-trace.arm@1")
_TRANSITION_TRACE_DISARM = OperationID("operation:transition-trace.disarm@1")


def aggregate_oracle_results(results: Iterable[OracleResult]) -> OracleResult:
    values = tuple(results)
    if any(result is OracleResult.INDETERMINATE for result in values):
        return OracleResult.INDETERMINATE
    if any(result is OracleResult.VIOLATED for result in values):
        return OracleResult.VIOLATED
    if values and all(result is OracleResult.SATISFIED for result in values):
        return OracleResult.SATISFIED
    return OracleResult.INDETERMINATE


def _invalid_output(location: str, detail: str) -> RegressionError:
    return RegressionError("runtime.invalid_operation_output", location, detail)


def _freeze_json(value: Any, location: str) -> Any:
    if value is None or type(value) in (bool, int, str):
        return value
    if type(value) is float:
        if not math.isfinite(value):
            raise _invalid_output(location, "JSON numbers must be finite")
        return value
    if isinstance(value, FrozenJSONObject):
        return value
    if isinstance(value, MappingABC):
        return FrozenJSONObject.from_mapping(value, location)
    if isinstance(value, (list, tuple)):
        return tuple(
            _freeze_json(item, f"{location}[{index}]")
            for index, item in enumerate(value)
        )
    raise _invalid_output(
        location,
        f"unsupported JSON value {type(value).__name__}",
    )


def _thaw_json(value: Any) -> Any:
    if isinstance(value, FrozenJSONObject):
        return value.payload()
    if isinstance(value, tuple):
        return [_thaw_json(item) for item in value]
    return value


def _validate_frozen_json(value: Any, location: str) -> None:
    if value is None or type(value) in (bool, int, str):
        return
    if type(value) is float:
        if not math.isfinite(value):
            raise _invalid_output(location, "JSON numbers must be finite")
        return
    if isinstance(value, FrozenJSONObject):
        return
    if isinstance(value, tuple):
        for index, item in enumerate(value):
            _validate_frozen_json(item, f"{location}[{index}]")
        return
    raise _invalid_output(
        location,
        "immutable JSON values must use FrozenJSONObject and tuple containers",
    )


@dataclass(frozen=True)
class FrozenJSONObject(MappingABC):
    entries: Tuple[Tuple[str, Any], ...] = ()

    def __post_init__(self) -> None:
        entries = tuple(self.entries)
        if any(
            not isinstance(item, tuple)
            or len(item) != 2
            or type(item[0]) is not str
            for item in entries
        ):
            raise _invalid_output(
                "outputs", "object entries must be (string, value) pairs"
            )
        keys = tuple(item[0] for item in entries)
        if keys != tuple(sorted(keys)) or len(keys) != len(set(keys)):
            raise _invalid_output(
                "outputs",
                "object fields must be unique and use stable lexical order",
            )
        for key, value in entries:
            _validate_frozen_json(value, f"outputs.{key}")
        object.__setattr__(self, "entries", entries)

    @classmethod
    def from_mapping(
        cls, value: Mapping[str, Any], location: str = "outputs"
    ) -> "FrozenJSONObject":
        if not isinstance(value, MappingABC):
            raise _invalid_output(location, "operation outputs must be a JSON object")
        keys = tuple(value.keys())
        if any(type(key) is not str for key in keys):
            raise _invalid_output(location, "JSON object field names must be strings")
        return cls(
            tuple(
                (key, _freeze_json(value[key], f"{location}.{key}"))
                for key in sorted(keys)
            )
        )

    def __getitem__(self, key: str) -> Any:
        for name, value in self.entries:
            if name == key:
                return value
        raise KeyError(key)

    def __iter__(self) -> Iterator[str]:
        return (name for name, _ in self.entries)

    def __len__(self) -> int:
        return len(self.entries)

    def payload(self) -> Dict[str, Any]:
        return {name: _thaw_json(value) for name, value in self.entries}


@dataclass(frozen=True)
class LaneGateView:
    lane: BoundLane
    node_id: NodeID


@dataclass(frozen=True)
class StateProductionView:
    key: StateKey
    schema: StateSchema
    preparation_id: PreparationID
    produced_by_call: CallID
    depends_on_tags: Tuple[StateTag, ...]


@dataclass(frozen=True)
class CallPlanView:
    call_id: CallID
    operation: OperationID
    contract_digest: Digest
    arguments_bytes: bytes
    arguments_digest: Digest
    implementation_locator: str
    implementation_digest: Digest
    max_invocations: int
    invalidates_tags: Tuple[StateTag, ...]
    phase: str
    preparation_id: Optional[PreparationID]
    state_productions: Tuple[StateProductionView, ...]


@dataclass(frozen=True)
class OperationInvocationView:
    grant_id: GrantID
    run_id: RunID
    plan_digest: Digest
    node_id: NodeID
    lease_id: LeaseID
    lane: BoundLane
    call_id: CallID
    operation: OperationID
    contract_digest: Digest
    arguments_template_digest: Digest
    arguments_bytes: bytes
    arguments_digest: Digest
    implementation_locator: str
    implementation_digest: Digest
    invocation_index: int
    invalidates_tags: Tuple[StateTag, ...]
    invoked: bool = False
    completed: bool = False
    succeeded: Optional[bool] = None
    outputs: Optional[FrozenJSONObject] = None
    detail: Optional[str] = None

    @property
    def uncertain(self) -> bool:
        return not self.completed


@dataclass(frozen=True)
class AcceptedArtifactView:
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
    object_path: str
    receipt_digest: Digest


@dataclass(frozen=True)
class OracleEvaluationView:
    obligation_id: ObligationID
    overall: OracleResult
    criteria: Tuple[Tuple[str, OracleResult], ...]
    negative_controls: Tuple[Tuple[str, OracleResult], ...]
    evidence_refs: Tuple[Digest, ...]
    detail: Tuple[Tuple[str, str], ...]


@dataclass(frozen=True)
class PreparedStateView:
    handle: StateHandle
    preparation_id: PreparationID
    produced_by_call: CallID
    lease_id: LeaseID
    event_sequence: int


@dataclass(frozen=True)
class LeaseView:
    lease_id: LeaseID
    node_id: NodeID
    lane: BoundLane
    sidekick_id: SidekickID
    claimed_at_millis: int
    deadline_millis: int
    calls: Tuple[CallPlanView, ...]
    cursor: int = 0
    invocations: Tuple[OperationInvocationView, ...] = ()
    status: LeaseStatus = LeaseStatus.ACTIVE
    envelope_digest: Optional[Digest] = None
    evidence_accepted: bool = False
    evidence: Tuple[AcceptedArtifactView, ...] = ()
    oracle_evaluations: Tuple[OracleEvaluationView, ...] = ()
    claim_sequence: int = 0

    @property
    def current_call(self) -> Optional[CallPlanView]:
        if self.cursor >= len(self.calls):
            return None
        return self.calls[self.cursor]

    @property
    def operations_complete(self) -> bool:
        return self.cursor == len(self.calls)

    @property
    def uncertain_invocations(self) -> Tuple[OperationInvocationView, ...]:
        return tuple(item for item in self.invocations if item.uncertain)

    def invocation(self, grant_id: GrantID) -> Optional[OperationInvocationView]:
        return next(
            (item for item in self.invocations if item.grant_id == grant_id), None
        )

    def invocation_count(self, call_id: CallID) -> int:
        return sum(item.call_id == call_id for item in self.invocations)

    def call_succeeded(self, call_id: CallID) -> bool:
        return any(
            item.call_id == call_id and item.completed and item.succeeded is True
            for item in self.invocations
        )


def _result_reference(
    value: str, location: str
) -> Optional[Tuple[CallID, str]]:
    if not value.startswith("result://"):
        return None
    parts = value[len("result://") :].split("/")
    if len(parts) != 2 or not parts[1]:
        raise RegressionError(
            "runtime.invalid_result_reference",
            location,
            "result reference must be result://<call-id>/<top-level-field>",
        )
    try:
        call_id = parse_call_id(parts[0], "operationArguments.resultReference.callId")
    except RegressionError as error:
        raise RegressionError(
            "runtime.invalid_result_reference",
            location,
            "result reference contains an invalid call id",
        ) from error
    return call_id, parts[1]


def _resolve_argument_value(value: Any, lease: LeaseView, location: str) -> Any:
    if isinstance(value, str):
        reference = _result_reference(value, location)
        if reference is None:
            return value
        call_id, field = reference
        call_index = next(
            (
                index
                for index, planned in enumerate(lease.calls)
                if planned.call_id == call_id
            ),
            None,
        )
        if call_index is None:
            raise RegressionError(
                "runtime.result_reference_unknown_call",
                location,
                f"result reference names call outside lease: {call_id}",
            )
        successful = next(
            (
                item
                for item in lease.invocations
                if item.call_id == call_id
                and item.completed
                and item.succeeded is True
            ),
            None,
        )
        if call_index >= lease.cursor or successful is None:
            code = (
                "runtime.result_reference_unsuccessful_call"
                if any(
                    item.call_id == call_id
                    and item.completed
                    and item.succeeded is False
                    for item in lease.invocations
                )
                else "runtime.result_reference_not_earlier"
            )
            raise RegressionError(
                code,
                location,
                f"result reference requires an earlier successful call: {call_id}",
            )
        if successful.outputs is None:
            raise RegressionError(
                "runtime.result_reference_invalid_output",
                location,
                f"successful call has no structured outputs: {call_id}",
            )
        try:
            return _thaw_json(successful.outputs[field])
        except KeyError as error:
            raise RegressionError(
                "runtime.result_reference_missing_field",
                location,
                f"call {call_id} did not produce top-level field {field!r}",
            ) from error
    if isinstance(value, list):
        return [
            _resolve_argument_value(item, lease, f"{location}[{index}]")
            for index, item in enumerate(value)
        ]
    if isinstance(value, dict):
        return {
            key: _resolve_argument_value(item, lease, f"{location}.{key}")
            for key, item in value.items()
        }
    return value


def resolve_call_arguments(lease: LeaseView, call: CallPlanView) -> bytes:
    if lease.current_call != call:
        raise RegressionError(
            "runtime.call_out_of_order",
            str(call.call_id),
            "only the current planned call can resolve arguments",
        )
    template = json.loads(call.arguments_bytes.decode("utf-8"))
    resolved = _resolve_argument_value(
        template,
        lease,
        f"{call.call_id}.arguments",
    )
    return canonical_bytes(resolved)


@dataclass(frozen=True)
class AdjudicationView:
    first_deviant_frame: Optional[int]
    region_observation: str
    attribution: Attribution
    signature: Optional[SignatureID]
    bundle_frame_count: int


@dataclass(frozen=True)
class NodeView:
    node_id: NodeID
    kind: str
    predecessors: Tuple[NodeID, ...]
    lane_candidates: Tuple[BoundLane, ...]
    gate_dependencies: Tuple[LaneGateView, ...]
    success: Optional[SuccessExpression] = None
    status: NodeStatus = NodeStatus.PENDING
    lane: Optional[BoundLane] = None
    lease_id: Optional[LeaseID] = None
    failure_ancestors: Tuple[NodeID, ...] = ()
    adjudication: Optional[AdjudicationView] = None


@dataclass(frozen=True)
class LaneView:
    lane: BoundLane
    epochs: EpochTable = EpochTable()
    interrupted: bool = False
    interruption_reason: Optional[str] = None
    active_lease_id: Optional[LeaseID] = None


@dataclass(frozen=True)
class RunView:
    run_id: Optional[RunID]
    plan_digest: Optional[Digest]
    events: Tuple[LedgerEvent, ...]
    nodes: Tuple[NodeView, ...]
    lanes: Tuple[LaneView, ...]
    leases: Tuple[LeaseView, ...]
    state_handles: Tuple[PreparedStateView, ...]
    outcome: Optional[RunOutcome] = None

    @property
    def closed(self) -> bool:
        return self.outcome is not None

    def node(self, node_id: NodeID) -> NodeView:
        found = next((item for item in self.nodes if item.node_id == node_id), None)
        if found is None:
            raise RegressionError(
                "runtime.unknown_node", str(node_id), "node is not part of this run"
            )
        return found

    def lane(self, lane: BoundLane) -> LaneView:
        found = next((item for item in self.lanes if item.lane is lane), None)
        if found is None:
            raise RegressionError(
                "runtime.unknown_lane", lane.value, "lane is not part of this run"
            )
        return found

    def lease(self, lease_id: LeaseID) -> LeaseView:
        found = next(
            (item for item in self.leases if item.lease_id == lease_id), None
        )
        if found is None:
            raise RegressionError(
                "runtime.unknown_lease", str(lease_id), "lease is not part of this run"
            )
        return found

    def valid_state_handle(
        self,
        key: StateKey,
        schema: StateSchema,
        lane: BoundLane,
        preparation_id: PreparationID,
    ) -> Optional[PreparedStateView]:
        epochs = self.lane(lane).epochs
        for prepared in reversed(self.state_handles):
            if prepared.preparation_id != preparation_id:
                continue
            if prepared.handle.is_valid(key, schema, lane, epochs):
                return prepared
        return None


def settled_oracle_result(
    node: NodeView, lease: Optional[LeaseView]
) -> Optional[OracleResult]:
    if (
        node.status is not NodeStatus.LEASED
        or node.success is None
        or lease is None
        or lease.node_id != node.node_id
        or not lease.operations_complete
        or not lease.evidence_accepted
    ):
        return None
    recorded = {item.obligation_id: item.overall for item in lease.oracle_evaluations}
    referenced = referenced_obligations(node.success)
    settled = evaluate_success(
        node.success,
        {
            key: recorded.get(key, OracleResult.INDETERMINATE)
            for key in referenced
        },
    )
    if referenced <= frozenset(recorded) or settled is not OracleResult.INDETERMINATE:
        return settled
    return None


def awaiting_adjudication(node: NodeView, lease: Optional[LeaseView]) -> bool:
    settled = settled_oracle_result(node, lease)
    return settled is not None and settled is not OracleResult.SATISFIED


def failure_ancestors(nodes: Iterable[NodeView]) -> Tuple[NodeID, ...]:
    result = set()
    for node in nodes:
        if node.status is NodeStatus.FAILED:
            result.add(node.node_id)
        elif node.status is NodeStatus.BLOCKED_BY:
            result.update(node.failure_ancestors)
    return tuple(sorted(result, key=str))


def strict_predecessors(node: NodeView) -> Tuple[NodeID, ...]:
    gates = frozenset(item.node_id for item in node.gate_dependencies)
    return tuple(item for item in node.predecessors if item not in gates)


def derivable_verdict(
    node: NodeView, nodes: Mapping[NodeID, NodeView]
) -> Optional[Tuple[NodeStatus, Tuple[NodeID, ...]]]:
    if node.status is not NodeStatus.PENDING:
        return None
    if node.kind == "bothJoin":
        predecessors = tuple(nodes[item] for item in node.predecessors)
        ancestors = failure_ancestors(predecessors)
        if ancestors:
            return (NodeStatus.BLOCKED_BY, ancestors)
        if all(item.status is NodeStatus.PASSED for item in predecessors):
            return (NodeStatus.PASSED, ())
        return None

    ancestors = failure_ancestors(
        tuple(nodes[item] for item in strict_predecessors(node))
    )
    if ancestors:
        return (NodeStatus.BLOCKED_BY, ancestors)
    gate_ancestors = []
    has_nonfailed_lane = False
    for lane in node.lane_candidates:
        gate = next(
            (item for item in node.gate_dependencies if item.lane is lane), None
        )
        if gate is None:
            has_nonfailed_lane = True
            continue
        found = failure_ancestors((nodes[gate.node_id],))
        if found:
            gate_ancestors.extend(found)
        else:
            has_nonfailed_lane = True
    if not has_nonfailed_lane and gate_ancestors:
        return (NodeStatus.BLOCKED_BY, tuple(sorted(set(gate_ancestors), key=str)))
    return None


def settled_node_statuses(view: RunView) -> Dict[NodeID, NodeStatus]:
    nodes = {item.node_id: item for item in view.nodes}
    while True:
        derived = None
        for node in nodes.values():
            decision = derivable_verdict(node, nodes)
            if decision is not None:
                derived = (node, decision)
                break
        if derived is None:
            return {node_id: item.status for node_id, item in nodes.items()}
        node, (status, ancestors) = derived
        nodes[node.node_id] = replace(
            node, status=status, failure_ancestors=ancestors
        )


def current_lease(view: RunView, node: NodeView) -> Optional[LeaseView]:
    if node.lease_id is None:
        return None
    return next(
        (item for item in view.leases if item.lease_id == node.lease_id), None
    )


def attempts_in_claim_order(view: RunView, node_id: NodeID) -> Tuple[LeaseView, ...]:
    return tuple(
        sorted(
            (item for item in view.leases if item.node_id == node_id),
            key=lambda item: item.claim_sequence,
        )
    )


def nodes_awaiting_adjudication(view: RunView) -> Tuple[NodeView, ...]:
    return tuple(
        node
        for node in view.nodes
        if awaiting_adjudication(node, current_lease(view, node))
    )


def build_run_view(events: Iterable[LedgerEvent]) -> RunView:
    event_values = tuple(events)
    if not event_values:
        return RunView(None, None, (), (), (), (), ())

    nodes: Dict[NodeID, NodeView] = {}
    lanes: Dict[BoundLane, LaneView] = {}
    leases: Dict[LeaseID, LeaseView] = {}
    handles = []
    outcome: Optional[RunOutcome] = None
    run_id = event_values[0].run_id
    plan_digest = event_values[0].plan_digest

    for event in event_values:
        location = f"sequence:{event.sequence}"
        if event.run_id != run_id or event.plan_digest != plan_digest:
            raise _transition(location, "event identity changed within the run")
        if outcome is not None:
            raise _transition(location, "events cannot follow RunClosed")
        payload = _mapping(payload_value(event.payload, location), location)

        if event.type is EventType.RUN_OPENED:
            if event.sequence != 1 or nodes or lanes or leases:
                raise _transition(location, "RunOpened must be the first event")
            _open_nodes(payload, nodes, location)
            continue

        if not nodes:
            raise _transition(location, "RunOpened must precede runtime events")

        if event.type is EventType.LANE_BOOTSTRAPPED:
            lane = _lane(payload.get("lane"), location + ".lane")
            if lane in lanes:
                raise _transition(location, "lane was bootstrapped more than once")
            lanes[lane] = LaneView(lane)
        elif event.type is EventType.NODE_CLAIMED:
            _claim_node(payload, nodes, lanes, leases, location)
        elif event.type is EventType.OPERATION_AUTHORIZED:
            _authorize(payload, event, leases, location)
        elif event.type is EventType.OPERATION_INVOKED:
            _invoke(payload, leases, lanes, location)
        elif event.type is EventType.OPERATION_COMPLETED:
            produced = _complete(payload, event, leases, lanes, location)
            handles.extend(produced)
        elif event.type is EventType.ENVELOPE_RECEIVED:
            _receive_envelope(payload, leases, location)
        elif event.type is EventType.EVIDENCE_ACCEPTED:
            _accept_evidence(payload, leases, location)
        elif event.type is EventType.ORACLE_EVALUATED:
            _record_oracle(payload, leases, location)
        elif event.type is EventType.VERDICT_RECORDED:
            _record_verdict(payload, nodes, lanes, leases, location)
        elif event.type is EventType.NODE_REOPENED:
            _reopen_node(payload, nodes, lanes, leases, location)
        elif event.type is EventType.LANE_INTERRUPTED:
            _interrupt_lane(payload, nodes, lanes, leases, location)
        elif event.type is EventType.RUN_CLOSED:
            if any(node.status in (NodeStatus.PENDING, NodeStatus.LEASED) for node in nodes.values()):
                raise _transition(location, "RunClosed requires terminal node states")
            if any(lease.status is LeaseStatus.ACTIVE for lease in leases.values()):
                raise _transition(location, "RunClosed cannot retain an active lease")
            try:
                outcome = RunOutcome(payload.get("outcome"))
            except (TypeError, ValueError) as error:
                raise _transition(location, "RunClosed has an invalid outcome") from error
        else:
            raise _transition(location, f"unsupported event type {event.type.value}")

    view = RunView(
        run_id,
        plan_digest,
        event_values,
        tuple(sorted(nodes.values(), key=lambda item: str(item.node_id))),
        tuple(sorted(lanes.values(), key=lambda item: item.lane.value)),
        tuple(sorted(leases.values(), key=lambda item: str(item.lease_id))),
        tuple(handles),
        outcome,
    )
    validate_emergency_interruption_records(view)
    return view


def _assigned_emergency_arm(
    lease: LeaseView,
    disarm_call: CallPlanView,
    generation: object,
    error_code: str,
    location: str,
) -> OperationInvocationView:
    template = decode_json_bytes(
        disarm_call.arguments_bytes,
        f"{location}.assignedArguments",
    )
    reference = template.get("generationToken") if isinstance(template, Mapping) else None
    prefix = "result://"
    suffix = "/generationToken"
    if (
        not isinstance(generation, str)
        or not isinstance(reference, str)
        or set(template) != {"generationToken"}
        or not reference.startswith(prefix)
        or not reference.endswith(suffix)
    ):
        raise RegressionError(
            error_code,
            location,
            "emergency disarm must use one assigned arm generation reference",
        )
    try:
        arm_call_id = parse_call_id(
            reference[len(prefix) : -len(suffix)],
            f"{location}.armCallId",
        )
    except RegressionError as error:
        raise RegressionError(
            error_code,
            location,
            "emergency disarm arm reference is invalid",
        ) from error
    arm = next(
        (
            invocation
            for invocation in lease.invocations
            if invocation.call_id == arm_call_id
            and invocation.operation == _TRANSITION_TRACE_ARM
            and invocation.completed
            and invocation.succeeded is True
            and invocation.outputs is not None
        ),
        None,
    )
    if arm is None or arm.outputs.payload().get("generationToken") != generation:
        raise RegressionError(
            error_code,
            location,
            "emergency disarm generation differs from its assigned completed arm",
        )
    return arm


def _pending_emergency_disarms(lease: LeaseView) -> Tuple[CallPlanView, ...]:
    pending = []
    for call in lease.calls:
        if call.operation != _TRANSITION_TRACE_DISARM or lease.call_succeeded(
            call.call_id
        ):
            continue
        template = decode_json_bytes(
            call.arguments_bytes,
            f"{call.call_id}.assignedArguments",
        )
        reference = template.get("generationToken") if isinstance(template, Mapping) else None
        if (
            not isinstance(reference, str)
            or set(template) != {"generationToken"}
            or not reference.startswith("result://")
            or not reference.endswith("/generationToken")
        ):
            continue
        try:
            arm_call_id = parse_call_id(
                reference[len("result://") : -len("/generationToken")],
                f"{call.call_id}.armCallId",
            )
        except RegressionError:
            continue
        arm = next(
            (
                invocation
                for invocation in lease.invocations
                if invocation.call_id == arm_call_id
                and invocation.operation == _TRANSITION_TRACE_ARM
                and invocation.completed
                and invocation.succeeded is True
                and invocation.outputs is not None
                and isinstance(
                    invocation.outputs.payload().get("generationToken"), str
                )
            ),
            None,
        )
        if arm is not None:
            pending.append(call)
    return tuple(pending)


def validate_emergency_interruption_records(view: RunView) -> None:
    for event in view.events:
        if event.type is not EventType.LANE_INTERRUPTED:
            continue
        location = f"sequence:{event.sequence}"
        event_payload = payload_value(event.payload, f"{location}.payload")
        if not isinstance(event_payload, Mapping):
            continue
        lease_id = event_payload.get("leaseId")
        lease = next(
            (item for item in view.leases if str(item.lease_id) == lease_id),
            None,
        )
        pending = () if lease is None else _pending_emergency_disarms(lease)
        reason = event_payload.get("reason")
        if not isinstance(reason, str) or not reason.startswith(
            TRANSITION_FAULT_INTERRUPTION_PREFIX
        ):
            if pending:
                raise RegressionError(
                    "runtime.missing_emergency_operation_record",
                    location,
                    "an interrupted armed transition must record its assigned emergency disarm",
                )
            continue
        encoded = reason[len(TRANSITION_FAULT_INTERRUPTION_PREFIX) :].encode(
            "utf-8"
        )
        record = decode_json_bytes(encoded, f"{location}.emergencyOperation")
        if not isinstance(record, Mapping) or canonical_bytes(record) != encoded:
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation record must be canonical JSON object",
            )
        if set(record) != {
            "schema",
            "schemaVersion",
            "reason",
            "affectedLeaseId",
            "emergencyOperation",
        } or (
            record.get("schema") != "enchron.regression.interruption"
            or record.get("schemaVersion") != 1
            or not isinstance(record.get("reason"), str)
            or not record.get("reason")
        ):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency interruption record has an invalid closed envelope",
            )
        if record.get("affectedLeaseId") != lease_id:
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation affected lease differs from LaneInterrupted",
            )
        if lease is None or lease.lane.value != event_payload.get("lane"):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation lease is absent or belongs to another lane",
            )
        operation = record.get("emergencyOperation")
        if not isinstance(operation, Mapping) or set(operation) != {
            "callId",
            "operation",
            "contractDigest",
            "argumentsBytes",
            "argumentsDigest",
            "implementationLocator",
            "implementationDigest",
            "trigger",
            "result",
        }:
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation identity has unknown or missing fields",
            )
        call = next(
            (
                item
                for item in lease.calls
                if str(item.call_id) == operation.get("callId")
            ),
            None,
        )
        if call is None or (
            call.operation != _TRANSITION_TRACE_DISARM
            or str(call.operation) != operation.get("operation")
            or str(call.contract_digest) != operation.get("contractDigest")
            or call.implementation_locator != operation.get("implementationLocator")
            or str(call.implementation_digest)
            != operation.get("implementationDigest")
        ):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation identity differs from the assigned disarm",
            )
        if pending != (call,):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation must account for the only pending assigned disarm",
            )
        arguments_text = operation.get("argumentsBytes")
        if not isinstance(arguments_text, str):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation argumentsBytes must be text",
            )
        arguments_bytes = arguments_text.encode("utf-8")
        arguments = decode_json_bytes(
            arguments_bytes, f"{location}.argumentsBytes"
        )
        if (
            canonical_bytes(arguments) != arguments_bytes
            or str(digest_bytes(arguments_bytes)) != operation.get("argumentsDigest")
            or not isinstance(arguments, Mapping)
            or set(arguments) != {"generationToken"}
            or not isinstance(arguments.get("generationToken"), str)
        ):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation arguments are not the recorded canonical object",
            )
        _assigned_emergency_arm(
            lease,
            call,
            arguments["generationToken"],
            "runtime.invalid_emergency_operation_record",
            location,
        )
        result = operation.get("result")
        if (
            not isinstance(result, Mapping)
            or set(result) != {"succeeded", "detail", "outputs"}
            or type(result.get("succeeded")) is not bool
            or not isinstance(result.get("detail"), str)
            or not isinstance(result.get("outputs"), Mapping)
        ):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation result has an invalid closed shape",
            )
        FrozenJSONObject.from_mapping(result["outputs"], f"{location}.result.outputs")
        if operation.get("trigger") not in ("exception", "cancellation"):
            raise RegressionError(
                "runtime.invalid_emergency_operation_record",
                location,
                "emergency Operation trigger is invalid",
            )


def _open_nodes(
    payload: Mapping[str, Any],
    nodes: Dict[NodeID, NodeView],
    location: str,
) -> None:
    values = _list(payload.get("nodes"), location + ".nodes")
    if not values:
        raise _transition(location, "RunOpened must declare plan nodes")
    for index, value in enumerate(values):
        item_location = f"{location}.nodes[{index}]"
        item = _mapping(value, item_location)
        node_id = _node_id(item.get("nodeId"), item_location + ".nodeId")
        if node_id in nodes:
            raise _transition(item_location, "RunOpened repeats a node")
        kind = _text(item.get("kind"), item_location + ".kind")
        if kind not in ("scenarioAttempt", "bothJoin"):
            raise _transition(item_location, "node kind is not recognized")
        predecessors = tuple(
            _node_id(value, item_location + ".predecessors")
            for value in _list(item.get("predecessors"), item_location + ".predecessors")
        )
        lane_candidates = tuple(
            _lane(value, item_location + ".laneCandidates")
            for value in _list(item.get("laneCandidates"), item_location + ".laneCandidates")
        )
        gates = []
        for gate_value in _list(
            item.get("gateDependencies"), item_location + ".gateDependencies"
        ):
            gate = _mapping(gate_value, item_location + ".gateDependencies")
            gates.append(
                LaneGateView(
                    _lane(gate.get("lane"), item_location + ".gate.lane"),
                    _node_id(gate.get("nodeId"), item_location + ".gate.nodeId"),
                )
            )
        raw_success = item.get("success")
        if kind == "scenarioAttempt":
            if raw_success is None:
                raise _transition(
                    item_location, "Scenario node needs its success expression"
                )
            success = parse_success_expression(
                raw_success, item_location + ".success"
            )
        else:
            if raw_success is not None:
                raise _transition(
                    item_location, "join node cannot carry a success expression"
                )
            success = None
        nodes[node_id] = NodeView(
            node_id,
            kind,
            predecessors,
            lane_candidates,
            tuple(gates),
            success,
        )
        if kind == "scenarioAttempt" and not lane_candidates:
            raise _transition(item_location, "Scenario node needs a lane candidate")
        if kind == "bothJoin" and lane_candidates:
            raise _transition(item_location, "join node cannot name a lane")
        if len(predecessors) != len(set(predecessors)):
            raise _transition(item_location, "node repeats a predecessor")
        if len({gate.lane for gate in gates}) != len(gates):
            raise _transition(item_location, "node repeats a lane gate")
        if any(gate.lane not in lane_candidates for gate in gates):
            raise _transition(item_location, "lane gate is not a node candidate")
    known = frozenset(nodes)
    for node in nodes.values():
        unknown = (frozenset(node.predecessors) | frozenset(
            gate.node_id for gate in node.gate_dependencies
        )) - known
        if unknown:
            raise _transition(location, "RunOpened references an unknown node")


def _claim_node(
    payload: Mapping[str, Any],
    nodes: Dict[NodeID, NodeView],
    lanes: Dict[BoundLane, LaneView],
    leases: Dict[LeaseID, LeaseView],
    location: str,
) -> None:
    node_id = _node_id(payload.get("nodeId"), location + ".nodeId")
    lease_id = _lease_id(payload.get("leaseId"), location + ".leaseId")
    lane = _lane(payload.get("lane"), location + ".lane")
    sidekick_id = SidekickID(
        parse_identifier("sidekick", payload.get("sidekickId"), location + ".sidekickId")
    )
    claimed_at = _integer(
        payload.get("claimedAtMillis"), location + ".claimedAtMillis"
    )
    deadline = _integer(payload.get("deadlineMillis"), location + ".deadlineMillis")
    if claimed_at < 0 or deadline <= claimed_at:
        raise _transition(location, "lease time bounds are invalid")
    node = nodes.get(node_id)
    if node is None or node.status is not NodeStatus.PENDING:
        raise _transition(location, "only a pending plan node may be claimed")
    lane_view = lanes.get(lane)
    if lane_view is None or lane_view.interrupted or lane_view.active_lease_id is not None:
        raise _transition(location, "lane cannot accept this claim")
    if lane not in node.lane_candidates:
        raise _transition(location, "claim lane is not a node candidate")
    gate_ids = frozenset(item.node_id for item in node.gate_dependencies)
    if any(
        nodes[item].status is not NodeStatus.PASSED
        for item in node.predecessors
        if item not in gate_ids
    ):
        raise _transition(location, "claim has an unfinished strict predecessor")
    gate = next((item for item in node.gate_dependencies if item.lane is lane), None)
    if gate is not None and nodes[gate.node_id].status is not NodeStatus.PASSED:
        raise _transition(location, "claim lane has not passed its MainGate")
    if lease_id in leases:
        raise _transition(location, "lease identifier was reused")
    calls = tuple(
        _call_plan(value, f"{location}.calls[{index}]")
        for index, value in enumerate(_list(payload.get("calls"), location + ".calls"))
    )
    if not calls or len({item.call_id for item in calls}) != len(calls):
        raise _transition(location, "a lease needs unique ordered calls")
    leases[lease_id] = LeaseView(
        lease_id,
        node_id,
        lane,
        sidekick_id,
        claimed_at,
        deadline,
        calls,
        claim_sequence=len(leases),
    )
    nodes[node_id] = replace(
        node, status=NodeStatus.LEASED, lane=lane, lease_id=lease_id
    )
    lanes[lane] = replace(lane_view, active_lease_id=lease_id)


def _authorize(
    payload: Mapping[str, Any],
    event: LedgerEvent,
    leases: Dict[LeaseID, LeaseView],
    location: str,
) -> None:
    invocation = _invocation(payload, location)
    lease = leases.get(invocation.lease_id)
    if lease is None or lease.status is not LeaseStatus.ACTIVE:
        raise _transition(location, "authorization does not belong to an active lease")
    call = lease.current_call
    if call is None or lease.uncertain_invocations:
        raise _transition(location, "authorization has no current call")
    if (
        invocation.run_id != event.run_id
        or invocation.plan_digest != event.plan_digest
        or invocation.node_id != lease.node_id
        or invocation.lane is not lease.lane
        or invocation.call_id != call.call_id
        or invocation.operation != call.operation
        or invocation.contract_digest != call.contract_digest
        or invocation.arguments_template_digest != call.arguments_digest
        or invocation.implementation_locator != call.implementation_locator
        or invocation.implementation_digest != call.implementation_digest
        or invocation.invalidates_tags != call.invalidates_tags
    ):
        raise _transition(location, "authorization does not match the exact planned call")
    try:
        resolved = resolve_call_arguments(lease, call)
    except RegressionError as error:
        raise _transition(
            location,
            f"authorization cannot resolve planned arguments: {error.code}",
        ) from error
    if (
        invocation.arguments_bytes != resolved
        or invocation.arguments_digest != digest_bytes(resolved)
    ):
        raise _transition(location, "authorization resolved arguments do not match replay")
    expected_index = lease.invocation_count(call.call_id) + 1
    if invocation.invocation_index != expected_index:
        raise _transition(location, "authorization invocation index is not monotonic")
    if expected_index > call.max_invocations:
        raise _transition(location, "authorization exceeds maxInvocations")
    leases[lease.lease_id] = replace(
        lease, invocations=lease.invocations + (invocation,)
    )


def _invoke(
    payload: Mapping[str, Any],
    leases: Dict[LeaseID, LeaseView],
    lanes: Dict[BoundLane, LaneView],
    location: str,
) -> None:
    grant_id = _grant_id(payload.get("grantId"), location + ".grantId")
    lease_id = _lease_id(payload.get("leaseId"), location + ".leaseId")
    lease = leases.get(lease_id)
    if lease is None or lease.status is not LeaseStatus.ACTIVE:
        raise _transition(location, "invocation does not belong to an active lease")
    index, invocation = _find_invocation(lease, grant_id, location)
    exact = _invocation(payload, location)
    if exact != invocation or invocation.invoked or invocation.completed:
        raise _transition(location, "invocation does not match its exact authorization")
    lane = lanes.get(lease.lane)
    if lane is None or lane.interrupted:
        raise _transition(location, "invocation lane is unavailable")
    advances = _list(payload.get("epochAdvances"), location + ".epochAdvances")
    declared = tuple(sorted(invocation.invalidates_tags, key=str))
    if len(advances) != len(declared):
        raise _transition(location, "epoch advances do not cover declared tags")
    values = dict(lane.epochs.as_mapping())
    seen = []
    for value in advances:
        advance = _mapping(value, location + ".epochAdvances")
        tag = StateTag(
            parse_identifier("state_tag", advance.get("tag"), location + ".epoch.tag")
        )
        before = _integer(advance.get("before"), location + ".epoch.before")
        after = _integer(advance.get("after"), location + ".epoch.after")
        if before != values.get(tag, 0) or after != before + 1:
            raise _transition(location, "epoch advance is not monotonic")
        values[tag] = after
        seen.append(tag)
    if tuple(seen) != declared:
        raise _transition(location, "epoch advances differ from declared tags")
    updated = replace(invocation, invoked=True)
    invocations = lease.invocations[:index] + (updated,) + lease.invocations[index + 1 :]
    leases[lease_id] = replace(lease, invocations=invocations)
    lanes[lease.lane] = replace(lane, epochs=EpochTable.from_mapping(values))


def _complete(
    payload: Mapping[str, Any],
    event: LedgerEvent,
    leases: Dict[LeaseID, LeaseView],
    lanes: Dict[BoundLane, LaneView],
    location: str,
) -> Tuple[PreparedStateView, ...]:
    grant_id = _grant_id(payload.get("grantId"), location + ".grantId")
    lease_id = _lease_id(payload.get("leaseId"), location + ".leaseId")
    lease = leases.get(lease_id)
    if lease is None or lease.status is not LeaseStatus.ACTIVE:
        raise _transition(location, "completion does not belong to an active lease")
    index, invocation = _find_invocation(lease, grant_id, location)
    if not invocation.invoked or invocation.completed:
        raise _transition(location, "completion needs one unfinished invocation")
    succeeded = payload.get("succeeded")
    if type(succeeded) is not bool:
        raise _transition(location, "completion succeeded must be a boolean")
    detail = payload.get("detail")
    if not isinstance(detail, str):
        raise _transition(location, "completion detail must be text")
    outputs = FrozenJSONObject.from_mapping(
        _mapping(payload.get("outputs"), location + ".outputs"),
        location + ".outputs",
    )
    state_values = _list(payload.get("stateHandles"), location + ".stateHandles")
    if state_values and not succeeded:
        raise _transition(location, "a failed call cannot produce state handles")
    produced = tuple(
        _prepared_state(value, lease, event.sequence, location)
        for value in state_values
    )
    call = lease.current_call
    if call is None or call.call_id != invocation.call_id:
        raise _transition(location, "completion is not for the current call")
    expected = {
        (
            item.key,
            item.schema,
            item.preparation_id,
            item.produced_by_call,
            item.depends_on_tags,
        )
        for item in call.state_productions
    }
    current_epochs = lanes[lease.lane].epochs
    actual = set()
    for item in produced:
        dependencies = item.handle.dependencies
        actual.add(
            (
                item.handle.key,
                item.handle.schema,
                item.preparation_id,
                item.produced_by_call,
                tuple(entry.tag for entry in dependencies.entries),
            )
        )
        if any(
            current_epochs.value(entry.tag) != entry.value
            for entry in dependencies.entries
        ):
            raise _transition(location, "state handle epoch snapshot is not current")
    if succeeded and (actual != expected or len(produced) != len(expected)):
        raise _transition(location, "completion state handles differ from the call plan")
    if not succeeded and actual:
        raise _transition(location, "failed completion cannot produce state handles")
    updated = replace(
        invocation,
        completed=True,
        succeeded=succeeded,
        outputs=outputs,
        detail=detail,
    )
    invocations = lease.invocations[:index] + (updated,) + lease.invocations[index + 1 :]
    cursor = lease.cursor + 1 if succeeded else lease.cursor
    leases[lease_id] = replace(lease, invocations=invocations, cursor=cursor)
    return produced


def _receive_envelope(
    payload: Mapping[str, Any], leases: Dict[LeaseID, LeaseView], location: str
) -> None:
    lease_id = _lease_id(payload.get("leaseId"), location + ".leaseId")
    digest = _digest(payload.get("envelopeDigest"), location + ".envelopeDigest")
    lease = leases.get(lease_id)
    if lease is None:
        raise _transition(location, "envelope names an unknown lease")
    if lease.status is not LeaseStatus.ACTIVE or not lease.operations_complete:
        raise _transition(location, "envelope requires a completed active lease")
    if lease.envelope_digest is not None and lease.envelope_digest != digest:
        raise _transition(location, "lease received conflicting envelope digests")
    leases[lease_id] = replace(lease, envelope_digest=digest)


def _accept_evidence(
    payload: Mapping[str, Any], leases: Dict[LeaseID, LeaseView], location: str
) -> None:
    lease_id = _lease_id(payload.get("leaseId"), location + ".leaseId")
    digest = _digest(payload.get("envelopeDigest"), location + ".envelopeDigest")
    lease = leases.get(lease_id)
    if (
        lease is None
        or lease.status is not LeaseStatus.ACTIVE
        or not lease.operations_complete
        or lease.envelope_digest != digest
        or lease.evidence_accepted
    ):
        raise _transition(location, "accepted evidence has no matching received envelope")
    artifacts = tuple(
        _accepted_artifact(value, f"{location}.artifacts[{index}]")
        for index, value in enumerate(
            _list(payload.get("artifacts"), location + ".artifacts")
        )
    )
    obligation_ids = tuple(item.obligation_id for item in artifacts)
    if not artifacts or len(obligation_ids) != len(set(obligation_ids)):
        raise _transition(location, "accepted evidence must bind unique obligations")
    for artifact in artifacts:
        call = next(
            (
                item
                for item in lease.calls
                if item.call_id == artifact.produced_by_call
            ),
            None,
        )
        if (
            call is None
            or call.contract_digest != artifact.producer_contract_digest
            or not lease.call_succeeded(artifact.produced_by_call)
        ):
            raise _transition(
                location,
                "accepted evidence producer differs from the planned Operation",
            )
        captured = _rfc3339_millis(
            artifact.captured_at, location + ".capturedAt"
        )
        if not lease.claimed_at_millis <= captured <= lease.deadline_millis:
            raise _transition(location, "accepted evidence was captured outside its lease")
    leases[lease_id] = replace(lease, evidence_accepted=True, evidence=artifacts)


def _record_oracle(
    payload: Mapping[str, Any], leases: Dict[LeaseID, LeaseView], location: str
) -> None:
    lease_id = _lease_id(payload.get("leaseId"), location + ".leaseId")
    lease = leases.get(lease_id)
    if (
        lease is None
        or lease.status is not LeaseStatus.ACTIVE
        or not lease.evidence_accepted
    ):
        raise _transition(location, "Oracle result needs accepted evidence")
    obligation_id = ObligationID(
        parse_identifier(
            "obligation", payload.get("obligationId"), location + ".obligationId"
        )
    )
    try:
        overall = OracleResult(payload.get("overall"))
    except (TypeError, ValueError) as error:
        raise _transition(location, "Oracle result is not recognized") from error
    criteria = tuple(
        (
            _text(item.get("criterion"), item_location + ".criterion"),
            _oracle_result(item.get("result"), item_location + ".result"),
        )
        for item_location, item in (
            (
                f"{location}.criteria[{index}]",
                _mapping(value, f"{location}.criteria[{index}]"),
            )
            for index, value in enumerate(
                _list(payload.get("criteria"), location + ".criteria")
            )
        )
    )
    negative_controls = tuple(
        (
            _text(
                item.get("negativeControl"),
                item_location + ".negativeControl",
            ),
            _oracle_result(item.get("result"), item_location + ".result"),
        )
        for item_location, item in (
            (
                f"{location}.negativeControls[{index}]",
                _mapping(value, f"{location}.negativeControls[{index}]"),
            )
            for index, value in enumerate(
                _list(
                    payload.get("negativeControls"),
                    location + ".negativeControls",
                )
            )
        )
    )
    canonical_overall = aggregate_oracle_results(
        result for _, result in criteria + negative_controls
    )
    if overall is not canonical_overall:
        raise _transition(
            location,
            "Oracle overall differs from the canonical component aggregate",
        )
    evidence_refs = tuple(
        _digest(
            _mapping(value, f"{location}.evidenceRefs[{index}]").get(
                "receiptDigest"
            ),
            f"{location}.evidenceRefs[{index}].receiptDigest",
        )
        for index, value in enumerate(
            _list(payload.get("evidenceRefs"), location + ".evidenceRefs")
        )
    )
    detail = tuple(
        (
            _text(item.get("code"), item_location + ".code"),
            _text_allow_empty(item.get("detail"), item_location + ".detail"),
        )
        for item_location, item in (
            (
                f"{location}.detail[{index}]",
                _mapping(value, f"{location}.detail[{index}]"),
            )
            for index, value in enumerate(
                _list(payload.get("detail"), location + ".detail")
            )
        )
    )
    if not criteria or not negative_controls or not evidence_refs:
        raise _transition(
            location,
            "Oracle evaluation needs criteria, negative controls, and evidence refs",
        )
    accepted = next(
        (item for item in lease.evidence if item.obligation_id == obligation_id),
        None,
    )
    if accepted is None or evidence_refs != (accepted.receipt_digest,):
        raise _transition(
            location,
            "Oracle evidence refs do not match the accepted artifact receipt",
        )
    if len(detail) > 16 or any(len(item[1]) > 1024 for item in detail):
        raise _transition(location, "Oracle diagnostic detail exceeds its bound")
    if any(item.obligation_id == obligation_id for item in lease.oracle_evaluations):
        raise _transition(location, "obligation was evaluated more than once")
    leases[lease_id] = replace(
        lease,
        oracle_evaluations=lease.oracle_evaluations
        + (
            OracleEvaluationView(
                obligation_id,
                overall,
                criteria,
                negative_controls,
                evidence_refs,
                detail,
            ),
        ),
    )


def _record_verdict(
    payload: Mapping[str, Any],
    nodes: Dict[NodeID, NodeView],
    lanes: Dict[BoundLane, LaneView],
    leases: Dict[LeaseID, LeaseView],
    location: str,
) -> None:
    node_id = _node_id(payload.get("nodeId"), location + ".nodeId")
    node = nodes.get(node_id)
    if node is None or node.status not in (NodeStatus.PENDING, NodeStatus.LEASED):
        raise _transition(location, "node verdict is duplicated or unknown")
    try:
        status = NodeStatus(payload.get("status"))
    except (TypeError, ValueError) as error:
        raise _transition(location, "node verdict status is not recognized") from error
    if status not in TERMINAL_NODE_STATUSES:
        raise _transition(location, "node verdict is not terminal")
    ancestors = tuple(
        _node_id(value, location + ".failureAncestors")
        for value in _list(payload.get("failureAncestors"), location + ".failureAncestors")
    )
    if status is NodeStatus.BLOCKED_BY and not ancestors:
        raise _transition(location, "BlockedBy needs a failed ancestor")
    if status is not NodeStatus.BLOCKED_BY and ancestors:
        raise _transition(location, "only BlockedBy may carry failure ancestors")

    raw_lease = payload.get("leaseId")
    settled = None
    if node.status is NodeStatus.LEASED:
        lease_id = _lease_id(raw_lease, location + ".leaseId")
        if lease_id != node.lease_id:
            raise _transition(location, "verdict lease does not match the node")
        lease = leases[lease_id]
        settled = settled_oracle_result(node, lease)
        if settled is not None and status not in ADJUDICATED_NODE_STATUSES[settled]:
            raise _transition(
                location, "node verdict contradicts the Oracle result of its own lease"
            )
        if status is NodeStatus.DEFERRED_HUMAN and not deferrable_from(
            node_id, leases
        ):
            raise _transition(
                location,
                "a node reaches the human layer only after two consecutive "
                "attempts that both timed out on the harness",
            )
        if (
            settled is None
            and lease.oracle_evaluations
            and status is not NodeStatus.INDETERMINATE
        ):
            raise _transition(
                location,
                "a half-evaluated lease carries no Oracle result to adjudicate",
            )
        if status in PRODUCT_NODE_STATUSES and (
            not lease.operations_complete
            or not lease.evidence_accepted
            or not lease.oracle_evaluations
        ):
            raise _transition(
                location,
                "product verdict needs completed operations and evaluated evidence",
            )
        if node.kind == "bothJoin":
            raise _transition(location, "join node cannot own a lease")
        if lease.status is LeaseStatus.ACTIVE:
            lease_status = (
                LeaseStatus.INTERRUPTED
                if status is NodeStatus.INDETERMINATE
                else LeaseStatus.COMPLETED
            )
            leases[lease_id] = replace(lease, status=lease_status)
        lane = lanes[lease.lane]
        if lane.active_lease_id == lease_id:
            lanes[lease.lane] = replace(lane, active_lease_id=None)
    elif raw_lease is not None:
        raise _transition(location, "an unleased node verdict cannot name a lease")
    elif node.kind == "scenarioAttempt" and status in PRODUCT_NODE_STATUSES:
        raise _transition(location, "Scenario product verdict needs its lease")
    elif node.kind == "bothJoin" and status in (
        *PRODUCT_FAILURE_NODE_STATUSES,
        NodeStatus.INDETERMINATE,
    ):
        if status in PRODUCT_FAILURE_NODE_STATUSES:
            raise _transition(location, "join nodes cannot create product failures")

    raw_adjudication = payload.get("adjudication")
    adjudication = None
    if settled is not None and settled is not OracleResult.SATISFIED:
        if raw_adjudication is None:
            raise _transition(
                location, "a non-satisfied node verdict needs its adjudication"
            )
        adjudication = _adjudication(
            raw_adjudication, status, location + ".adjudication"
        )
    elif raw_adjudication is not None:
        raise _transition(
            location, "only a non-satisfied node verdict carries an adjudication"
        )

    nodes[node_id] = replace(
        node,
        status=status,
        failure_ancestors=tuple(sorted(set(ancestors), key=str)),
        adjudication=adjudication,
    )


def timed_out_on_the_harness(lease: LeaseView) -> bool:
    for invocation in lease.invocations:
        if not invocation.completed or invocation.outputs is None:
            continue
        failure = invocation.outputs.payload().get("failure")
        if not isinstance(failure, Mapping):
            continue
        if (
            failure.get("class") == "instrument"
            and failure.get("kind") in HARNESS_TIMEOUT_KINDS
        ):
            return True
    return False


def deferrable_from(
    node_id: NodeID, leases: Mapping[LeaseID, LeaseView]
) -> bool:
    owned = sorted(
        (item for item in leases.values() if item.node_id == node_id),
        key=lambda item: item.claim_sequence,
    )
    if len(owned) < MAX_NODE_ATTEMPTS:
        return False
    return all(
        timed_out_on_the_harness(item) for item in owned[-MAX_NODE_ATTEMPTS:]
    )


def attempts_of(node_id: NodeID, leases: Mapping[LeaseID, LeaseView]) -> int:
    return sum(1 for item in leases.values() if item.node_id == node_id)


def reopen_refusal(
    node: Optional[NodeView],
    attempts: int,
    lanes: Mapping[BoundLane, LaneView],
) -> Optional[str]:
    if node is None:
        return "reopen names a node this run does not hold"
    if node.status is not NodeStatus.INDETERMINATE:
        return (
            f"a node is reopened out of {NodeStatus.INDETERMINATE.value}, not out of "
            f"{node.status.value}"
        )
    if node.adjudication is None:
        return "a reopened node carries the adjudication that sent it back"
    if node.adjudication.attribution is not Attribution.HARNESS:
        return (
            "only a harness attribution reopens a node; "
            f"{node.adjudication.attribution.value} is a conclusion, not a retry"
        )
    if attempts >= MAX_NODE_ATTEMPTS:
        return (
            f"{node.node_id} already ran {attempts} of {MAX_NODE_ATTEMPTS} attempts"
        )
    open_lanes = [
        candidate
        for candidate in node.lane_candidates
        if candidate in lanes and not lanes[candidate].interrupted
    ]
    if not open_lanes:
        return (
            f"every lane {node.node_id} can run on is interrupted, so reopening it "
            "would leave it pending with nothing able to claim it"
        )
    return None


def _reopen_node(
    payload: Mapping[str, Any],
    nodes: Dict[NodeID, NodeView],
    lanes: Dict[BoundLane, LaneView],
    leases: Dict[LeaseID, LeaseView],
    location: str,
) -> None:
    node_id = _node_id(payload.get("nodeId"), location + ".nodeId")
    node = nodes.get(node_id)
    attempts = attempts_of(node_id, leases)
    refusal = reopen_refusal(node, attempts, lanes)
    if refusal is not None:
        raise _transition(location, refusal)
    recorded = payload.get("attemptsBefore")
    if recorded != attempts:
        raise _transition(
            location,
            f"the reopen records {recorded!r} attempts before it, and the ledger "
            f"holds {attempts}",
        )
    nodes[node_id] = replace(node, status=NodeStatus.PENDING, lease_id=None)


def _adjudication(value: Any, status: NodeStatus, location: str) -> AdjudicationView:
    item = _mapping(value, location)
    unknown = set(item) - {
        "attribution",
        "bundleFrameCount",
        "firstDeviantFrame",
        "regionObservation",
        "signature",
    }
    if unknown:
        raise _transition(
            location, "adjudication field(s) not recognized: " + ", ".join(sorted(unknown))
        )
    frame_count = _positive_integer(
        item.get("bundleFrameCount"), location + ".bundleFrameCount"
    )
    raw_frame = item.get("firstDeviantFrame")
    frame = (
        None
        if raw_frame is None
        else _integer(raw_frame, location + ".firstDeviantFrame")
    )
    if frame is not None and not 0 <= frame < frame_count:
        raise _transition(
            location, "first deviant frame lies outside the bundle frame count"
        )
    observation = _text(
        item.get("regionObservation"), location + ".regionObservation"
    )
    try:
        attribution = Attribution(item.get("attribution"))
    except (TypeError, ValueError) as error:
        raise _transition(location, "attribution is not recognized") from error
    raw_signature = item.get("signature")
    signature = (
        None
        if raw_signature is None
        else SignatureID(
            parse_identifier("signature", raw_signature, location + ".signature")
        )
    )
    if status is NodeStatus.FAILED_KNOWN and signature is None:
        raise _transition(location, "a known defect verdict needs its signature")
    return AdjudicationView(frame, observation, attribution, signature, frame_count)


def _interrupt_lane(
    payload: Mapping[str, Any],
    nodes: Dict[NodeID, NodeView],
    lanes: Dict[BoundLane, LaneView],
    leases: Dict[LeaseID, LeaseView],
    location: str,
) -> None:
    lane_value = _lane(payload.get("lane"), location + ".lane")
    reason = _text(payload.get("reason"), location + ".reason")
    lane = lanes.get(lane_value)
    if lane is None:
        raise _transition(location, "interruption names an unknown lane")
    if lane.interrupted:
        raise _transition(location, "lane interruption was recorded more than once")
    raw_lease = payload.get("leaseId")
    lease_id = None if raw_lease is None else _lease_id(raw_lease, location + ".leaseId")
    if lease_id is not None:
        lease = leases.get(lease_id)
        if lease is None or lease.lane is not lane_value:
            raise _transition(location, "interruption lease does not match the lane")
        if lease.status is LeaseStatus.ACTIVE:
            leases[lease_id] = replace(lease, status=LeaseStatus.INTERRUPTED)
    lanes[lane_value] = replace(
        lane,
        interrupted=True,
        interruption_reason=reason,
        active_lease_id=None,
    )


def _call_plan(value: Any, location: str) -> CallPlanView:
    item = _mapping(value, location)
    call_id = parse_call_id(item.get("callId"), location + ".callId")
    operation = OperationID(
        parse_identifier("operation", item.get("operation"), location + ".operation")
    )
    maximum = _integer(item.get("maxInvocations"), location + ".maxInvocations")
    if maximum < 1:
        raise _transition(location, "maxInvocations must be positive")
    tags = tuple(
        StateTag(parse_identifier("state_tag", tag, location + ".invalidatesTags"))
        for tag in _list(item.get("invalidatesTags"), location + ".invalidatesTags")
    )
    if tags != tuple(sorted(set(tags), key=str)):
        raise _transition(location, "invalidation tags must be unique and sorted")
    phase = _text(item.get("phase"), location + ".phase")
    if phase not in ("preparation", "scenario"):
        raise _transition(location, "call phase is not recognized")
    raw_preparation = item.get("preparationId")
    preparation_id = (
        None
        if raw_preparation is None
        else PreparationID(
            parse_identifier(
                "preparation", raw_preparation, location + ".preparationId"
            )
        )
    )
    if (phase == "preparation") != (preparation_id is not None):
        raise _transition(location, "preparation phase must bind a Preparation")
    productions = tuple(
        _state_production(value, preparation_id, location)
        for value in _list(item.get("stateProductions"), location + ".stateProductions")
    )
    try:
        allowed = AllowedOperationCall(
            call_id=call_id,
            operation=operation,
            contract_digest=_digest(
                item.get("contractDigest"), location + ".contractDigest"
            ),
            arguments_bytes=_text(
                item.get("argumentsBytes"), location + ".argumentsBytes"
            ).encode("utf-8"),
            arguments_digest=_digest(
                item.get("argumentsDigest"), location + ".argumentsDigest"
            ),
            implementation_locator=_text(
                item.get("implementationLocator"),
                location + ".implementationLocator",
            ),
            implementation_digest=_digest(
                item.get("implementationDigest"),
                location + ".implementationDigest",
            ),
            max_invocations=maximum,
            invalidates_tags=tags,
        )
    except RegressionError as error:
        raise _transition(
            location, f"call plan is not a valid exact capability: {error.code}"
        ) from error
    return CallPlanView(
        allowed.call_id,
        allowed.operation,
        allowed.contract_digest,
        allowed.arguments_bytes,
        allowed.arguments_digest,
        allowed.implementation_locator,
        allowed.implementation_digest,
        allowed.max_invocations,
        allowed.invalidates_tags,
        phase,
        preparation_id,
        productions,
    )


def _state_production(
    value: Any, preparation_id: Optional[PreparationID], location: str
) -> StateProductionView:
    if preparation_id is None:
        raise _transition(location, "scenario calls cannot produce reusable state")
    item = _mapping(value, location + ".stateProductions")
    tags = tuple(
        StateTag(parse_identifier("state_tag", tag, location + ".dependsOnTags"))
        for tag in _list(item.get("dependsOnTags"), location + ".dependsOnTags")
    )
    return StateProductionView(
        parse_state_key(item.get("key"), location + ".key"),
        parse_state_schema(item.get("schema"), location + ".schema"),
        preparation_id,
        parse_call_id(item.get("producedByCall"), location + ".producedByCall"),
        tuple(sorted(set(tags), key=str)),
    )


def _invocation(value: Mapping[str, Any], location: str) -> OperationInvocationView:
    tags = tuple(
        StateTag(parse_identifier("state_tag", tag, location + ".invalidatesTags"))
        for tag in _list(value.get("invalidatesTags"), location + ".invalidatesTags")
    )
    try:
        grant = OperationGrant(
            id=_grant_id(value.get("grantId"), location + ".grantId"),
            run_id=RunID(
                parse_identifier("run", value.get("runId"), location + ".runId")
            ),
            plan_digest=_digest(
                value.get("planDigest"), location + ".planDigest"
            ),
            node_id=_node_id(value.get("nodeId"), location + ".nodeId"),
            lease_id=_lease_id(value.get("leaseId"), location + ".leaseId"),
            lane=_lane(value.get("lane"), location + ".lane"),
            call_id=parse_call_id(value.get("callId"), location + ".callId"),
            operation=OperationID(
                parse_identifier(
                    "operation", value.get("operation"), location + ".operation"
                )
            ),
            contract_digest=_digest(
                value.get("contractDigest"), location + ".contractDigest"
            ),
            arguments_template_digest=_digest(
                value.get("argumentsTemplateDigest"),
                location + ".argumentsTemplateDigest",
            ),
            arguments_bytes=_text(
                value.get("argumentsBytes"), location + ".argumentsBytes"
            ).encode("utf-8"),
            arguments_digest=_digest(
                value.get("argumentsDigest"), location + ".argumentsDigest"
            ),
            implementation_locator=_text(
                value.get("implementationLocator"),
                location + ".implementationLocator",
            ),
            implementation_digest=_digest(
                value.get("implementationDigest"),
                location + ".implementationDigest",
            ),
            invocation_index=_positive_integer(
                value.get("invocationIndex"), location + ".invocationIndex"
            ),
            invalidates_tags=tags,
        )
    except RegressionError as error:
        raise _transition(
            location, f"operation grant fields are invalid: {error.code}"
        ) from error
    return OperationInvocationView(
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


def _prepared_state(
    value: Any, lease: LeaseView, sequence: int, location: str
) -> PreparedStateView:
    item = _mapping(value, location + ".stateHandles")
    entries = tuple(
        TagEpoch(
            StateTag(
                parse_identifier(
                    "state_tag", epoch.get("tag"), location + ".dependencies.tag"
                )
            ),
            _integer(epoch.get("value"), location + ".dependencies.value"),
        )
        for epoch in (
            _mapping(value, location + ".dependencies")
            for value in _list(item.get("dependencies"), location + ".dependencies")
        )
    )
    preparation_id = PreparationID(
        parse_identifier(
            "preparation", item.get("preparationId"), location + ".preparationId"
        )
    )
    produced_by_call = parse_call_id(
        item.get("producedByCall"), location + ".producedByCall"
    )
    handle = StateHandle(
        parse_state_key(item.get("key"), location + ".key"),
        parse_state_schema(item.get("schema"), location + ".schema"),
        _lane(item.get("lane"), location + ".lane"),
        _node_id(item.get("producedByNode"), location + ".producedByNode"),
        EpochTable(tuple(sorted(entries, key=lambda entry: str(entry.tag)))),
        _digest(item.get("fingerprint"), location + ".fingerprint"),
    )
    if handle.lane is not lease.lane or handle.produced_by_node != lease.node_id:
        raise _transition(location, "state handle identity differs from its lease")
    return PreparedStateView(
        handle, preparation_id, produced_by_call, lease.lease_id, sequence
    )


def _accepted_artifact(value: Any, location: str) -> AcceptedArtifactView:
    item = _mapping(value, location)
    relative_path = _text(item.get("relativePath"), location + ".relativePath")
    object_path = _text(item.get("objectPath"), location + ".objectPath")
    byte_length = _integer(item.get("byteLength"), location + ".byteLength")
    if byte_length <= 0:
        raise _transition(location, "artifact byte length must be positive")
    return AcceptedArtifactView(
        ObligationID(
            parse_identifier(
                "obligation", item.get("obligationId"), location + ".obligationId"
            )
        ),
        parse_evidence_type(item.get("evidenceType"), location + ".evidenceType"),
        parse_evidence_schema(
            item.get("evidenceSchema"), location + ".evidenceSchema"
        ),
        parse_case_key(item.get("caseKey"), location + ".caseKey"),
        parse_call_id(item.get("producedByCall"), location + ".producedByCall"),
        _text(item.get("capturedAt"), location + ".capturedAt"),
        _digest(
            item.get("producerContractDigest"),
            location + ".producerContractDigest",
        ),
        relative_path,
        byte_length,
        _digest(item.get("digest"), location + ".digest"),
        object_path,
        _digest(item.get("receiptDigest"), location + ".receiptDigest"),
    )


def _find_invocation(
    lease: LeaseView, grant_id: GrantID, location: str
) -> Tuple[int, OperationInvocationView]:
    for index, invocation in enumerate(lease.invocations):
        if invocation.grant_id == grant_id:
            return index, invocation
    raise _transition(location, "grant is not authorized by this lease")


def _mapping(value: Any, location: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise _transition(location, "event payload field must be an object")
    return value


def _list(value: Any, location: str) -> Tuple[Any, ...]:
    if not isinstance(value, list):
        raise _transition(location, "event payload field must be an array")
    return tuple(value)


def _text(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value:
        raise _transition(location, "event payload field must be a non-empty string")
    return value


def _text_allow_empty(value: Any, location: str) -> str:
    if not isinstance(value, str):
        raise _transition(location, "event payload field must be a string")
    return value


def _oracle_result(value: Any, location: str) -> OracleResult:
    try:
        return OracleResult(value)
    except (TypeError, ValueError) as error:
        raise _transition(location, "Oracle result is not recognized") from error


_RFC3339_INSTANT = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})"
)


def _rfc3339_millis(value: object, location: str) -> int:
    if not isinstance(value, str) or _RFC3339_INSTANT.fullmatch(value) is None:
        raise _transition(location, "capturedAt is not an RFC 3339 instant")
    try:
        return int(
            datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
            * 1000
        )
    except ValueError as error:
        raise _transition(location, "capturedAt is not a valid instant") from error


def _integer(value: Any, location: str) -> int:
    if type(value) is not int:
        raise _transition(location, "event payload field must be an integer")
    return value


def _positive_integer(value: Any, location: str) -> int:
    result = _integer(value, location)
    if result < 1:
        raise _transition(location, "event payload field must be positive")
    return result


def _lane(value: Any, location: str) -> BoundLane:
    try:
        return BoundLane(value)
    except (TypeError, ValueError) as error:
        raise _transition(location, "event payload lane is not recognized") from error


def _digest(value: Any, location: str) -> Digest:
    return Digest(parse_identifier("digest", value, location))


def _node_id(value: Any, location: str) -> NodeID:
    return NodeID(parse_identifier("node", value, location))


def _lease_id(value: Any, location: str) -> LeaseID:
    return LeaseID(parse_identifier("lease", value, location))


def _grant_id(value: Any, location: str) -> GrantID:
    return GrantID(parse_identifier("grant", value, location))


def _transition(location: str, detail: str) -> RegressionError:
    return RegressionError("replay.invalid_transition", location, detail)


__all__ = (
    "ADJUDICATED_NODE_STATUSES",
    "AcceptedArtifactView",
    "AdjudicationView",
    "Attribution",
    "CallPlanView",
    "FrozenJSONObject",
    "LaneGateView",
    "LaneView",
    "LeaseStatus",
    "LeaseView",
    "NodeStatus",
    "NodeView",
    "OperationInvocationView",
    "OracleEvaluationView",
    "PRODUCT_FAILURE_NODE_STATUSES",
    "PRODUCT_NODE_STATUSES",
    "PreparedStateView",
    "RunOutcome",
    "RunView",
    "StateProductionView",
    "TERMINAL_NODE_STATUSES",
    "TRANSITION_FAULT_INTERRUPTION_PREFIX",
    "aggregate_oracle_results",
    "awaiting_adjudication",
    "build_run_view",
    "nodes_awaiting_adjudication",
    "resolve_call_arguments",
    "settled_oracle_result",
    "validate_emergency_interruption_records",
)
