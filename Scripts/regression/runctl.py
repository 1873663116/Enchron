#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from types import MappingProxyType
from typing import Any, Mapping, Optional, Sequence


if __package__ in (None, ""):
    scripts_root = Path(__file__).resolve().parents[1]
    if str(scripts_root) not in sys.path:
        sys.path.insert(0, str(scripts_root))

from regression.core.applicability import ReviewedFact
from regression.core.catalog import load_catalog
from regression.core.compiler import accept_reviews, compile_run
from regression.core.contracts import ArgumentValueKind, BoundLane
from regression.core.digest import canonical_bytes, canonical_digest
from regression.core.errors import RegressionError
from regression.core.ids import SidekickID
from regression.core.plan import CompileRequest, FullSelector, compiled_plan_bytes
from regression.core.replay import replay
from regression.core.review import (
    ReviewClass,
    ReviewUnitKind,
    approve_review_budgets,
    complete_reviews,
)
from regression.core.review_catalog import (
    build_catalog_review_units,
    plan_catalog_reviews,
)
from regression.core.runview import RunOutcome
from regression.execution_identity import (
    ExecutionIdentityError,
    PreparedLaneProvenance,
    freeze_execution_input,
    load_execution_input,
    prepare_build_provenance,
    write_execution_input,
)
from regression.oracle_agent import AgentOracleProvider
from regression.review_io import load_review_policy, load_review_receipts
from regression.review_stage import review_status
from regression.sidekick_runner import open_main_agent
from verification.regression_oracle_adapter import RegressionOracleAdapter


class RunControlError(ValueError):
    pass


@dataclass(frozen=True)
class LaneExecutionError:
    lane: BoundLane
    kind: str
    detail: str


@dataclass(frozen=True)
class LaneExecutionResult:
    receipts: tuple[Any, ...]
    errors: tuple[LaneExecutionError, ...]
    completed_by_lane: Mapping[BoundLane, int]


def _repository_path(repository: Path, value: Path, label: str) -> Path:
    candidate = Path(value)
    resolved = candidate.resolve() if candidate.is_absolute() else (repository / candidate).resolve()
    try:
        resolved.relative_to(repository)
    except ValueError as error:
        raise RunControlError(f"{label} must stay inside the repository") from error
    return resolved


