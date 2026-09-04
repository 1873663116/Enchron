#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

from regression.tools.pixel_heuristics import (
    ALL_BLACK,
    LIMITED_RANGE_OFFSET,
    CAPTURE_FAILED,
    DEFAULT_BLACK_PEAK,
    DEFAULT_BLACK_THRESHOLD,
    all_black,
    capture_failed,
    frame_delta,
    limited_range,
)
from regression.tools.raster import RasterError, decode_png
from test_regression_raster import flat, gradient, png


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
        with self.assertRaisesRegex(RasterError, "non-negative luma"):
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
        with self.assertRaisesRegex(RasterError, "20x12 against 10x12"):
            frame_delta(png(20, 12, gradient(20, 12)), png(10, 12, gradient(10, 12)))


class StripedFrameTests(unittest.TestCase):
    """A stride sharing a factor with the width collapses sampling onto a fixed
    set of columns, and a frame of alternating black and white columns then
    reads as whichever column the stride happened to land on."""

    @staticmethod
    def large(width: int, height: int, samples: bytes) -> bytes:
        return png(width, height, samples)

    def test_a_column_striped_frame_is_not_aliased_away(self) -> None:
        width, height = 1600, 128
        samples = bytearray()
        for row in range(height):
            for column in range(width):
                value = 0 if column % 2 else 255
                samples.extend(bytes([value, value, value]))
        frame = self.large(width, height, bytes(samples))
        self.assertIsNone(all_black(frame))


if __name__ == "__main__":
    unittest.main()
