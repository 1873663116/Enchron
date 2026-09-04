#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from math import gcd
import struct
from typing import Optional, Tuple
import zlib

from regression.core.ids import SignatureID


CAPTURE_FAILED = SignatureID("signature:capture-failed")
ALL_BLACK = SignatureID("signature:all-black")

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
SUPPORTED_BIT_DEPTH = 8
SUPPORTED_COLOR_TYPES = {0: 1, 2: 3, 4: 2, 6: 4}
LUMA_WEIGHTS = (299, 587, 114)
LUMA_SCALE = 1000
FULL_SCALE = 255
SAMPLE_BUDGET = 200_000
DEGENERATE_EDGE = 1
LIMITED_RANGE_OFFSET = 16
LIMITED_RANGE_SPAN = 219
DEFAULT_BLACK_THRESHOLD = 18.0
DEFAULT_BLACK_PEAK = 40.0


class PixelHeuristicError(ValueError):
    pass


@dataclass(frozen=True)
class Raster:
    width: int
    height: int
    channels: int
    samples: bytes

    @property
    def degenerate(self) -> bool:
        return self.width <= DEGENERATE_EDGE or self.height <= DEGENERATE_EDGE

    def stride(self) -> int:
        pixels = self.width * self.height
        if pixels <= SAMPLE_BUDGET:
            return 1
        step = pixels // SAMPLE_BUDGET + 1
        while step < self.width and gcd(step, self.width) != 1:
            step += 1
        return step

    def luma(self) -> Tuple[int, ...]:
        step = self.stride() * self.channels
        if self.channels <= 2:
            return tuple(self.samples[index] for index in range(0, len(self.samples), step))
        red, green, blue = LUMA_WEIGHTS
        return tuple(
            (
                self.samples[index] * red
                + self.samples[index + 1] * green
                + self.samples[index + 2] * blue
            )
            // LUMA_SCALE
            for index in range(0, len(self.samples) - self.channels + 1, step)
        )


def decode_png(data: bytes) -> Raster:
    try:
        return _decode_png(data)
    except (struct.error, zlib.error, ValueError) as error:
        if isinstance(error, PixelHeuristicError):
            raise
        raise PixelHeuristicError(f"the PNG bytes are malformed: {error}") from error


def _decode_png(data: bytes) -> Raster:
    if not isinstance(data, bytes) or not data.startswith(PNG_MAGIC):
        raise PixelHeuristicError("the heuristics read PNG bytes")
    width = height = None
    depth = color_type = interlace = None
    compressed = bytearray()
    offset = len(PNG_MAGIC)
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset : offset + 8])
        if offset + 12 + length > len(data):
            raise PixelHeuristicError(
                f"the {kind.decode('ascii', 'replace')} chunk runs past the end of "
                "the PNG"
            )
        body = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            if length != 13:
                raise PixelHeuristicError("the PNG header is not 13 bytes")
            width, height, depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", body
            )
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            break
    if width is None or not compressed:
        raise PixelHeuristicError("the PNG carries no header or no image data")
    if depth != SUPPORTED_BIT_DEPTH or interlace != 0:
        raise PixelHeuristicError(
            f"the heuristics read 8-bit non-interlaced PNG, not depth {depth} "
            f"interlace {interlace}"
        )
    channels = SUPPORTED_COLOR_TYPES.get(color_type)
    if channels is None:
        raise PixelHeuristicError(f"PNG colour type {color_type} is not supported")
    return Raster(
        width, height, channels, _unfilter(zlib.decompress(bytes(compressed)), width, height, channels)
    )


def _unfilter(raw: bytes, width: int, height: int, channels: int) -> bytes:
    line_length = width * channels
    expected = (line_length + 1) * height
    if len(raw) < expected:
        raise PixelHeuristicError("the PNG image data is shorter than its header claims")
    out = bytearray(line_length * height)
    previous = bytearray(line_length)
    position = 0
    for row in range(height):
        filter_type = raw[position]
        position += 1
        line = bytearray(raw[position : position + line_length])
        position += line_length
        if filter_type == 1:
            for index in range(channels, line_length):
                line[index] = (line[index] + line[index - channels]) & 0xFF
        elif filter_type == 2:
            for index in range(line_length):
                line[index] = (line[index] + previous[index]) & 0xFF
        elif filter_type == 3:
            for index in range(line_length):
                left = line[index - channels] if index >= channels else 0
                line[index] = (line[index] + ((left + previous[index]) >> 1)) & 0xFF
        elif filter_type == 4:
            for index in range(line_length):
                left = line[index - channels] if index >= channels else 0
                upper_left = previous[index - channels] if index >= channels else 0
                line[index] = (
                    line[index] + _paeth(left, previous[index], upper_left)
                ) & 0xFF
        elif filter_type != 0:
            raise PixelHeuristicError(f"PNG filter type {filter_type} is not defined")
        out[row * line_length : (row + 1) * line_length] = line
        previous = line
    return bytes(out)


def _paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    distance_left = abs(estimate - left)
    distance_above = abs(estimate - above)
    distance_corner = abs(estimate - upper_left)
    if distance_left <= distance_above and distance_left <= distance_corner:
        return left
    if distance_above <= distance_corner:
        return above
    return upper_left


def capture_failed(image: bytes) -> Optional[SignatureID]:
    return CAPTURE_FAILED if decode_png(image).degenerate else None


def limited_range(luma: int) -> int:
    return LIMITED_RANGE_OFFSET + (luma * LIMITED_RANGE_SPAN) // 255


def all_black(
    image: bytes,
    threshold: float = DEFAULT_BLACK_THRESHOLD,
    peak: float = DEFAULT_BLACK_PEAK,
) -> Optional[SignatureID]:
    for level in (threshold, peak):
        if not isinstance(level, (int, float)) or level < 0:
            raise PixelHeuristicError(
                "the black thresholds are non-negative luma levels"
            )
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
        raise PixelHeuristicError(
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
    "PixelHeuristicError",
    "Raster",
    "all_black",
    "capture_failed",
    "decode_png",
    "frame_delta",
    "limited_range",
)
