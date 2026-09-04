#!/usr/bin/env python3

from __future__ import annotations

import ast
from dataclasses import FrozenInstanceError, replace
from operator import setitem
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from typing import Dict, List, Optional, Tuple, Union
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.capability import (
    AllowedOperationCall,
    OperationGrant,
    OperationRequest,
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
from regression.core.events import EventType, payload_value
from regression.core.expression import AllOf, ObservationRef, OracleResult
from regression.core.ids import (
    CallID,
    CaseKey,
    EvidenceSchema,
    EvidenceType,
    JourneyID,
    NodeID,
    ObligationID,
    OperationID,
    OracleID,
    PreparationID,
    RubricID,
    ScenarioID,
    SidekickID,
    StateKey,
    StateSchema,
    StateTag,
)
from regression.core.plan import (
    AgentEnvironment,
    BothJoinNode,
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
    RunPlanNode,
    ScenarioAttemptNode,
    ToolchainIdentity,
)
from regression.core.ledger import LedgerWriter
from regression.core.replay import replay
from regression.core.runtime import (
    CriterionEvaluation,
    EvidenceArtifact,
    EvidenceEnvelope,
    EvidenceReference,
    NegativeControlEvaluation,
    OperationResult,
    OracleDiagnostic,
    OracleEvaluation,
    OracleEvaluatorIdentity,
    StateFingerprint,
    open_run,
)
from regression.core.runview import (
    CallPlanView,
    FrozenJSONObject,
    NodeStatus,
    RunOutcome,
    awaiting_adjudication,
    build_run_view,
    nodes_awaiting_adjudication,
)
from regression.core.scheduler import CriticalCost


ARGUMENTS = b"{}"


def _digest(label: str):
    return canonical_digest({"fixture": label})


def _call(
    name: str,
    *,
    arguments: bytes = ARGUMENTS,
    max_invocations: int = 1,
    tags: Tuple[str, ...] = (),
) -> AllowedOperationCall:
    return AllowedOperationCall(
        call_id=CallID(f"call:{name}"),
        operation=OperationID(f"operation:fake.{name}@1"),
        contract_digest=_digest(f"operation:{name}"),
        arguments_bytes=arguments,
        arguments_digest=digest_bytes(arguments),
        implementation_locator=f"fake://operation/{name}",
        implementation_digest=_digest(f"implementation:{name}"),
        max_invocations=max_invocations,
        invalidates_tags=tuple(StateTag(tag) for tag in tags),
    )


def _request(
    call: Union[AllowedOperationCall, CallPlanView]
) -> OperationRequest:
    return OperationRequest(
        call.call_id,
        call.operation,
        call.contract_digest,
        call.arguments_digest,
        call.implementation_locator,
        call.implementation_digest,
    )


def _evaluation(name: str, call: AllowedOperationCall) -> EvaluationBinding:
    return EvaluationBinding(
        ObligationID(f"obligation:{name}"),
        ArtifactClass.COVERAGE,
        EvidenceType("fake.frame"),
        EvidenceSchema("fake.frame@1"),
        CaseKey("default"),
        call.call_id,
        call.contract_digest,
        OracleEvaluationBinding(
            OracleID(f"oracle:fake.{name}@1"),
            OracleKind.DETERMINISTIC,
            _digest(f"oracle-contract:{name}"),
            f"fake://oracle/{name}",
            _digest(f"oracle-implementation:{name}"),
            f"Oracle body for {name}",
        ),
        RubricEvaluationBinding(
            RubricID(f"rubric:fake.{name}@1"),
            _digest(f"rubric:{name}"),
            (f"{name} is visible",),
            (f"{name} is absent",),
            f"Rubric body for {name}",
        ),
    )


def _node(
    name: str,
    lane_candidates: Tuple[BoundLane, ...],
    *,
    calls: Optional[Tuple[AllowedOperationCall, ...]] = None,
    predecessors: Tuple[NodeID, ...] = (),
    gates: Tuple[LaneGateDependency, ...] = (),
    requirements: Tuple[PreparationRequirementBinding, ...] = (),
    critical: int = 100,
) -> ScenarioAttemptNode:
    planned_calls = calls or (_call(f"{name}-evidence"),)
    binding = _evaluation(name, planned_calls[-1])
    return ScenarioAttemptNode(
        NodeID(f"node:{name}"),
        ScenarioID(f"scenario:{name}"),
        JourneyID("journey:runtime"),
        _digest(f"scenario:{name}"),
        lane_candidates,
        len(lane_candidates) > 1,
        10,
        predecessors,
        gates,
        requirements,
        planned_calls,
        (binding,),
        ObservationRef(binding.id),
        _build_identity(lane_candidates),
        _evidence_environment(),
        critical,
    )


def _build_identity(lanes: Tuple[BoundLane, ...]) -> BuildIdentity:
    return BuildIdentity(
        "dev.enchron.runtime-tests",
        "0123456789abcdef",
        _digest("source-tree"),
        _digest("configuration"),
        ToolchainIdentity(
            "26.0",
            "17A5305f",
            "26.0",
            "23A5308g",
            "26.0",
            "23A5308g",
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


def _evidence_environment(
    nodes: Tuple[RunPlanNode, ...] = ()
) -> EvidenceEnvironmentIdentity:
    operations = {
        call.operation
        for node in nodes
        for call in getattr(node, "calls", ())
    }
    operations.add(OperationID("operation:fake.placeholder@1"))
    return EvidenceEnvironmentIdentity(
        {item: _digest(f"implementation:{item}") for item in sorted(operations)}
    )


def _plan(
    nodes: Tuple[RunPlanNode, ...],
    gates: Tuple[MainGateBinding, ...],
    *,
    preparations: Tuple[PreparationBinding, ...] = (),
) -> CompiledRunPlan:
    lanes = tuple(item.lane for item in gates)
    build = _build_identity(lanes)
    environment = _evidence_environment(nodes)
    rebound = tuple(
        node
        if isinstance(node, BothJoinNode)
        else replace(
            node,
            build_identity=build,
            evidence_environment_identity=environment.narrowed(
                item.operation for item in node.calls
            ),
        )
        for node in nodes
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


def _single_node_plan(
    *,
    calls: Optional[Tuple[AllowedOperationCall, ...]] = None,
    requirements: Tuple[PreparationRequirementBinding, ...] = (),
    preparations: Tuple[PreparationBinding, ...] = (),
) -> CompiledRunPlan:
    node = _node(
        "gate",
        (BoundLane.SIMULATOR,),
        calls=calls,
        requirements=requirements,
    )
    return _plan(
        (node,),
        (MainGateBinding(BoundLane.SIMULATOR, node.scenario_id, node.id),),
        preparations=preparations,
    )


class FakeOperationAdapter:
    def __init__(self, results: Optional[List[OperationResult]] = None) -> None:
        self.results = list(results or [OperationResult(True)])
        self.calls: List[OperationGrant] = []
        self.arguments: List[bytes] = []

    def invoke(self, grant: OperationGrant, arguments: bytes) -> OperationResult:
        self.calls.append(grant)
        self.arguments.append(arguments)
        return self.results.pop(0)


class FakeOracleIdentity:
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


class FakeOracle(FakeOracleIdentity):
    def __init__(
        self, results: Union[OracleResult, Dict[ObligationID, OracleResult]]
    ) -> None:
        self.results = results
        self.requests = []

    def evaluate(self, request):
        self.requests.append(request)
        if isinstance(self.results, dict):
            overall = self.results[request.binding.id]
        else:
            overall = self.results
        return OracleEvaluation(
            overall,
            tuple(
                CriterionEvaluation(item, overall)
                for item in request.binding.rubric.criteria
            ),
            tuple(
                NegativeControlEvaluation(item, overall)
                for item in request.binding.rubric.negative_controls
            ),
            (EvidenceReference(request.artifact.receipt_digest),),
            (OracleDiagnostic("fixture", "test evaluator"),),
        )


class SimulatedCrash(BaseException):
    pass


class CrashingAdapter:
    def __init__(self) -> None:
        self.calls = 0

    def invoke(self, grant: OperationGrant, arguments: bytes) -> OperationResult:
        self.calls += 1
        raise SimulatedCrash()


def _invoke_current(main, lease, adapter: FakeOperationAdapter) -> OperationResult:
    call = main.view.lease(lease.id).current_call
    assert call is not None
    request = _request(call)
    grant = main.authorize_operation(lease.capability, request, now_millis=1)
    return main.invoke_operation(grant, grant.arguments_bytes, adapter)


def _complete_operations(main, lease) -> None:
    while True:
        call = main.view.lease(lease.id).current_call
        if call is None:
            return
        fingerprints = tuple(
            StateFingerprint(item.key, item.schema, _digest(f"state:{item.key}"))
            for item in call.state_productions
        )
        _invoke_current(
            main,
            lease,
            FakeOperationAdapter([OperationResult(True, fingerprints)]),
        )


def _envelope(main, lease, *, data: bytes = b"frame", path_suffix: str = ""):
    node = next(item for item in main.plan.nodes if item.id == lease.node_id)
    artifacts = []
    for binding in node.evaluation_bindings:
        relative_path = f"evidence/{binding.id}{path_suffix}.bin"
        path = lease.assignment_directory / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        artifacts.append(
            EvidenceArtifact(
                binding.id,
                binding.evidence_type,
                binding.evidence_schema,
                binding.case_key,
                binding.produced_by_call,
                "1970-01-01T00:00:01Z",
                binding.producer_contract_digest,
                relative_path,
                len(data),
                digest_bytes(data),
            )
        )
    return EvidenceEnvelope(
        main.run_id,
        main.plan.plan_digest,
        lease.node_id,
        lease.id,
        lease.lane,
        lease.sidekick_id,
        node.build_identity.digest,
        node.evidence_environment_identity.digest,
        tuple(artifacts),
    )


def _run_claimed_node(main, result: OracleResult):
    lease = main.claim(
        BoundLane.SIMULATOR,
        SidekickID("sidekick:main"),
        now_millis=0,
    )
    _complete_operations(main, lease)
    envelope = _envelope(main, lease)
    receipt = main.accept_evidence(envelope, FakeOracle(result))
    return lease, envelope, receipt


ADJUDICATION = {
    "attribution": "product",
    "bundleFrameCount": 12,
    "firstDeviantFrame": 3,
    "regionObservation": "the poster grid stayed blank",
    "signature": None,
}


def _verdict_payload(node_id, lease_id, status, adjudication=ADJUDICATION):
    payload = {
        "nodeId": str(node_id),
        "leaseId": None if lease_id is None else str(lease_id),
        "status": status.value,
        "failureAncestors": [],
    }
    if adjudication is not None:
        payload["adjudication"] = dict(adjudication)
    return payload


def _two_obligation_plan() -> CompiledRunPlan:
    calls = (_call("gate-first"), _call("gate-second"))
    bindings = (_evaluation("gate-first", calls[0]), _evaluation("gate-second", calls[1]))
    node = ScenarioAttemptNode(
        NodeID("node:gate"),
        ScenarioID("scenario:gate"),
        JourneyID("journey:runtime"),
        _digest("scenario:gate"),
        (BoundLane.SIMULATOR,),
        False,
        10,
        (),
        (),
        (),
        calls,
        bindings,
        AllOf(tuple(ObservationRef(item.id) for item in bindings)),
        _build_identity((BoundLane.SIMULATOR,)),
        _evidence_environment(),
        100,
    )
    return _plan(
        (node,),
        (MainGateBinding(BoundLane.SIMULATOR, node.scenario_id, node.id),),
    )


def _half_evaluated_run(root: Path, plan, first: OracleResult):
    complete = root / "complete"
    main = open_run(plan, complete)
    lease = main.claim(
        BoundLane.SIMULATOR,
        SidekickID("sidekick:main"),
        now_millis=0,
    )
    _complete_operations(main, lease)
    main.accept_evidence(
        _envelope(main, lease),
        FakeOracle(
            {
                ObligationID("obligation:gate-first"): first,
                ObligationID("obligation:gate-second"): OracleResult.VIOLATED,
            }
        ),
    )
    main.close()

    crashed = root / "crashed"
    crashed.mkdir(parents=True, exist_ok=True)
    kept = []
    for line in (complete / "ledger.jsonl").read_bytes().splitlines(keepends=True):
        kept.append(line)
        if b'"OracleEvaluated"' in line:
            break
    (crashed / "ledger.jsonl").write_bytes(b"".join(kept))
    for item in complete.iterdir():
        if item.name != "ledger.jsonl" and item.name != "ledger.lock":
            _copy_tree(item, crashed / item.name)
    return crashed, lease


def _copy_tree(source: Path, target: Path) -> None:
    if source.is_dir():
        target.mkdir(parents=True, exist_ok=True)
        for item in source.iterdir():
            _copy_tree(item, target / item.name)
    else:
        target.write_bytes(source.read_bytes())


def _append_verdict(directory: Path, plan, payload):
    view = replay(directory)
    with LedgerWriter(
        directory, view.run_id, plan.plan_digest, build_run_view
    ) as writer:
        return writer.append(
            EventType.VERDICT_RECORDED,
            payload,
            "2026-09-04T00:00:00.000Z",
            f"verdict:{payload['nodeId']}",
        )


class RuntimeHappyPathTests(unittest.TestCase):
    def test_happy_path_writes_cas_and_public_replay_returns_frozen_view(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _single_node_plan()
            main = open_run(plan, directory)
            lease, envelope, receipt = _run_claimed_node(
                main, OracleResult.SATISFIED
            )
            final = main.finalize()

            self.assertEqual(NodeStatus.PASSED, receipt.node_status)
            self.assertEqual(RunOutcome.PASSED, final.outcome)
            restored = replay(directory)
            self.assertEqual(final, restored)
            self.assertEqual(envelope.digest, restored.lease(lease.id).envelope_digest)
            accepted = restored.lease(lease.id).evidence[0]
            self.assertEqual(EvidenceSchema("fake.frame@1"), accepted.evidence_schema)
            self.assertEqual(CaseKey("default"), accepted.case_key)
            self.assertEqual("1970-01-01T00:00:01Z", accepted.captured_at)
            evaluation = restored.lease(lease.id).oracle_evaluations[0]
            self.assertEqual(OracleResult.SATISFIED, evaluation.overall)
            self.assertEqual(
                (("gate is visible", OracleResult.SATISFIED),),
                evaluation.criteria,
            )
            self.assertEqual(1, len(evaluation.evidence_refs))
            self.assertEqual((("fixture", "test evaluator"),), evaluation.detail)
            self.assertEqual(
                b"frame", (directory / restored.lease(lease.id).evidence[0].object_path).read_bytes()
            )
            self.assertTrue((directory / "plan.json").is_file())
            self.assertFalse((directory / "current.json").exists())
            self.assertFalse((directory / "snapshot.json").exists())
            with self.assertRaises(FrozenInstanceError):
                setattr(restored, "outcome", None)

    def test_a_violated_node_stays_open_until_the_ledger_adjudicates_it(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _single_node_plan()
            main = open_run(plan, directory)
            lease, _, receipt = _run_claimed_node(main, OracleResult.VIOLATED)

            self.assertEqual(NodeStatus.LEASED, receipt.node_status)
            self.assertEqual(
                (lease.node_id,),
                tuple(item.node_id for item in nodes_awaiting_adjudication(main.view)),
            )
            with self.assertRaises(RegressionError) as raised:
                main.finalize()
            self.assertEqual("runtime.adjudication_owed", raised.exception.code)
            main.close()

            _append_verdict(
                directory,
                plan,
                _verdict_payload(lease.node_id, lease.id, NodeStatus.FAILED),
            )
            adjudicated = replay(directory)
            node = adjudicated.node(lease.node_id)
            self.assertEqual(NodeStatus.FAILED, node.status)
            self.assertEqual(3, node.adjudication.first_deviant_frame)
            self.assertEqual((), nodes_awaiting_adjudication(adjudicated))
            self.assertEqual(RunOutcome.FAILED, open_run(plan, directory).finalize().outcome)

    def test_the_ledger_refuses_a_verdict_its_own_lease_contradicts(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _single_node_plan()
            main = open_run(plan, directory)
            lease, _, _ = _run_claimed_node(main, OracleResult.VIOLATED)
            main.close()
            before = (directory / "ledger.jsonl").stat().st_size

            for status, adjudication in (
                (NodeStatus.PASSED, None),
                (NodeStatus.DEFERRED_HUMAN, ADJUDICATION),
                (NodeStatus.INDETERMINATE, ADJUDICATION),
            ):
                with self.subTest(status=status):
                    with self.assertRaisesRegex(
                        RegressionError, "contradicts the Oracle result"
                    ):
                        _append_verdict(
                            directory,
                            plan,
                            _verdict_payload(
                                lease.node_id, lease.id, status, adjudication
                            ),
                        )

            self.assertEqual(before, (directory / "ledger.jsonl").stat().st_size)

    def test_an_adjudication_is_required_and_bounded_by_its_bundle(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _single_node_plan()
            main = open_run(plan, directory)
            lease, _, _ = _run_claimed_node(main, OracleResult.VIOLATED)
            main.close()
            before = (directory / "ledger.jsonl").stat().st_size

            rejected = (
                (NodeStatus.FAILED, None, "needs its adjudication"),
                (
                    NodeStatus.FAILED,
                    {**ADJUDICATION, "firstDeviantFrame": 12},
                    "outside the bundle frame count",
                ),
                (
                    NodeStatus.FAILED,
                    {**ADJUDICATION, "regionObservation": ""},
                    "must be a non-empty string",
                ),
                (
                    NodeStatus.FAILED,
                    {**ADJUDICATION, "attribution": "operator"},
                    "attribution is not recognized",
                ),
                (NodeStatus.FAILED_KNOWN, ADJUDICATION, "needs its signature"),
            )
            for status, adjudication, refusal in rejected:
                with self.subTest(refusal=refusal):
                    with self.assertRaisesRegex(RegressionError, refusal):
                        _append_verdict(
                            directory,
                            plan,
                            _verdict_payload(
                                lease.node_id, lease.id, status, adjudication
                            ),
                        )
            self.assertEqual(before, (directory / "ledger.jsonl").stat().st_size)

    def test_a_violation_already_determined_survives_a_half_evaluated_lease(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan = _two_obligation_plan()
            crashed, lease = _half_evaluated_run(
                root, plan, OracleResult.VIOLATED
            )
            view = replay(crashed)
            self.assertEqual(1, len(view.lease(lease.id).oracle_evaluations))
            self.assertTrue(
                awaiting_adjudication(view.node(lease.node_id), view.lease(lease.id))
            )

            with self.assertRaisesRegex(
                RegressionError, "contradicts the Oracle result"
            ):
                _append_verdict(
                    crashed,
                    plan,
                    _verdict_payload(
                        lease.node_id, lease.id, NodeStatus.INDETERMINATE, None
                    ),
                )
            with self.assertRaisesRegex(RegressionError, "needs its adjudication"):
                _append_verdict(
                    crashed,
                    plan,
                    _verdict_payload(
                        lease.node_id, lease.id, NodeStatus.FAILED, None
                    ),
                )

            _append_verdict(
                crashed,
                plan,
                _verdict_payload(lease.node_id, lease.id, NodeStatus.FAILED),
            )
            self.assertEqual(
                NodeStatus.FAILED, replay(crashed).node(lease.node_id).status
            )

    def test_an_undetermined_lease_owes_nothing_and_resumes_from_its_envelope(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan = _two_obligation_plan()
            crashed, lease = _half_evaluated_run(
                root, plan, OracleResult.SATISFIED
            )
            view = replay(crashed)
            node = view.node(lease.node_id)
            self.assertEqual(1, len(view.lease(lease.id).oracle_evaluations))
            self.assertFalse(awaiting_adjudication(node, view.lease(lease.id)))

            with self.assertRaisesRegex(RegressionError, "half-evaluated lease"):
                _append_verdict(
                    crashed,
                    plan,
                    _verdict_payload(lease.node_id, lease.id, NodeStatus.FAILED),
                )

            resumed = open_run(plan, crashed)
            receipt = resumed.accept_evidence(
                _envelope(resumed, lease),
                FakeOracle(
                    {
                        ObligationID("obligation:gate-first"): OracleResult.SATISFIED,
                        ObligationID("obligation:gate-second"): OracleResult.VIOLATED,
                    }
                ),
            )
            self.assertEqual(NodeStatus.LEASED, receipt.node_status)
            self.assertEqual(1, len(nodes_awaiting_adjudication(resumed.view)))
            resumed.close()

    def test_an_interruption_cannot_launder_a_node_that_owes_a_verdict(self) -> None:
        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            lease, _, _ = _run_claimed_node(main, OracleResult.VIOLATED)
            view = main.interrupt_lane(lease.lane, "device-detached", lease.id)

            self.assertTrue(view.lane(lease.lane).interrupted)
            self.assertEqual(NodeStatus.LEASED, view.node(lease.node_id).status)
            self.assertTrue(
                awaiting_adjudication(
                    view.node(lease.node_id), view.lease(lease.id)
                )
            )
            main.close()


class RuntimeFaultTests(unittest.TestCase):
    def test_oracle_overall_must_equal_its_canonical_component_aggregate(self) -> None:
        class ContradictoryOracle(FakeOracleIdentity):
            def evaluate(self, request):
                return OracleEvaluation(
                    OracleResult.SATISFIED,
                    tuple(
                        CriterionEvaluation(item, OracleResult.SATISFIED)
                        for item in request.binding.rubric.criteria
                    ),
                    tuple(
                        NegativeControlEvaluation(item, OracleResult.VIOLATED)
                        for item in request.binding.rubric.negative_controls
                    ),
                    (EvidenceReference(request.artifact.receipt_digest),),
                )

        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:contradictory-oracle"),
                now_millis=0,
            )
            _complete_operations(main, lease)

            with self.assertRaises(RegressionError) as raised:
                main.accept_evidence(
                    _envelope(main, lease),
                    ContradictoryOracle(),
                )

            self.assertEqual("runtime.oracle_overall_mismatch", raised.exception.code)
            self.assertFalse(
                any(
                    event.type is EventType.ORACLE_EVALUATED
                    for event in main.view.events
                )
            )
            self.assertEqual(NodeStatus.INDETERMINATE, main.view.node(lease.node_id).status)
            main.close()

    def test_evaluator_identity_and_typed_protocol_are_mandatory(self) -> None:
        class ForgedIdentityOracle(FakeOracle):
            def identity_for(self, oracle_id):
                return OracleEvaluatorIdentity(
                    oracle_id,
                    "human://unreviewed",
                    _digest("human-evaluator"),
                    None,
                )

        def callable_escape(request):
            return FakeOracle(OracleResult.SATISFIED).evaluate(request)

        for name, evaluator in (
            (
                "forged-identity",
                ForgedIdentityOracle(OracleResult.SATISFIED),
            ),
            ("callable-escape", callable_escape),
        ):
            with self.subTest(name=name), TemporaryDirectory() as temporary:
                main = open_run(_single_node_plan(), Path(temporary))
                lease = main.claim(
                    BoundLane.SIMULATOR,
                    SidekickID(f"sidekick:{name}"),
                    now_millis=0,
                )
                _complete_operations(main, lease)
                with self.assertRaises(RegressionError) as raised:
                    main.accept_evidence(_envelope(main, lease), evaluator)
                self.assertIn(
                    raised.exception.code,
                    {
                        "runtime.invalid_oracle_evaluator",
                        "runtime.oracle_evaluator_identity_mismatch",
                    },
                )
                self.assertFalse(
                    any(
                        event.type is EventType.ORACLE_EVALUATED
                        for event in main.view.events
                    )
                )
                main.close()

    def test_evaluator_agent_environment_must_match_the_frozen_node(self) -> None:
        expected_environment = AgentEnvironment(
            "agent-expected",
            _digest("prompt-expected"),
            _digest("configuration-expected"),
        )
        wrong_environment = AgentEnvironment(
            "agent-wrong",
            _digest("prompt-wrong"),
            _digest("configuration-wrong"),
        )
        base = _single_node_plan()
        evidence_environment = EvidenceEnvironmentIdentity(
            dict(base.nodes[0].evidence_environment_identity.operation_digests),
            expected_environment,
        )
        node = replace(
            base.nodes[0], evidence_environment_identity=evidence_environment
        )
        plan = replace(
            base,
            evidence_environment_identity=evidence_environment,
            nodes=(node,),
        )

        class WrongProviderEnvironmentOracle(FakeOracle):
            def identity_for(self, oracle_id):
                identity = super().identity_for(oracle_id)
                return replace(identity, agent_environment=wrong_environment)

        with TemporaryDirectory() as temporary:
            main = open_run(plan, Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:wrong-provider-environment"),
                now_millis=0,
            )
            _complete_operations(main, lease)
            with self.assertRaises(RegressionError) as raised:
                main.accept_evidence(
                    _envelope(main, lease),
                    WrongProviderEnvironmentOracle(OracleResult.SATISFIED),
                )
            self.assertEqual(
                "runtime.oracle_agent_environment_mismatch",
                raised.exception.code,
            )
            self.assertFalse(
                any(
                    event.type is EventType.ENVELOPE_RECEIVED
                    for event in main.view.events
                )
            )
            main.close()

    def test_schema_case_time_and_producer_digest_tampering_are_rejected(self) -> None:
        tamperers = (
            (
                "schema",
                lambda artifact: replace(
                    artifact, evidence_schema=EvidenceSchema("fake.frame@2")
                ),
                "runtime.envelope_binding_mismatch",
            ),
            (
                "case",
                lambda artifact: replace(artifact, case_key=CaseKey("other")),
                "runtime.envelope_binding_mismatch",
            ),
            (
                "producer-digest",
                lambda artifact: replace(
                    artifact,
                    producer_contract_digest=_digest("wrong-operation"),
                ),
                "runtime.envelope_binding_mismatch",
            ),
            (
                "capture-time",
                lambda artifact: replace(
                    artifact, captured_at="1970-01-01T00:01:01Z"
                ),
                "runtime.artifact_capture_outside_lease",
            ),
        )
        for name, tamper, code in tamperers:
            with self.subTest(name=name), TemporaryDirectory() as temporary:
                main = open_run(_single_node_plan(), Path(temporary))
                lease = main.claim(
                    BoundLane.SIMULATOR,
                    SidekickID("sidekick:tamper"),
                    now_millis=0,
                )
                _complete_operations(main, lease)
                envelope = _envelope(main, lease)
                changed = replace(
                    envelope,
                    artifacts=(tamper(envelope.artifacts[0]),),
                )
                with self.assertRaises(RegressionError) as raised:
                    main.accept_evidence(
                        changed, FakeOracle(OracleResult.SATISFIED)
                    )
                self.assertEqual(code, raised.exception.code)
                self.assertFalse((Path(temporary) / "objects").exists())
                events = main.view.events
                self.assertFalse(
                    any(
                        event.type is EventType.ENVELOPE_RECEIVED
                        for event in events
                    )
                )
                self.assertEqual(
                    [f"invalid-evidence-envelope:{code}"],
                    [
                        payload_value(event.payload)["reason"]
                        for event in events
                        if event.type is EventType.LANE_INTERRUPTED
                    ],
                )
                main.close()
                main.close()

    def test_zero_byte_artifact_and_incomplete_oracle_result_are_rejected(self) -> None:
        with self.assertRaises(RegressionError) as raised:
            EvidenceArtifact(
                ObligationID("obligation:zero"),
                EvidenceType("fake.frame"),
                EvidenceSchema("fake.frame@1"),
                CaseKey("default"),
                CallID("call:zero"),
                "1970-01-01T00:00:01Z",
                _digest("operation:zero"),
                "zero.bin",
                0,
                digest_bytes(b""),
            )
        self.assertEqual("runtime.invalid_artifact_length", raised.exception.code)
        with self.assertRaises(RegressionError) as raised:
            OracleEvaluation(
                OracleResult.SATISFIED,
                (CriterionEvaluation("criterion", OracleResult.SATISFIED),),
                (
                    NegativeControlEvaluation(
                        "negative control", OracleResult.SATISFIED
                    ),
                ),
                (EvidenceReference(_digest("receipt")),),
                tuple(
                    OracleDiagnostic(f"detail-{index}", "bounded")
                    for index in range(17)
                ),
            )
        self.assertEqual("runtime.invalid_oracle_evaluation", raised.exception.code)

        class IncompleteOracle(FakeOracleIdentity):
            def evaluate(self, request):
                return OracleEvaluation(
                    OracleResult.SATISFIED,
                    (),
                    tuple(
                        NegativeControlEvaluation(
                            item, OracleResult.SATISFIED
                        )
                        for item in request.binding.rubric.negative_controls
                    ),
                    (EvidenceReference(request.artifact.receipt_digest),),
                )

        class WrongEvidenceRefOracle(FakeOracleIdentity):
            def evaluate(self, request):
                return OracleEvaluation(
                    OracleResult.SATISFIED,
                    tuple(
                        CriterionEvaluation(item, OracleResult.SATISFIED)
                        for item in request.binding.rubric.criteria
                    ),
                    tuple(
                        NegativeControlEvaluation(
                            item, OracleResult.SATISFIED
                        )
                        for item in request.binding.rubric.negative_controls
                    ),
                    (EvidenceReference(_digest("wrong-receipt")),),
                )

        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:oracle"),
                now_millis=0,
            )
            _complete_operations(main, lease)
            with self.assertRaises(RegressionError) as raised:
                main.accept_evidence(_envelope(main, lease), IncompleteOracle())
            self.assertEqual(
                "runtime.incomplete_oracle_criteria", raised.exception.code
            )
            main.close()

        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:oracle-ref"),
                now_millis=0,
            )
            _complete_operations(main, lease)
            with self.assertRaises(RegressionError) as raised:
                main.accept_evidence(
                    _envelope(main, lease), WrongEvidenceRefOracle()
                )
            self.assertEqual(
                "runtime.oracle_evidence_ref_mismatch", raised.exception.code
            )
            main.close()

    def test_indeterminate_and_invalid_envelope_interrupt_instead_of_fail(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            indeterminate = open_run(_single_node_plan(), root / "indeterminate")
            _, _, receipt = _run_claimed_node(
                indeterminate, OracleResult.INDETERMINATE
            )
            self.assertEqual(NodeStatus.LEASED, receipt.node_status)
            self.assertNotEqual(NodeStatus.FAILED, receipt.node_status)
            self.assertEqual(
                1, len(nodes_awaiting_adjudication(indeterminate.view))
            )
            indeterminate.close()

            invalid = open_run(_single_node_plan(), root / "invalid")
            lease = invalid.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:invalid"),
                now_millis=0,
            )
            _complete_operations(invalid, lease)
            envelope = _envelope(invalid, lease)
            wrong = replace(
                envelope,
                artifacts=(
                    replace(
                        envelope.artifacts[0],
                        evidence_type=EvidenceType("fake.other"),
                    ),
                ),
            )
            with self.assertRaises(RegressionError) as raised:
                invalid.accept_evidence(wrong, FakeOracle(OracleResult.SATISFIED))
            self.assertEqual("runtime.envelope_binding_mismatch", raised.exception.code)
            self.assertEqual(NodeStatus.INDETERMINATE, invalid.view.node(lease.node_id).status)
            self.assertFalse((root / "invalid" / "objects").exists())
            invalid.close()

    def test_invoked_call_without_completion_is_interrupted_on_recovery(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _single_node_plan(
                calls=(
                    _call(
                        "crash", tags=("app.session", "library.cache")
                    ),
                )
            )
            main = open_run(plan, directory)
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:crash"),
                now_millis=0,
            )
            adapter = CrashingAdapter()
            call = main.view.lease(lease.id).current_call
            assert call is not None
            grant = main.authorize_operation(
                lease.capability,
                _request(call),
                now_millis=1,
            )
            with self.assertRaises(SimulatedCrash):
                main.invoke_operation(grant, grant.arguments_bytes, adapter)
            main.close()

            recovered = open_run(plan, directory)
            self.assertEqual(1, adapter.calls)
            self.assertEqual(NodeStatus.INDETERMINATE, recovered.view.node(lease.node_id).status)
            self.assertTrue(recovered.view.lane(BoundLane.SIMULATOR).interrupted)
            self.assertEqual(
                1,
                recovered.view.lane(BoundLane.SIMULATOR).epochs.value(
                    StateTag("app.session")
                ),
            )
            invoked = next(
                event
                for event in recovered.view.events
                if event.type is EventType.OPERATION_INVOKED
            )
            self.assertEqual(
                ["app.session", "library.cache"],
                [
                    item["tag"]
                    for item in payload_value(invoked.payload)["epochAdvances"]
                ],
            )
            recovered.close()

    def test_authorized_call_without_invocation_is_interrupted_on_recovery(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _single_node_plan()
            main = open_run(plan, directory)
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:authorized-crash"),
                now_millis=0,
            )
            call = main.view.lease(lease.id).current_call
            assert call is not None
            main.authorize_operation(
                lease.capability,
                _request(call),
                now_millis=1,
            )
            main.close()

            recovered = open_run(plan, directory)
            self.assertEqual(
                NodeStatus.INDETERMINATE, recovered.view.node(lease.node_id).status
            )
            invoked = [
                event
                for event in recovered.view.events
                if event.type is EventType.OPERATION_INVOKED
            ]
            self.assertEqual([], invoked)
            recovered.close()

    def test_non_enum_oracle_result_interrupts_the_lane(self) -> None:
        class InvalidResultOracle(FakeOracleIdentity):
            def evaluate(self, request):
                return "satisfied"

        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:invalid-oracle"),
                now_millis=0,
            )
            _complete_operations(main, lease)
            with self.assertRaises(RegressionError) as raised:
                main.accept_evidence(_envelope(main, lease), InvalidResultOracle())
            self.assertEqual("runtime.invalid_oracle_result", raised.exception.code)
            self.assertEqual(
                NodeStatus.INDETERMINATE, main.view.node(lease.node_id).status
            )
            main.close()


class RuntimeCapabilityTests(unittest.TestCase):
    def test_calls_are_strictly_ordered_retry_is_bounded_and_grant_is_exact(self) -> None:
        first = _call("first", max_invocations=2)
        second = _call("second")
        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(calls=(first, second)), Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:ordered"),
                now_millis=0,
            )
            with self.assertRaises(RegressionError) as out_of_order:
                main.authorize_operation(
                    lease.capability,
                    _request(second),
                    now_millis=1,
                )
            self.assertEqual("runtime.call_out_of_order", out_of_order.exception.code)

            failed = FakeOperationAdapter([OperationResult(False)])
            _invoke_current(main, lease, failed)
            self.assertEqual(first.call_id, main.view.lease(lease.id).current_call.call_id)

            current = main.view.lease(lease.id).current_call
            assert current is not None
            grant = main.authorize_operation(
                lease.capability,
                _request(current),
                now_millis=2,
            )
            untouched = FakeOperationAdapter()
            with self.assertRaises(RegressionError) as mismatch:
                main.invoke_operation(grant, b'{"tampered":true}', untouched)
            self.assertEqual("runtime.arguments_mismatch", mismatch.exception.code)
            self.assertEqual([], untouched.calls)

            main.invoke_operation(grant, grant.arguments_bytes, FakeOperationAdapter())
            self.assertEqual(second.call_id, main.view.lease(lease.id).current_call.call_id)
            with self.assertRaises(RegressionError):
                main.authorize_operation(
                    lease.capability,
                    _request(first),
                    now_millis=3,
                )
            main.close()

    def test_unauthorized_request_never_reaches_fake_adapter(self) -> None:
        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:unauthorized"),
                now_millis=0,
            )
            current = main.view.lease(lease.id).current_call
            assert current is not None
            grant = main.authorize_operation(
                lease.capability,
                _request(current),
                now_millis=1,
            )
            adapter = FakeOperationAdapter()
            with self.assertRaises(RegressionError) as mismatch:
                replace(grant, plan_digest=_digest("foreign-plan"))
            self.assertEqual("capability.grant_id_mismatch", mismatch.exception.code)
            self.assertEqual([], adapter.calls)
            main.close()

    def test_result_references_resolve_recursively_before_adapter_access(self) -> None:
        producer = _call("producer")
        consumer_template = canonical_bytes(
            {
                "direct": "result://call:producer/token",
                "nested": {
                    "items": [
                        "literal",
                        "result://call:producer/count",
                        {"value": "result://call:producer/details"},
                    ],
                    "interpolationIsLiteral": "token=result://call:producer/token",
                },
            }
        )
        consumer = _call("consumer", arguments=consumer_template)
        expected = canonical_bytes(
            {
                "direct": "session-42",
                "nested": {
                    "items": [
                        "literal",
                        7,
                        {"value": {"kind": "receipt", "valid": True}},
                    ],
                    "interpolationIsLiteral": "token=result://call:producer/token",
                },
            }
        )

        with TemporaryDirectory() as temporary:
            main = open_run(
                _single_node_plan(calls=(producer, consumer)), Path(temporary)
            )
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:references"),
                now_millis=0,
            )
            producer_adapter = FakeOperationAdapter(
                [
                    OperationResult(
                        True,
                        outputs={
                            "token": "session-42",
                            "count": 7,
                            "details": {"kind": "receipt", "valid": True},
                        },
                    )
                ]
            )
            _invoke_current(main, lease, producer_adapter)

            consumer_adapter = FakeOperationAdapter()
            _invoke_current(main, lease, consumer_adapter)
            grant = consumer_adapter.calls[0]

            self.assertEqual([expected], consumer_adapter.arguments)
            self.assertEqual(consumer.arguments_digest, grant.arguments_template_digest)
            self.assertEqual(expected, grant.arguments_bytes)
            self.assertEqual(digest_bytes(expected), grant.arguments_digest)
            self.assertEqual(
                consumer.implementation_locator, grant.implementation_locator
            )
            self.assertEqual(
                consumer.implementation_digest, grant.implementation_digest
            )
            self.assertEqual(
                consumer.arguments_bytes,
                lease.capability.calls[1].arguments_bytes,
            )
            main.close()

    def test_missing_result_output_interrupts_without_authorizing_or_invoking(self) -> None:
        producer = _call("missing-producer")
        consumer = _call(
            "missing-consumer",
            arguments=canonical_bytes(
                {
                    "input": "result://call:missing-producer/absent",
                }
            ),
        )
        with TemporaryDirectory() as temporary:
            main = open_run(
                _single_node_plan(calls=(producer, consumer)), Path(temporary)
            )
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:missing-output"),
                now_millis=0,
            )
            _invoke_current(
                main,
                lease,
                FakeOperationAdapter(
                    [OperationResult(True, outputs={"other": "present"})]
                ),
            )
            call = main.view.lease(lease.id).current_call
            assert call is not None
            before = tuple(
                event
                for event in main.view.events
                if event.type is EventType.OPERATION_AUTHORIZED
            )

            with self.assertRaises(RegressionError) as raised:
                main.authorize_operation(
                    lease.capability,
                    _request(call),
                    now_millis=2,
                )

            self.assertEqual(
                "runtime.result_reference_missing_field", raised.exception.code
            )
            after = tuple(
                event
                for event in main.view.events
                if event.type is EventType.OPERATION_AUTHORIZED
            )
            self.assertEqual(before, after)
            self.assertEqual(
                NodeStatus.INDETERMINATE, main.view.node(lease.node_id).status
            )
            self.assertTrue(main.view.lane(lease.lane).interrupted)
            main.close()

    def test_malformed_result_reference_interrupts_before_target_access(self) -> None:
        call = _call(
            "malformed-reference",
            arguments=canonical_bytes(
                {"input": "result://call:malformed-reference"}
            ),
        )
        with TemporaryDirectory() as temporary:
            main = open_run(
                _single_node_plan(calls=(call,)), Path(temporary)
            )
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:malformed-reference"),
                now_millis=0,
            )
            current = main.view.lease(lease.id).current_call
            assert current is not None

            with self.assertRaises(RegressionError) as raised:
                main.authorize_operation(
                    lease.capability,
                    _request(current),
                    now_millis=1,
                )

            self.assertEqual(
                "runtime.invalid_result_reference", raised.exception.code
            )
            self.assertFalse(
                any(
                    event.type is EventType.OPERATION_AUTHORIZED
                    for event in main.view.events
                )
            )
            self.assertEqual(
                NodeStatus.INDETERMINATE, main.view.node(lease.node_id).status
            )
            main.close()

    def test_completed_outputs_survive_reopen_and_resolve_the_next_call(self) -> None:
        producer = _call("durable-producer")
        consumer = _call(
            "durable-consumer",
            arguments=canonical_bytes(
                {
                    "receipt": "result://call:durable-producer/receipt",
                }
            ),
        )
        plan = _single_node_plan(calls=(producer, consumer))
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(plan, directory)
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:durable-output"),
                now_millis=0,
            )
            result = OperationResult(
                True,
                outputs={"receipt": {"id": "receipt-7", "parts": [1, 2]}},
            )
            _invoke_current(main, lease, FakeOperationAdapter([result]))
            completed = next(
                event
                for event in main.view.events
                if event.type is EventType.OPERATION_COMPLETED
            )
            self.assertEqual(
                {"receipt": {"id": "receipt-7", "parts": [1, 2]}},
                payload_value(completed.payload)["outputs"],
            )
            main.close()

            reopened = open_run(plan, directory)
            restored = reopened.view.lease(lease.id).invocations[0]
            self.assertEqual(result.outputs, restored.outputs)
            call = reopened.view.lease(lease.id).current_call
            assert call is not None
            grant = reopened.authorize_operation(
                lease.capability,
                _request(call),
                now_millis=2,
            )
            adapter = FakeOperationAdapter()
            reopened.invoke_operation(grant, grant.arguments_bytes, adapter)
            self.assertEqual(
                [canonical_bytes({"receipt": {"id": "receipt-7", "parts": [1, 2]}})],
                adapter.arguments,
            )
            reopened.close()

    def test_operation_outputs_are_immutable_json_values(self) -> None:
        source = {"nested": {"values": ["first"]}}
        result = OperationResult(True, outputs=source)
        source["nested"]["values"].append("mutated")

        self.assertEqual(("first",), result.outputs["nested"]["values"])
        with self.assertRaises(TypeError):
            setitem(result.outputs, "new", "forbidden")
        with self.assertRaises(RegressionError) as unsupported:
            OperationResult(True, outputs={"unsupported": {"set"}})
        self.assertEqual(
            "runtime.invalid_operation_output", unsupported.exception.code
        )
        with self.assertRaises(RegressionError) as mutable_wrapper:
            FrozenJSONObject((("mutable", []),))
        self.assertEqual(
            "runtime.invalid_operation_output", mutable_wrapper.exception.code
        )


