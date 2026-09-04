#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Any, Dict, Mapping, Optional, Tuple

from regression.core.ids import CallID, NodeID, SignatureID
from regression.core.replay import replay
from regression.core.runview import LeaseView, OperationInvocationView, RunView
from regression.tools.op_tool import screenshot_bytes
from regression.tools.pixel_heuristics import all_black, capture_failed, frame_delta
from regression.tools.raster import (
    RasterError,
    decode_png,
    encode_png,
    scale_down,
    tile,
)
from regression.tools.signatures import FRAME_UNCHANGED

MONTAGE_COLUMNS = 2
MONTAGE_REDUCTION = 4
UNCHANGED_FRAME_DELTA = 0.002
NO_BASELINE = None

CROP_REFUSAL = (
    "the matched element reports its frame in points and no field of the "
    "operation response records the screen size in points, so no point to pixel "
    "scale can be derived from this run; the crop is left out rather than cut at "
    "a guessed scale"
)


class BundleError(ValueError):
    pass


@dataclass(frozen=True)
class BundleImage:
    caption: str
    png: bytes


@dataclass(frozen=True)
class ExceptionBundle:
    node: NodeID
    attempt: int
    call: CallID
    before_after: Tuple[BundleImage, ...] = ()
    contact_sheet: Optional[BundleImage] = None
    frame_count: int = 0
    crops: Tuple[BundleImage, ...] = ()
    crop_refusal: Optional[str] = None
    field_diff: Mapping[str, Any] = MappingProxyType({})
    matched_signature: Tuple[SignatureID, ...] = ()

    def images(self) -> Tuple[BundleImage, ...]:
        montage = () if self.contact_sheet is None else (self.contact_sheet,)
        return self.before_after + montage + self.crops

    def payload(self) -> Dict[str, Any]:
        return {
            "node": str(self.node),
            "attempt": self.attempt,
            "call": str(self.call),
            "beforeAfter": [item.caption for item in self.before_after],
            "contactSheet": (
                None if self.contact_sheet is None else self.contact_sheet.caption
            ),
            "frameCount": self.frame_count,
            "crops": [item.caption for item in self.crops],
            "cropRefusal": self.crop_refusal,
            "fieldDiff": {
                key: list(value) for key, value in sorted(self.field_diff.items())
            },
            "matchedSignature": [str(item) for item in self.matched_signature],
        }


def run(run_directory: Path, node: NodeID, attempt: int) -> ExceptionBundle:
    if type(attempt) is not int or attempt < 1:
        raise BundleError(f"attempts are numbered from one, not {attempt}")
    current = replay(Path(run_directory))
    lease = _lease_for(current, node, attempt)
    completed = tuple(item for item in lease.invocations if item.completed)
    if not completed:
        raise BundleError(
            f"{node} attempt {attempt} completed no Operation call, so there is "
            "nothing for a bundle to show"
        )
    index = len(completed) - 1
    failing = completed[index]
    after = screenshot_bytes(_outputs(failing))
    before = (
        screenshot_bytes(_outputs(completed[index - 1])) if index > 0 else None
    )
    frames = tuple(item for item in (before, after) if item is not None)
    return ExceptionBundle(
        node=node,
        attempt=attempt,
        call=failing.call_id,
        before_after=_before_after(before, after, completed, index),
        contact_sheet=_contact_sheet(frames, failing.call_id),
        frame_count=len(frames),
        crops=(),
        crop_refusal=CROP_REFUSAL,
        field_diff=_field_diff(_outputs(failing)),
        matched_signature=_signatures(before, after),
    )


def _lease_for(current: RunView, node: NodeID, attempt: int) -> LeaseView:
    current.node(node)
    leases = tuple(item for item in current.leases if item.node_id == node)
    if not leases:
        raise BundleError(f"{node} was never claimed, so it recorded no attempt")
    if attempt > len(leases):
        raise BundleError(
            f"{node} recorded {len(leases)} attempt(s), not {attempt}; the ledger "
            "admits one lease per node, so a second attempt lives in a later run"
        )
    return leases[attempt - 1]


def _outputs(invocation: OperationInvocationView) -> Mapping[str, Any]:
    return {} if invocation.outputs is None else dict(invocation.outputs.payload())


def _before_after(
    before: Optional[bytes],
    after: Optional[bytes],
    completed: Tuple[OperationInvocationView, ...],
    index: int,
) -> Tuple[BundleImage, ...]:
    images = []
    if before is not None:
        images.append(BundleImage(f"before {completed[index].call_id}", before))
    if after is not None:
        images.append(BundleImage(f"after {completed[index].call_id}", after))
    return tuple(images)


def _contact_sheet(
    frames: Tuple[bytes, ...], call: CallID
) -> Optional[BundleImage]:
    if not frames:
        return None
    try:
        rasters = [scale_down(decode_png(item), MONTAGE_REDUCTION) for item in frames]
        montage = tile(rasters, min(MONTAGE_COLUMNS, len(rasters)))
        return BundleImage(
            f"{len(frames)} frame(s) around {call}, numbered from zero",
            encode_png(montage),
        )
    except RasterError:
        return None


def _field_diff(outputs: Mapping[str, Any]) -> Mapping[str, Any]:
    return MappingProxyType(
        {key: (NO_BASELINE, value) for key, value in outputs.items()}
    )


def _signatures(
    before: Optional[bytes], after: Optional[bytes]
) -> Tuple[SignatureID, ...]:
    if after is None:
        return ()
    found = []
    try:
        for hit in (capture_failed(after), all_black(after)):
            if hit is not None:
                found.append(hit)
        if before is not None and frame_delta(before, after) < UNCHANGED_FRAME_DELTA:
            found.append(FRAME_UNCHANGED)
    except (RasterError, OSError, ValueError):
        return tuple(found)
    return tuple(found)


__all__ = (
    "CROP_REFUSAL",
    "MONTAGE_COLUMNS",
    "MONTAGE_REDUCTION",
    "UNCHANGED_FRAME_DELTA",
    "BundleError",
    "BundleImage",
    "ExceptionBundle",
    "run",
)
