#!/usr/bin/env python3

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import threading
import time
from types import MappingProxyType
from typing import Any, Callable, Mapping, Optional, Tuple

from regression.core.capability import OperationGrant, OperationRequest
from regression.core.contracts import BoundLane
from regression.core.digest import canonical_bytes, canonical_digest, digest_bytes
from regression.core.errors import RegressionError
from regression.core.ids import CallID, PreparationID, SidekickID, StateKey, StateSchema
from regression.core.plan import (
    BuildIdentity,
    CompiledRunPlan,
    EvidenceEnvironmentIdentity,
    ScenarioAttemptNode,
)
from regression.core.runtime import (
    AssignmentLease,
    EmergencyOperationResult,
    EvidenceArtifact,
    EvidenceEnvelope,
    EvidenceReceipt,
    OperationResult,
    StateFingerprint,
    open_run,
)
from regression.core.runview import (
    CallPlanView,
    LeaseStatus,
    NodeStatus,
    OperationInvocationView,
    RunView,
)
from verification.regression_operation_adapter import (
    OperationContext,
    RegressionOperationAdapter,
    ResidentOperationBackend,
    SPECS,
)
from verification.regression_oracle_adapter import (
    EvidenceAttachment,
    EvidenceProvenance,
    OracleAdapterError,
    build_typed_evidence_payload,
)


DEFAULT_LEASE_DURATION_MILLIS = 4 * 60 * 60 * 1000
_TRANSITION_TRACE_ARM = "operation:transition-trace.arm@1"
_TRANSITION_TRACE_DISARM = "operation:transition-trace.disarm@1"


def _millis() -> int:
    return int(time.time() * 1000)


def _rfc3339(millis: int) -> str:
    return datetime.fromtimestamp(millis / 1000, timezone.utc).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z")


def _attachment_source(
    assignment_directory: Path,
    value: object,
    base_directory: Path,
    role: str,
) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise RegressionError(
            "sidekick.evidence_attachment_missing",
            role,
            "the evidence producer omitted a required attachment path",
        )
    unresolved = Path(value)
    candidate = unresolved if unresolved.is_absolute() else base_directory / unresolved
    if candidate.is_symlink():
        raise RegressionError(
            "sidekick.evidence_attachment_symlink",
            role,
            "evidence attachments cannot be symlinks",
        )
    root = assignment_directory.resolve()
    resolved = candidate.resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise RegressionError(
            "sidekick.evidence_attachment_outside_assignment",
            role,
            "evidence attachments must stay inside the Sidekick assignment",
        ) from error
    if not resolved.is_file():
        raise RegressionError(
            "sidekick.evidence_attachment_missing",
            role,
            "the evidence attachment is not a regular file",
        )
    return resolved