class RuntimeStateTests(unittest.TestCase):
    def test_lane_local_handle_reuse_and_selective_epoch_invalidation(self) -> None:
        setup = _call("prepare-account")
        preparation_id = PreparationID("preparation:account")
        requirement = StateRequirement(StateKey("signed-in"), StateSchema("auth.session@1"))
        preparation = PreparationBinding(
            preparation_id,
            BoundLane.SIMULATOR,
            _digest("preparation:account"),
            5,
            (),
            (setup,),
            (
                StateDeclaration(
                    requirement.key,
                    requirement.schema,
                    setup.call_id,
                    (StateTag("account.session"),),
                ),
            ),
        )
        requirement_binding = PreparationRequirementBinding(
            BoundLane.SIMULATOR, requirement, preparation_id
        )
        gate = _node("gate", (BoundLane.SIMULATOR,), critical=400)
        first = _node(
            "first",
            (BoundLane.SIMULATOR,),
            calls=(_call("first-evidence", tags=("library.cache",)),),
            predecessors=(gate.id,),
            gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
            requirements=(requirement_binding,),
            critical=300,
        )
        second = _node(
            "second",
            (BoundLane.SIMULATOR,),
            calls=(_call("second-evidence", tags=("account.session",)),),
            predecessors=(gate.id, first.id),
            gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
            requirements=(requirement_binding,),
            critical=200,
        )
        third = _node(
            "third",
            (BoundLane.SIMULATOR,),
            predecessors=(gate.id, second.id),
            gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
            requirements=(requirement_binding,),
            critical=100,
        )
        plan = _plan(
            (gate, first, second, third),
            (MainGateBinding(BoundLane.SIMULATOR, gate.scenario_id, gate.id),),
            preparations=(preparation,),
        )

        with TemporaryDirectory() as temporary:
            main = open_run(plan, Path(temporary))
            _run_claimed_node(main, OracleResult.SATISFIED)

            first_lease = main.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:first"), now_millis=0
            )
            self.assertEqual("preparation", main.view.lease(first_lease.id).calls[0].phase)
            _complete_operations(main, first_lease)
            main.accept_evidence(
                _envelope(main, first_lease), FakeOracle(OracleResult.SATISFIED)
            )
            self.assertEqual(1, len(main.view.state_handles))
            self.assertIsNotNone(
                main.view.valid_state_handle(
                    requirement.key,
                    requirement.schema,
                    BoundLane.SIMULATOR,
                    preparation_id,
                )
            )

            second_lease = main.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:second"), now_millis=0
            )
            self.assertEqual(
                ("scenario",),
                tuple(item.phase for item in main.view.lease(second_lease.id).calls),
            )
            _complete_operations(main, second_lease)
            main.accept_evidence(
                _envelope(main, second_lease), FakeOracle(OracleResult.SATISFIED)
            )
            self.assertIsNone(
                main.view.valid_state_handle(
                    requirement.key,
                    requirement.schema,
                    BoundLane.SIMULATOR,
                    preparation_id,
                )
            )

            third_lease = main.claim(
                BoundLane.SIMULATOR, SidekickID("sidekick:third"), now_millis=0
            )
            self.assertEqual("preparation", main.view.lease(third_lease.id).calls[0].phase)
            main.close()