def load_blueprint_fact_values(path: Path) -> Mapping[str, bool | int | str]:
    source_path = Path(path)
    if source_path.is_symlink() or not source_path.is_file():
        raise RunControlError("Catalog blueprint must be a current regular file")
    try:
        value = json.loads(source_path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RunControlError("Catalog blueprint must be valid UTF-8 JSON") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 2:
        raise RunControlError("Catalog blueprint schemaVersion must be 2")
    recorded = value.get("contentDigest")
    if not isinstance(recorded, str):
        raise RunControlError("Catalog blueprint has no content digest")
    unsigned = dict(value)
    unsigned.pop("contentDigest", None)
    if str(canonical_digest(unsigned)) != recorded:
        raise RunControlError("Catalog blueprint content digest is stale")
    facts = value.get("analysisFactValues")
    if not isinstance(facts, dict) or not facts:
        raise RunControlError("Catalog blueprint has no reviewed Fact values")
    result: dict[str, bool | int | str] = {}
    for identifier, fact_value in facts.items():
        if not isinstance(identifier, str) or not identifier.startswith("fact:"):
            raise RunControlError("Catalog blueprint has an invalid Fact identifier")
        if type(fact_value) not in (bool, int, str):
            raise RunControlError(
                f"Catalog blueprint Fact {identifier} has an unsupported value"
            )
        result[identifier] = fact_value
    return MappingProxyType(result)


def derive_reviewed_facts(
    catalog: Any,
    completed_review: Any,
    values: Mapping[str, bool | int | str],
) -> tuple[ReviewedFact, ...]:
    facts = tuple(catalog.facts)
    expected = {str(item.id) for item in facts}
    actual = set(values)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise RunControlError(
            "reviewed Fact values must cover the current Catalog exactly; "
            f"missing={missing}, extra={extra}"
        )
    receipts = {
        item.packet_digest: item for item in completed_review.receipts
    }
    human_receipts = {}
    for packet in completed_review.packets:
        if packet.reviewer is not ReviewClass.HUMAN_COVERAGE:
            continue
        receipt = receipts.get(packet.packet_digest)
        if receipt is None:
            raise RunControlError("HumanCoverage packet has no accepted receipt")
        for unit in packet.units:
            if unit.kind is ReviewUnitKind.FACT:
                if unit.ref in human_receipts:
                    raise RunControlError(
                        f"Fact {unit.ref} has more than one HumanCoverage receipt"
                    )
                human_receipts[unit.ref] = receipt

    reviewed = []
    for fact in sorted(facts, key=lambda item: str(item.id)):
        identifier = str(fact.id)
        value = values[identifier]
        expected_type = {
            ArgumentValueKind.BOOLEAN: bool,
            ArgumentValueKind.INTEGER: int,
            ArgumentValueKind.STRING: str,
        }[fact.value_type]
        if type(value) is not expected_type:
            raise RunControlError(
                f"reviewed Fact {identifier} does not match {fact.value_type.value}"
            )
        receipt = human_receipts.get(identifier)
        if receipt is None:
            raise RunControlError(
                f"reviewed Fact {identifier} has no HumanCoverage receipt"
            )
        reviewed.append(
            ReviewedFact(
                fact.id,
                value,
                fact.source_digest,
                receipt.receipt_digest,
            )
        )
    return tuple(reviewed)


def load_current_reviewed_catalog(
    repository_root: Path,
    catalog_root: Path,
    policy_path: Path,
    reviews_root: Path,
) -> tuple[Any, Any]:
    repository = Path(repository_root).resolve()
    catalog_path = _repository_path(repository, catalog_root, "Catalog root")
    policy = _repository_path(repository, policy_path, "review policy")
    reviews = _repository_path(repository, reviews_root, "reviews root")
    status = review_status(repository, catalog_path, policy, reviews)
    pending = {
        reviewer.value: count
        for reviewer, count in status.pending.items()
        if count
    }
    if pending:
        raise RunControlError(f"Catalog reviews are incomplete: {pending}")
    catalog = load_catalog(catalog_path)
    review_policy = load_review_policy(policy)
    planned = plan_catalog_reviews(catalog, review_policy)
    approved = approve_review_budgets(planned)
    completed = complete_reviews(
        build_catalog_review_units(catalog),
        approved,
        load_review_receipts(reviews),
        catalog.digest,
    )
    return accept_reviews(catalog, completed), completed


def compile_execution_plan(
    repository_root: Path,
    execution_input_path: Path,
    catalog_root: Path,
    policy_path: Path,
    reviews_root: Path,
    blueprint_path: Path,
) -> tuple[Any, Any]:
    repository = Path(repository_root).resolve()
    execution = load_execution_input(execution_input_path)
    reviewed_catalog, completed = load_current_reviewed_catalog(
        repository, catalog_root, policy_path, reviews_root
    )
    blueprint = _repository_path(repository, blueprint_path, "Catalog blueprint")
    facts = derive_reviewed_facts(
        reviewed_catalog.catalog,
        completed,
        load_blueprint_fact_values(blueprint),
    )
    request = CompileRequest(
        FullSelector(),
        facts,
        (BoundLane.SIMULATOR, BoundLane.DEVICE),
        execution.build_identity,
        execution.evidence_environment_identity,
    )
    return compile_run(reviewed_catalog, request), execution


def execute_lanes(coordinator: Any) -> LaneExecutionResult:
    condition = threading.Condition()
    progress = 0
    active = 0
    receipts = []
    errors = []
    completed = {BoundLane.SIMULATOR: 0, BoundLane.DEVICE: 0}

    def run_lane(lane: BoundLane) -> None:
        nonlocal progress, active
        ordinal = 0
        while True:
            with condition:
                snapshot = progress
                active += 1
            ordinal += 1
            try:
                receipt = coordinator.run_sidekick(
                    lane,
                    coordinator.lane_targets[lane],
                    SidekickID(f"sidekick:{lane.value}-{ordinal:04d}"),
                )
            except RegressionError as error:
                if error.code != "scheduler.no_ready_work":
                    with condition:
                        active -= 1
                        errors.append(
                            LaneExecutionError(lane, error.code, str(error))
                        )
                        progress += 1
                        condition.notify_all()
                    return
                with condition:
                    active -= 1
                    if progress != snapshot:
                        condition.notify_all()
                        continue
                    if active == 0:
                        condition.notify_all()
                        return
                    condition.wait_for(
                        lambda: progress != snapshot or active == 0,
                        timeout=1,
                    )
                    if progress == snapshot and active == 0:
                        return
                continue
            except Exception as error:
                with condition:
                    active -= 1
                    errors.append(
                        LaneExecutionError(lane, type(error).__name__, str(error))
                    )
                    progress += 1
                    condition.notify_all()
                return
            with condition:
                active -= 1
                receipts.append(receipt)
                completed[lane] += 1
                progress += 1
                condition.notify_all()

    workers = tuple(
        threading.Thread(
            target=run_lane,
            args=(lane,),
            name=f"regression-{lane.value}",
        )
        for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
    )
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join()
    return LaneExecutionResult(
        tuple(receipts),
        tuple(errors),
        MappingProxyType(dict(completed)),
    )


def _write_once(path: Path, source: bytes) -> Path:
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if destination.is_symlink() or not destination.is_file():
            raise RunControlError(f"output path is not a regular file: {destination}")
        if destination.read_bytes() != source:
            raise RunControlError(f"output already contains different bytes: {destination}")
        return destination
    with destination.open("xb") as output:
        output.write(source)
        output.flush()
        os.fsync(output.fileno())
    return destination


def _view_payload(view: Any) -> Mapping[str, Any]:
    return {
        "runId": None if view.run_id is None else str(view.run_id),
        "planDigest": None if view.plan_digest is None else str(view.plan_digest),
        "outcome": None if view.outcome is None else view.outcome.value,
        "eventCount": len(view.events),
        "nodes": [
            {
                "nodeId": str(item.node_id),
                "status": item.status.value,
                "lane": None if item.lane is None else item.lane.value,
                "leaseId": None if item.lease_id is None else str(item.lease_id),
                "failureAncestors": [str(value) for value in item.failure_ancestors],
            }
            for item in view.nodes
        ],
        "lanes": [
            {
                "lane": item.lane.value,
                "interrupted": item.interrupted,
                "interruptionReason": item.interruption_reason,
                "activeLeaseId": (
                    None if item.active_lease_id is None else str(item.active_lease_id)
                ),
            }
            for item in view.lanes
        ],
    }


def _assert_ignored_runtime_path(repository: Path, path: Path) -> Path:
    resolved = _repository_path(repository, path, "run directory")
    relative = resolved.relative_to(repository).as_posix()
    completed = subprocess.run(
        ["git", "-C", str(repository), "check-ignore", "--no-index", "-q", relative],
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RunControlError("run directory must be excluded from the source snapshot")
    return resolved


def _run_full(
    repository: Path,
    execution_input_path: Path,
    catalog_root: Path,
    policy_path: Path,
    reviews_root: Path,
    blueprint_path: Path,
    run_directory: Path,
) -> tuple[Mapping[str, Any], int]:
    plan, execution = compile_execution_plan(
        repository,
        execution_input_path,
        catalog_root,
        policy_path,
        reviews_root,
        blueprint_path,
    )
    run_root = _assert_ignored_runtime_path(repository, run_directory)
    provider = AgentOracleProvider(
        repository,
        run_root / "oracle-agent",
        model=execution.agent_model,
        executable=execution.agent_executable,
    )
    evaluator = RegressionOracleAdapter(provider)
    environment_keys = ("ENCHRON_ARTIFACT_ROOT", "ENCHRON_EXECUTION_INPUT")
    previous_environment = {key: os.environ.get(key) for key in environment_keys}
    os.environ["ENCHRON_ARTIFACT_ROOT"] = str(execution.artifact_root)
    os.environ["ENCHRON_EXECUTION_INPUT"] = str(
        Path(execution_input_path).resolve()
    )
    try:
        with open_main_agent(
            plan,
            run_root,
            execution.build_identity,
            execution.evidence_environment_identity,
            execution.lane_targets,
            evaluator,
        ) as coordinator:
            lane_result = execute_lanes(coordinator)
            load_execution_input(execution_input_path)
            view = coordinator.finalize()
    finally:
        for key, value in previous_environment.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    payload = {
        "schema": "enchron.regression.full-run-summary",
        "schemaVersion": 1,
        "catalogDigest": str(plan.catalog_digest),
        "catalogGateDigest": str(plan.catalog_gate_digest),
        "buildIdentityDigest": str(plan.build_identity.digest),
        "evidenceEnvironmentDigest": str(
            plan.evidence_environment_identity.digest
        ),
        "completedByLane": {
            lane.value: lane_result.completed_by_lane[lane]
            for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
        },
        "executionErrors": [
            {"lane": item.lane.value, "kind": item.kind, "detail": item.detail}
            for item in lane_result.errors
        ],
        "run": _view_payload(view),
    }
    _write_once(run_root / "summary.json", canonical_bytes(payload) + b"\n")
    passed = view.outcome is RunOutcome.PASSED and not lane_result.errors
    return payload, 0 if passed else 1


def _artifact_path(repository: Path, path: Path) -> Path:
    return path.resolve() if path.is_absolute() else (repository / path).resolve()


def _prepared_build_payload(
    artifact_root: Path, prepared: Sequence[PreparedLaneProvenance]
) -> Mapping[str, Any]:
    identity = prepared[0].identity
    toolchain = identity.toolchain
    return {
        "operation": "prepare-build",
        "artifactRoot": str(artifact_root),
        "gitRevision": identity.git_revision,
        "sourceTreeDigest": str(identity.source_tree_digest),
        "toolchain": {
            "xcodeVersion": toolchain.xcode_version,
            "xcodeBuild": toolchain.xcode_build,
            "visionOSSDKVersion": toolchain.visionos_sdk_version,
            "visionOSSDKBuild": toolchain.visionos_sdk_build,
            "visionOSSimulatorSDKVersion": (
                toolchain.visionos_simulator_sdk_version
            ),
            "visionOSSimulatorSDKBuild": toolchain.visionos_simulator_sdk_build,
        },
        "lanes": [
            {
                "lane": item.lane.value,
                "provenancePath": str(item.path),
                "provenanceDigest": str(item.digest),
                "xcodeBuildSetting": item.xcode_build_setting,
            }
            for item in prepared
        ],
    }


def _common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--repository-root", type=Path, default=Path.cwd())
    parser.add_argument("--catalog-root", type=Path, default=Path("Regression"))
    parser.add_argument(
        "--policy", type=Path, default=Path("Regression/review-policy.md")
    )
    parser.add_argument(
        "--blueprint", type=Path, default=Path("Config/regression/catalog-v2.json")
    )
    parser.add_argument("--reviews-root", type=Path, required=True)
    parser.add_argument("--execution-input", type=Path, required=True)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare builds, freeze execution input, compile, execute, and inspect "
            "Enchron Regression runs."
        )
    )
    commands = parser.add_subparsers(dest="operation", required=True)
    prepare = commands.add_parser("prepare-build")
    prepare.add_argument("--repository-root", type=Path, default=Path.cwd())
    prepare.add_argument("--artifact-root", type=Path, required=True)
    freeze = commands.add_parser("freeze")
    freeze.add_argument("--repository-root", type=Path, default=Path.cwd())
    freeze.add_argument("--artifact-root", type=Path, required=True)
    freeze.add_argument("--simulator-target", required=True)
    freeze.add_argument("--device-target", required=True)
    freeze.add_argument("--agent-model", required=True)
    freeze.add_argument("--agent-executable", default="codex")
    freeze.add_argument("--output", type=Path, required=True)
    compile_parser = commands.add_parser("compile")
    _common(compile_parser)
    compile_parser.add_argument("--output", type=Path, required=True)
    run_parser = commands.add_parser("run")
    _common(run_parser)
    run_parser.add_argument("--run-directory", type=Path, required=True)
    status_parser = commands.add_parser("status")
    status_parser.add_argument("--run-directory", type=Path, required=True)
    return parser


