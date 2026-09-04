#!/usr/bin/env python3

from __future__ import annotations

import ast
import base64
from dataclasses import replace
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import threading
from typing import Any, Mapping, Optional, Tuple
import unittest
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.capability import (
    AllowedOperationCall,
    AssignmentCapability,
    InvocationCounts,
    OperationRequest,
    authorize_operation,
)
from regression.core.contracts import (
    ArtifactClass,
    BoundLane,
    OracleKind,
    StateDeclaration,
    StateRequirement,
)
from regression.core.digest import canonical_bytes, canonical_digest, digest_bytes
from regression.core.errors import RegressionError
from regression.core.events import EventType, LedgerEvent, payload_value
from regression.core.expression import ObservationRef, OracleResult
from regression.core.ids import (
    CallID,
    CaseKey,
    Digest,
    EvidenceSchema,
    EvidenceType,
    JourneyID,
    LeaseID,
    NodeID,
    ObligationID,
    OperationID,
    OracleID,
    PreparationID,
    RubricID,
    RunID,
    ScenarioID,
    SidekickID,
    StateKey,
    StateSchema,
    StateTag,
)
from regression.core.plan import (
    AgentEnvironment,
    BuildIdentity,
    CompiledRunPlan,
    EvaluationBinding,
    EvidenceEnvironmentIdentity,
    FullSelector,
    LaneBuildArtifact,
    LaneGateDependency,
    MainGateBinding,
    OracleEvaluationBinding,
    PreparationBinding,
    PreparationRequirementBinding,
    RubricEvaluationBinding,
    ScenarioAttemptNode,
    ToolchainIdentity,
)
from regression.core.replay import LEDGER_FILENAME, replay as core_replay
from regression.core.runtime import (
    CriterionEvaluation,
    EvidenceReference,
    NegativeControlEvaluation,
    OracleEvaluation,
    OracleEvaluatorIdentity,
    TRANSITION_FAULT_INTERRUPTION_PREFIX,
    replay,
)
from regression.core.runview import NodeStatus, RunOutcome
from regression.core.scheduler import CriticalCost
from regression.sidekick_runner import (
    MainAgentCoordinator,
    PREPARATION_TRANSCRIPT_SCHEMA,
    ResidentGrantBridge,
)
from verification.regression_operation_adapter import OperationContext
from verification.regression_oracle_adapter import (
    OracleDecision,
    OracleDecisionRequest,
    RegressionOracleAdapter,
    SPECS as ORACLE_SPECS,
    implementation_identity,
)


def _digest(label: str):
    return canonical_digest({"fixture": label})


class Clock:
    def __init__(self, value: int = 1_000) -> None:
        self.value = value
        self.lock = threading.Lock()

    def __call__(self) -> int:
        with self.lock:
            self.value += 10
            return self.value


def _call(
    name: str,
    *,
    operation: str = "operation:diagnostics.playback-state@1",
    arguments: Optional[Mapping[str, Any]] = None,
    max_invocations: int = 1,
) -> AllowedOperationCall:
    encoded = canonical_bytes(dict(arguments or {}))
    return AllowedOperationCall(
        CallID(f"call:{name}"),
        OperationID(operation),
        _digest(f"operation:{name}"),
        encoded,
        digest_bytes(encoded),
        f"resident://{operation}",
        _digest(f"implementation:{operation}"),
        max_invocations,
    )


def _evidence_pair(operation: OperationID) -> tuple[EvidenceType, EvidenceSchema]:
    values = {
        OperationID("operation:diagnostics.playback-state@1"): (
            EvidenceType("playback.probe"),
            EvidenceSchema("playback-probe@1"),
        ),
        OperationID("operation:transition-trace.fetch@1"): (
            EvidenceType("transition.trace"),
            EvidenceSchema("transition-trace@1"),
        ),
        OperationID("operation:evidence.capture-frames@1"): (
            EvidenceType("visual.frames"),
            EvidenceSchema("frame-sequence@2"),
        ),
    }
    return values[operation]


def _evaluation(
    name: str,
    call: AllowedOperationCall,
    evidence_pair: Optional[tuple[EvidenceType, EvidenceSchema]] = None,
    oracle_id: Optional[str] = None,
    oracle_kind: OracleKind = OracleKind.DETERMINISTIC,
) -> EvaluationBinding:
    evidence_type, evidence_schema = evidence_pair or _evidence_pair(call.operation)
    identifier = oracle_id or f"oracle:fake.{name}@1"
    if identifier in ORACLE_SPECS:
        identity = implementation_identity(identifier)
        implementation_locator = identity.locator
        implementation_digest = Digest(identity.digest)
        oracle_kind = ORACLE_SPECS[identifier].kind
    else:
        implementation_locator = f"fake://oracle/{name}"
        implementation_digest = _digest(f"oracle-implementation:{name}")
    return EvaluationBinding(
        ObligationID(f"obligation:{name}"),
        ArtifactClass.COVERAGE,
        evidence_type,
        evidence_schema,
        CaseKey("default"),
        call.call_id,
        call.contract_digest,
        OracleEvaluationBinding(
            OracleID(identifier),
            oracle_kind,
            _digest(f"oracle-contract:{name}"),
            implementation_locator,
            implementation_digest,
            f"Oracle body {name}",
        ),
        RubricEvaluationBinding(
            RubricID(f"rubric:fake.{name}@1"),
            _digest(f"rubric:{name}"),
            (f"{name} is present",),
            (f"{name} is absent",),
            f"Rubric body {name}",
        ),
    )


def _build(lanes: Tuple[BoundLane, ...], revision: str = "abc123") -> BuildIdentity:
    return BuildIdentity(
        "dev.enchron.sidekick-tests",
        revision,
        _digest("source"),
        _digest("configuration"),
        ToolchainIdentity(
            "27.0",
            "18A5301h",
            "27.0",
            "24A5298h",
            "27.0",
            "24A5298h",
        ),
        tuple(
            LaneBuildArtifact(
                lane,
                _digest(f"xctestrun:{lane.value}"),
                _digest(f"test-products:{lane.value}"),
                _digest(f"application-code:{lane.value}"),
            )
            for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
        ),
    )


def _environment() -> EvidenceEnvironmentIdentity:
    return EvidenceEnvironmentIdentity(_digest("runtime"))


