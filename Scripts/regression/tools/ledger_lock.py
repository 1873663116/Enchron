#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from regression.core.contracts import BoundLane
from regression.core.ids import NodeID
from regression.core.runview import (
    ADJUDICATED_NODE_STATUSES,
    NodeStatus,
    RunView,
    awaiting_adjudication,
    settled_oracle_result,
)
from regression.tools.verdict import Verdict


LOCKED_UNTIL_ADJUDICATED = (
    "this lane holds a node whose Oracle result was not satisfied; it stays closed "
    "to further operations until the ledger receives that node's verdict"
)
LOCKED_BY_INTERRUPTION = "this lane was interrupted and accepts no further work"
LOCKED_BY_RUN_CLOSURE = "this run is closed and no lane accepts further work"
LOCKED_WHILE_UNDETERMINED = (
    "this lane holds a lease whose evidence was accepted and whose Oracle "
    "evaluation was never closed into a verdict; reopening the run settles it "
    "and no adjudication is owed"
)
LOCKED_WHILE_WORKING = "this lane holds a lease that is still running its operations"
UNLOCKED = "this lane holds no lease and owes no verdict"


class LedgerLockError(ValueError):
    pass


@dataclass(frozen=True)
class LaneLock:
    lane: BoundLane
    locked: bool
    pending_node: Optional[NodeID]
    reason: str


def lane_lock_state(view: RunView, lane: BoundLane) -> LaneLock:
    if not isinstance(lane, BoundLane):
        raise LedgerLockError("a lane lock is read for one concrete lane")
    if view.closed:
        return LaneLock(lane, True, None, LOCKED_BY_RUN_CLOSURE)
    nodes = {item.node_id: item for item in view.nodes}
    for lease in view.leases:
        if lease.lane is not lane:
            continue
        node = nodes.get(lease.node_id)
        if node is None or node.status is not NodeStatus.LEASED:
            continue
        if awaiting_adjudication(node, lease):
            return LaneLock(lane, True, node.node_id, LOCKED_UNTIL_ADJUDICATED)
        if view.lane(lane).interrupted:
            break
        if lease.evidence_accepted and lease.oracle_evaluations:
            return LaneLock(lane, True, None, LOCKED_WHILE_UNDETERMINED)
        return LaneLock(lane, True, None, LOCKED_WHILE_WORKING)
    if view.lane(lane).interrupted:
        return LaneLock(lane, True, None, LOCKED_BY_INTERRUPTION)
    return LaneLock(lane, False, None, UNLOCKED)


def admit_verdict(
    view: RunView,
    verdict: Verdict,
    status: NodeStatus,
    bundle_frame_count: int,
) -> None:
    if not isinstance(verdict, Verdict):
        raise LedgerLockError("the ledger admits a Verdict")
    if not isinstance(status, NodeStatus):
        raise LedgerLockError("the ledger admits a NodeStatus")
    if type(bundle_frame_count) is not int or bundle_frame_count < 1:
        raise LedgerLockError("the montage frame count must be a positive integer")

    node = next(
        (item for item in view.nodes if item.node_id == verdict.node), None
    )
    if node is None:
        raise LedgerLockError(f"the run holds no node {verdict.node}")
    lease = next(
        (item for item in view.leases if item.node_id == node.node_id), None
    )
    if not awaiting_adjudication(node, lease):
        raise LedgerLockError(
            f"node {verdict.node} carries the status {node.status.value} and owes "
            "no verdict"
        )

    settled = settled_oracle_result(node, lease)
    admissible = ADJUDICATED_NODE_STATUSES[settled]
    if status not in admissible:
        allowed = ", ".join(item.value for item in admissible)
        raise LedgerLockError(
            f"the Oracle result for {verdict.node} was {settled.value}, which the "
            f"ledger closes as {allowed}, not as {status.value}"
        )
    if not verdict.region_observation.strip():
        raise LedgerLockError(
            "a verdict states what the cropped region showed; that observation is empty"
        )
    frame = verdict.first_deviant_frame
    if frame is not None and frame >= bundle_frame_count:
        raise LedgerLockError(
            f"the first deviant frame {frame} is outside the {bundle_frame_count} "
            "frames the montage holds"
        )
    if status is NodeStatus.FAILED_KNOWN and verdict.signature is None:
        raise LedgerLockError(
            "a known defect verdict names the signature it matched"
        )


def verdict_payload(
    node_lease_id: str,
    verdict: Verdict,
    status: NodeStatus,
    bundle_frame_count: int,
) -> dict:
    return {
        "nodeId": str(verdict.node),
        "leaseId": node_lease_id,
        "status": status.value,
        "failureAncestors": [],
        "adjudication": {
            "attribution": verdict.attribution.value,
            "bundleFrameCount": bundle_frame_count,
            "firstDeviantFrame": verdict.first_deviant_frame,
            "regionObservation": verdict.region_observation,
            "signature": (
                None if verdict.signature is None else str(verdict.signature)
            ),
        },
    }


__all__ = (
    "LOCKED_BY_INTERRUPTION",
    "LOCKED_BY_RUN_CLOSURE",
    "LOCKED_UNTIL_ADJUDICATED",
    "LOCKED_WHILE_UNDETERMINED",
    "LOCKED_WHILE_WORKING",
    "UNLOCKED",
    "LaneLock",
    "LedgerLockError",
    "admit_verdict",
    "lane_lock_state",
    "verdict_payload",
)
