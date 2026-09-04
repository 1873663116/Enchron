#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import struct
import sys
import unittest
import zlib

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.tools.raster import (
    DEGENERATE_EDGE,
    ENCODED_COLOR_TYPES,
    SAMPLE_BUDGET,
    Raster,
    RasterError,
    crop,
    decode_png,
    encode_png,
)

COLOR_TYPES = ENCODED_COLOR_TYPES
FILTER_NAMES = ("none", "sub", "up", "average", "paeth")


def paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    if abs(estimate - left) <= abs(estimate - above) and abs(
        estimate - left
    ) <= abs(estimate - upper_left):
        return left
    if abs(estimate - above) <= abs(estimate - upper_left):
        return above
    return upper_left


def chunk(kind: bytes, body: bytes) -> bytes:
    return (
        struct.pack(">I", len(body))
        + kind
        + body
        + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    )


def png(
    width: int,
    height: int,
    samples: bytes,
    channels: int = 3,
    filter_type: int = 0,
    bit_depth: int = 8,
    interlace: int = 0,
    color_type: int = None,
) -> bytes:
    resolved = COLOR_TYPES[channels] if color_type is None else color_type
    header = struct.pack(
        ">IIBBBBB", width, height, bit_depth, resolved, 0, 0, interlace
    )
    line_length = width * channels
    raw = bytearray()
    previous = bytearray(line_length)
    for row in range(height):
        line = bytearray(samples[row * line_length : (row + 1) * line_length])
        raw.append(filter_type)
        encoded = bytearray(line_length)
        for index in range(line_length):
            left = line[index - channels] if index >= channels else 0
            above = previous[index]
            corner = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                encoded[index] = line[index]
            elif filter_type == 1:
                encoded[index] = (line[index] - left) & 0xFF
            elif filter_type == 2:
                encoded[index] = (line[index] - above) & 0xFF
            elif filter_type == 3:
                encoded[index] = (line[index] - ((left + above) >> 1)) & 0xFF
            else:
                encoded[index] = (line[index] - paeth(left, above, corner)) & 0xFF
        raw.extend(encoded)
        previous = line
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw)))
        + chunk(b"IEND", b"")
    )


def flat(width: int, height: int, value, channels: int = 3) -> bytes:
    pixel = bytes(value) if isinstance(value, (tuple, list)) else bytes([value] * channels)
    return pixel * (width * height)


def gradient(width: int, height: int, channels: int = 3) -> bytes:
    return bytes(
        (row * width + column + channel * 37) % 256
        for row in range(height)
        for column in range(width)
        for channel in range(channels)
    )


class DecoderTests(unittest.TestCase):
    def test_every_filter_type_reconstructs_the_same_pixels(self) -> None:
        samples = gradient(19, 11)
        for filter_type, name in enumerate(FILTER_NAMES):
            with self.subTest(filter=name):
                raster = decode_png(png(19, 11, samples, filter_type=filter_type))
                self.assertEqual(samples, raster.samples)
                self.assertEqual((19, 11, 3), (raster.width, raster.height, raster.channels))

    def test_each_supported_channel_count_decodes(self) -> None:
        for channels in sorted(COLOR_TYPES):
            with self.subTest(channels=channels):
                samples = gradient(8, 6, channels)
                raster = decode_png(png(8, 6, samples, channels=channels))
                self.assertEqual(channels, raster.channels)
                self.assertEqual(samples, raster.samples)

    def test_bytes_that_are_not_a_png_are_refused(self) -> None:
        for rejected in (b"", b"not a png at all", "a string"):
            with self.subTest(value=rejected):
                with self.assertRaisesRegex(RasterError, "read from PNG bytes"):
                    decode_png(rejected)

    def test_an_unsupported_depth_or_interlace_is_named_in_the_refusal(self) -> None:
        with self.assertRaisesRegex(RasterError, "8-bit non-interlaced"):
            decode_png(png(4, 4, gradient(4, 4), bit_depth=16))
        with self.assertRaisesRegex(RasterError, "8-bit non-interlaced"):
            decode_png(png(4, 4, gradient(4, 4), interlace=1))

    def test_an_unsupported_colour_type_is_refused(self) -> None:
        with self.assertRaisesRegex(RasterError, "colour type 3"):
            decode_png(png(4, 4, gradient(4, 4), color_type=3))

    def test_an_undefined_filter_type_is_refused(self) -> None:
        with self.assertRaisesRegex(RasterError, "filter type 5"):
            decode_png(png(4, 4, gradient(4, 4), filter_type=5))

    def test_image_data_shorter_than_the_header_claims_is_refused(self) -> None:
        truncated = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00" + b"\x00" * 11))
            + chunk(b"IEND", b"")
        )
        with self.assertRaisesRegex(RasterError, "shorter than its header"):
            decode_png(truncated)

    def test_a_png_without_image_data_is_refused(self) -> None:
        headerless = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
            + chunk(b"IEND", b"")
        )
        with self.assertRaisesRegex(RasterError, "no header or no image data"):
            decode_png(headerless)


