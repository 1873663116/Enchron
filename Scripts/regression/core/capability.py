from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any, Dict, List, Tuple

from .contracts import BoundLane
from .digest import canonical_bytes, canonical_digest, digest_bytes
from .errors import RegressionError
from .ids import (
    CallID,
    Digest,
    GrantID,
    LeaseID,
    NodeID,
    OperationID,
    RunID,
    StateTag,
    parse_call_id,
    parse_identifier,
)


def _identifier(kind: str, value: object, location: str):
    return parse_identifier(kind, value, location)


class _DuplicateArgumentKey(ValueError):
    pass


def _argument_object(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateArgumentKey(key)
        result[key] = value
    return result


def _reject_json_constant(value: str) -> Any:
    raise ValueError(value)


def _canonical_argument_bytes(value: object, location: str) -> bytes:
    if not isinstance(value, bytes):
        raise RegressionError(
            "capability.invalid_arguments",
            location,
            "operation arguments must be canonical JSON bytes",
        )
    try:
        decoded = json.loads(
            value.decode("utf-8"),
            object_pairs_hook=_argument_object,
            parse_constant=_reject_json_constant,
        )
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as error:
        raise RegressionError(
            "capability.invalid_arguments",
            location,
            f"operation arguments are not valid JSON: {error}",
        ) from error
    if not isinstance(decoded, dict):
        raise RegressionError(
            "capability.arguments_not_object",
            location,
            "operation arguments must be a JSON object",
        )
    if canonical_bytes(decoded) != value:
        raise RegressionError(
            "capability.noncanonical_arguments",
            location,
            "operation arguments must use canonical JSON encoding",
        )
    return value


def _implementation_locator(value: object, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise RegressionError(
            "capability.invalid_implementation_locator",
            location,
            "implementation locator must be non-empty text",
        )
    return value


@dataclass(frozen=True)
class AllowedOperationCall:
    call_id: CallID
    operation: OperationID
    contract_digest: Digest
    arguments_bytes: bytes
    arguments_digest: Digest
    implementation_locator: str
    implementation_digest: Digest
    max_invocations: int = 1
    invalidates_tags: Tuple[StateTag, ...] = ()

    def __post_init__(self) -> None:
        call_id = parse_call_id(self.call_id, "allowedOperationCall.callId")
        object.__setattr__(self, "call_id", call_id)
        object.__setattr__(
            self,
            "operation",
            OperationID(
                _identifier(
                    "operation",
                    self.operation,
                    f"allowedOperationCall.{call_id}.operation",
                )
            ),
        )
        arguments = _canonical_argument_bytes(
            self.arguments_bytes,
            f"allowedOperationCall.{call_id}.argumentsBytes",
        )
        object.__setattr__(self, "arguments_bytes", arguments)
        for field_name in (
            "contract_digest",
            "arguments_digest",
            "implementation_digest",
        ):
            object.__setattr__(
                self,
                field_name,
                Digest(
                    _identifier(
                        "digest",
                        getattr(self, field_name),
                        f"allowedOperationCall.{call_id}.{field_name}",
                    )
                ),
            )
        if digest_bytes(arguments) != self.arguments_digest:
            raise RegressionError(
                "capability.arguments_digest_mismatch",
                str(call_id),
                "argument bytes differ from arguments_digest",
            )
        object.__setattr__(
            self,
            "implementation_locator",
            _implementation_locator(
                self.implementation_locator,
                f"allowedOperationCall.{call_id}.implementationLocator",
            ),
        )
        if type(self.max_invocations) is not int or self.max_invocations < 1:
            raise RegressionError(
                "capability.invalid_invocation_limit",
                self.call_id,
                "max_invocations must be a positive integer",
            )
        tags = tuple(
            StateTag(
                _identifier(
                    "state_tag",
                    tag,
                    f"allowedOperationCall.{call_id}.invalidatesTags",
                )
            )
            for tag in self.invalidates_tags
        )
        if len(tags) != len(set(tags)):
            raise RegressionError(
                "capability.duplicate_state_tag",
                self.call_id,
                "invalidates_tags cannot repeat a state tag",
            )
        object.__setattr__(self, "invalidates_tags", tuple(sorted(tags)))


@dataclass(frozen=True)
class AssignmentCapability:
    run_id: RunID
    plan_digest: Digest
    node_id: NodeID
    lease_id: LeaseID
    lane: BoundLane
    calls: Tuple[AllowedOperationCall, ...]
    deadline_millis: int

    def __post_init__(self) -> None:
        object.__setattr__(
            self, "run_id", RunID(_identifier("run", self.run_id, "capability.runId"))
        )
        object.__setattr__(
            self,
            "plan_digest",
            Digest(_identifier("digest", self.plan_digest, "capability.planDigest")),
        )
        object.__setattr__(
            self,
            "node_id",
            NodeID(_identifier("node", self.node_id, "capability.nodeId")),
        )
        object.__setattr__(
            self,
            "lease_id",
            LeaseID(_identifier("lease", self.lease_id, "capability.leaseId")),
        )
        if not isinstance(self.lane, BoundLane):
            raise RegressionError(
                "capability.invalid_lane",
                str(self.lease_id),
                "an assignment capability must bind one concrete lane",
            )
        calls = tuple(self.calls)
        if any(not isinstance(call, AllowedOperationCall) for call in calls):
            raise RegressionError(
                "capability.invalid_allowlist_entry",
                str(self.lease_id),
                "calls must contain compiled AllowedOperationCall values",
            )
        object.__setattr__(self, "calls", calls)
        call_ids = tuple(call.call_id for call in calls)
        if not call_ids:
            raise RegressionError(
                "capability.empty_allowlist",
                str(self.lease_id),
                "an assignment must authorize at least one exact call",
            )
        if len(call_ids) != len(set(call_ids)):
            raise RegressionError(
                "capability.duplicate_call",
                str(self.lease_id),
                "an assignment cannot contain the same call id twice",
            )
        if type(self.deadline_millis) is not int or self.deadline_millis < 0:
            raise RegressionError(
                "capability.invalid_deadline",
                str(self.lease_id),
                "deadline_millis must be a non-negative integer",
            )


@dataclass(frozen=True)
class OperationRequest:
    call_id: CallID
    operation: OperationID
    contract_digest: Digest
    arguments_digest: Digest
    implementation_locator: str
    implementation_digest: Digest

    def __post_init__(self) -> None:
        call_id = parse_call_id(self.call_id, "operationRequest.callId")
        object.__setattr__(self, "call_id", call_id)
        object.__setattr__(
            self,
            "operation",
            OperationID(
                _identifier(
                    "operation", self.operation, f"operationRequest.{call_id}.operation"
                )
            ),
        )
        for field_name in (
            "contract_digest",
            "arguments_digest",
            "implementation_digest",
        ):
            object.__setattr__(
                self,
                field_name,
                Digest(
                    _identifier(
                        "digest",
                        getattr(self, field_name),
                        f"operationRequest.{call_id}.{field_name}",
                    )
                ),
            )
        object.__setattr__(
            self,
            "implementation_locator",
            _implementation_locator(
                self.implementation_locator,
                f"operationRequest.{call_id}.implementationLocator",
            ),
        )


@dataclass(frozen=True)
class InvocationCount:
    call_id: CallID
    count: int

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "call_id",
            parse_call_id(self.call_id, "invocationCount.callId"),
        )
        if type(self.count) is not int or self.count < 0:
            raise RegressionError(
                "capability.invalid_invocation_count",
                self.call_id,
                "invocation count must be a non-negative integer",
            )


@dataclass(frozen=True)
class InvocationCounts:
    entries: Tuple[InvocationCount, ...] = ()

    def __post_init__(self) -> None:
        call_ids = tuple(entry.call_id for entry in self.entries)
        if call_ids != tuple(sorted(call_ids)):
            raise RegressionError(
                "capability.unsorted_counts",
                "$invocations",
                "invocation counts must use stable lexical order",
            )
        if len(call_ids) != len(set(call_ids)):
            raise RegressionError(
                "capability.duplicate_count",
                "$invocations",
                "an invocation count can appear only once",
            )

    def count(self, call_id: CallID) -> int:
        for entry in self.entries:
            if entry.call_id == call_id:
                return entry.count
        return 0

    def increment(self, call_id: CallID) -> "InvocationCounts":
        values = {entry.call_id: entry.count for entry in self.entries}
        values[call_id] = values.get(call_id, 0) + 1
        return InvocationCounts(
            tuple(InvocationCount(key, values[key]) for key in sorted(values))
        )


def _grant_identity_payload(grant: "OperationGrant") -> Dict[str, Any]:
    return {
        "runId": str(grant.run_id),
        "planDigest": str(grant.plan_digest),
        "nodeId": str(grant.node_id),
        "leaseId": str(grant.lease_id),
        "lane": grant.lane.value,
        "callId": str(grant.call_id),
        "operation": str(grant.operation),
        "contractDigest": str(grant.contract_digest),
        "argumentsTemplateDigest": str(grant.arguments_template_digest),
        "argumentsBytes": grant.arguments_bytes.decode("utf-8"),
        "argumentsDigest": str(grant.arguments_digest),
        "implementationLocator": grant.implementation_locator,
        "implementationDigest": str(grant.implementation_digest),
        "invocationIndex": grant.invocation_index,
        "invalidatesTags": [str(tag) for tag in grant.invalidates_tags],
    }


@dataclass(frozen=True)
class OperationGrant:
    id: GrantID
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
    invalidates_tags: Tuple[StateTag, ...] = ()

    def __post_init__(self) -> None:
        object.__setattr__(
            self, "id", GrantID(_identifier("grant", self.id, "operationGrant.id"))
        )
        object.__setattr__(
            self,
            "run_id",
            RunID(_identifier("run", self.run_id, "operationGrant.runId")),
        )
        object.__setattr__(
            self,
            "plan_digest",
            Digest(
                _identifier("digest", self.plan_digest, "operationGrant.planDigest")
            ),
        )
        object.__setattr__(
            self,
            "node_id",
            NodeID(_identifier("node", self.node_id, "operationGrant.nodeId")),
        )
        object.__setattr__(
            self,
            "lease_id",
            LeaseID(_identifier("lease", self.lease_id, "operationGrant.leaseId")),
        )
        if not isinstance(self.lane, BoundLane):
            raise RegressionError(
                "capability.invalid_lane",
                str(self.lease_id),
                "an operation grant must bind one concrete lane",
            )
        call_id = parse_call_id(self.call_id, "operationGrant.callId")
        object.__setattr__(self, "call_id", call_id)
        object.__setattr__(
            self,
            "operation",
            OperationID(
                _identifier(
                    "operation", self.operation, f"operationGrant.{call_id}.operation"
                )
            ),
        )
        for field_name in (
            "contract_digest",
            "arguments_template_digest",
            "arguments_digest",
            "implementation_digest",
        ):
            object.__setattr__(
                self,
                field_name,
                Digest(
                    _identifier(
                        "digest",
                        getattr(self, field_name),
                        f"operationGrant.{call_id}.{field_name}",
                    )
                ),
            )
        arguments = _canonical_argument_bytes(
            self.arguments_bytes,
            f"operationGrant.{call_id}.argumentsBytes",
        )
        object.__setattr__(self, "arguments_bytes", arguments)
        if digest_bytes(arguments) != self.arguments_digest:
            raise RegressionError(
                "capability.arguments_digest_mismatch",
                str(call_id),
                "resolved argument bytes differ from arguments_digest",
            )
        object.__setattr__(
            self,
            "implementation_locator",
            _implementation_locator(
                self.implementation_locator,
                f"operationGrant.{call_id}.implementationLocator",
            ),
        )
        if type(self.invocation_index) is not int or self.invocation_index < 1:
            raise RegressionError(
                "capability.invalid_invocation_index",
                str(call_id),
                "invocation_index must be a positive integer",
            )
        tags = tuple(
            StateTag(
                _identifier(
                    "state_tag",
                    tag,
                    f"operationGrant.{call_id}.invalidatesTags",
                )
            )
            for tag in self.invalidates_tags
        )
        if len(tags) != len(set(tags)):
            raise RegressionError(
                "capability.duplicate_state_tag",
                str(call_id),
                "invalidates_tags cannot repeat a state tag",
            )
        object.__setattr__(self, "invalidates_tags", tuple(sorted(tags)))
        expected = GrantID(
            "grant:"
            + str(canonical_digest(_grant_identity_payload(self))).removeprefix(
                "sha256:"
            )
        )
        if self.id != expected:
            raise RegressionError(
                "capability.grant_id_mismatch",
                str(self.id),
                f"grant id does not bind its exact fields; expected {expected}",
            )

    def payload(self) -> Dict[str, Any]:
        return {"grantId": str(self.id), **_grant_identity_payload(self)}


@dataclass(frozen=True)
class AuthorizationDecision:
    grant: OperationGrant
    counts: InvocationCounts


def authorize_operation(
    capability: AssignmentCapability,
    request: OperationRequest,
    counts: InvocationCounts,
    now_millis: int,
    arguments_bytes: bytes,
) -> AuthorizationDecision:
    if type(now_millis) is not int or now_millis < 0:
        raise RegressionError(
            "capability.invalid_clock",
            str(capability.lease_id),
            "now_millis must be a non-negative integer",
        )
    if now_millis > capability.deadline_millis:
        raise RegressionError(
            "capability.expired_lease",
            str(capability.lease_id),
            "the assignment lease has expired",
        )
    allowed = next(
        (call for call in capability.calls if call.call_id == request.call_id),
        None,
    )
    if allowed is None:
        raise RegressionError(
            "capability.call_not_allowed",
            request.call_id,
            "the lease does not authorize this call id",
        )
    for attribute, expected, actual in (
        ("operation", allowed.operation, request.operation),
        ("contract_digest", allowed.contract_digest, request.contract_digest),
        ("arguments_digest", allowed.arguments_digest, request.arguments_digest),
        (
            "implementation_locator",
            allowed.implementation_locator,
            request.implementation_locator,
        ),
        (
            "implementation_digest",
            allowed.implementation_digest,
            request.implementation_digest,
        ),
    ):
        if actual != expected:
            raise RegressionError(
                "capability.call_mismatch",
                request.call_id,
                f"{attribute} does not match the compiled allowlist",
            )
    invocation_index = counts.count(request.call_id) + 1
    if invocation_index > allowed.max_invocations:
        raise RegressionError(
            "capability.invocation_limit",
            request.call_id,
            "the compiled invocation limit has been exhausted",
        )
    resolved = _canonical_argument_bytes(
        arguments_bytes,
        f"operationGrant.{request.call_id}.argumentsBytes",
    )
    resolved_digest = digest_bytes(resolved)
    grant_payload = {
        "runId": str(capability.run_id),
        "planDigest": str(capability.plan_digest),
        "nodeId": str(capability.node_id),
        "leaseId": str(capability.lease_id),
        "lane": capability.lane.value,
        "callId": str(request.call_id),
        "operation": str(request.operation),
        "contractDigest": str(request.contract_digest),
        "argumentsTemplateDigest": str(request.arguments_digest),
        "argumentsBytes": resolved.decode("utf-8"),
        "argumentsDigest": str(resolved_digest),
        "implementationLocator": request.implementation_locator,
        "implementationDigest": str(request.implementation_digest),
        "invocationIndex": invocation_index,
        "invalidatesTags": [str(tag) for tag in allowed.invalidates_tags],
    }
    grant_digest = str(canonical_digest(grant_payload)).removeprefix("sha256:")
    grant = OperationGrant(
        id=GrantID("grant:" + grant_digest),
        run_id=capability.run_id,
        plan_digest=capability.plan_digest,
        node_id=capability.node_id,
        lease_id=capability.lease_id,
        lane=capability.lane,
        call_id=request.call_id,
        operation=request.operation,
        contract_digest=request.contract_digest,
        arguments_template_digest=request.arguments_digest,
        arguments_bytes=resolved,
        arguments_digest=resolved_digest,
        implementation_locator=request.implementation_locator,
        implementation_digest=request.implementation_digest,
        invocation_index=invocation_index,
        invalidates_tags=allowed.invalidates_tags,
    )
    return AuthorizationDecision(grant, counts.increment(request.call_id))


__all__ = (
    "AllowedOperationCall",
    "AssignmentCapability",
    "AuthorizationDecision",
    "InvocationCount",
    "InvocationCounts",
    "OperationGrant",
    "OperationRequest",
    "authorize_operation",
)
