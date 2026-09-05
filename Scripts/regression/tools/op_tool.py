#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys
from types import MappingProxyType
from typing import Any, Dict, Mapping, Optional, Tuple

from regression.core.capability import OperationGrant, OperationRequest
from regression.core.contracts import BoundLane
from regression.core.digest import canonical_digest
from regression.core.errors import RegressionError
from regression.core.events import decode_json_bytes
from regression.core.fields import ABSENT, SCREENSHOT_KEYS, field_value, screenshot_paths
from regression.core.ids import CallID, NodeID, OperationID, SidekickID, SignatureID
from regression.core.plan import CompiledRunPlan
from regression.core.runtime import OperationResult, StateFingerprint, open_run
from regression.core.runview import LeaseStatus, NodeStatus
from regression.tools.ledger_lock import lane_lock_state
from regression.tools.pixel_heuristics import all_black, capture_failed
from regression.tools.raster import RasterError
from regression.rubric_compiler import FieldPredicate, compile_criteria


VERIFICATION = Path(__file__).resolve().parents[2] / "verification"
if str(VERIFICATION) not in sys.path:
    sys.path.insert(0, str(VERIFICATION))

from harness.failures import InstrumentFault
from regression_operation_adapter import (
    OperationContext,
    RegressionOperationAdapter,
    ResidentOperationBackend,
)


OP_LEASE_DURATION_MILLIS = 4 * 60 * 60 * 1000
TRANSITION_TRACE_ARM = OperationID("operation:transition-trace.arm@1")
PREPARATION_TRANSCRIPT_SCHEMA = "enchron.regression.preparation-transcript@1"
DESIGNATED_RESPONSE_KEYS = ("response", "record", "playbackState")
TARGET_FILENAME = "lane-target"
SCREENSHOT_MEDIA_TYPE = "image/png"
MAXIMUM_SCREENSHOT_BYTES = 16 * 1024 * 1024
NO_FIELD_PREDICATE = "no compiled field predicate"
FIELD_ABSENT = "indeterminate"
FIELD_HOLDS = "satisfied"
FIELD_FAILS = "violated"

ARM_WITHOUT_DISARM_REFUSAL = (
    "this call arms the transition trace, and a tool that stops after one call "
    "leaves the device armed with no disarm; the emergency cleanup that pairs "
    "with it is not part of this phase"
)


class OpToolError(ValueError):
    pass




@dataclass(frozen=True)
class OpOutcome:
    node: Optional[NodeID] = None
    call: Optional[CallID] = None
    succeeded: bool = False
    detail: str = ""
    fields: Mapping[str, Any] = MappingProxyType({})
    signatures: Tuple[SignatureID, ...] = ()
    screenshot: Optional[bytes] = None
    predicates: Mapping[str, str] = MappingProxyType({})
    refused: bool = False
    lane: Optional[str] = None
    pending_node: Optional[NodeID] = None
    state: Optional[str] = None

    def payload(self) -> Dict[str, Any]:
        if self.refused:
            return {
                "refused": True,
                "lane": self.lane,
                "state": self.state,
                "pendingNode": None
                if self.pending_node is None
                else str(self.pending_node),
                "reason": self.detail,
            }
        return {
            "node": str(self.node),
            "call": str(self.call),
            "succeeded": self.succeeded,
            "detail": self.detail,
            "fields": dict(self.fields),
            "signatures": [str(item) for item in self.signatures],
            "predicates": dict(self.predicates),
            "screenshotBytes": 0 if self.screenshot is None else len(self.screenshot),
        }


class _AdapterBridge:
    def __init__(self, context: OperationContext, productions: Tuple[Any, ...], receipts: Tuple[Any, ...]) -> None:
        self._context = context
        self._productions = productions
        self._receipts = receipts
        self.invocation = None

    def invoke(self, grant: OperationGrant, arguments_bytes: bytes) -> OperationResult:
        arguments = decode_json_bytes(arguments_bytes, str(grant.call_id))
        adapter = RegressionOperationAdapter(ResidentOperationBackend())
        try:
            self.invocation = adapter.invoke(
                str(grant.operation), arguments, self._context
            )
        except InstrumentFault as fault:
            return OperationResult(
                False,
                (),
                f"instrument fault {fault.kind}",
                {
                    "succeeded": False,
                    "failure": {
                        "class": "instrument",
                        "kind": fault.kind,
                        "evidence": dict(fault.evidence),
                    },
                },
            )
        outputs = dict(self.invocation.result)
        succeeded = outputs.get("succeeded")
        if type(succeeded) is not bool:
            raise RegressionError(
                "op.invalid_backend_result",
                str(grant.call_id),
                "the resident backend result must carry a boolean succeeded field",
            )
        detail = "" if succeeded else str(outputs.get("reason", "operation failed"))
        fingerprints = ()
        if succeeded and self._productions:
            fingerprint = canonical_digest(
                {
                    "schema": PREPARATION_TRANSCRIPT_SCHEMA,
                    "calls": [*self._receipts, _receipt(grant, outputs)],
                }
            )
            fingerprints = tuple(
                StateFingerprint(item.key, item.schema, fingerprint)
                for item in self._productions
            )
        return OperationResult(succeeded, fingerprints, detail, outputs)