def _node(
    name: str,
    lane: BoundLane,
    *,
    calls: Optional[Tuple[AllowedOperationCall, ...]] = None,
    predecessors: Tuple[NodeID, ...] = (),
    gate: Optional[NodeID] = None,
    evidence_pair: Optional[tuple[EvidenceType, EvidenceSchema]] = None,
    oracle_id: Optional[str] = None,
    oracle_kind: OracleKind = OracleKind.DETERMINISTIC,
    preparation_requirements: Tuple[PreparationRequirementBinding, ...] = (),
) -> ScenarioAttemptNode:
    planned = calls or (_call(f"{name}-evidence"),)
    evaluation = _evaluation(
        name,
        planned[-1],
        evidence_pair,
        oracle_id,
        oracle_kind,
    )
    gates = () if gate is None else (LaneGateDependency(lane, gate),)
    return ScenarioAttemptNode(
        NodeID(f"node:{name}"),
        ScenarioID(f"scenario:{name}"),
        JourneyID("journey:sidekick-tests"),
        _digest(f"scenario:{name}"),
        (lane,),
        False,
        10,
        predecessors,
        gates,
        preparation_requirements,
        planned,
        (evaluation,),
        ObservationRef(evaluation.id),
        _build((lane,)),
        _environment(),
        100,
    )


def _plan(
    nodes: Tuple[ScenarioAttemptNode, ...],
    gate_nodes: Mapping[BoundLane, ScenarioAttemptNode],
    preparations: Tuple[PreparationBinding, ...] = (),
) -> CompiledRunPlan:
    lanes = tuple(
        lane
        for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
        if lane in gate_nodes
    )
    build = _build(lanes)
    environment = _environment()
    rebound = tuple(
        replace(
            node,
            build_identity=build,
            evidence_environment_identity=environment,
        )
        for node in nodes
    )
    rebound_by_id = {node.id: node for node in rebound}
    gates = tuple(
        MainGateBinding(lane, rebound_by_id[gate_nodes[lane].id].scenario_id, gate_nodes[lane].id)
        for lane in lanes
    )
    return CompiledRunPlan(
        _digest("catalog"),
        _digest("catalog-gate"),
        FullSelector(),
        (),
        build,
        environment,
        lanes,
        preparations,
        rebound,
        gates,
        tuple(CriticalCost(node.id, node.critical_remaining_millis) for node in rebound),
    )


def _single_plan(*, calls: Optional[Tuple[AllowedOperationCall, ...]] = None):
    gate = _node("sim-gate", BoundLane.SIMULATOR, calls=calls)
    return _plan((gate,), {BoundLane.SIMULATOR: gate})


class FakeOracle:
    def __init__(self) -> None:
        self.requests = []

    def identity_for(self, oracle_id: OracleID) -> OracleEvaluatorIdentity:
        identifier = str(oracle_id)
        prefix = "oracle:fake."
        suffix = "@1"
        if not identifier.startswith(prefix) or not identifier.endswith(suffix):
            raise AssertionError(f"unexpected fake Oracle ID {identifier}")
        name = identifier[len(prefix) : -len(suffix)]
        return OracleEvaluatorIdentity(
            oracle_id,
            f"fake://oracle/{name}",
            _digest(f"oracle-implementation:{name}"),
            None,
        )

    def evaluate(self, request):
        self.requests.append(request)
        return OracleEvaluation(
            OracleResult.SATISFIED,
            tuple(
                CriterionEvaluation(item, OracleResult.SATISFIED)
                for item in request.binding.rubric.criteria
            ),
            tuple(
                NegativeControlEvaluation(item, OracleResult.SATISFIED)
                for item in request.binding.rubric.negative_controls
            ),
            (EvidenceReference(request.artifact.receipt_digest),),
        )


class BarrierOracle(FakeOracle):
    def __init__(self, parties: int = 2) -> None:
        super().__init__()
        self.barrier = threading.Barrier(parties, timeout=3)

    def evaluate(self, request):
        self.barrier.wait()
        return super().evaluate(request)


class BarrierFailingOracle(BarrierOracle):
    def __init__(self, failing_obligation: ObligationID) -> None:
        super().__init__()
        self.failing_obligation = failing_obligation

    def evaluate(self, request):
        self.barrier.wait()
        if request.binding.id == self.failing_obligation:
            raise RuntimeError("simulated concurrent Oracle failure")
        return FakeOracle.evaluate(self, request)


class SatisfyingDecisionProvider:
    def __init__(self) -> None:
        self.agent_environment = None
        self.requests: list[OracleDecisionRequest] = []

    def decide(self, request: OracleDecisionRequest) -> OracleDecision:
        self.requests.append(request)
        return OracleDecision(
            tuple(
                CriterionEvaluation(item, OracleResult.SATISFIED)
                for item in request.criteria
            ),
            tuple(
                NegativeControlEvaluation(item, OracleResult.SATISFIED)
                for item in request.negative_controls
            ),
        )


class FakeBackend:
    def __init__(self, succeeded: Optional[list[bool]] = None) -> None:
        self.succeeded = list(succeeded or [])
        self.calls: list[tuple[str, dict[str, Any], OperationContext]] = []
        self.lock = threading.Lock()

    def execute(self, operation_id, arguments, context):
        with self.lock:
            self.calls.append((operation_id, dict(arguments), context))
            succeeded = self.succeeded.pop(0) if self.succeeded else True
        result = {"succeeded": succeeded, "observed": context.target}
        if operation_id == "operation:transition-trace.arm@1":
            result["generationToken"] = "7"
        elif operation_id == "operation:transition-trace.fetch@1":
            result.update(
                {
                    "response": {"success": True},
                    "snapshot": {
                        "generation": str(arguments["generationToken"]),
                        "records": [{"sequence": 1}],
                    },
                    "analysis": {"switchCount": 1},
                }
            )
        elif operation_id == "operation:diagnostics.playback-state@1":
            result.update(
                {
                    "fields": {
                        "presentation": "window",
                        "lifecycle": "playing",
                    },
                    "session": "session-test",
                    "audioTrack": "1",
                    "mediaName": "fixture.mkv",
                    "response": {"success": True, "hierarchy": "Window"},
                }
            )
        elif operation_id == "operation:evidence.capture-frames@1":
            context.controller_directory.mkdir(exist_ok=True)
            frame_path = context.controller_directory / "frame-0.png"
            frame_path.write_bytes(
                base64.b64decode(
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
                )
            )
            result.update(
                {
                    "context": arguments["context"],
                    "artifactRoot": "controller",
                    "frames": [
                        {
                            "index": 0,
                            "capturedAtMonotonicMillis": 10,
                            "record": {
                                "success": True,
                                "localScreenshotPath": str(frame_path.resolve()),
                            },
                        }
                    ],
                    "remoteObservation": {"generation": 7, "requests": 3},
                    "artworkObservation": {"storedDigest": _digest("artwork")},
                }
            )
        return result


