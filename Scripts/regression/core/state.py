from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Mapping, Tuple

from .contracts import BoundLane
from .errors import RegressionError
from .ids import (
    Digest,
    NodeID,
    StateKey,
    StateSchema,
    StateTag,
    parse_identifier,
    parse_state_key,
    parse_state_schema,
)


@dataclass(frozen=True)
class TagEpoch:
    tag: StateTag
    value: int

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "tag",
            StateTag(parse_identifier("state_tag", self.tag, "tagEpoch.tag")),
        )
        if type(self.value) is not int or self.value < 0:
            raise RegressionError(
                "epoch.invalid_value",
                str(self.tag),
                "an epoch must be a non-negative integer",
            )


@dataclass(frozen=True)
class EpochTable:
    entries: Tuple[TagEpoch, ...] = ()

    def __post_init__(self) -> None:
        tags = tuple(str(entry.tag) for entry in self.entries)
        if tags != tuple(sorted(tags)):
            raise RegressionError(
                "epoch.unsorted_tags",
                "$epochs",
                "epoch tags must be in stable lexical order",
            )
        if len(tags) != len(set(tags)):
            raise RegressionError(
                "epoch.duplicate_tag",
                "$epochs",
                "an epoch table cannot contain a tag twice",
            )

    @classmethod
    def from_mapping(cls, values: Mapping[StateTag, int]) -> "EpochTable":
        return cls(
            tuple(
                TagEpoch(StateTag(tag), value)
                for tag, value in sorted(values.items(), key=lambda item: str(item[0]))
            )
        )

    def as_mapping(self) -> Mapping[StateTag, int]:
        return {entry.tag: entry.value for entry in self.entries}

    def value(self, tag: StateTag) -> int:
        for entry in self.entries:
            if entry.tag == tag:
                return entry.value
        return 0

    def snapshot(self, tags: Iterable[StateTag]) -> "EpochTable":
        unique = sorted(set(tags), key=str)
        return EpochTable(tuple(TagEpoch(tag, self.value(tag)) for tag in unique))

    def advance(self, tags: Iterable[StateTag]) -> "EpochTransition":
        values = dict(self.as_mapping())
        advances = []
        for tag in sorted(set(tags), key=str):
            before = values.get(tag, 0)
            after = before + 1
            values[tag] = after
            advances.append(TagEpochAdvanced(tag, before, after))
        return EpochTransition(EpochTable.from_mapping(values), tuple(advances))


@dataclass(frozen=True)
class TagEpochAdvanced:
    tag: StateTag
    before: int
    after: int

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "tag",
            StateTag(parse_identifier("state_tag", self.tag, "tagEpochAdvanced.tag")),
        )
        if (
            type(self.before) is not int
            or type(self.after) is not int
            or self.before < 0
        ):
            raise RegressionError(
                "epoch.invalid_transition",
                str(self.tag),
                "an epoch transition needs non-negative integer values",
            )
        if self.after != self.before + 1:
            raise RegressionError(
                "epoch.non_monotonic_advance",
                str(self.tag),
                "a tag advance must increment exactly once",
            )


@dataclass(frozen=True)
class EpochTransition:
    table: EpochTable
    advances: Tuple[TagEpochAdvanced, ...]


@dataclass(frozen=True)
class StateHandle:
    key: StateKey
    schema: StateSchema
    lane: BoundLane
    produced_by_node: NodeID
    dependencies: EpochTable
    fingerprint: Digest

    def __post_init__(self) -> None:
        key = parse_state_key(self.key, "stateHandle.key")
        object.__setattr__(self, "key", key)
        object.__setattr__(
            self,
            "schema",
            parse_state_schema(self.schema, f"stateHandle.{key}.schema"),
        )
        if not isinstance(self.lane, BoundLane):
            raise RegressionError(
                "state.invalid_lane",
                str(key),
                "a state handle must belong to a concrete lane",
            )
        object.__setattr__(
            self,
            "produced_by_node",
            NodeID(
                parse_identifier(
                    "node",
                    self.produced_by_node,
                    f"stateHandle.{key}.producedByNode",
                )
            ),
        )
        if not isinstance(self.dependencies, EpochTable):
            raise RegressionError(
                "state.invalid_dependencies",
                str(key),
                "state dependencies must be an epoch table",
            )
        if not self.dependencies.entries:
            raise RegressionError(
                "state.empty_dependencies",
                str(key),
                "a reusable state handle must depend on an invalidation tag",
            )
        object.__setattr__(
            self,
            "fingerprint",
            Digest(
                parse_identifier(
                    "digest", self.fingerprint, f"stateHandle.{key}.fingerprint"
                )
            ),
        )

    def is_valid(
        self,
        key: StateKey,
        schema: StateSchema,
        lane: BoundLane,
        current: EpochTable,
    ) -> bool:
        if key != self.key or schema != self.schema or lane is not self.lane:
            return False
        return all(
            current.value(entry.tag) == entry.value
            for entry in self.dependencies.entries
        )


def capture_state_handle(
    key: StateKey,
    schema: StateSchema,
    lane: BoundLane,
    produced_by_node: NodeID,
    current: EpochTable,
    depends_on: Iterable[StateTag],
    fingerprint: Digest,
) -> StateHandle:
    return StateHandle(
        key,
        schema,
        lane,
        produced_by_node,
        current.snapshot(depends_on),
        fingerprint,
    )


__all__ = (
    "EpochTable",
    "EpochTransition",
    "StateHandle",
    "TagEpoch",
    "TagEpochAdvanced",
    "capture_state_handle",
)
