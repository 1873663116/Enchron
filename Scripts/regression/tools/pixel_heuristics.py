#!/usr/bin/env python3

from __future__ import annotations

from typing import Optional

from regression.core.ids import SignatureID
from regression.tools.raster import FULL_SCALE, RasterError, decode_png
from regression.tools.signatures import ALL_BLACK, CAPTURE_FAILED

LIMITED_RANGE_OFFSET = 16
LIMITED_RANGE_SPAN = 219
DEFAULT_BLACK_THRESHOLD = 18.0
DEFAULT_BLACK_PEAK = 40.0


def capture_failed(image: bytes) -> Optional[SignatureID]:
    return CAPTURE_FAILED if decode_png(image).degenerate else None


def limited_range(luma: int) -> int:
    return LIMITED_RANGE_OFFSET + (luma * LIMITED_RANGE_SPAN) // FULL_SCALE


def all_black(
    image: bytes,
    threshold: float = DEFAULT_BLACK_THRESHOLD,
    peak: float = DEFAULT_BLACK_PEAK,
) -> Optional[SignatureID]:
    for level in (threshold, peak):
        if not isinstance(level, (int, float)) or level < 0:
            raise RasterError("the black thresholds are non-negative luma levels")
    raster = decode_png(image)
    if raster.degenerate:
        return None
    luma = tuple(limited_range(item) for item in raster.luma())
    mean = sum(luma) / len(luma)
    return ALL_BLACK if mean < threshold and max(luma) < peak else None


def frame_delta(before: bytes, after: bytes) -> float:
    first = decode_png(before)
    second = decode_png(after)
    if (first.width, first.height) != (second.width, second.height):
        raise RasterError(
            f"a frame delta compares one geometry, not {first.width}x{first.height} "
            f"against {second.width}x{second.height}"
        )
    left = first.luma()
    right = second.luma()
    if not left:
        return 0.0
    total = sum(abs(a - b) for a, b in zip(left, right))
    return total / (len(left) * FULL_SCALE)


__all__ = (
    "ALL_BLACK",
    "CAPTURE_FAILED",
    "DEFAULT_BLACK_PEAK",
    "DEFAULT_BLACK_THRESHOLD",
    "all_black",
    "capture_failed",
    "frame_delta",
    "limited_range",
)
