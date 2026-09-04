#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from types import MappingProxyType
from typing import Mapping, Tuple

from regression.core.ids import SignatureID


class AdjudicationTier(Enum):
    FIELD_PREDICATE = "L0"
    PIXEL_HEURISTIC = "L1"
    AGENT_ATTRIBUTION = "L2"


class SignatureError(ValueError):
    pass


@dataclass(frozen=True)
class Signature:
    id: SignatureID
    tier: AdjudicationTier
    criterion: str


CAPTURE_FAILED = SignatureID("signature:capture-failed")
ALL_BLACK = SignatureID("signature:all-black")
FRAME_UNCHANGED = SignatureID("signature:frame-unchanged")

REGISTERED: Tuple[Signature, ...] = (
    Signature(
        CAPTURE_FAILED,
        AdjudicationTier.PIXEL_HEURISTIC,
        "the capture is one pixel on a side, which is what the screenshot channel "
        "returns when it produced no image at all",
    ),
    Signature(
        ALL_BLACK,
        AdjudicationTier.PIXEL_HEURISTIC,
        "mean limited-range luma below 18.0 with no pixel above 40.0, which is a "
        "frame that carries no rendered content rather than a dark scene",
    ),
    Signature(
        FRAME_UNCHANGED,
        AdjudicationTier.PIXEL_HEURISTIC,
        "the frames before and after the call differ by less than one luma step, so "
        "the call left the screen as it found it",
    ),
)

SIGNATURES: Mapping[SignatureID, Signature] = MappingProxyType(
    {item.id: item for item in REGISTERED}
)

if len(SIGNATURES) != len(REGISTERED):
    raise RuntimeError("two signatures share one identifier")


def signature(identifier: SignatureID) -> Signature:
    found = SIGNATURES.get(identifier)
    if found is None:
        registered = ", ".join(sorted(SIGNATURES))
        raise SignatureError(
            f"{identifier} names no registered signature; the ledger records one of "
            f"{registered}"
        )
    return found


__all__ = (
    "ALL_BLACK",
    "AdjudicationTier",
    "CAPTURE_FAILED",
    "FRAME_UNCHANGED",
    "REGISTERED",
    "SIGNATURES",
    "Signature",
    "SignatureError",
    "signature",
)