class BarrierBackend(FakeBackend):
    def __init__(self, parties: int = 2) -> None:
        super().__init__()
        self.barrier = threading.Barrier(parties, timeout=3)

    def execute(self, operation_id, arguments, context):
        self.barrier.wait()
        return super().execute(operation_id, arguments, context)


class BlockingBackend(FakeBackend):
    def __init__(self) -> None:
        super().__init__()
        self.entered = threading.Event()
        self.release = threading.Event()

    def execute(self, operation_id, arguments, context):
        self.entered.set()
        if not self.release.wait(3):
            raise RuntimeError("test release timed out")
        return super().execute(operation_id, arguments, context)


class TransitionLifecycleBackend:
    def __init__(
        self,
        *,
        probe_failure: BaseException | None = None,
        cleanup_failure: BaseException | None = None,
    ) -> None:
        self.probe_failure = probe_failure
        self.cleanup_failure = cleanup_failure
        self.calls: list[tuple[str, dict[str, Any], OperationContext]] = []

    def execute(self, operation_id, arguments, context):
        self.calls.append((operation_id, dict(arguments), context))
        if operation_id == "operation:transition-trace.arm@1":
            return {
                "succeeded": True,
                "generationToken": "7",
                "fault": arguments.get("fault", "none"),
            }
        if operation_id == "operation:transition-trace.disarm@1":
            if self.cleanup_failure is not None:
                raise self.cleanup_failure
            return {
                "succeeded": True,
                "generationToken": str(arguments["generationToken"]),
                "disarmed": True,
                "postActionState": {"generation": 7, "isArmed": False},
            }
        if operation_id == "operation:diagnostics.playback-state@1":
            if self.probe_failure is not None:
                raise self.probe_failure
            return {
                "succeeded": True,
                "session": "session-test",
                "audioTrack": "1",
                "mediaName": "fixture.mkv",
                "fields": {"lifecycle": "playing"},
                "response": {"success": True},
            }
        raise AssertionError(f"unexpected operation {operation_id}")


def _coordinator(directory: Path, plan, backend, oracle=None):
    targets = {
        lane: f"target-{lane.value}"
        for lane in plan.requested_lanes
    }
    return MainAgentCoordinator(
        plan,
        directory,
        plan.build_identity,
        plan.evidence_environment_identity,
        targets,
        oracle or FakeOracle(),
        backend=backend,
        clock=Clock(),
    )


class GrantBridgeTests(unittest.TestCase):
    def test_bridge_enforces_exact_grant_and_canonical_bytes(self) -> None:
        call = _call(
            "exact",
            arguments={
                "context": "window",
                "identifier": "PlayerUI-window-control-plane",
            },
            operation="operation:accessibility.inspect@2",
        )
        capability = AssignmentCapability(
            RunID("run:test"),
            _digest("plan"),
            NodeID("node:test"),
            LeaseID("lease:test"),
            BoundLane.SIMULATOR,
            (call,),
            10_000,
        )
        request = OperationRequest(
            call.call_id,
            call.operation,
            call.contract_digest,
            call.arguments_digest,
            call.implementation_locator,
            call.implementation_digest,
        )
        grant = authorize_operation(
            capability, request, InvocationCounts(), 1_000, call.arguments_bytes
        ).grant
        backend = FakeBackend()
        with TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            bridge = ResidentGrantBridge(
                OperationContext("simulator", "target", root, root / "controller"),
                backend,
            )
            with self.assertRaisesRegex(RegressionError, "sidekick.arguments_mismatch"):
                bridge.invoke(grant, b"{}")
            result = bridge.invoke(grant, grant.arguments_bytes)

        self.assertTrue(result.succeeded)
        self.assertEqual(
            {
                "context": "window",
                "identifier": "PlayerUI-window-control-plane",
            },
            backend.calls[0][1],
        )

    def test_result_references_arrive_only_as_core_resolved_grant_bytes(self) -> None:
        arm = _call("ref-arm", operation="operation:transition-trace.arm@1")
        fetch = _call(
            "ref-fetch",
            operation="operation:transition-trace.fetch@1",
            arguments={"generationToken": "result://call:ref-arm/generationToken"},
        )
        disarm = _call(
            "ref-disarm",
            operation="operation:transition-trace.disarm@1",
            arguments={"generationToken": "result://call:ref-arm/generationToken"},
        )
        plan = _single_plan(calls=(arm, fetch, disarm, _call("ref-producer")))
        backend = FakeBackend()
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, backend)
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:resolved"),
            )
            coordinator.close()

        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        self.assertEqual("7", backend.calls[1][1]["generationToken"])
        self.assertNotIn("result://", json.dumps(backend.calls[1][1]))