class SamplingTests(unittest.TestCase):
    def large(self, width: int, height: int, samples: bytes) -> bytes:
        self.assertLess(SAMPLE_BUDGET, width * height)
        return png(width, height, samples)

    def test_an_image_past_the_budget_is_subsampled(self) -> None:
        width, height = 640, 480
        raster = decode_png(self.large(width, height, flat(width, height, 0)))
        self.assertLess(1, raster.stride())
        self.assertGreaterEqual(SAMPLE_BUDGET, len(raster.luma()))
        self.assertLess(width * height // (raster.stride() + 1), len(raster.luma()))

    def test_the_stride_never_shares_a_factor_with_the_width(self) -> None:
        from math import gcd

        for width, height in ((640, 480), (1600, 1200), (1920, 1080), (1024, 768)):
            with self.subTest(size=(width, height)):
                raster = decode_png(self.large(width, height, flat(width, height, 0)))
                self.assertEqual(1, gcd(raster.stride(), width))

    def test_the_sampled_mean_tracks_the_exact_mean(self) -> None:
        width, height = 641, 480
        samples = bytearray()
        for row in range(height):
            for column in range(width):
                value = (row * 7 + column * 13) % 256
                samples.extend(bytes([value, value, value]))
        raster = decode_png(self.large(width, height, bytes(samples)))
        sampled = raster.luma()
        exact = [raster.samples[index] for index in range(0, len(raster.samples), 3)]
        self.assertAlmostEqual(
            sum(exact) / len(exact), sum(sampled) / len(sampled), delta=4.0
        )


class MalformedInputTests(unittest.TestCase):
    def test_a_corrupt_compressed_stream_is_one_error_type(self) -> None:
        corrupt = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", b"not a deflate stream at all")
            + chunk(b"IEND", b"")
        )
        with self.assertRaisesRegex(RasterError, "malformed"):
            decode_png(corrupt)

    def test_a_short_header_is_refused(self) -> None:
        short = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIB", 8, 8, 8))
            + chunk(b"IDAT", zlib.compress(b"\x00"))
            + chunk(b"IEND", b"")
        )
        with self.assertRaisesRegex(RasterError, "not 13 bytes"):
            decode_png(short)

    def test_a_chunk_running_past_the_buffer_is_refused(self) -> None:
        overrun = (
            b"\x89PNG\r\n\x1a\n"
            + struct.pack(">I", 4096)
            + b"IDAT"
            + b"\x00" * 8
        )
        with self.assertRaisesRegex(RasterError, "runs past the end"):
            decode_png(overrun)

    def test_a_truncated_file_never_raises_a_zlib_or_struct_error(self) -> None:
        whole = png(40, 30, flat(40, 30, 90))
        for cut in range(9, len(whole), max(1, len(whole) // 24)):
            with self.subTest(cut=cut):
                try:
                    decode_png(whole[:cut])
                except RasterError:
                    continue


class EncoderTests(unittest.TestCase):
    """The bundle cuts regions out of a screenshot and hands them back as PNG,
    so the encoder has to be the exact inverse of the decoder that reads the
    screenshot in the first place."""

    def test_every_channel_count_round_trips_through_the_encoder(self) -> None:
        for channels in sorted(COLOR_TYPES):
            with self.subTest(channels=channels):
                width, height = 7, 5
                samples = gradient(width, height, channels)
                original = Raster(width, height, channels, samples)

                restored = decode_png(encode_png(original))

                self.assertEqual(original, restored)

    def test_the_encoded_bytes_are_a_png_another_reader_accepts(self) -> None:
        original = Raster(4, 3, 3, gradient(4, 3, 3))

        encoded = encode_png(original)

        self.assertTrue(encoded.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertIn(b"IHDR", encoded)
        self.assertIn(b"IDAT", encoded)
        self.assertTrue(encoded.endswith(chunk(b"IEND", b"")))

    def test_a_sample_count_that_contradicts_the_geometry_is_refused(self) -> None:
        with self.assertRaisesRegex(RasterError, "holds 36 samples, not 12"):
            encode_png(Raster(4, 3, 3, gradient(4, 1, 3)))

    def test_a_channel_count_with_no_png_colour_type_is_refused(self) -> None:
        with self.assertRaisesRegex(RasterError, "no PNG colour type"):
            encode_png(Raster(2, 2, 5, bytes(20)))


class CropTests(unittest.TestCase):
    """Crops name the region a verdict describes. A crop that silently slid to
    fit would put the wrong region under the observation."""

    def frame(self) -> Raster:
        return decode_png(png(6, 4, gradient(6, 4)))

    def test_a_crop_carries_the_pixels_at_its_own_offset(self) -> None:
        original = self.frame()

        cut = crop(original, 2, 1, 3, 2)

        self.assertEqual((3, 2, 3), (cut.width, cut.height, cut.channels))
        for row in range(2):
            for column in range(3):
                start = ((row + 1) * 6 + (column + 2)) * 3
                self.assertEqual(
                    original.samples[start : start + 3],
                    cut.samples[(row * 3 + column) * 3 : (row * 3 + column) * 3 + 3],
                )

    def test_a_crop_of_the_whole_frame_is_the_frame(self) -> None:
        original = self.frame()

        self.assertEqual(original, crop(original, 0, 0, 6, 4))

    def test_a_crop_reaching_past_any_edge_is_refused_rather_than_clamped(self) -> None:
        original = self.frame()
        for left, top, width, height in (
            (4, 0, 3, 1),
            (0, 3, 1, 2),
            (-1, 0, 2, 2),
            (0, -1, 2, 2),
        ):
            with self.subTest(box=(left, top, width, height)):
                with self.assertRaisesRegex(RasterError, "leaves the 6x4 frame"):
                    crop(original, left, top, width, height)

    def test_a_crop_enclosing_no_pixels_is_refused(self) -> None:
        original = self.frame()
        for width, height in ((0, 2), (2, 0), (-1, 2)):
            with self.subTest(size=(width, height)):
                with self.assertRaisesRegex(RasterError, "encloses no pixels"):
                    crop(original, 0, 0, width, height)

    def test_a_crop_bounded_by_anything_but_whole_pixels_is_refused(self) -> None:
        original = self.frame()

        with self.assertRaisesRegex(RasterError, "whole pixels"):
            crop(original, 0.0, 0, 2, 2)

    def test_a_crop_re_encodes_to_a_png_that_decodes_back(self) -> None:
        cut = crop(self.frame(), 1, 1, 4, 2)

        self.assertEqual(cut, decode_png(encode_png(cut)))


if __name__ == "__main__":
    unittest.main()
