#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from regression.core.contracts import BoundLane
from regression.core.events import EventType, now_rfc3339_millis
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
    admit_verdict,
    lane_lock_state,
    verdict_payload,
)
from regression.tools.verdict import Verdict


def write(
    run_directory: Path,
    verdict: Verdict,
    status: NodeStatus,
    bundle_frame_count: int,
) -> Dict[str, Any]:
    directory = Path(run_directory)
    log = read_event_log(directory)
    if not log.events:
        raise LedgerLockError(f"{directory} holds no ledger to write a verdict into")
    with LedgerWriter(
        directory, log.run_id, log.plan_digest, build_run_view
    ) as writer:
        current = build_run_view(writer.events)
        admit_verdict(current, verdict, status, bundle_frame_count)
        node = current.node(verdict.node)
        writer.append(
            EventType.VERDICT_RECORDED,
            verdict_payload(
                str(node.lease_id), verdict, status, bundle_frame_count
            ),
            now_rfc3339_millis(),
            f"verdict:{verdict.node}",
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


__all__ = ("projection", "resume", "view", "write")