def _store_attachment(
    evidence_directory: Path,
    source: Path,
    role: str,
    media_type: str,
    suffix: str,
) -> EvidenceAttachment:
    data = source.read_bytes()
    digest = str(digest_bytes(data))
    attachment_directory = evidence_directory / "attachments"
    attachment_directory.mkdir(exist_ok=True)
    destination = attachment_directory / f"{digest[7:]}.{suffix}"
    if destination.is_symlink():
        raise RegressionError(
            "sidekick.evidence_attachment_conflict",
            role,
            "the content-addressed attachment destination is a symlink",
        )
    if destination.exists():
        if not destination.is_file() or destination.read_bytes() != data:
            raise RegressionError(
                "sidekick.evidence_attachment_conflict",
                role,
                "the content-addressed attachment contains different bytes",
            )
    else:
        try:
            with destination.open("xb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
        except FileExistsError:
            return _store_attachment(
                evidence_directory, source, role, media_type, suffix
            )
    return EvidenceAttachment(
        role=role,
        media_type=media_type,
        path=str(destination.resolve()),
        byte_length=len(data),
        digest=digest,
    )


def _materialize_attachments(
    assignment_directory: Path,
    evidence_directory: Path,
    evidence_type: str,
    operation_output: Mapping[str, Any],
) -> tuple[EvidenceAttachment, ...]:
    if evidence_type == "audio.measurement":
        source = _attachment_source(
            assignment_directory,
            operation_output.get("wavPath"),
            assignment_directory,
            "audio.capture",
        )
        return (
            _store_attachment(
                evidence_directory, source, "audio.capture", "audio/wav", "wav"
            ),
        )
    if evidence_type == "structural.test":
        source = _attachment_source(
            assignment_directory,
            operation_output.get("artifactPath"),
            assignment_directory,
            "structural.log",
        )
        return (
            _store_attachment(
                evidence_directory,
                source,
                "structural.log",
                "text/plain",
                "log",
            ),
        )
    if evidence_type != "visual.frames":
        return ()

    artifact_root_value = operation_output.get("artifactRoot")
    if not isinstance(artifact_root_value, str) or not artifact_root_value.strip():
        raise RegressionError(
            "sidekick.invalid_visual_artifact_root",
            "visual.artifact-root",
            "visual evidence must name its artifact root",
        )
    unresolved_root = Path(artifact_root_value)
    root_candidate = (
        unresolved_root
        if unresolved_root.is_absolute()
        else assignment_directory / unresolved_root
    )
    root = root_candidate.resolve()
    try:
        root.relative_to(assignment_directory.resolve())
    except ValueError as error:
        raise RegressionError(
            "sidekick.evidence_attachment_outside_assignment",
            "visual.artifact-root",
            "the visual artifact root must stay inside the Sidekick assignment",
        ) from error
    if root_candidate.is_symlink() or not root.is_dir():
        raise RegressionError(
            "sidekick.invalid_visual_artifact_root",
            "visual.artifact-root",
            "the visual artifact root must be a real directory",
        )
    frames = operation_output.get("frames")
    if not isinstance(frames, list):
        raise RegressionError(
            "sidekick.invalid_visual_frames",
            "visual.frames",
            "visual evidence must contain frame records",
        )
    attachments: list[EvidenceAttachment] = []
    for position, frame in enumerate(frames):
        record = frame.get("record") if isinstance(frame, dict) else None
        if not isinstance(record, dict):
            raise RegressionError(
                "sidekick.invalid_visual_frames",
                f"visual.frame[{position}]",
                "each visual frame must contain a controller record",
            )
        path_value = next(
            (
                record.get(field)
                for field in (
                    "localScreenshotPath",
                    "screenshotPath",
                    "screenshot",
                )
                if isinstance(record.get(field), str)
            ),
            None,
        )
        role = f"visual.frame[{position}]"
        source = _attachment_source(
            assignment_directory, path_value, root, role
        )
        attachments.append(
            _store_attachment(
                evidence_directory, source, role, "image/png", "png"
            )
        )
    return tuple(attachments)


def _request_for(call: Any) -> OperationRequest:
    return OperationRequest(
        call.call_id,
        call.operation,
        call.contract_digest,
        call.arguments_digest,
        call.implementation_locator,
        call.implementation_digest,
    )


def _build_identity_snapshot(identity: BuildIdentity) -> Tuple[Any, ...]:
    toolchain = identity.toolchain
    return (
        identity.bundle_identifier,
        identity.git_revision,
        identity.source_tree_digest,
        identity.configuration_digest,
        (
            toolchain.xcode_version,
            toolchain.xcode_build,
            toolchain.visionos_sdk_version,
            toolchain.visionos_sdk_build,
            toolchain.visionos_simulator_sdk_version,
            toolchain.visionos_simulator_sdk_build,
        ),
        tuple(
            (
                artifact.lane,
                artifact.xctestrun_digest,
                artifact.test_products_digest,
                artifact.application_code_digest,
            )
            for artifact in identity.lane_artifacts
        ),
        identity.digest,
    )


def _evidence_environment_snapshot(
    identity: EvidenceEnvironmentIdentity,
) -> Tuple[Any, ...]:
    agent = identity.agent_environment
    return (
        identity.deterministic_runtime_digest,
        None
        if agent is None
        else (
            agent.model,
            agent.prompt_digest,
            agent.configuration_digest,
        ),
        identity.digest,
    )


@dataclass(frozen=True)
class _StateProduction:
    key: StateKey
    schema: StateSchema


@dataclass(frozen=True)
class _PendingTransitionDisarm:
    generation_token: str
    call_id: CallID
    arguments_bytes: bytes


def _transition_disarm_assignments(
    calls: Tuple[CallPlanView, ...],
) -> Mapping[CallID, CallID]:
    result: dict[CallID, CallID] = {}
    claimed_disarms: set[CallID] = set()
    for index, arm in enumerate(calls):
        if str(arm.operation) != _TRANSITION_TRACE_ARM:
            continue
        expected_arguments = {
            "generationToken": f"result://{arm.call_id}/generationToken"
        }
        matches = []
        for candidate in calls[index + 1 :]:
            if str(candidate.operation) != _TRANSITION_TRACE_DISARM:
                continue
            try:
                arguments = json.loads(candidate.arguments_bytes.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise RegressionError(
                    "sidekick.transition_fault_disarm_assignment",
                    str(candidate.call_id),
                    "assigned transition disarm arguments are not canonical JSON",
                ) from error
            if arguments == expected_arguments:
                matches.append(candidate)
        if len(matches) != 1 or matches[0].call_id in claimed_disarms:
            raise RegressionError(
                "sidekick.transition_fault_disarm_assignment",
                str(arm.call_id),
                "each transition fault arm needs one later generation-bound disarm",
            )
        disarm = matches[0]
        result[arm.call_id] = disarm.call_id
        claimed_disarms.add(disarm.call_id)
    return MappingProxyType(result)


PREPARATION_TRANSCRIPT_SCHEMA = "enchron.regression.preparation-transcript@1"


def _operation_receipt(
    *,
    grant_id: object,
    call_id: object,
    operation: object,
    contract_digest: object,
    arguments_digest: object,
    implementation_digest: object,
    invocation_index: int,
    succeeded: bool,
    outputs: Mapping[str, Any],
) -> Mapping[str, Any]:
    return {
        "grantId": str(grant_id),
        "callId": str(call_id),
        "operation": str(operation),
        "contractDigest": str(contract_digest),
        "argumentsDigest": str(arguments_digest),
        "implementationDigest": str(implementation_digest),
        "invocationIndex": invocation_index,
        "succeeded": succeeded,
        "operationResult": dict(outputs),
    }


def _completed_operation_receipt(
    invocation: OperationInvocationView,
) -> Mapping[str, Any]:
    if (
        not invocation.completed
        or type(invocation.succeeded) is not bool
        or invocation.outputs is None
    ):
        raise RegressionError(
            "sidekick.incomplete_preparation_receipt",
            str(invocation.call_id),
            "a Preparation transcript can contain only completed Operation receipts",
        )
    return _operation_receipt(
        grant_id=invocation.grant_id,
        call_id=invocation.call_id,
        operation=invocation.operation,
        contract_digest=invocation.contract_digest,
        arguments_digest=invocation.arguments_digest,
        implementation_digest=invocation.implementation_digest,
        invocation_index=invocation.invocation_index,
        succeeded=invocation.succeeded,
        outputs=invocation.outputs.payload(),
    )


class ResidentGrantBridge:
    """Executes one exact core grant through the closed Resident backend."""

    def __init__(
        self,
        context: OperationContext,
        backend: Optional[Any] = None,
        state_productions: Tuple[_StateProduction, ...] = (),
        *,
        preparation_id: Optional[PreparationID] = None,
        preparation_receipts: Tuple[Mapping[str, Any], ...] = (),
    ) -> None:
        self.context = context
        self.backend = backend if backend is not None else ResidentOperationBackend()
        self.state_productions = tuple(state_productions)
        self.preparation_id = preparation_id
        self.preparation_receipts = tuple(dict(item) for item in preparation_receipts)

    def invoke(self, grant: OperationGrant, arguments: bytes) -> OperationResult:
        if not isinstance(grant, OperationGrant):
            raise RegressionError(
                "sidekick.invalid_grant", "grant", "Resident bridge needs an OperationGrant"
            )
        if type(arguments) is not bytes or arguments != grant.arguments_bytes:
            raise RegressionError(
                "sidekick.arguments_mismatch",
                str(grant.call_id),
                "Resident bridge accepts only the exact canonical grant bytes",
            )
        if digest_bytes(arguments) != grant.arguments_digest:
            raise RegressionError(
                "sidekick.arguments_digest_mismatch",
                str(grant.call_id),
                "Resident bridge argument bytes do not match the grant digest",
            )
        try:
            decoded = json.loads(arguments.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RegressionError(
                "sidekick.invalid_arguments",
                str(grant.call_id),
                "grant arguments are not a JSON object",
            ) from error
        if not isinstance(decoded, dict) or canonical_bytes(decoded) != arguments:
            raise RegressionError(
                "sidekick.noncanonical_arguments",
                str(grant.call_id),
                "grant arguments must be canonical JSON object bytes",
            )

        invocation = RegressionOperationAdapter(self.backend).invoke(
            str(grant.operation), decoded, self.context
        )
        outputs = dict(invocation.result)
        succeeded = outputs.get("succeeded")
        if type(succeeded) is not bool:
            raise RegressionError(
                "sidekick.invalid_backend_result",
                str(grant.call_id),
                "Resident backend result must contain a boolean succeeded field",
            )
        fingerprints = ()
        if succeeded and self.state_productions:
            if self.preparation_id is None:
                raise RegressionError(
                    "sidekick.missing_preparation_identity",
                    str(grant.call_id),
                    "reusable state must bind the Preparation whose transcript produced it",
                )
            current_receipt = _operation_receipt(
                grant_id=grant.id,
                call_id=grant.call_id,
                operation=grant.operation,
                contract_digest=grant.contract_digest,
                arguments_digest=grant.arguments_digest,
                implementation_digest=grant.implementation_digest,
                invocation_index=grant.invocation_index,
                succeeded=True,
                outputs=outputs,
            )
            result_digest = canonical_digest(
                {
                    "schema": PREPARATION_TRANSCRIPT_SCHEMA,
                    "preparationId": str(self.preparation_id),
                    "calls": [*self.preparation_receipts, current_receipt],
                }
            )
            fingerprints = tuple(
                StateFingerprint(item.key, item.schema, result_digest)
                for item in self.state_productions
            )
        detail = "" if succeeded else str(outputs.get("reason", "operation failed"))
        return OperationResult(succeeded, fingerprints, detail, outputs)


class _UnlockedBridge:
    def __init__(self, lock: threading.Lock, bridge: ResidentGrantBridge) -> None:
        self._lock = lock
        self._bridge = bridge

    def invoke(self, grant: OperationGrant, arguments: bytes) -> OperationResult:
        self._lock.release()
        try:
            return self._bridge.invoke(grant, arguments)
        finally:
            self._lock.acquire()


class _UnlockedEvaluator:
    def __init__(self, lock: threading.Lock, evaluator: Any) -> None:
        self._lock = lock
        self._evaluator = evaluator

    def identity_for(self, oracle_id: Any) -> Any:
        identity_for = getattr(self._evaluator, "identity_for", None)
        if not callable(identity_for):
            raise TypeError("Oracle evaluator does not expose identity_for")
        return identity_for(oracle_id)

    def evaluate(self, request: Any) -> Any:
        self._lock.release()
        try:
            evaluate = getattr(self._evaluator, "evaluate", None)
            if not callable(evaluate):
                raise TypeError("Oracle evaluator does not expose evaluate")
            return evaluate(request)
        finally:
            self._lock.acquire()


class MainAgentCoordinator:
    """Single Main writer with lane-local Sidekick execution."""

    def __init__(
        self,
        plan: CompiledRunPlan,
        run_directory: Path,
        build_identity: BuildIdentity,
        evidence_environment_identity: EvidenceEnvironmentIdentity,
        lane_targets: Mapping[BoundLane, str],
        evaluator: Any,
        *,
        backend: Optional[Any] = None,
        clock: Callable[[], int] = _millis,
        lease_duration_millis: int = DEFAULT_LEASE_DURATION_MILLIS,
    ) -> None:
        if not isinstance(plan, CompiledRunPlan):
            raise RegressionError(
                "sidekick.invalid_plan", "plan", "coordinator needs a CompiledRunPlan"
            )
        if build_identity != plan.build_identity:
            raise RegressionError(
                "sidekick.build_identity_mismatch",
                str(run_directory),
                "the supplied build identity differs from the immutable compiled plan",
            )
        if evidence_environment_identity != plan.evidence_environment_identity:
            raise RegressionError(
                "sidekick.evidence_environment_mismatch",
                str(run_directory),
                "the supplied evidence environment differs from the immutable compiled plan",
            )
        targets = dict(lane_targets)
        if set(targets) != set(plan.requested_lanes):
            raise RegressionError(
                "sidekick.lane_target_coverage",
                "laneTargets",
                "lane targets must cover the compiled run lanes exactly once",
            )
        if any(not isinstance(lane, BoundLane) for lane in targets) or any(
            not isinstance(target, str) or not target.strip() for target in targets.values()
        ):
            raise RegressionError(
                "sidekick.invalid_lane_target",
                "laneTargets",
                "every concrete lane needs one non-empty target",
            )
        if type(lease_duration_millis) is not int or lease_duration_millis < 1:
            raise RegressionError(
                "sidekick.invalid_lease_duration",
                "leaseDurationMillis",
                "lease duration must be a positive integer",
            )
        if not callable(clock):
            raise RegressionError(
                "sidekick.invalid_clock", "clock", "clock must be callable"
            )

        self.plan = plan
        self.run_directory = Path(run_directory).resolve()
        self.build_identity = build_identity
        self.evidence_environment_identity = evidence_environment_identity
        self.lane_targets = MappingProxyType(targets)
        self.evaluator = evaluator
        self.backend = backend
        self.clock = clock
        self.lease_duration_millis = lease_duration_millis
        self._pinned_build_identity = _build_identity_snapshot(build_identity)
        self._pinned_evidence_environment = _evidence_environment_snapshot(
            evidence_environment_identity
        )
        self._pinned_lane_targets = tuple(
            (lane, targets[lane])
            for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
            if lane in targets
        )
        self._writer_lock = threading.Lock()
        self._active_sidekicks: dict[SidekickID, AssignmentLease] = {}
        self._artifact_capture_times: dict[tuple[str, str], str] = {}
        self._main = open_run(plan, self.run_directory)

    @property
    def view(self) -> RunView:
        with self._writer_lock:
            self._assert_pinned_identity()
            return self._main.view

    def run_sidekick(
        self,
        lane: BoundLane,
        lane_target: str,
        sidekick_id: SidekickID,
    ) -> EvidenceReceipt:
        parsed_sidekick = SidekickID(sidekick_id)
        with self._writer_lock:
            self._assert_pinned_identity()
            if self.lane_targets.get(lane) != lane_target:
                raise RegressionError(
                    "sidekick.lane_target_mismatch",
                    lane.value if isinstance(lane, BoundLane) else str(lane),
                    "Sidekick target differs from the target pinned for this run",
                )
            if parsed_sidekick in self._active_sidekicks:
                raise RegressionError(
                    "sidekick.already_leased",
                    str(parsed_sidekick),
                    "one Sidekick may own only one Scenario lease at a time",
                )
            lease = self._main.claim(
                lane,
                parsed_sidekick,
                now_millis=self.clock(),
                lease_duration_millis=self.lease_duration_millis,
            )
            self._active_sidekicks[parsed_sidekick] = lease

        try:
            self._execute_operations(lease, lane_target)
            envelope = self._materialize_envelope(lease)
            with self._writer_lock:
                self._assert_pinned_identity()
                return self._main.accept_evidence(
                    envelope,
                    _UnlockedEvaluator(self._writer_lock, self.evaluator),
                )
        except BaseException:
            self._interrupt_if_active(lease)
            raise
        finally:
            with self._writer_lock:
                self._active_sidekicks.pop(parsed_sidekick, None)

    def finalize(self) -> RunView:
        with self._writer_lock:
            self._assert_pinned_identity()
            if self._active_sidekicks:
                raise RegressionError(
                    "sidekick.active_leases",
                    str(self.run_directory),
                    "a run cannot finalize while Sidekicks own active leases",
                )
            return self._main.finalize()

    def close(self) -> None:
        with self._writer_lock:
            if self._active_sidekicks:
                raise RegressionError(
                    "sidekick.active_leases",
                    str(self.run_directory),
                    "a coordinator cannot close while Sidekicks own active leases",
                )
            self._main.close()

    def __enter__(self) -> "MainAgentCoordinator":
        return self

    def __exit__(self, exception_type: Any, exception: Any, traceback: Any) -> None:
        self.close()

    def _execute_operations(self, lease: AssignmentLease, lane_target: str) -> None:
        context = OperationContext(
            lease.lane.value,
            lane_target,
            lease.assignment_directory.resolve(),
            (lease.assignment_directory / "controller").resolve(),
            self.build_identity.bundle_identifier,
        )
        operation_backend = (
            self.backend if self.backend is not None else ResidentOperationBackend()
        )
        pending_disarm: Optional[_PendingTransitionDisarm] = None
        primary_error: Optional[BaseException] = None
        try:
            with self._writer_lock:
                assignments = _transition_disarm_assignments(
                    self._main.view.lease(lease.id).calls
                )
            while True:
                with self._writer_lock:
                    self._assert_pinned_identity()
                    current = self._main.view.lease(lease.id)
                    if current.status is not LeaseStatus.ACTIVE:
                        raise RegressionError(
                            "sidekick.lease_interrupted",
                            str(lease.id),
                            "the affected lane interrupted before the Scenario completed",
                        )
                    call = current.current_call
                    if call is None:
                        return
                    grant = self._main.authorize_operation(
                        lease.capability,
                        _request_for(call),
                        now_millis=self.clock(),
                        defer_interruption=True,
                    )
                    productions = tuple(
                        _StateProduction(item.key, item.schema)
                        for item in call.state_productions
                    )
                    preparation_receipts: Tuple[Mapping[str, Any], ...] = ()
                    if productions:
                        if call.preparation_id is None:
                            raise RegressionError(
                                "sidekick.scenario_state_production",
                                str(call.call_id),
                                "Scenario calls cannot produce reusable Preparation state",
                            )
                        preparation_call_ids = {
                            planned.call_id
                            for planned in current.calls
                            if planned.preparation_id == call.preparation_id
                        }
                        preparation_receipts = tuple(
                            _completed_operation_receipt(invocation)
                            for invocation in current.invocations
                            if invocation.call_id in preparation_call_ids
                        )
                    bridge = ResidentGrantBridge(
                        context,
                        operation_backend,
                        productions,
                        preparation_id=call.preparation_id,
                        preparation_receipts=preparation_receipts,
                    )
                    result = self._main.invoke_operation(
                        grant,
                        grant.arguments_bytes,
                        _UnlockedBridge(self._writer_lock, bridge),
                        defer_interruption=True,
                    )
                    resolved_arguments = json.loads(grant.arguments_bytes.decode("utf-8"))
                    operation_id = str(grant.operation)
                    if result.succeeded and operation_id == _TRANSITION_TRACE_ARM:
                        generation = result.outputs.payload().get("generationToken")
                        if not isinstance(generation, str) or not generation:
                            raise RegressionError(
                                "sidekick.transition_fault_generation_missing",
                                str(grant.call_id),
                                "a successful transition fault arm must return its generation",
                            )
                        disarm_call_id = assignments[grant.call_id]
                        updated_lease = self._main.view.lease(lease.id)
                        disarm_call = next(
                            item
                            for item in updated_lease.calls
                            if item.call_id == disarm_call_id
                        )
                        pending_disarm = _PendingTransitionDisarm(
                            generation,
                            disarm_call_id,
                            canonical_bytes({"generationToken": generation}),
                        )
                    elif (
                        result.succeeded
                        and operation_id == _TRANSITION_TRACE_DISARM
                        and pending_disarm is not None
                        and grant.call_id == pending_disarm.call_id
                        and resolved_arguments.get("generationToken")
                        == pending_disarm.generation_token
                    ):
                        pending_disarm = None
                    if not result.succeeded:
                        updated_lease = self._main.view.lease(lease.id)
                        if (
                            updated_lease.invocation_count(grant.call_id)
                            >= call.max_invocations
                        ):
                            raise RegressionError(
                                "sidekick.lease_interrupted",
                                str(grant.call_id),
                                result.detail or "Operation retries were exhausted",
                            )
        except BaseException as error:
            primary_error = error
            raise
        finally:
            emergency_operation: Optional[EmergencyOperationResult] = None
            if pending_disarm is not None:
                trigger = (
                    "cancellation"
                    if isinstance(
                        primary_error,
                        (KeyboardInterrupt, SystemExit, asyncio.CancelledError),
                    )
                    else "exception"
                )
                cleanup_result: Optional[Mapping[str, Any]] = None
                cleanup_error: Optional[BaseException] = None
                try:
                    cleanup_invocation = RegressionOperationAdapter(
                        operation_backend
                    ).invoke(
                        _TRANSITION_TRACE_DISARM,
                        json.loads(pending_disarm.arguments_bytes.decode("utf-8")),
                        context,
                    )
                    cleanup_result = dict(cleanup_invocation.result)
                    if cleanup_result.get("succeeded") is not True:
                        raise RegressionError(
                            "sidekick.transition_fault_cleanup_failed",
                            pending_disarm.generation_token,
                            "the generation-bound disarm returned an unsuccessful result",
                        )
                except BaseException as error:
                    cleanup_error = error
                detail = (
                    ""
                    if cleanup_error is None
                    else f"{type(cleanup_error).__name__}: {cleanup_error}"
                )
                emergency_operation = EmergencyOperationResult(
                    pending_disarm.call_id,
                    pending_disarm.arguments_bytes,
                    OperationResult(
                        cleanup_error is None,
                        detail=detail,
                        outputs={} if cleanup_result is None else cleanup_result,
                    ),
                    trigger,
                )
                if cleanup_error is not None:
                    detail = (
                        "transition fault cleanup failed for generation "
                        f"{pending_disarm.generation_token}: {type(cleanup_error).__name__}: "
                        f"{cleanup_error}"
                    )
                    if primary_error is not None:
                        primary_error.add_note(detail)
                    else:
                        raise RegressionError(
                            "sidekick.transition_fault_cleanup_failed",
                            pending_disarm.generation_token,
                            detail,
                        ) from cleanup_error
            if primary_error is not None:
                with self._writer_lock:
                    node = self._main.view.node(lease.node_id)
                    lane = self._main.view.lane(lease.lane)
                    if node.status is NodeStatus.LEASED and not lane.interrupted:
                        self._main.interrupt_lane(
                            lease.lane,
                            "sidekick-execution-error",
                            lease.id,
                            emergency_operation,
                        )

    def _materialize_envelope(self, lease: AssignmentLease) -> EvidenceEnvelope:
        with self._writer_lock:
            self._assert_pinned_identity()
            lease_view = self._main.view.lease(lease.id)
            node = next(item for item in self.plan.nodes if item.id == lease.node_id)
            if not isinstance(node, ScenarioAttemptNode):
                raise RegressionError(
                    "sidekick.non_scenario_lease",
                    str(lease.id),
                    "only Scenario attempts may produce evidence",
                )
            invocations = tuple(lease_view.invocations)

        artifacts = tuple(
            self._materialize_artifact(lease, binding, invocations)
            for binding in node.evaluation_bindings
        )
        return EvidenceEnvelope(
            lease.capability.run_id,
            self.plan.plan_digest,
            lease.node_id,
            lease.id,
            lease.lane,
            lease.sidekick_id,
            self.build_identity.digest,
            self.evidence_environment_identity.digest,
            artifacts,
        )

    def _materialize_artifact(
        self,
        lease: AssignmentLease,
        binding: Any,
        invocations: Tuple[OperationInvocationView, ...],
    ) -> EvidenceArtifact:
        producer = next(
            (
                item
                for item in reversed(invocations)
                if item.call_id == binding.produced_by_call
                and item.completed
                and item.succeeded is True
                and item.outputs is not None
            ),
            None,
        )
        if producer is None:
            raise RegressionError(
                "sidekick.missing_evidence_producer",
                str(binding.id),
                "the obligation producer has no successful typed result",
            )
        specification = SPECS.get(str(producer.operation))
        semantic_pair = (str(binding.evidence_type), str(binding.evidence_schema))
        if specification is None or semantic_pair not in specification.outputs:
            raise RegressionError(
                "sidekick.semantic_producer_mismatch",
                str(binding.id),
                "the planned Operation does not produce the obligation's semantic evidence pair",
            )
        evidence_directory = lease.assignment_directory / "evidence"
        evidence_directory.mkdir(exist_ok=True)
        name = str(canonical_digest({"obligationId": str(binding.id)}))[7:] + ".json"
        path = evidence_directory / name
        capture_key = (str(lease.id), str(binding.id))
        captured_at = self._artifact_capture_times.setdefault(
            capture_key, _rfc3339(self.clock())
        )
        payload = self._artifact_payload(
            binding,
            producer,
            invocations,
            lease.assignment_directory,
            evidence_directory,
        )
        if path.exists():
            data = path.read_bytes()
            try:
                existing = json.loads(data.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise RegressionError(
                    "sidekick.artifact_conflict",
                    str(path),
                    "existing obligation artifact is not canonical JSON",
                ) from error
            if not isinstance(existing, dict) or canonical_bytes(existing) + b"\n" != data:
                raise RegressionError(
                    "sidekick.artifact_conflict",
                    str(path),
                    "existing obligation artifact is not canonical JSON",
                )
            if existing != payload:
                raise RegressionError(
                    "sidekick.artifact_conflict",
                    str(path),
                    "existing obligation artifact contains different typed evidence",
                )
        else:
            data = canonical_bytes(payload) + b"\n"
            try:
                with path.open("xb") as output:
                    output.write(data)
                    output.flush()
                    os.fsync(output.fileno())
            except FileExistsError:
                return self._materialize_artifact(lease, binding, invocations)
        if not data:
            raise RegressionError(
                "sidekick.empty_artifact",
                str(binding.id),
                "every obligation artifact must contain bytes",
            )
        relative_path = path.relative_to(lease.assignment_directory).as_posix()
        return EvidenceArtifact(
            binding.id,
            binding.evidence_type,
            binding.evidence_schema,
            binding.case_key,
            binding.produced_by_call,
            captured_at,
            binding.producer_contract_digest,
            relative_path,
            len(data),
            digest_bytes(data),
        )

    @staticmethod
    def _artifact_payload(
        binding: Any,
        producer: OperationInvocationView,
        invocations: Tuple[OperationInvocationView, ...],
        assignment_directory: Path,
        evidence_directory: Path,
    ) -> Mapping[str, Any]:
        assert producer.outputs is not None
        try:
            arguments = json.loads(producer.arguments_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RegressionError(
                "sidekick.invalid_evidence_arguments",
                str(binding.id),
                "the evidence producer arguments are not canonical JSON",
            ) from error
        if not isinstance(arguments, dict) or canonical_bytes(arguments) != producer.arguments_bytes:
            raise RegressionError(
                "sidekick.invalid_evidence_arguments",
                str(binding.id),
                "the evidence producer arguments must be a canonical JSON object",
            )
        output_payload = producer.outputs.payload()
        transcript: list[Mapping[str, Any]] = []
        for invocation in invocations:
            if not invocation.completed:
                continue
            if (
                type(invocation.succeeded) is not bool
                or invocation.outputs is None
                or not isinstance(invocation.detail, str)
            ):
                raise RegressionError(
                    "sidekick.incomplete_operation_transcript",
                    str(invocation.call_id),
                    "a completed transcript attempt must preserve its result and error",
                )
            try:
                invocation_arguments = json.loads(
                    invocation.arguments_bytes.decode("utf-8")
                )
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise RegressionError(
                    "sidekick.invalid_transcript_arguments",
                    str(invocation.call_id),
                    "the operation transcript arguments are not canonical JSON",
                ) from error
            if (
                not isinstance(invocation_arguments, dict)
                or canonical_bytes(invocation_arguments)
                != invocation.arguments_bytes
            ):
                raise RegressionError(
                    "sidekick.invalid_transcript_arguments",
                    str(invocation.call_id),
                    "the operation transcript arguments must be a canonical object",
                )
            transcript.append(
                {
                    "grantId": str(invocation.grant_id),
                    "callId": str(invocation.call_id),
                    "operationId": str(invocation.operation),
                    "contractDigest": str(invocation.contract_digest),
                    "arguments": invocation_arguments,
                    "argumentsDigest": str(invocation.arguments_digest),
                    "implementationLocator": invocation.implementation_locator,
                    "implementationDigest": str(
                        invocation.implementation_digest
                    ),
                    "invocationIndex": invocation.invocation_index,
                    "status": (
                        "succeeded" if invocation.succeeded else "failed"
                    ),
                    "operationResult": invocation.outputs.payload(),
                    "operationError": invocation.detail,
                }
            )
            if invocation.grant_id == producer.grant_id:
                break
        if not transcript or transcript[-1]["grantId"] != str(producer.grant_id):
            raise RegressionError(
                "sidekick.incomplete_operation_transcript",
                str(binding.id),
                "the operation transcript does not end at its successful producer attempt",
            )
        try:
            attachments = _materialize_attachments(
                assignment_directory,
                evidence_directory,
                str(binding.evidence_type),
                output_payload,
            )
            return build_typed_evidence_payload(
                str(binding.evidence_type),
                str(binding.evidence_schema),
                output_payload,
                EvidenceProvenance(
                    obligation_id=str(binding.id),
                    case_key=str(binding.case_key),
                    call_id=str(producer.call_id),
                    operation_id=str(producer.operation),
                    contract_digest=str(producer.contract_digest),
                    arguments=arguments,
                    arguments_digest=str(producer.arguments_digest),
                    implementation_locator=producer.implementation_locator,
                    implementation_digest=str(producer.implementation_digest),
                ),
                tuple(transcript),
                attachments,
            )
        except OracleAdapterError as error:
            raise RegressionError(
                "sidekick.invalid_evidence_output",
                str(binding.id),
                str(error),
            ) from error

    def _interrupt_if_active(self, lease: AssignmentLease) -> None:
        with self._writer_lock:
            try:
                node = self._main.view.node(lease.node_id)
                lane = self._main.view.lane(lease.lane)
            except RegressionError:
                return
            if node.status is NodeStatus.LEASED and not lane.interrupted:
                self._main.interrupt_lane(
                    lease.lane, "sidekick-execution-error", lease.id
                )

    def _assert_pinned_identity(self) -> None:
        if (
            _build_identity_snapshot(self.plan.build_identity)
            != self._pinned_build_identity
            or _build_identity_snapshot(self.build_identity)
            != self._pinned_build_identity
            or _evidence_environment_snapshot(
                self.plan.evidence_environment_identity
            )
            != self._pinned_evidence_environment
            or _evidence_environment_snapshot(self.evidence_environment_identity)
            != self._pinned_evidence_environment
            or tuple(
                (lane, self.lane_targets[lane])
                for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
                if lane in self.lane_targets
            )
            != self._pinned_lane_targets
        ):
            raise RegressionError(
                "sidekick.immutable_identity_changed",
                str(self.run_directory),
                "build or evidence identity changed after execution started",
            )


def open_main_agent(
    plan: CompiledRunPlan,
    run_directory: Path,
    build_identity: BuildIdentity,
    evidence_environment_identity: EvidenceEnvironmentIdentity,
    lane_targets: Mapping[BoundLane, str],
    evaluator: Any,
    **options: Any,
) -> MainAgentCoordinator:
    return MainAgentCoordinator(
        plan,
        run_directory,
        build_identity,
        evidence_environment_identity,
        lane_targets,
        evaluator,
        **options,
    )


__all__ = (
    "DEFAULT_LEASE_DURATION_MILLIS",
    "MainAgentCoordinator",
    "ResidentGrantBridge",
    "open_main_agent",
)