class CoordinatorTests(unittest.TestCase):
    def test_prepared_state_fingerprint_binds_the_complete_ordered_transcript(self) -> None:
        requirement = StateRequirement(
            StateKey("fixture-set-test-ready"),
            StateSchema("fixture-set.test@1"),
        )
        first = _call(
            "prepare-transcript-first",
            operation="operation:harness.assert-channels@2",
        )
        final = _call(
            "prepare-transcript-final",
            operation="operation:harness.reset-product-state@2",
        )
        preparation_id = PreparationID("preparation:test-fixtures")
        preparation = PreparationBinding(
            preparation_id,
            BoundLane.SIMULATOR,
            _digest("preparation:test-fixtures"),
            20,
            (),
            (first, final),
            (
                StateDeclaration(
                    requirement.key,
                    requirement.schema,
                    final.call_id,
                    (StateTag("library.contents"),),
                ),
            ),
        )
        gate = _node(
            "prepared-transcript",
            BoundLane.SIMULATOR,
            preparation_requirements=(
                PreparationRequirementBinding(
                    BoundLane.SIMULATOR,
                    requirement,
                    preparation_id,
                ),
            ),
        )
        plan = _plan(
            (gate,),
            {BoundLane.SIMULATOR: gate},
            (preparation,),
        )

        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, FakeBackend())
            coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:preparation-transcript"),
            )
            view = coordinator.view
            coordinator.close()

        prepared = view.valid_state_handle(
            requirement.key,
            requirement.schema,
            BoundLane.SIMULATOR,
            preparation_id,
        )
        self.assertIsNotNone(prepared)
        assert prepared is not None
        invocations = view.leases[0].invocations[:2]
        transcript = []
        for invocation in invocations:
            assert invocation.outputs is not None
            transcript.append(
                {
                    "grantId": str(invocation.grant_id),
                    "callId": str(invocation.call_id),
                    "operation": str(invocation.operation),
                    "contractDigest": str(invocation.contract_digest),
                    "argumentsDigest": str(invocation.arguments_digest),
                    "implementationDigest": str(invocation.implementation_digest),
                    "invocationIndex": invocation.invocation_index,
                    "succeeded": invocation.succeeded,
                    "operationResult": invocation.outputs.payload(),
                }
            )
        expected = canonical_digest(
            {
                "schema": PREPARATION_TRANSCRIPT_SCHEMA,
                "preparationId": str(preparation_id),
                "calls": transcript,
            }
        )
        legacy_final_only = canonical_digest(
            {
                "grantId": str(invocations[-1].grant_id),
                "operationResult": invocations[-1].outputs.payload(),
            }
        )
        self.assertEqual(expected, prepared.handle.fingerprint)
        self.assertNotEqual(legacy_final_only, prepared.handle.fingerprint)

    def test_one_sidekick_can_hold_only_one_scenario_lease(self) -> None:
        simulator = _node("sim-gate", BoundLane.SIMULATOR)
        device = _node("device-gate", BoundLane.DEVICE)
        plan = _plan(
            (simulator, device),
            {BoundLane.SIMULATOR: simulator, BoundLane.DEVICE: device},
        )
        backend = BlockingBackend()
        failures = []
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, backend)

            def run_first():
                try:
                    coordinator.run_sidekick(
                        BoundLane.SIMULATOR,
                        "target-simulator",
                        SidekickID("sidekick:one"),
                    )
                except BaseException as error:
                    failures.append(error)

            worker = threading.Thread(target=run_first)
            worker.start()
            self.assertTrue(backend.entered.wait(2))
            with self.assertRaisesRegex(RegressionError, "sidekick.already_leased"):
                coordinator.run_sidekick(
                    BoundLane.DEVICE,
                    "target-device",
                    SidekickID("sidekick:one"),
                )
            backend.release.set()
            worker.join(3)
            coordinator.close()

        self.assertFalse(worker.is_alive())
        self.assertEqual([], failures)

    def test_two_lane_workers_overlap_backend_work_and_serialize_main_ledger(self) -> None:
        simulator = _node("sim-gate", BoundLane.SIMULATOR)
        device = _node("device-gate", BoundLane.DEVICE)
        plan = _plan(
            (simulator, device),
            {BoundLane.SIMULATOR: simulator, BoundLane.DEVICE: device},
        )
        backend = BarrierBackend()
        failures = []
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, backend)

            def run(lane, target, sidekick):
                try:
                    coordinator.run_sidekick(lane, target, SidekickID(sidekick))
                except BaseException as error:
                    failures.append(error)

            workers = [
                threading.Thread(target=run, args=(BoundLane.SIMULATOR, "target-simulator", "sidekick:sim")),
                threading.Thread(target=run, args=(BoundLane.DEVICE, "target-device", "sidekick:device")),
            ]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(5)
            view = coordinator.view
            coordinator.close()
            restored = replay(directory)
            lines = (directory / LEDGER_FILENAME).read_text().splitlines()

        self.assertEqual([], failures)
        self.assertTrue(all(not worker.is_alive() for worker in workers))
        self.assertEqual(2, len(backend.calls))
        self.assertEqual(view, restored)
        self.assertEqual(list(range(1, len(lines) + 1)), [json.loads(line)["sequence"] for line in lines])
        self.assertTrue(all(node.status is NodeStatus.PASSED for node in view.nodes))

    def test_two_lane_oracles_overlap_and_serialize_main_ledger(self) -> None:
        simulator = _node("sim-gate", BoundLane.SIMULATOR)
        device = _node("device-gate", BoundLane.DEVICE)
        plan = _plan(
            (simulator, device),
            {BoundLane.SIMULATOR: simulator, BoundLane.DEVICE: device},
        )
        oracle = BarrierOracle()
        failures = []
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, FakeBackend(), oracle)

            def run(lane, target, sidekick):
                try:
                    coordinator.run_sidekick(lane, target, SidekickID(sidekick))
                except BaseException as error:
                    failures.append(error)

            workers = [
                threading.Thread(
                    target=run,
                    args=(
                        BoundLane.SIMULATOR,
                        "target-simulator",
                        "sidekick:sim-oracle",
                    ),
                ),
                threading.Thread(
                    target=run,
                    args=(
                        BoundLane.DEVICE,
                        "target-device",
                        "sidekick:device-oracle",
                    ),
                ),
            ]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(5)
            view = coordinator.view
            coordinator.close()
            restored = replay(directory)
            lines = (directory / LEDGER_FILENAME).read_text().splitlines()

        self.assertEqual([], failures)
        self.assertTrue(all(not worker.is_alive() for worker in workers))
        self.assertEqual(2, len(oracle.requests))
        self.assertEqual(view, restored)
        self.assertEqual(
            list(range(1, len(lines) + 1)),
            [json.loads(line)["sequence"] for line in lines],
        )
        self.assertTrue(all(node.status is NodeStatus.PASSED for node in view.nodes))

    def test_unlocked_oracle_failure_does_not_deadlock_the_successful_lane(self) -> None:
        simulator = _node("sim-gate", BoundLane.SIMULATOR)
        device = _node("device-gate", BoundLane.DEVICE)
        plan = _plan(
            (simulator, device),
            {BoundLane.SIMULATOR: simulator, BoundLane.DEVICE: device},
        )
        oracle = BarrierFailingOracle(ObligationID("obligation:sim-gate"))
        failures = []
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, FakeBackend(), oracle)

            def run(lane, target, sidekick):
                try:
                    coordinator.run_sidekick(lane, target, SidekickID(sidekick))
                except BaseException as error:
                    failures.append(error)

            workers = [
                threading.Thread(
                    target=run,
                    args=(
                        BoundLane.SIMULATOR,
                        "target-simulator",
                        "sidekick:sim-oracle-failure",
                    ),
                ),
                threading.Thread(
                    target=run,
                    args=(
                        BoundLane.DEVICE,
                        "target-device",
                        "sidekick:device-oracle-success",
                    ),
                ),
            ]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(5)
            view = coordinator.view
            coordinator.close()
            restored = replay(directory)

        self.assertTrue(all(not worker.is_alive() for worker in workers))
        self.assertEqual(1, len(failures))
        self.assertIn("simulated concurrent Oracle failure", str(failures[0]))
        self.assertEqual(NodeStatus.INTERRUPTED, view.node(simulator.id).status)
        self.assertEqual(NodeStatus.PASSED, view.node(device.id).status)
        self.assertEqual(view, restored)

    def test_main_gate_unlock_is_lane_local(self) -> None:
        sim_gate = _node("sim-gate", BoundLane.SIMULATOR)
        device_gate = _node("device-gate", BoundLane.DEVICE)
        sim_child = _node(
            "sim-child",
            BoundLane.SIMULATOR,
            predecessors=(sim_gate.id,),
            gate=sim_gate.id,
        )
        device_child = _node(
            "device-child",
            BoundLane.DEVICE,
            predecessors=(device_gate.id,),
            gate=device_gate.id,
        )
        plan = _plan(
            (sim_gate, device_gate, sim_child, device_child),
            {BoundLane.SIMULATOR: sim_gate, BoundLane.DEVICE: device_gate},
        )
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, FakeBackend())
            coordinator.run_sidekick(
                BoundLane.SIMULATOR, "target-simulator", SidekickID("sidekick:gate")
            )
            coordinator.run_sidekick(
                BoundLane.SIMULATOR, "target-simulator", SidekickID("sidekick:child")
            )
            view = coordinator.view
            coordinator.close()

        self.assertEqual(NodeStatus.PASSED, view.node(sim_gate.id).status)
        self.assertEqual(NodeStatus.PASSED, view.node(sim_child.id).status)
        self.assertEqual(NodeStatus.PENDING, view.node(device_gate.id).status)
        self.assertEqual(NodeStatus.PENDING, view.node(device_child.id).status)

    def test_immutable_identity_and_lane_target_changes_are_rejected(self) -> None:
        plan = _single_plan()
        changed = _build(plan.requested_lanes, revision="different")
        with TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(RegressionError, "sidekick.build_identity_mismatch"):
                MainAgentCoordinator(
                    plan,
                    Path(temporary),
                    changed,
                    plan.evidence_environment_identity,
                    {BoundLane.SIMULATOR: "target-simulator"},
                    FakeOracle(),
                    backend=FakeBackend(),
                )
            coordinator = _coordinator(Path(temporary), plan, FakeBackend())
            with self.assertRaisesRegex(RegressionError, "sidekick.lane_target_mismatch"):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "different-target",
                    SidekickID("sidekick:identity"),
                )
            coordinator.build_identity = changed
            with self.assertRaisesRegex(
                RegressionError, "sidekick.immutable_identity_changed"
            ):
                _ = coordinator.view
            coordinator.close()

    def test_artifact_provenance_oracle_submission_and_idempotent_materialization(self) -> None:
        plan = _single_plan()
        oracle = FakeOracle()
        envelopes = []
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, FakeBackend(), oracle)
            original = coordinator._materialize_envelope

            def materialize_twice(lease):
                first = original(lease)
                second = original(lease)
                self.assertEqual(first, second)
                envelopes.append(second)
                return second

            with mock.patch.object(
                coordinator,
                "_materialize_envelope",
                side_effect=materialize_twice,
            ):
                receipt = coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:artifact"),
                )
            with coordinator._writer_lock:
                replayed_receipt = coordinator._main.accept_evidence(
                    envelopes[0], oracle
                )
            lease = coordinator.view.leases[0]
            staged = directory / "assignments" / str(lease.lease_id) / lease.evidence[0].relative_path
            payload = json.loads(staged.read_text())
            staged_size = staged.stat().st_size
            coordinator.close()

        binding = next(node for node in plan.nodes if isinstance(node, ScenarioAttemptNode)).evaluation_bindings[0]
        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        self.assertEqual(receipt, replayed_receipt)
        self.assertGreater(staged_size, 0)
        self.assertEqual("enchron.regression.oracle-evidence", payload["schema"])
        self.assertEqual("playback.probe", payload["evidenceType"])
        self.assertEqual("playback-probe@1", payload["evidenceSchema"])
        self.assertEqual(str(binding.id), payload["obligationId"])
        self.assertEqual(str(binding.case_key), payload["caseKey"])
        self.assertEqual(str(binding.produced_by_call), payload["producer"]["callId"])
        self.assertEqual(
            "operation:diagnostics.playback-state@1",
            payload["producer"]["operationId"],
        )
        self.assertEqual({}, payload["producer"]["arguments"])
        self.assertEqual("playing", payload["snapshots"][0]["fields"]["lifecycle"])
        self.assertEqual(payload["snapshots"][0], payload["operationOutput"])
        self.assertNotIn("operationResult", payload)
        self.assertNotIn("assertions", payload)
        self.assertEqual(1, len(oracle.requests))
        self.assertEqual(envelopes[0].digest, receipt.envelope_digest)

    def test_agent_decision_provider_environment_mismatch_is_rejected(self) -> None:
        gate = _node(
            "provider-environment-mismatch",
            BoundLane.SIMULATOR,
            oracle_id="oracle:agent-structured-playback-probe@1",
        )
        plan = _plan((gate,), {BoundLane.SIMULATOR: gate})
        provider = SatisfyingDecisionProvider()
        provider.agent_environment = AgentEnvironment(
            "wrong-agent",
            _digest("wrong-agent-prompt"),
            _digest("wrong-agent-configuration"),
        )
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(
                Path(temporary),
                plan,
                FakeBackend(),
                RegressionOracleAdapter(provider),
            )
            with self.assertRaises(RegressionError) as raised:
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:wrong-provider-environment"),
                )
            view = coordinator.view
            coordinator.close()

        self.assertEqual(
            "runtime.oracle_agent_environment_mismatch",
            raised.exception.code,
        )
        self.assertEqual([], provider.requests)
        self.assertEqual(NodeStatus.INTERRUPTED, view.node(gate.id).status)

    def test_typed_artifact_preserves_the_ordered_operation_transcript_through_its_producer(self) -> None:
        navigation = _call(
            "transcript-navigation",
            operation="operation:navigation.select-tab@1",
            arguments={"tab": "files"},
        )
        producer = _call("transcript-producer")
        gate = _node(
            "typed-operation-transcript",
            BoundLane.SIMULATOR,
            calls=(navigation, producer),
            oracle_id="oracle:agent-structured-playback-probe@1",
        )
        plan = _plan((gate,), {BoundLane.SIMULATOR: gate})
        provider = SatisfyingDecisionProvider()
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(
                Path(temporary),
                plan,
                FakeBackend(),
                RegressionOracleAdapter(provider),
            )
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:operation-transcript"),
            )
            payload = json.loads(
                provider.requests[0].artifact_path.read_text(encoding="utf-8")
            )
            coordinator.close()

        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        transcript = payload["operationTranscript"]
        self.assertEqual(
            [str(navigation.call_id), str(producer.call_id)],
            [entry["callId"] for entry in transcript],
        )
        self.assertEqual([1, 1], [entry["invocationIndex"] for entry in transcript])
        self.assertEqual(
            ["succeeded", "succeeded"],
            [entry["status"] for entry in transcript],
        )
        self.assertEqual({"tab": "files"}, transcript[0]["arguments"])
        self.assertEqual("target-simulator", transcript[0]["operationResult"]["observed"])
        self.assertEqual(payload["producer"], {
            field: transcript[-1][field]
            for field in (
                "callId",
                "operationId",
                "contractDigest",
                "arguments",
                "argumentsDigest",
                "implementationLocator",
                "implementationDigest",
            )
        })
        self.assertEqual(payload["operationOutput"], transcript[-1]["operationResult"])

    def test_typed_artifact_preserves_failed_retry_before_successful_producer(self) -> None:
        producer = _call("retrying-producer", max_invocations=2)
        gate = _node(
            "typed-retry-transcript",
            BoundLane.SIMULATOR,
            calls=(producer,),
            oracle_id="oracle:agent-structured-playback-probe@1",
        )
        plan = _plan((gate,), {BoundLane.SIMULATOR: gate})
        provider = SatisfyingDecisionProvider()
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(
                Path(temporary),
                plan,
                FakeBackend([False, True]),
                RegressionOracleAdapter(provider),
            )
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:operation-retry-transcript"),
            )
            payload = json.loads(
                provider.requests[0].artifact_path.read_text(encoding="utf-8")
            )
            coordinator.close()

        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        transcript = payload["operationTranscript"]
        self.assertEqual([str(producer.call_id)] * 2, [item["callId"] for item in transcript])
        self.assertEqual(2, len({item["grantId"] for item in transcript}))
        self.assertEqual([1, 2], [item["invocationIndex"] for item in transcript])
        self.assertEqual(["failed", "succeeded"], [item["status"] for item in transcript])
        self.assertEqual(
            [False, True],
            [item["operationResult"]["succeeded"] for item in transcript],
        )
        self.assertEqual("operation failed", transcript[0]["operationError"])
        self.assertEqual("", transcript[1]["operationError"])
        self.assertEqual(payload["operationOutput"], transcript[-1]["operationResult"])

    def test_real_structured_agent_oracle_accepts_the_materialized_typed_artifact(self) -> None:
        gate = _node(
            "typed-deterministic",
            BoundLane.SIMULATOR,
            oracle_id="oracle:agent-structured-playback-probe@1",
        )
        plan = _plan((gate,), {BoundLane.SIMULATOR: gate})
        provider = SatisfyingDecisionProvider()
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(
                Path(temporary),
                plan,
                FakeBackend(),
                RegressionOracleAdapter(provider),
            )
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:typed-deterministic"),
            )
            view = coordinator.view
            accepted_payload = json.loads(
                provider.requests[0].artifact_path.read_text(encoding="utf-8")
            )
            coordinator.close()

        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        self.assertEqual(NodeStatus.PASSED, view.node(gate.id).status)
        self.assertIs(provider.requests[0].oracle_kind, OracleKind.AGENT)
        self.assertEqual(
            provider.requests[0].artifact_payload,
            accepted_payload,
        )
        self.assertEqual(
            "playing", accepted_payload["snapshots"][0]["fields"]["lifecycle"]
        )
        self.assertNotIn("operationResult", accepted_payload)

    def test_real_agent_oracle_accepts_captured_frames(self) -> None:
        capture = _call(
            "typed-agent-frames",
            operation="operation:evidence.capture-frames@1",
            arguments={
                "count": 1,
                "minimumIntervalMillis": 0,
                "context": "window",
            },
        )
        gate = _node(
            "typed-agent",
            BoundLane.SIMULATOR,
            calls=(capture,),
            oracle_id="oracle:agent-visual@2",
            oracle_kind=OracleKind.AGENT,
        )
        plan = _plan((gate,), {BoundLane.SIMULATOR: gate})
        provider = SatisfyingDecisionProvider()
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(
                Path(temporary),
                plan,
                FakeBackend(),
                RegressionOracleAdapter(provider),
            )
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:typed-agent"),
            )
            accepted_payload = json.loads(
                provider.requests[0].artifact_path.read_text(encoding="utf-8")
            )
            coordinator.close()

        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        self.assertIs(provider.requests[0].oracle_kind, OracleKind.AGENT)
        self.assertTrue(
            accepted_payload["frames"][0]["record"]["localScreenshotPath"].endswith(
                "/controller/frame-0.png"
            )
        )
        self.assertEqual(1, len(accepted_payload["attachments"]))
        attachment = accepted_payload["attachments"][0]
        self.assertEqual("visual.frame[0]", attachment["role"])
        self.assertEqual("image/png", attachment["mediaType"])
        self.assertIn("/evidence/attachments/", attachment["path"])
        self.assertEqual(
            {"generation": 7, "requests": 3},
            accepted_payload["operationOutput"]["remoteObservation"],
        )
        self.assertIn("artworkObservation", accepted_payload["operationOutput"])
        self.assertEqual("default", accepted_payload["caseKey"])
        self.assertEqual(
            {
                "context": "window",
                "count": 1,
                "minimumIntervalMillis": 0,
            },
            accepted_payload["producer"]["arguments"],
        )

    def test_missing_provider_keeps_a_real_deterministic_route_non_passing(self) -> None:
        gate = _node(
            "typed-no-provider",
            BoundLane.SIMULATOR,
            oracle_id="oracle:agent-structured-playback-probe@1",
        )
        plan = _plan((gate,), {BoundLane.SIMULATOR: gate})
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(
                Path(temporary),
                plan,
                FakeBackend(),
                RegressionOracleAdapter(),
            )
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:no-provider"),
            )
            view = coordinator.view
            coordinator.close()

        self.assertEqual(NodeStatus.INTERRUPTED, receipt.node_status)
        self.assertEqual(NodeStatus.INTERRUPTED, view.node(gate.id).status)
        self.assertIs(
            view.leases[0].oracle_evaluations[0].overall,
            OracleResult.INDETERMINATE,
        )

    def test_operation_failure_interrupts_only_its_lane(self) -> None:
        simulator = _node("sim-gate", BoundLane.SIMULATOR)
        device = _node("device-gate", BoundLane.DEVICE)
        plan = _plan(
            (simulator, device),
            {BoundLane.SIMULATOR: simulator, BoundLane.DEVICE: device},
        )
        backend = FakeBackend([False, True])
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, backend)
            with self.assertRaisesRegex(
                RegressionError, "sidekick.lease_interrupted"
            ):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:failed"),
                )
            device_receipt = coordinator.run_sidekick(
                BoundLane.DEVICE,
                "target-device",
                SidekickID("sidekick:healthy"),
            )
            view = coordinator.view
            coordinator.close()

        self.assertEqual(NodeStatus.INTERRUPTED, view.node(simulator.id).status)
        self.assertEqual(NodeStatus.PASSED, view.node(device.id).status)
        self.assertEqual(NodeStatus.PASSED, device_receipt.node_status)

    def test_action_receipt_cannot_impersonate_semantic_evidence(self) -> None:
        action = _call("action-only", operation="operation:app.relaunch@1")
        gate = _node(
            "sim-gate",
            BoundLane.SIMULATOR,
            calls=(action,),
            evidence_pair=(
                EvidenceType("window.control-plane"),
                EvidenceSchema("window-control-plane@1"),
            ),
        )
        plan = _plan((gate,), {BoundLane.SIMULATOR: gate})
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, FakeBackend())
            with self.assertRaisesRegex(
                RegressionError, "sidekick.semantic_producer_mismatch"
            ):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:semantic"),
                )
            view = coordinator.view
            coordinator.close()

        self.assertEqual(NodeStatus.INTERRUPTED, view.node(gate.id).status)

    def test_failed_operation_retries_within_compiled_limit(self) -> None:
        retry_call = _call("retry", max_invocations=2)
        plan = _single_plan(calls=(retry_call,))
        backend = FakeBackend([False, True])
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, backend)
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:retry"),
            )
            final = coordinator.finalize()

        self.assertEqual(2, len(backend.calls))
        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        self.assertEqual(RunOutcome.PASSED, final.outcome)

    def test_runner_contains_no_build_command_or_catalog_lookup(self) -> None:
        source_path = SCRIPTS / "regression/sidekick_runner.py"
        source = source_path.read_text()
        tree = ast.parse(source)
        imports = {
            alias.name
            for node in ast.walk(tree)
            if isinstance(node, ast.Import)
            for alias in node.names
        }
        self.assertNotIn("subprocess", imports)
        self.assertNotIn("xcodebuild", source)
        self.assertNotIn("build-for-testing", source)
        self.assertNotIn("catalog-v2", source)
        self.assertNotIn("Config/regression", source)