def _receipt(grant: OperationGrant, outputs: Mapping[str, Any]) -> Dict[str, Any]:
    return {
        "callId": str(grant.call_id),
        "operation": str(grant.operation),
        "contractDigest": str(grant.contract_digest),
        "argumentsDigest": str(grant.arguments_digest),
        "implementationDigest": str(grant.implementation_digest),
        "invocationIndex": grant.invocation_index,
        "outputs": dict(outputs),
    }


def _completed_receipts(lease, call_id: CallID) -> Tuple[Dict[str, Any], ...]:
    receipts = []
    for item in lease.invocations:
        if item.call_id == call_id or not item.completed or item.succeeded is not True:
            continue
        receipts.append(
            {
                "callId": str(item.call_id),
                "operation": str(item.operation),
                "contractDigest": str(item.contract_digest),
                "argumentsDigest": str(item.arguments_digest),
                "implementationDigest": str(item.implementation_digest),
                "invocationIndex": item.invocation_index,
                "outputs": {}
                if item.outputs is None
                else dict(item.outputs.payload()),
            }
        )
    return tuple(receipts)


def _request(call) -> OperationRequest:
    return OperationRequest(
        call.call_id,
        call.operation,
        call.contract_digest,
        call.arguments_digest,
        call.implementation_locator,
        call.implementation_digest,
    )


def screenshot_bytes(outputs: Mapping[str, Any]) -> Optional[bytes]:
    """One capture reaches the Agent's context base64 encoded. A file larger
    than the cap is left where it is rather than spent on that context."""
    for candidate in _designated_paths(outputs) + screenshot_paths(outputs)[::-1]:
        path = Path(candidate)
        if path.is_file() and not path.is_symlink():
            if path.stat().st_size > MAXIMUM_SCREENSHOT_BYTES:
                continue
            return path.read_bytes()
    return None


def _designated_paths(outputs: Mapping[str, Any]) -> Tuple[str, ...]:
    designated = []
    for key in SCREENSHOT_KEYS:
        value = outputs.get(key)
        if isinstance(value, str) and value:
            designated.append(value)
    for key in DESIGNATED_RESPONSE_KEYS:
        nested = outputs.get(key)
        if isinstance(nested, Mapping):
            designated.extend(_designated_paths(nested))
    return tuple(designated)


def pixel_signatures(screenshot: Optional[bytes]) -> Tuple[SignatureID, ...]:
    if screenshot is None:
        return ()
    try:
        hits = (capture_failed(screenshot), all_black(screenshot))
    except (RasterError, OSError, ValueError):
        return ()
    return tuple(item for item in hits if item is not None)


def field_predicates(node, outputs: Mapping[str, Any]) -> Dict[str, str]:
    return {
        str(binding.id): _obligation_reading(binding, outputs)
        for binding in getattr(node, "evaluation_bindings", ())
    }


def _obligation_reading(binding, outputs: Mapping[str, Any]) -> str:
    predicates, _ = compile_criteria(binding.rubric.criteria)
    if not predicates:
        return NO_FIELD_PREDICATE
    return "; ".join(_predicate_reading(item, outputs) for item in predicates)


def _predicate_reading(predicate: FieldPredicate, outputs: Mapping[str, Any]) -> str:
    named = f"{predicate.field}{predicate.operator}{predicate.value}"
    read = field_value(outputs, predicate.field)
    if read is ABSENT:
        return f"{FIELD_ABSENT}: {named} names a field this call did not report"
    if read == predicate.value:
        return f"{FIELD_HOLDS}: {named}"
    return f"{FIELD_FAILS}: {named}, read {read!r}"


