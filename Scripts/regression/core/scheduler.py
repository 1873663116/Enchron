from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Iterable, Mapping, Sequence, Tuple

from .contracts import BoundLane
from .errors import RegressionError
from .ids import NodeID


@dataclass(frozen=True)
class PlannedNode:
    id: NodeID
    cost_millis: int
    predecessors: Tuple[NodeID, ...]
    lane_candidates: Tuple[BoundLane, ...]
    runnable: bool = True

    def __post_init__(self) -> None:
        if type(self.cost_millis) is not int or self.cost_millis < 0:
            raise RegressionError(
                "scheduler.invalid_cost",
                str(self.id),
                "node cost must be a non-negative integer number of milliseconds",
            )
        if type(self.runnable) is not bool:
            raise RegressionError(
                "scheduler.invalid_runnable",
                str(self.id),
                "runnable must be a boolean",
            )
        if self.runnable and not self.lane_candidates:
            raise RegressionError(
                "scheduler.no_lane_candidate",
                str(self.id),
                "a runnable node must have at least one candidate lane",
            )
        if not self.runnable and self.lane_candidates:
            raise RegressionError(
                "scheduler.join_has_lane",
                str(self.id),
                "a non-runnable join node cannot name a candidate lane",
            )
        if len(self.lane_candidates) != len(set(self.lane_candidates)):
            raise RegressionError(
                "scheduler.duplicate_lane_candidate",
                str(self.id),
                "a node cannot name the same candidate lane twice",
            )
        if len(self.predecessors) != len(set(self.predecessors)):
            raise RegressionError(
                "scheduler.duplicate_predecessor",
                str(self.id),
                "a node cannot name the same predecessor twice",
            )


@dataclass(frozen=True)
class CriticalCost:
    node_id: NodeID
    remaining_millis: int


@dataclass(frozen=True)
class ReadyCandidate:
    node_id: NodeID
    lane_candidates: Tuple[BoundLane, ...]
    critical_remaining_millis: int
    reusable_state_count: int
    node_cost_millis: int

    def __post_init__(self) -> None:
        for name, value in (
            ("critical_remaining_millis", self.critical_remaining_millis),
            ("reusable_state_count", self.reusable_state_count),
            ("node_cost_millis", self.node_cost_millis),
        ):
            if type(value) is not int or value < 0:
                raise RegressionError(
                    "scheduler.invalid_ready_metric",
                    str(self.node_id),
                    f"{name} must be a non-negative integer",
                )


def compute_critical_costs(nodes: Sequence[PlannedNode]) -> Tuple[CriticalCost, ...]:
    by_id = _validated_nodes(nodes)
    successors = {node_id: [] for node_id in by_id}
    for node in by_id.values():
        for predecessor in node.predecessors:
            successors[predecessor].append(node.id)

    order = _topological_order(by_id)
    remaining: Dict[NodeID, int] = {}
    for node_id in reversed(order):
        tail = max((remaining[item] for item in successors[node_id]), default=0)
        remaining[node_id] = by_id[node_id].cost_millis + tail
    return tuple(
        CriticalCost(node_id, remaining[node_id])
        for node_id in sorted(remaining, key=str)
    )


def choose_ready(
    candidates: Iterable[ReadyCandidate], lane: BoundLane
) -> ReadyCandidate:
    eligible = tuple(
        candidate for candidate in candidates if lane in candidate.lane_candidates
    )
    if not eligible:
        raise RegressionError(
            "scheduler.no_ready_work",
            lane.value,
            "no ready candidate can run on this lane",
        )
    exclusive = tuple(
        candidate for candidate in eligible if candidate.lane_candidates == (lane,)
    )
    pool = exclusive or eligible
    return min(
        pool,
        key=lambda candidate: (
            -candidate.critical_remaining_millis,
            -candidate.reusable_state_count,
            -candidate.node_cost_millis,
            str(candidate.node_id),
        ),
    )


def _validated_nodes(nodes: Sequence[PlannedNode]) -> Mapping[NodeID, PlannedNode]:
    by_id: Dict[NodeID, PlannedNode] = {}
    for node in nodes:
        if node.id in by_id:
            raise RegressionError(
                "scheduler.duplicate_node",
                str(node.id),
                "a plan cannot contain the same node twice",
            )
        by_id[node.id] = node
    for node in nodes:
        missing = sorted(set(node.predecessors) - set(by_id), key=str)
        if missing:
            raise RegressionError(
                "scheduler.unknown_predecessor",
                str(node.id),
                "unknown predecessor(s): " + ", ".join(map(str, missing)),
            )
    return by_id


def _topological_order(nodes: Mapping[NodeID, PlannedNode]) -> Tuple[NodeID, ...]:
    permanent = set()
    active = []
    order = []

    def visit(node_id: NodeID) -> None:
        if node_id in permanent:
            return
        if node_id in active:
            start = active.index(node_id)
            cycle = active[start:] + [node_id]
            raise RegressionError(
                "scheduler.cycle",
                str(node_id),
                "dependency cycle: " + " -> ".join(map(str, cycle)),
            )
        active.append(node_id)
        for predecessor in sorted(nodes[node_id].predecessors, key=str):
            visit(predecessor)
        active.pop()
        permanent.add(node_id)
        order.append(node_id)

    for node_id in sorted(nodes, key=str):
        visit(node_id)
    return tuple(order)


__all__ = (
    "CriticalCost",
    "PlannedNode",
    "ReadyCandidate",
    "choose_ready",
    "compute_critical_costs",
)
