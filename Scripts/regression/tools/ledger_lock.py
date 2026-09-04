#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional

from regression.core.contracts import BoundLane
from regression.core.ids import NodeID
from regression.core.runview import (
    ADJUDICATED_NODE_STATUSES,
    MAX_NODE_ATTEMPTS,
    NodeStatus,
    RunView,
    attempts_of,
    awaiting_adjudication,
    deferrable_from,
    current_lease,
    reopen_refusal,
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


class LaneLockState(Enum):
    OPEN = "open"
    WORKING = "working"
    UNDETERMINED = "undetermined"
    AWAITING_VERDICT = "awaitingVerdict"
    INTERRUPTED = "interrupted"
    CLOSED = "closed"


STATES_REFUSING_AN_OPERATION = (
    LaneLockState.UNDETERMINED,
    LaneLockState.AWAITING_VERDICT,
    LaneLockState.INTERRUPTED,
    LaneLockState.CLOSED,
)


class LedgerLockError(ValueError):
    pass


@dataclass(frozen=True)
class LaneLock:
    lane: BoundLane
    state: LaneLockState
    pending_node: Optional[NodeID]
    reason: str

    @property
    def locked(self) -> bool:
        return self.state is not LaneLockState.OPEN

    @property
    def refuses_an_operation(self) -> bool:
        return self.state in STATES_REFUSING_AN_OPERATION


def lane_lock_state(view: RunView, lane: BoundLane) -> LaneLock:
    if not isinstance(lane, BoundLane):
        raise LedgerLockError("a lane lock is read for one concrete lane")
    if view.closed:
        return LaneLock(lane, LaneLockState.CLOSED, None, LOCKED_BY_RUN_CLOSURE)
    nodes = {item.node_id: item for item in view.nodes}
    for lease in view.leases:
        if lease.lane is not lane:
            continue
        node = nodes.get(lease.node_id)
        if (
            node is None
            or node.status is not NodeStatus.LEASED
            or node.lease_id != lease.lease_id
        ):
            continue
        if awaiting_adjudication(node, lease):
            return LaneLock(lane, LaneLockState.AWAITING_VERDICT, node.node_id, LOCKED_UNTIL_ADJUDICATED)
        if view.lane(lane).interrupted:
            break
        if lease.evidence_accepted and lease.oracle_evaluations:
            return LaneLock(lane, LaneLockState.UNDETERMINED, None, LOCKED_WHILE_UNDETERMINED)
        return LaneLock(lane, LaneLockState.WORKING, None, LOCKED_WHILE_WORKING)
    if view.lane(lane).interrupted:
        return LaneLock(lane, LaneLockState.INTERRUPTED, None, LOCKED_BY_INTERRUPTION)
    return LaneLock(lane, LaneLockState.OPEN, None, UNLOCKED)


def attempts(view: RunView, node: NodeID) -> int:
    return sum(1 for item in view.leases if item.node_id == node)


def deferrable(view: RunView, node: NodeID) -> bool:
    return deferrable_from(node, {item.lease_id: item for item in view.leases})


def admit_reopen(view: RunView, node: NodeID) -> None:
    found = next((item for item in view.nodes if item.node_id == node), None)
    refusal = reopen_refusal(
        found, attempts(view, node), {item.lane: item for item in view.lanes}
    )
    if refusal is not None:
        raise LedgerLockError(refusal)


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
    if type(bundle_frame_count) is not int or bundle_frame_count < 0:
        raise LedgerLockError("the montage frame count is derived from the run")

    node = next(
        (item for item in view.nodes if item.node_id == verdict.node), None
    )
    if node is None:
        raise LedgerLockError(f"the run holds no node {verdict.node}")
    lease = current_lease(view, node)
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
    if status is NodeStatus.DEFERRED_HUMAN and not deferrable(view, verdict.node):
        raise LedgerLockError(
            f"{verdict.node} reaches the human layer only after two consecutive "
            "attempts that both timed out on the harness"
        )
    if not verdict.region_observation.strip():
        raise LedgerLockError(
            "a verdict states what the cropped region showed; that observation is empty"
        )
    frame = verdict.first_deviant_frame
    if frame is not None and bundle_frame_count == 0:
        raise LedgerLockError(
            f"the bundle for {verdict.node} holds no frame, so frame {frame} names "
            "nothing a reviewer can look at"
        )
    if frame is not None and frame >= bundle_frame_count:
        raise LedgerLockError(
            f"the first deviant frame {frame} is outside the {bundle_frame_count} "
            "frames the montage holds"
        )



def verdict_payload(
    node_lease_id: str,
    verdict: Verdict,
    status: NodeStatus,
    bundle_frame_count: int,
    known_defect: Optional[dict] = None,
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
            **({} if known_defect is None else {"knownDefect": known_defect}),
        },
    }


__all__ = (
    "MAX_NODE_ATTEMPTS",
    "LOCKED_BY_INTERRUPTION",
    "LOCKED_BY_RUN_CLOSURE",
    "LOCKED_UNTIL_ADJUDICATED",
    "LOCKED_WHILE_UNDETERMINED",
    "LOCKED_WHILE_WORKING",
    "UNLOCKED",
    "LaneLock",
    "LaneLockState",
    "LedgerLockError",
    "STATES_REFUSING_AN_OPERATION",
    "admit_reopen",
    "admit_verdict",
    "attempts",
    "deferrable",
    "lane_lock_state",
    "verdict_payload",
)
