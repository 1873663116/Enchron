#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Iterable, Mapping, Tuple

from regression.core.digest import canonical_digest
from regression.core.ids import Digest, NodeID
from regression.core.runview import Attribution, NodeStatus, RunView

CHECKLIST_SCHEMA = "enchron.regression.human-checklist"
RECEIPT_SCHEMA = "enchron.regression.human-receipt"


class HumanReceiptError(ValueError):
    pass


@dataclass(frozen=True)
class Checklist:
    deferred: Tuple[NodeID, ...]
    widened: Tuple[NodeID, ...]

    @property
    def nodes(self) -> Tuple[NodeID, ...]:
        return tuple(sorted(set(self.deferred) | set(self.widened), key=str))

    def digest(self) -> Digest:
        return canonical_digest(
            {
                "schema": CHECKLIST_SCHEMA,
                "deferred": [str(item) for item in sorted(self.deferred, key=str)],
                "widened": [str(item) for item in sorted(self.widened, key=str)],
            }
        )


@dataclass(frozen=True)
class NodeAttribution:
    node: NodeID
    attribution: Attribution
    description: str
    frames: Tuple[int, ...]

    def payload(self) -> Dict[str, Any]:
        return {
            "node": str(self.node),
            "attribution": self.attribution.value,
            "description": self.description,
            "frames": list(self.frames),
        }


@dataclass(frozen=True)
class HumanReceipt:
    checklist_digest: Digest
    build_digest: Digest
    device_id: str
    recording_digest: Digest
    attributions: Tuple[NodeAttribution, ...]

    def covered(self) -> Tuple[NodeID, ...]:
        return tuple(sorted({item.node for item in self.attributions}, key=str))

    def payload(self) -> Dict[str, Any]:
        return {
            "schema": RECEIPT_SCHEMA,
            "schemaVersion": 1,
            "checklistDigest": str(self.checklist_digest),
            "buildDigest": str(self.build_digest),
            "deviceId": self.device_id,
            "recordingDigest": str(self.recording_digest),
            "attributions": [item.payload() for item in self.attributions],
        }


def build_checklist(
    view: RunView, widened: Iterable[NodeID] = ()
) -> Checklist:
    deferred = tuple(
        node.node_id
        for node in view.nodes
        if node.status is NodeStatus.DEFERRED_HUMAN
    )
    extra = tuple(NodeID(str(item)) for item in widened)
    unknown = sorted(
        str(item)
        for item in set(extra)
        if all(node.node_id != item for node in view.nodes)
    )
    if unknown:
        raise HumanReceiptError(
            "the checklist was widened to " + ", ".join(unknown) + ", which this run "
            "does not hold"
        )
    return Checklist(tuple(sorted(deferred, key=str)), tuple(sorted(set(extra), key=str)))


def seal(
    checklist: Checklist,
    build_digest: Digest,
    device_id: str,
    recording_digest: Digest,
    attributions: Iterable[NodeAttribution],
) -> HumanReceipt:
    if not isinstance(checklist, Checklist):
        raise HumanReceiptError("a receipt seals one Checklist")
    for value, label in (
        (build_digest, "build digest"),
        (recording_digest, "recording digest"),
    ):
        if not isinstance(value, str) or not value.startswith("sha256:"):
            raise HumanReceiptError(f"a receipt names its {label}")
    if not isinstance(device_id, str) or not device_id.strip():
        raise HumanReceiptError("a receipt names the device the wearer used")
    recorded = tuple(attributions)
    for item in recorded:
        if not isinstance(item, NodeAttribution):
            raise HumanReceiptError("every attribution is a NodeAttribution")
        if not item.description.strip():
            raise HumanReceiptError(
                f"{item.node} carries no description of what the wearer saw"
            )
    covered = {item.node for item in recorded}
    missing = sorted(str(item) for item in set(checklist.nodes) - covered)
    if missing:
        raise HumanReceiptError(
            "the checklist holds " + ", ".join(missing) + " with no attribution"
        )
    return HumanReceipt(
        checklist.digest(),
        build_digest,
        device_id,
        recording_digest,
        tuple(sorted(recorded, key=lambda item: str(item.node))),
    )


def _digest_field(payload: Mapping[str, Any], key: str, label: str) -> Digest:
    value = payload[key]
    if not isinstance(value, str) or not value.startswith("sha256:"):
        raise HumanReceiptError(f"a receipt names its {label} as a sha256 digest")
    return Digest(value)


def load_receipt(payload: Mapping[str, Any]) -> HumanReceipt:
    if not isinstance(payload, Mapping) or payload.get("schema") != RECEIPT_SCHEMA:
        raise HumanReceiptError(f"a human receipt is a {RECEIPT_SCHEMA} document")
    try:
        return HumanReceipt(
            _digest_field(payload, "checklistDigest", "checklist digest"),
            _digest_field(payload, "buildDigest", "build digest"),
            str(payload["deviceId"]),
            _digest_field(payload, "recordingDigest", "recording digest"),
            tuple(
                NodeAttribution(
                    NodeID(str(item["node"])),
                    Attribution(item["attribution"]),
                    str(item["description"]),
                    tuple(int(value) for value in item.get("frames", ())),
                )
                for item in payload["attributions"]
            ),
        )
    except (KeyError, TypeError, ValueError) as error:
        raise HumanReceiptError(f"the human receipt is malformed: {error}") from error


__all__ = (
    "CHECKLIST_SCHEMA",
    "RECEIPT_SCHEMA",
    "Checklist",
    "HumanReceipt",
    "HumanReceiptError",
    "NodeAttribution",
    "build_checklist",
    "load_receipt",
    "seal",
)
