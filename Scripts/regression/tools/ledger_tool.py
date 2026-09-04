#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Mapping, Optional, Tuple

from regression.core.contracts import BoundLane
from regression.core.ids import NodeID, ScenarioID
from regression.core.events import EventType, now_rfc3339_millis
from regression.core.runtime import PLAN_FILENAME
from regression.core.ledger import LedgerWriter
from regression.core.replay import read_event_log, replay
from regression.core.runview import (
    NodeStatus,
    NodeView,
    RunView,
    build_run_view,
    nodes_awaiting_adjudication,
    settled_node_statuses,
)
from regression.tools.ledger_lock import (
    LaneLock,
    LedgerLockError,
    admit_reopen,
    admit_verdict,
    attempts,
    lane_lock_state,
    verdict_payload,
)
from regression.tools.bundle_tool import BundleError, frames_of
from regression.rubric_compiler import FieldPredicate
from regression.tools.known_defects import matching_defect
from regression.tools.verdict import Verdict


DERIVED_ONLY_STATUSES = (NodeStatus.FAILED_KNOWN,)


def write(
    run_directory: Path,
    verdict: Verdict,
    status: NodeStatus,
) -> Dict[str, Any]:
    directory = Path(run_directory)
    log = read_event_log(directory)
    if not log.events:
        raise LedgerLockError(f"{directory} holds no ledger to write a verdict into")
    with LedgerWriter(
        directory, log.run_id, log.plan_digest, build_run_view
    ) as writer:
        if status in DERIVED_ONLY_STATUSES:
            raise LedgerLockError(
                f"{status.value} is derived from the known defect ledger, not "
                "requested; write the failure and let the ledger decide"
            )
        current = build_run_view(writer.events)
        exemption = None
        if status is NodeStatus.FAILED:
            record = matching_defect(
                scenario_of(directory, verdict.node),
                verdict,
                recorded_fields(current, verdict.node),
            )
            if record is not None:
                status = NodeStatus.FAILED_KNOWN
                exemption = _exemption_payload(record)
        bundle_frame_count = bundled_frame_count(
            current, verdict.node, attempts(current, verdict.node) or 1
        )
        admit_verdict(current, verdict, status, bundle_frame_count)
        node = current.node(verdict.node)
        writer.append(
            EventType.VERDICT_RECORDED,
            verdict_payload(
                str(node.lease_id), verdict, status, bundle_frame_count, exemption
            ),
            now_rfc3339_millis(),
            f"verdict:{verdict.node}:{attempts(current, verdict.node)}",
        )
        return projection(build_run_view(writer.events))


def _exemption_payload(record) -> dict:
    """The record that exempted a failure goes into the ledger beside the
    verdict, so a replay can read which record spoke rather than inferring it
    from a signature the verdict happened to carry."""
    match = record.match
    return {
        "scenario": str(record.scenario),
        "match": match.payload() if isinstance(match, FieldPredicate) else str(match),
    }


def bundled_frame_count(current: RunView, node: NodeID, attempt: int) -> int:
    """The frame a verdict names is bounded by the montage the reviewer sees,
    and the montage is built from the run, so the bound is read, not stated."""
    try:
        return len(frames_of(current, node, attempt))
    except BundleError:
        return 0


def scenario_of(run_directory: Path, node: NodeID) -> Optional[ScenarioID]:
    path = Path(run_directory) / PLAN_FILENAME
    if not path.is_file():
        return None
    payload = json.loads(path.read_text(encoding="utf-8"))
    for item in payload.get("nodes", []):
        if isinstance(item, Mapping) and item.get("id") == str(node):
            found = item.get("scenarioId")
            return None if found is None else ScenarioID(str(found))
    return None


def recorded_fields(current: RunView, node: NodeID) -> Mapping[str, Any]:
    found = next((item for item in current.nodes if item.node_id == node), None)
    if found is None or found.lease_id is None:
        return {}
    completed = [
        item
        for item in current.lease(found.lease_id).invocations
        if item.completed and item.outputs is not None
    ]
    if not completed:
        return {}
    return dict(completed[-1].outputs.payload())


