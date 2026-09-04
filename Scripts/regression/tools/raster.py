#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from math import gcd
import struct
from typing import Sequence, Tuple
import zlib

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
SUPPORTED_BIT_DEPTH = 8
SUPPORTED_COLOR_TYPES = {0: 1, 2: 3, 4: 2, 6: 4}
ENCODED_COLOR_TYPES = {1: 0, 2: 4, 3: 2, 4: 6}
COMPRESSION_LEVEL = 6
LUMA_WEIGHTS = (299, 587, 114)
LUMA_SCALE = 1000
FULL_SCALE = 255
SAMPLE_BUDGET = 200_000
DEGENERATE_EDGE = 1
TILE_PADDING = 2
TILE_BACKGROUND = 32


class RasterError(ValueError):
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
        if isinstance(error, RasterError):
            raise
        raise RasterError(f"the PNG bytes are malformed: {error}") from error


def _decode_png(data: bytes) -> Raster:
    if not isinstance(data, bytes) or not data.startswith(PNG_MAGIC):
        raise RasterError("a raster is read from PNG bytes")
    width = height = None
    depth = color_type = interlace = None
    compressed = bytearray()
    offset = len(PNG_MAGIC)
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset : offset + 8])
        if offset + 12 + length > len(data):
            raise RasterError(
                f"the {kind.decode('ascii', 'replace')} chunk runs past the end of "
                "the PNG"
            )
        body = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            if length != 13:
                raise RasterError("the PNG header is not 13 bytes")
            width, height, depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", body
            )
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            break
    if width is None or not compressed:
        raise RasterError("the PNG carries no header or no image data")
    if depth != SUPPORTED_BIT_DEPTH or interlace != 0:
        raise RasterError(
            f"a raster is read from 8-bit non-interlaced PNG, not depth {depth} "
            f"interlace {interlace}"
        )
    channels = SUPPORTED_COLOR_TYPES.get(color_type)
    if channels is None:
        raise RasterError(f"PNG colour type {color_type} is not supported")
    return Raster(
        width, height, channels, _unfilter(zlib.decompress(bytes(compressed)), width, height, channels)
    )


def _unfilter(raw: bytes, width: int, height: int, channels: int) -> bytes:
    line_length = width * channels
    expected = (line_length + 1) * height
    if len(raw) < expected:
        raise RasterError("the PNG image data is shorter than its header claims")
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
            raise RasterError(f"PNG filter type {filter_type} is not defined")
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


def encode_png(raster: Raster) -> bytes:
    color_type = ENCODED_COLOR_TYPES.get(raster.channels)
    if color_type is None:
        raise RasterError(
            f"a raster of {raster.channels} channels has no PNG colour type"
        )
    line_length = raster.width * raster.channels
    if len(raster.samples) != line_length * raster.height:
        raise RasterError(
            f"a {raster.width}x{raster.height} raster of {raster.channels} channels "
            f"holds {line_length * raster.height} samples, not {len(raster.samples)}"
        )
    raw = bytearray()
    for row in range(raster.height):
        raw.append(0)
        raw.extend(raster.samples[row * line_length : (row + 1) * line_length])
    header = struct.pack(
        ">IIBBBBB",
        raster.width,
        raster.height,
        SUPPORTED_BIT_DEPTH,
        color_type,
        0,
        0,
        0,
    )
    return b"".join(
        (
            PNG_MAGIC,
            _chunk(b"IHDR", header),
            _chunk(b"IDAT", zlib.compress(bytes(raw), COMPRESSION_LEVEL)),
            _chunk(b"IEND", b""),
        )
    )


def _chunk(kind: bytes, body: bytes) -> bytes:
    return b"".join(
        (
            struct.pack(">I", len(body)),
            kind,
            body,
            struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF),
        )
    )


def crop(raster: Raster, left: int, top: int, width: int, height: int) -> Raster:
    for value in (left, top, width, height):
        if type(value) is not int:
            raise RasterError("a crop is bounded by whole pixels")
    if width < 1 or height < 1:
        raise RasterError(f"a crop of {width}x{height} encloses no pixels")
    if left < 0 or top < 0 or left + width > raster.width or top + height > raster.height:
        raise RasterError(
            f"the crop {width}x{height} at ({left}, {top}) leaves the "
            f"{raster.width}x{raster.height} frame it is cut from"
        )
    line_length = raster.width * raster.channels
    row_bytes = width * raster.channels
    out = bytearray()
    for row in range(top, top + height):
        start = row * line_length + left * raster.channels
        out.extend(raster.samples[start : start + row_bytes])
    return Raster(width, height, raster.channels, bytes(out))


def scale_down(raster: Raster, factor: int) -> Raster:
    if type(factor) is not int or factor < 1:
        raise RasterError(f"a raster is reduced by a whole factor, not {factor}")
    if factor == 1:
        return raster
    width = max(1, raster.width // factor)
    height = max(1, raster.height // factor)
    line_length = raster.width * raster.channels
    out = bytearray()
    for row in range(height):
        source = row * factor * line_length
        for column in range(width):
            start = source + column * factor * raster.channels
            out.extend(raster.samples[start : start + raster.channels])
    return Raster(width, height, raster.channels, bytes(out))


def tile(rasters: Sequence[Raster], columns: int, padding: int = TILE_PADDING) -> Raster:
    if not rasters:
        raise RasterError("a montage is tiled from at least one frame")
    if type(columns) is not int or columns < 1:
        raise RasterError(f"a montage has at least one column, not {columns}")
    if type(padding) is not int or padding < 0:
        raise RasterError(f"a montage pads by whole pixels, not {padding}")
    channels = rasters[0].channels
    if any(item.channels != channels for item in rasters):
        raise RasterError("a montage tiles frames that carry the same channels")
    cell_width = max(item.width for item in rasters)
    cell_height = max(item.height for item in rasters)
    rows = -(-len(rasters) // columns)
    width = columns * cell_width + (columns + 1) * padding
    height = rows * cell_height + (rows + 1) * padding
    line_length = width * channels
    canvas = bytearray(bytes([TILE_BACKGROUND]) * (line_length * height))
    for index, item in enumerate(rasters):
        left = padding + (index % columns) * (cell_width + padding)
        top = padding + (index // columns) * (cell_height + padding)
        source_line = item.width * channels
        for row in range(item.height):
            start = (top + row) * line_length + left * channels
            canvas[start : start + source_line] = item.samples[
                row * source_line : (row + 1) * source_line
            ]
    return Raster(width, height, channels, bytes(canvas))


__all__ = (
    "DEGENERATE_EDGE",
    "FULL_SCALE",
    "TILE_PADDING",
    "Raster",
    "RasterError",
    "crop",
    "decode_png",
    "encode_png",
    "scale_down",
    "tile",
)
