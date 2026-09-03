from __future__ import annotations

from typing import Iterable, Mapping, Sequence

CAMPAIGN_TOKEN_ENV = "ENCHRON_CAMPAIGN_TOKEN"


def lane_targets(execution_input: Mapping[str, object]) -> set[str]:
    build_identity = (execution_input or {}).get("buildIdentity") or {}
    artifacts = build_identity.get("laneArtifacts") or []
    targets: set[str] = set()
    for artifact in artifacts:
        lane = artifact.get("lane") if isinstance(artifact, Mapping) else None
        if isinstance(lane, str) and lane:
            targets.add(lane)
    return targets


def partition_by_target(
    assignments: Iterable[Mapping[str, object]]
) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {}
    for assignment in assignments:
        target = str(assignment["target"])
        grouped.setdefault(target, []).append(str(assignment["segment"]))
    return grouped


def parallelizable_targets(
    frozen_lanes: set[str],
    pending_by_target: Mapping[str, Sequence[str]],
    reachable: Mapping[str, bool],
    worktrees: Mapping[str, str] | None = None,
) -> list[str]:
    qualifying = sorted(
        target
        for target, segments in pending_by_target.items()
        if segments and target in frozen_lanes and reachable.get(target, False)
    )
    if worktrees is None:
        return qualifying
    claimed: set[str] = set()
    isolated: list[str] = []
    for target in qualifying:
        worktree = worktrees.get(target)
        if worktree is None or worktree in claimed:
            continue
        claimed.add(worktree)
        isolated.append(target)
    return isolated


def parallelizable(
    frozen_lanes: set[str],
    pending_by_target: Mapping[str, Sequence[str]],
    reachable: Mapping[str, bool],
    worktrees: Mapping[str, str] | None = None,
) -> bool:
    return (
        len(
            parallelizable_targets(
                frozen_lanes, pending_by_target, reachable, worktrees
            )
        )
        >= 2
    )


def serial_run_refused(
    execution_input: Mapping[str, object],
    campaign: Mapping[str, object] | None,
    token: str | None,
    this_segment: str,
) -> str | None:
    if token:
        return None
    if not campaign:
        return None
    assignments = campaign.get("assignments") or []
    reachable = campaign.get("reachable") or {}
    worktrees = campaign.get("worktrees") or None
    frozen = lane_targets(execution_input)
    partitioned = partition_by_target(assignments)
    targets = parallelizable_targets(frozen, partitioned, reachable, worktrees)
    if len(targets) < 2:
        return None
    if not any(str(entry.get("segment")) == this_segment for entry in assignments):
        return None
    return serial_refusal_reason(targets)


def serial_refusal_reason(targets: Sequence[str]) -> str:
    joined = " and ".join(targets)
    return (
        f"{joined} each have pending segments on reachable hardware from one freeze, "
        "so they must run concurrently through the campaign launcher, not one segment "
        "at a time by hand. Launch the campaign; a bare serial segment stays refused "
        "while the lanes are parallelizable."
    )