class TransitionFaultCleanupTests(unittest.TestCase):
    @staticmethod
    def calls(*, explicit_disarm: bool) -> Tuple[AllowedOperationCall, ...]:
        arm = _call(
            "fault-arm",
            operation="operation:transition-trace.arm@1",
            arguments={"fault": "settlement-timeout"},
        )
        producer = _call("fault-producer")
        if not explicit_disarm:
            return (arm, producer)
        disarm = _call(
            "fault-disarm",
            operation="operation:transition-trace.disarm@1",
            arguments={
                "generationToken": "result://call:fault-arm/generationToken"
            },
        )
        return (arm, disarm, producer)

    @staticmethod
    def interrupted_calls() -> Tuple[AllowedOperationCall, ...]:
        arm, disarm, _ = TransitionFaultCleanupTests.calls(explicit_disarm=True)
        return (
            arm,
            _call("fault-probe-before-disarm"),
            disarm,
            _call("fault-evidence"),
        )

    @staticmethod
    def interruption_document(directory: Path) -> Mapping[str, Any]:
        restored = replay(directory)
        reason = restored.lane(BoundLane.SIMULATOR).interruption_reason
        if reason is None or not reason.startswith(
            TRANSITION_FAULT_INTERRUPTION_PREFIX
        ):
            raise AssertionError(f"expected emergency Operation record, found {reason!r}")
        return json.loads(reason[len(TRANSITION_FAULT_INTERRUPTION_PREFIX) :])

    def test_unassigned_disarm_is_rejected_before_arm_execution(self) -> None:
        plan = _single_plan(calls=self.calls(explicit_disarm=False))
        backend = TransitionLifecycleBackend()
        with TemporaryDirectory() as temporary:
            coordinator = _coordinator(Path(temporary), plan, backend)
            with self.assertRaisesRegex(
                RegressionError, "one later generation-bound disarm"
            ):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:fault-unassigned"),
                )
            coordinator.close()
        self.assertEqual([], backend.calls)

    def test_operation_exception_records_assigned_disarm_result_in_ledger(self) -> None:
        plan = _single_plan(calls=self.interrupted_calls())
        backend = TransitionLifecycleBackend(
            probe_failure=RuntimeError("original operation failure")
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, backend)
            with self.assertRaisesRegex(
                RegressionError, "original operation failure"
            ):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:fault-error"),
                )
            coordinator.close()
            restored = replay(directory)
            cleanup = self.interruption_document(directory)

        self.assertEqual(backend.calls[-1][0], "operation:transition-trace.disarm@1")
        lease = restored.leases[0]
        assigned = next(
            call
            for call in lease.calls
            if str(call.operation) == "operation:transition-trace.disarm@1"
        )
        emergency = cleanup["emergencyOperation"]
        self.assertEqual(cleanup["affectedLeaseId"], str(lease.lease_id))
        self.assertEqual(emergency["callId"], str(assigned.call_id))
        self.assertEqual(emergency["operation"], str(assigned.operation))
        self.assertEqual(
            emergency["contractDigest"], str(assigned.contract_digest)
        )
        self.assertEqual(
            emergency["implementationLocator"], assigned.implementation_locator
        )
        self.assertEqual(
            emergency["implementationDigest"], str(assigned.implementation_digest)
        )
        self.assertTrue(emergency["result"]["succeeded"])
        self.assertFalse(
            list((directory / "assignments").glob("*/transition-fault-cleanup.json"))
        )

    def test_cancellation_disarms_fault_without_converting_the_cancellation(self) -> None:
        plan = _single_plan(calls=self.interrupted_calls())
        backend = TransitionLifecycleBackend(
            probe_failure=KeyboardInterrupt("cancelled")
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, backend)
            with self.assertRaisesRegex(KeyboardInterrupt, "cancelled"):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:fault-cancel"),
                )
            coordinator.close()
            cleanup = self.interruption_document(directory)

        self.assertEqual(backend.calls[-1][0], "operation:transition-trace.disarm@1")
        emergency = cleanup["emergencyOperation"]
        self.assertEqual(emergency["trigger"], "cancellation")
        self.assertTrue(emergency["result"]["succeeded"])

    def test_replay_rejects_rehashed_emergency_identity_tampering(self) -> None:
        plan = _single_plan(calls=self.interrupted_calls())
        backend = TransitionLifecycleBackend(
            probe_failure=RuntimeError("original operation failure")
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, backend)
            with self.assertRaises(RegressionError):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:fault-tamper"),
                )
            coordinator.close()
            original = replay(directory)
            previous = None
            rewritten = []
            for event in original.events:
                payload = payload_value(event.payload)
                if event.type is EventType.LANE_INTERRUPTED:
                    record = json.loads(
                        payload["reason"][
                            len(TRANSITION_FAULT_INTERRUPTION_PREFIX) :
                        ]
                    )
                    record["emergencyOperation"]["implementationDigest"] = str(
                        _digest("forged-cleanup-implementation")
                    )
                    payload["reason"] = (
                        TRANSITION_FAULT_INTERRUPTION_PREFIX
                        + canonical_bytes(record).decode("utf-8")
                    )
                rebuilt = LedgerEvent.create(
                    event.sequence,
                    previous,
                    event.recorded_at,
                    event.run_id,
                    event.plan_digest,
                    event.type,
                    payload,
                    event.idempotency_key,
                )
                rewritten.append(rebuilt.canonical_line())
                previous = rebuilt.event_digest
            (directory / LEDGER_FILENAME).write_bytes(b"".join(rewritten))

            with self.assertRaisesRegex(
                RegressionError, "emergency Operation identity differs"
            ):
                core_replay(directory)

    def test_core_replay_rejects_stripped_emergency_record(self) -> None:
        plan = _single_plan(calls=self.interrupted_calls())
        backend = TransitionLifecycleBackend(
            probe_failure=RuntimeError("original operation failure")
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, backend)
            with self.assertRaises(RegressionError):
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:fault-stripped-record"),
                )
            coordinator.close()
            original = core_replay(directory)
            previous = None
            rewritten = []
            for event in original.events:
                payload = payload_value(event.payload)
                if event.type is EventType.LANE_INTERRUPTED:
                    payload["reason"] = "sidekick-execution-error"
                rebuilt = LedgerEvent.create(
                    event.sequence,
                    previous,
                    event.recorded_at,
                    event.run_id,
                    event.plan_digest,
                    event.type,
                    payload,
                    event.idempotency_key,
                )
                rewritten.append(rebuilt.canonical_line())
                previous = rebuilt.event_digest
            (directory / LEDGER_FILENAME).write_bytes(b"".join(rewritten))

            with self.assertRaisesRegex(
                RegressionError, "must record its assigned emergency disarm"
            ):
                core_replay(directory)

    def test_explicit_disarm_clean_run_has_no_emergency_record(self) -> None:
        plan = _single_plan(calls=self.calls(explicit_disarm=True))
        backend = TransitionLifecycleBackend()
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, backend)
            receipt = coordinator.run_sidekick(
                BoundLane.SIMULATOR,
                "target-simulator",
                SidekickID("sidekick:fault-explicit"),
            )
            view = coordinator.view
            coordinator.close()

        self.assertEqual(NodeStatus.PASSED, receipt.node_status)
        self.assertIsNone(view.lane(BoundLane.SIMULATOR).interruption_reason)
        self.assertEqual(
            [call[0] for call in backend.calls].count(
                "operation:transition-trace.disarm@1"
            ),
            1,
        )
        self.assertEqual(
            [str(item.operation) for item in view.leases[0].invocations],
            [
                "operation:transition-trace.arm@1",
                "operation:transition-trace.disarm@1",
                "operation:diagnostics.playback-state@1",
            ],
        )

    def test_cleanup_failure_is_ledger_bound_without_overwriting_original_error(self) -> None:
        plan = _single_plan(calls=self.interrupted_calls())
        backend = TransitionLifecycleBackend(
            probe_failure=RuntimeError("original operation failure"),
            cleanup_failure=RuntimeError("cleanup transport failure"),
        )
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            coordinator = _coordinator(directory, plan, backend)
            with self.assertRaisesRegex(
                RegressionError, "original operation failure"
            ) as raised:
                coordinator.run_sidekick(
                    BoundLane.SIMULATOR,
                    "target-simulator",
                    SidekickID("sidekick:fault-double-error"),
                )
            coordinator.close()
            cleanup = self.interruption_document(directory)

        self.assertIn(
            "cleanup transport failure",
            " ".join(getattr(raised.exception, "__notes__", ())),
        )
        result = cleanup["emergencyOperation"]["result"]
        self.assertFalse(result["succeeded"])
        self.assertIn("cleanup transport failure", result["detail"])


if __name__ == "__main__":
    unittest.main()