def _execute(arguments: argparse.Namespace) -> tuple[Mapping[str, Any], int]:
    if arguments.operation == "prepare-build":
        repository = arguments.repository_root.resolve()
        artifact_root = _artifact_path(repository, arguments.artifact_root)
        prepared = prepare_build_provenance(repository, artifact_root)
        return _prepared_build_payload(artifact_root, prepared), 0
    if arguments.operation == "freeze":
        repository = arguments.repository_root.resolve()
        artifact_root = _artifact_path(repository, arguments.artifact_root)
        value = freeze_execution_input(
            repository,
            artifact_root,
            {
                BoundLane.SIMULATOR: arguments.simulator_target,
                BoundLane.DEVICE: arguments.device_target,
            },
            arguments.agent_model,
            arguments.agent_executable,
        )
        output = arguments.output
        if not output.is_absolute():
            output = artifact_root / output
        write_execution_input(output, value)
        return {
            "operation": "freeze",
            "path": str(output.resolve()),
            "buildIdentityDigest": str(value.build_identity.digest),
            "evidenceEnvironmentDigest": str(
                value.evidence_environment_identity.digest
            ),
        }, 0
    if arguments.operation == "status":
        return {"operation": "status", "run": _view_payload(replay(arguments.run_directory))}, 0

    repository = arguments.repository_root.resolve()
    execution_input = arguments.execution_input
    if not execution_input.is_absolute():
        execution_input = repository / execution_input
    if arguments.operation == "compile":
        plan, _ = compile_execution_plan(
            repository,
            execution_input,
            arguments.catalog_root,
            arguments.policy,
            arguments.reviews_root,
            arguments.blueprint,
        )
        output = arguments.output
        if not output.is_absolute():
            output = repository / output
        _write_once(output, compiled_plan_bytes(plan) + b"\n")
        return {
            "operation": "compile",
            "path": str(output.resolve()),
            "planDigest": str(plan.plan_digest),
            "catalogDigest": str(plan.catalog_digest),
            "nodeCount": len(plan.nodes),
        }, 0
    return _run_full(
        repository,
        execution_input,
        arguments.catalog_root,
        arguments.policy,
        arguments.reviews_root,
        arguments.blueprint,
        arguments.run_directory,
    )


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = _parser()
    arguments = parser.parse_args(argv)
    try:
        payload, status = _execute(arguments)
    except (
        ExecutionIdentityError,
        RegressionError,
        RunControlError,
        OSError,
        subprocess.SubprocessError,
    ) as error:
        parser.exit(2, f"runctl: {error}\n")
    sys.stdout.buffer.write(canonical_bytes(payload) + b"\n")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