def reopen(run_directory: Path, node: NodeID) -> Dict[str, Any]:
    directory = Path(run_directory)
    log = read_event_log(directory)
    if not log.events:
        raise LedgerLockError(f"{directory} holds no ledger to reopen a node in")
    with LedgerWriter(
        directory, log.run_id, log.plan_digest, build_run_view
    ) as writer:
        current = build_run_view(writer.events)
        admit_reopen(current, node)
        attempt = attempts(current, node)
        writer.append(
            EventType.NODE_REOPENED,
            {"nodeId": str(node), "attemptsBefore": attempt},
            now_rfc3339_millis(),
            f"reopen:{node}:{attempt}",
        )
        return projection(build_run_view(writer.events))


def view(
    run_directory: Path, lane: Optional[BoundLane] = None
) -> Dict[str, Any]:
    return projection(replay(Path(run_directory)), lane)


def resume(run_directory: Path) -> Dict[str, Any]:
    current = replay(Path(run_directory))
    locks = {item.lane: lane_lock_state(current, item.lane) for item in current.lanes}
    statuses = settled_node_statuses(current)
    ready = tuple(
        node.node_id
        for node in current.nodes
        if statuses.get(node.node_id) is NodeStatus.PENDING
        and _predecessors_passed(node, statuses)
        and _open_lanes(node, statuses, locks)
    )
    return {
        "ready": [str(item) for item in ready],
        "awaitingVerdict": [
            str(item.node_id) for item in nodes_awaiting_adjudication(current)
        ],
    }


def projection(
    current: RunView, lane: Optional[BoundLane] = None
) -> Dict[str, Any]:
    lanes = tuple(
        item for item in current.lanes if lane is None or item.lane is lane
    )
    selected = frozenset(item.lane for item in lanes)
    return {
        "nodes": [
            {
                "node": str(item.node_id),
                "status": item.status.value,
                "lane": None if item.lane is None else item.lane.value,
                "failureAncestors": [str(value) for value in item.failure_ancestors],
                "adjudication": _adjudication_payload(item),
            }
            for item in current.nodes
            if item.lane is None or item.lane in selected
        ],
        "lanes": [
            {
                "lane": item.lane.value,
                "interrupted": item.interrupted,
                "interruptionReason": item.interruption_reason,
                "activeLease": (
                    None
                    if item.active_lease_id is None
                    else str(item.active_lease_id)
                ),
            }
            for item in lanes
        ],
        "locks": [
            _lock_payload(lane_lock_state(current, item.lane)) for item in lanes
        ],
    }


def _adjudication_payload(node: NodeView) -> Optional[Dict[str, Any]]:
    found = node.adjudication
    if found is None:
        return None
    return {
        "attribution": found.attribution.value,
        "bundleFrameCount": found.bundle_frame_count,
        "firstDeviantFrame": found.first_deviant_frame,
        "regionObservation": found.region_observation,
        "signature": None if found.signature is None else str(found.signature),
        **(
            {}
            if found.known_defect is None
            else {"knownDefect": dict(found.known_defect)}
        ),
    }


def _lock_payload(lock: LaneLock) -> Dict[str, Any]:
    return {
        "lane": lock.lane.value,
        "locked": lock.locked,
        "state": lock.state.value,
        "pendingNode": None if lock.pending_node is None else str(lock.pending_node),
        "reason": lock.reason,
    }


def _predecessors_passed(node: NodeView, statuses) -> bool:
    gates = frozenset(item.node_id for item in node.gate_dependencies)
    return all(
        statuses.get(item) is NodeStatus.PASSED
        for item in node.predecessors
        if item not in gates
    )


def _open_lanes(node: NodeView, statuses, locks) -> Tuple[BoundLane, ...]:
    open_lanes = []
    for candidate in node.lane_candidates:
        lock = locks.get(candidate)
        if lock is None or lock.locked:
            continue
        gate = next(
            (item for item in node.gate_dependencies if item.lane is candidate), None
        )
        if gate is not None and statuses.get(gate.node_id) is not NodeStatus.PASSED:
            continue
        open_lanes.append(candidate)
    return tuple(open_lanes)


__all__ = (
    "projection",
    "recorded_fields",
    "reopen",
    "resume",
    "scenario_of",
    "view",
    "write",
)