def run(
    plan: CompiledRunPlan,
    run_directory: Path,
    node: NodeID,
    call: CallID,
    lane: BoundLane,
    target: str,
    sidekick: SidekickID,
    now_millis: Optional[int] = None,
) -> OpOutcome:
    if not isinstance(lane, BoundLane):
        raise OpToolError("op drives one concrete lane")
    if not isinstance(target, str) or not target:
        raise OpToolError("op needs the device or simulator it drives")
    main = open_run(plan, Path(run_directory))
    try:
        lock = lane_lock_state(main.view, lane)
        if lock.refuses_an_operation:
            return OpOutcome(
                refused=True,
                lane=lane.value,
                state=lock.state.value,
                pending_node=lock.pending_node,
                detail=lock.reason,
            )
        armed = _armed_call(main, node)
        if armed is not None:
            return OpOutcome(
                node=node,
                call=armed,
                refused=True,
                lane=lane.value,
                state=lock.state.value,
                detail=ARM_WITHOUT_DISARM_REFUSAL,
            )
        offered = _lease_for(main, lane, node, sidekick, now_millis)
        if isinstance(offered, OpOutcome):
            return offered
        lease = offered
        view = main.view.lease(lease.lease_id)
        current = view.current_call
        if current is None:
            raise OpToolError(
                f"every planned call on {view.node_id} has already run"
            )
        if current.call_id != call:
            raise OpToolError(
                f"{view.node_id} runs its calls in plan order; {current.call_id} "
                f"comes before {call}"
            )
        if current.operation == TRANSITION_TRACE_ARM:
            raise OpToolError(ARM_WITHOUT_DISARM_REFUSAL)

        assignment = (
            Path(run_directory) / "assignments" / str(view.lease_id)
        ).resolve()
        _pin_target(assignment, target)
        context = OperationContext(
            lane.value,
            target,
            assignment,
            (assignment / "controller").resolve(),
            main.plan.build_identity.bundle_identifier,
        )
        bridge = _AdapterBridge(
            context,
            current.state_productions,
            _completed_receipts(view, current.call_id),
        )
        grant = main.authorize_operation(
            main.capability_for_lease(view), _request(current), now_millis=now_millis
        )
        result = main.invoke_operation(grant, grant.arguments_bytes, bridge)
        outputs = dict(result.outputs.payload())
        screenshot = screenshot_bytes(outputs)
        return OpOutcome(
            view.node_id,
            current.call_id,
            result.succeeded,
            result.detail,
            outputs,
            pixel_signatures(screenshot),
            screenshot,
            _node_predicates(main, view.node_id, outputs),
        )
    finally:
        main.close()


def _node_predicates(main, node_id: NodeID, outputs: Mapping[str, Any]) -> Dict[str, str]:
    found = next((item for item in main.plan.nodes if item.id == node_id), None)
    return field_predicates(found, outputs)


def _armed_call(main, node: NodeID) -> Optional[CallID]:
    found = next((item for item in main.plan.nodes if item.id == node), None)
    for call in getattr(found, "calls", ()):
        if call.operation == TRANSITION_TRACE_ARM:
            return call.call_id
    return None


def _pin_target(assignment: Path, target: str) -> None:
    assignment.mkdir(parents=True, exist_ok=True)
    pin = assignment / TARGET_FILENAME
    if not pin.exists():
        pin.write_text(target, encoding="utf-8")
        return
    recorded = pin.read_text(encoding="utf-8")
    if recorded != target:
        raise OpToolError(
            f"this lease already ran against {recorded}; one Scenario does not "
            f"move to {target} part way through"
        )


def _lease_for(main, lane: BoundLane, node: NodeID, sidekick: SidekickID, now_millis):
    current = main.view
    existing = next(
        (
            item
            for item in current.leases
            if item.lane is lane
            and item.status is LeaseStatus.ACTIVE
            and current.node(item.node_id).status is NodeStatus.LEASED
        ),
        None,
    )
    if existing is not None:
        if existing.node_id != node:
            raise OpToolError(
                f"the {lane.value} lane already holds {existing.node_id}, not {node}"
            )
        if existing.sidekick_id != sidekick:
            raise OpToolError(
                f"this lease belongs to {existing.sidekick_id}, not {sidekick}"
            )
        return existing
    claimed = main.claim(
        lane,
        sidekick,
        now_millis=now_millis,
        lease_duration_millis=OP_LEASE_DURATION_MILLIS,
    )
    if claimed.node_id != node:
        return OpOutcome(
            node=claimed.node_id,
            refused=True,
            lane=lane.value,
            state=lane_lock_state(main.view, lane).state.value,
            detail=(
                f"the scheduler offers {claimed.node_id} on {lane.value}, not "
                f"{node}; that node now holds the lane"
            ),
        )
    return main.view.lease(claimed.id)


__all__ = (
    "ARM_WITHOUT_DISARM_REFUSAL",
    "FIELD_ABSENT",
    "FIELD_FAILS",
    "FIELD_HOLDS",
    "NO_FIELD_PREDICATE",
    "OP_LEASE_DURATION_MILLIS",
    "OpOutcome",
    "OpToolError",
    "field_predicates",
    "field_value",
    "pixel_signatures",
    "run",
    "screenshot_bytes",
)
