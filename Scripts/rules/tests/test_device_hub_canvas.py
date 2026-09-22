from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

import numpy

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from Scripts.verification.device_hub_canvas import (
    CanvasError,
    _canvas_pixel_rect,
    _glyph_spans,
    _pointer_mode_index,
    bind_booted_vision_target,
)


class DeviceHubCanvasTests(unittest.TestCase):
    def test_canvas_detection_tolerates_bright_content_across_part_of_the_view(self) -> None:
        image = numpy.full((420, 700, 3), 255, dtype=numpy.int16)
        for row in range(20, 380):
            image[row, 30:670] = 40 + row % 100
        image[20:180, 500:670] = 255

        self.assertEqual(
            _canvas_pixel_rect(image),
            {"x": 30, "y": 20, "width": 640, "height": 360},
        )

    def test_toolbar_glyph_detection_ignores_white_background_and_dark_window_edges(self) -> None:
        band = numpy.full((52, 1000), 245, dtype=numpy.int16)
        band[:, :8] = 0
        band[:, -8:] = 0
        for index in range(10):
            left = 220 + index * 58
            band[18:34, left : left + 14] = 20

        spans, _ = _glyph_spans(band)

        self.assertEqual(len(spans), 10)
        self.assertTrue(all(span[0] >= 220 for span in spans))

    def test_pointer_mode_index_tracks_the_recording_toolbar_variant(self) -> None:
        self.assertEqual(_pointer_mode_index(10), 3)
        self.assertEqual(_pointer_mode_index(11), 4)

        with self.assertRaises(CanvasError):
            _pointer_mode_index(12)

    def test_target_binding_requires_the_one_booted_vision_simulator(self) -> None:
        listing = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.xrOS-27-0": [
                    {
                        "udid": "SIM-1",
                        "name": "Apple Vision Pro",
                        "state": "Booted",
                        "deviceTypeIdentifier": (
                            "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-4K"
                        ),
                    }
                ],
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                    {
                        "udid": "PHONE-1",
                        "name": "iPhone",
                        "state": "Booted",
                        "deviceTypeIdentifier": (
                            "com.apple.CoreSimulator.SimDeviceType.iPhone-18"
                        ),
                    }
                ],
            }
        }
        completed = subprocess.CompletedProcess(
            [], 0, json.dumps(listing), ""
        )
        with mock.patch(
            "Scripts.verification.device_hub_canvas._run",
            return_value=completed,
        ):
            self.assertEqual(
                bind_booted_vision_target("sim-1"),
                {
                    "device": "SIM-1",
                    "name": "Apple Vision Pro",
                    "runtime": "com.apple.CoreSimulator.SimRuntime.xrOS-27-0",
                },
            )

    def test_target_binding_rejects_a_different_or_ambiguous_simulator(self) -> None:
        entry = {
            "udid": "SIM-1",
            "name": "Apple Vision Pro",
            "state": "Booted",
            "deviceTypeIdentifier": (
                "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-4K"
            ),
        }
        with self.subTest("different target"), mock.patch(
            "Scripts.verification.device_hub_canvas._run",
            return_value=subprocess.CompletedProcess(
                [], 0, json.dumps({"devices": {"xrOS": [entry]}}), ""
            ),
        ), self.assertRaisesRegex(CanvasError, "not requested target"):
            bind_booted_vision_target("SIM-2")

        with self.subTest("ambiguous targets"), mock.patch(
            "Scripts.verification.device_hub_canvas._run",
            return_value=subprocess.CompletedProcess(
                [],
                0,
                json.dumps(
                    {
                        "devices": {
                            "xrOS": [entry, {**entry, "udid": "SIM-2"}]
                        }
                    }
                ),
                "",
            ),
        ), self.assertRaisesRegex(CanvasError, "exactly one"):
            bind_booted_vision_target("SIM-1")


if __name__ == "__main__":
    unittest.main()