class RuntimeEvidenceAndDagTests(unittest.TestCase):
    def test_envelope_resubmission_is_idempotent_and_conflicting_digest_rejected(self) -> None:
        with TemporaryDirectory() as temporary:
            main = open_run(_single_node_plan(), Path(temporary))
            lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:idempotent"),
                now_millis=0,
            )
            _complete_operations(main, lease)
            envelope = _envelope(main, lease)
            oracle = FakeOracle(OracleResult.SATISFIED)
            first = main.accept_evidence(envelope, oracle)
            second = main.accept_evidence(envelope, oracle)
            self.assertEqual(first, second)
            self.assertEqual(1, len(oracle.requests))

            conflict = _envelope(
                main, lease, data=b"different", path_suffix="-different"
            )
            with self.assertRaises(RegressionError) as raised:
                main.accept_evidence(conflict, oracle)
            self.assertEqual("runtime.envelope_conflict", raised.exception.code)
            main.close()

    def test_both_main_gate_unlocks_each_lane_without_waiting_for_join(self) -> None:
        simulator_gate = _node(
            "both-gate-simulator",
            (BoundLane.SIMULATOR,),
            critical=500,
        )
        device_gate = replace(
            _node(
                "both-gate-device",
                (BoundLane.DEVICE,),
                critical=500,
            ),
            scenario_id=simulator_gate.scenario_id,
            journey_id=simulator_gate.journey_id,
        )
        join = BothJoinNode(
            NodeID("node:both-gate-join"),
            simulator_gate.scenario_id,
            simulator_gate.journey_id,
            (simulator_gate.id, device_gate.id),
            400,
        )
        simulator_branch = _node(
            "simulator-after-gate",
            (BoundLane.SIMULATOR,),
            predecessors=(simulator_gate.id,),
            gates=(
                LaneGateDependency(
                    BoundLane.SIMULATOR,
                    simulator_gate.id,
                ),
            ),
            critical=300,
        )
        plan = _plan(
            (
                simulator_gate,
                device_gate,
                join,
                simulator_branch,
            ),
            (
                MainGateBinding(
                    BoundLane.SIMULATOR,
                    simulator_gate.scenario_id,
                    simulator_gate.id,
                ),
                MainGateBinding(
                    BoundLane.DEVICE,
                    device_gate.scenario_id,
                    device_gate.id,
                ),
            ),
        )

        with TemporaryDirectory() as temporary:
            main = open_run(plan, Path(temporary))
            simulator_gate_lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:simulator-gate"),
                now_millis=0,
            )
            self.assertEqual(simulator_gate.id, simulator_gate_lease.node_id)
            _complete_operations(main, simulator_gate_lease)
            main.accept_evidence(
                _envelope(main, simulator_gate_lease),
                FakeOracle(OracleResult.SATISFIED),
            )

            branch_lease = main.claim(
                BoundLane.SIMULATOR,
                SidekickID("sidekick:simulator-branch"),
                now_millis=0,
            )
            self.assertEqual(simulator_branch.id, branch_lease.node_id)
            self.assertEqual(NodeStatus.PENDING, main.view.node(device_gate.id).status)
            self.assertEqual(NodeStatus.PENDING, main.view.node(join.id).status)

            device_gate_lease = main.claim(
                BoundLane.DEVICE,
                SidekickID("sidekick:device-gate"),
                now_millis=0,
            )
            _complete_operations(main, device_gate_lease)
            main.accept_evidence(
                _envelope(main, device_gate_lease),
                FakeOracle(OracleResult.VIOLATED),
            )
            self.assertEqual(NodeStatus.LEASED, main.view.node(device_gate.id).status)
            self.assertEqual(
                (device_gate.id,),
                tuple(item.node_id for item in nodes_awaiting_adjudication(main.view)),
            )
            self.assertEqual(NodeStatus.PENDING, main.view.node(join.id).status)
            self.assertEqual(NodeStatus.LEASED, main.view.node(simulator_branch.id).status)

            _complete_operations(main, branch_lease)
            branch_receipt = main.accept_evidence(
                _envelope(main, branch_lease),
                FakeOracle(OracleResult.SATISFIED),
            )
            self.assertEqual(NodeStatus.PASSED, branch_receipt.node_status)
            main.close()

    def test_failed_ancestor_blocks_strict_successor_while_independent_branch_runs(self) -> None:
        gate = _node("gate", (BoundLane.SIMULATOR,), critical=500)
        failing = _node(
            "failing",
            (BoundLane.SIMULATOR,),
            predecessors=(gate.id,),
            gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
            critical=400,
        )
        successor = _node(
            "successor",
            (BoundLane.SIMULATOR,),
            predecessors=(gate.id, failing.id),
            gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
            critical=300,
        )
        independent = _node(
            "independent",
            (BoundLane.SIMULATOR,),
            predecessors=(gate.id,),
            gates=(LaneGateDependency(BoundLane.SIMULATOR, gate.id),),
            critical=100,
        )
        plan = _plan(
            (gate, failing, successor, independent),
            (MainGateBinding(BoundLane.SIMULATOR, gate.scenario_id, gate.id),),
        )

        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(plan, directory)
            _run_claimed_node(main, OracleResult.SATISFIED)
            failed_lease, _, _ = _run_claimed_node(main, OracleResult.VIOLATED)
            self.assertEqual(failing.id, failed_lease.node_id)
            self.assertEqual(NodeStatus.PENDING, main.view.node(successor.id).status)
            main.close()

            _append_verdict(
                directory,
                plan,
                _verdict_payload(
                    failed_lease.node_id, failed_lease.id, NodeStatus.FAILED
                ),
            )
            main = open_run(plan, directory)
            blocked = main.view.node(successor.id)
            self.assertEqual(NodeStatus.BLOCKED_BY, blocked.status)
            self.assertEqual((failing.id,), blocked.failure_ancestors)

            independent_lease, _, receipt = _run_claimed_node(
                main, OracleResult.SATISFIED
            )
            self.assertEqual(independent.id, independent_lease.node_id)
            self.assertEqual(NodeStatus.PASSED, receipt.node_status)
            self.assertEqual(RunOutcome.FAILED, main.finalize().outcome)

    def test_open_run_is_idempotent_for_same_plan_and_rejects_plan_conflict(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan = _single_node_plan()
            first = open_run(plan, directory)
            run_id = first.run_id
            first.close()
            second = open_run(plan, directory)
            self.assertEqual(run_id, second.run_id)
            second.close()

            different = _single_node_plan(calls=(_call("different"),))
            with self.assertRaises(RegressionError) as raised:
                open_run(different, directory)
            self.assertEqual("runtime.plan_conflict", raised.exception.code)


class CompatibilityTests(unittest.TestCase):
    def test_runtime_sources_parse_with_python_39_grammar(self) -> None:
        for filename in ("runtime.py", "runview.py"):
            path = SCRIPTS / "regression" / "core" / filename
            with self.subTest(path=path):
                ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
