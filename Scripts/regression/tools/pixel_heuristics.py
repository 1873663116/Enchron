#!/usr/bin/env python3

from __future__ import annotations

from typing import Optional, Sequence, Tuple

from regression.core.ids import SignatureID
from regression.tools.raster import FULL_SCALE, RasterError, decode_png
from regression.tools.signatures import ALL_BLACK, CAPTURE_FAILED

LIMITED_RANGE_OFFSET = 16
LIMITED_RANGE_SPAN = 219
DEFAULT_BLACK_THRESHOLD = 18.0
DEFAULT_BLACK_PEAK = 40.0
REGION_MINIMUM_COORDINATE = 0.0
REGION_MAXIMUM_COORDINATE = 1.0
REGION_CHANNEL_COUNT = 3
REGION_CHANNEL_MAXIMUM = 255


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


def region_rgb(
    image: bytes, normalized_x: float, normalized_y: float
) -> Tuple[int, int, int]:
    raster = decode_png(image)
    if raster.degenerate:
        raise RasterError(
            f"a capture of {raster.width}x{raster.height} encloses no region to "
            "sample; the screenshot channel returned no image at all"
        )
    for name, value in (("normalized_x", normalized_x), ("normalized_y", normalized_y)):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise RasterError(f"{name} is a normalized coordinate, not {value!r}")
        if not REGION_MINIMUM_COORDINATE <= value <= REGION_MAXIMUM_COORDINATE:
            raise RasterError(
                f"{name} addresses a pixel from the top left of the frame within "
                f"[{REGION_MINIMUM_COORDINATE}, {REGION_MAXIMUM_COORDINATE}], not "
                f"{value!r}"
            )
    column = min(int(normalized_x * raster.width), raster.width - 1)
    row = min(int(normalized_y * raster.height), raster.height - 1)
    index = (row * raster.width + column) * raster.channels
    samples = raster.samples
    if raster.channels <= 2:
        grey = samples[index]
        return (grey, grey, grey)
    return (samples[index], samples[index + 1], samples[index + 2])


def region_rgb_matches(
    image: bytes,
    normalized_x: float,
    normalized_y: float,
    expected: Sequence[int],
    tolerance: int,
) -> bool:
    if type(tolerance) is not int or tolerance < 0:
        raise RasterError(
            f"a region matches within a whole, non-negative tolerance, not {tolerance!r}"
        )
    try:
        channels = tuple(expected)
    except TypeError:
        raise RasterError(
            f"a region is expected as three channel levels, not {expected!r}"
        ) from None
    if len(channels) != REGION_CHANNEL_COUNT or any(
        type(channel) is not int or not 0 <= channel <= REGION_CHANNEL_MAXIMUM
        for channel in channels
    ):
        raise RasterError(
            f"a region is expected as three channel levels in [0, "
            f"{REGION_CHANNEL_MAXIMUM}], not {expected!r}"
        )
    actual = region_rgb(image, normalized_x, normalized_y)
    return all(
        abs(actual[channel] - channels[channel]) <= tolerance
        for channel in range(REGION_CHANNEL_COUNT)
    )


__all__ = (
    "ALL_BLACK",
    "CAPTURE_FAILED",
    "DEFAULT_BLACK_PEAK",
    "DEFAULT_BLACK_THRESHOLD",
    "REGION_CHANNEL_MAXIMUM",
    "REGION_MAXIMUM_COORDINATE",
    "REGION_MINIMUM_COORDINATE",
    "all_black",
    "capture_failed",
    "frame_delta",
    "limited_range",
    "region_rgb",
    "region_rgb_matches",
)
