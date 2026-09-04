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

from regression.tools.pixel_heuristics import (
    ALL_BLACK,
    CAPTURE_FAILED,
    DEFAULT_BLACK_PEAK,
    DEFAULT_BLACK_THRESHOLD,
    LIMITED_RANGE_OFFSET,
    SAMPLE_BUDGET,
    limited_range,
    PixelHeuristicError,
    all_black,
    capture_failed,
    decode_png,
    frame_delta,
)


COLOR_TYPES = {1: 0, 2: 4, 3: 2, 4: 6}
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
                with self.assertRaisesRegex(PixelHeuristicError, "read PNG bytes"):
                    decode_png(rejected)

    def test_an_unsupported_depth_or_interlace_is_named_in_the_refusal(self) -> None:
        with self.assertRaisesRegex(PixelHeuristicError, "8-bit non-interlaced"):
            decode_png(png(4, 4, gradient(4, 4), bit_depth=16))
        with self.assertRaisesRegex(PixelHeuristicError, "8-bit non-interlaced"):
            decode_png(png(4, 4, gradient(4, 4), interlace=1))

    def test_an_unsupported_colour_type_is_refused(self) -> None:
        with self.assertRaisesRegex(PixelHeuristicError, "colour type 3"):
            decode_png(png(4, 4, gradient(4, 4), color_type=3))

    def test_an_undefined_filter_type_is_refused(self) -> None:
        with self.assertRaisesRegex(PixelHeuristicError, "filter type 5"):
            decode_png(png(4, 4, gradient(4, 4), filter_type=5))

    def test_image_data_shorter_than_the_header_claims_is_refused(self) -> None:
        truncated = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00" + b"\x00" * 11))
            + chunk(b"IEND", b"")
        )
        with self.assertRaisesRegex(PixelHeuristicError, "shorter than its header"):
            decode_png(truncated)

    def test_a_png_without_image_data_is_refused(self) -> None:
        headerless = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
            + chunk(b"IEND", b"")
        )
        with self.assertRaisesRegex(PixelHeuristicError, "no header or no image data"):
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

    def test_a_column_striped_frame_is_not_aliased_away(self) -> None:
        width, height = 1600, 128
        samples = bytearray()
        for row in range(height):
            for column in range(width):
                value = 0 if column % 2 else 255
                samples.extend(bytes([value, value, value]))
        frame = self.large(width, height, bytes(samples))
        self.assertIsNone(all_black(frame))

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
        with self.assertRaisesRegex(PixelHeuristicError, "malformed"):
            decode_png(corrupt)

    def test_a_short_header_is_refused(self) -> None:
        short = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIB", 8, 8, 8))
            + chunk(b"IDAT", zlib.compress(b"\x00"))
            + chunk(b"IEND", b"")
        )
        with self.assertRaisesRegex(PixelHeuristicError, "not 13 bytes"):
            decode_png(short)

    def test_a_chunk_running_past_the_buffer_is_refused(self) -> None:
        overrun = (
            b"\x89PNG\r\n\x1a\n"
            + struct.pack(">I", 4096)
            + b"IDAT"
            + b"\x00" * 8
        )
        with self.assertRaisesRegex(PixelHeuristicError, "runs past the end"):
            decode_png(overrun)

    def test_a_truncated_file_never_raises_a_zlib_or_struct_error(self) -> None:
        whole = png(40, 30, flat(40, 30, 90))
        for cut in range(9, len(whole), max(1, len(whole) // 24)):
            with self.subTest(cut=cut):
                try:
                    decode_png(whole[:cut])
                except PixelHeuristicError:
                    continue


class CaptureFailedTests(unittest.TestCase):
    def test_a_one_by_one_capture_is_the_signature(self) -> None:
        self.assertEqual(CAPTURE_FAILED, capture_failed(png(1, 1, flat(1, 1, 0))))

    def test_any_degenerate_edge_counts_as_a_failed_capture(self) -> None:
        self.assertEqual(CAPTURE_FAILED, capture_failed(png(1, 40, flat(1, 40, 200))))
        self.assertEqual(CAPTURE_FAILED, capture_failed(png(40, 1, flat(40, 1, 200))))

    def test_the_criterion_is_the_size_and_not_the_content(self) -> None:
        self.assertIsNone(capture_failed(png(32, 24, flat(32, 24, 0))))
        self.assertEqual(CAPTURE_FAILED, capture_failed(png(1, 1, flat(1, 1, 255))))


class AllBlackTests(unittest.TestCase):
    def test_a_black_frame_hits_the_signature(self) -> None:
        self.assertEqual(ALL_BLACK, all_black(png(24, 16, flat(24, 16, 0))))

    def test_a_bright_frame_does_not(self) -> None:
        self.assertIsNone(all_black(png(24, 16, flat(24, 16, 200))))

    def test_the_threshold_is_a_luma_level_the_caller_sets(self) -> None:
        frame = png(24, 16, flat(24, 16, 30))
        self.assertIsNone(all_black(frame))
        self.assertEqual(ALL_BLACK, all_black(frame, 60.0, 60.0))

    def test_the_thresholds_are_read_in_the_reference_limited_range(self) -> None:
        self.assertEqual(LIMITED_RANGE_OFFSET, limited_range(0))
        self.assertEqual(235, limited_range(255))
        self.assertEqual(ALL_BLACK, all_black(png(24, 16, flat(24, 16, 2))))
        self.assertIsNone(all_black(png(24, 16, flat(24, 16, 3))))

    def test_a_peak_above_the_ceiling_denies_the_signature_on_its_own(self) -> None:
        samples = bytearray(flat(200, 200, 0))
        samples[0:3] = b"\xff\xff\xff"
        frame = png(200, 200, bytes(samples))
        raster = decode_png(frame)
        luma = tuple(limited_range(item) for item in raster.luma())
        self.assertGreater(DEFAULT_BLACK_THRESHOLD, sum(luma) / len(luma))
        self.assertLessEqual(DEFAULT_BLACK_PEAK, max(luma))
        self.assertIsNone(all_black(frame))

    def test_a_real_device_capture_is_never_reported_as_black(self) -> None:
        capture = (
            SCRIPTS.parent
            / "docs/archive/acceptance/evidence"
            / "playback-seek-and-menu-surface-20260821"
            / "menu-after-popover-minimum-window.png"
        )
        if not capture.is_file():
            self.skipTest("the archived device capture is not in this checkout")
        self.assertIsNone(all_black(capture.read_bytes()))

    def test_a_grey_channel_frame_is_measured_on_its_own_samples(self) -> None:
        self.assertEqual(ALL_BLACK, all_black(png(16, 16, flat(16, 16, 0, 1), channels=1)))
        self.assertIsNone(all_black(png(16, 16, flat(16, 16, 90, 1), channels=1)))

    def test_a_frame_is_black_by_its_mean_and_not_by_its_darkest_pixel(self) -> None:
        half = bytearray()
        for row in range(16):
            for column in range(24):
                half.extend(b"\x00\x00\x00" if column < 12 else b"\xff\xff\xff")
        self.assertIsNone(all_black(png(24, 16, bytes(half))))

    def test_one_bright_band_lifts_a_mostly_black_frame_out_of_the_signature(
        self,
    ) -> None:
        banded = bytearray()
        for row in range(16):
            value = 255 if row == 0 else 0
            banded.extend(bytes([value, value, value]) * 24)
        frame = png(24, 16, bytes(banded))
        self.assertIsNone(all_black(frame))
        self.assertEqual(ALL_BLACK, all_black(frame, 40.0, 255.0))

    def test_a_failed_capture_is_not_reported_as_a_black_frame(self) -> None:
        self.assertIsNone(all_black(png(1, 1, flat(1, 1, 0))))

    def test_a_negative_threshold_is_refused(self) -> None:
        with self.assertRaisesRegex(PixelHeuristicError, "non-negative luma"):
            all_black(png(8, 8, flat(8, 8, 0)), -1.0)


class FrameDeltaTests(unittest.TestCase):
    def test_a_frame_against_itself_is_zero(self) -> None:
        frame = png(20, 12, gradient(20, 12))
        self.assertEqual(0.0, frame_delta(frame, frame))

    def test_black_against_white_is_the_whole_range(self) -> None:
        self.assertAlmostEqual(
            1.0,
            frame_delta(png(20, 12, flat(20, 12, 0)), png(20, 12, flat(20, 12, 255))),
            places=2,
        )

    def test_a_partial_change_lands_between_the_ends(self) -> None:
        delta = frame_delta(
            png(20, 12, flat(20, 12, 0)), png(20, 12, flat(20, 12, 128))
        )
        self.assertLess(0.4, delta)
        self.assertGreater(0.6, delta)

    def test_two_geometries_cannot_be_compared(self) -> None:
        with self.assertRaisesRegex(PixelHeuristicError, "20x12 against 10x12"):
            frame_delta(png(20, 12, gradient(20, 12)), png(10, 12, gradient(10, 12)))


if __name__ == "__main__":
    unittest.main()
