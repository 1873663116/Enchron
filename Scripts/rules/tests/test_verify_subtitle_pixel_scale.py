from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

import verify_subtitle_pixel_scale as verifier


def mapping(mode: str = "window", extent: str = "0.48x0.108", aspect: str = "1.0") -> str:
    return (
        f"123 subtitlePixelMapping presentation={mode} kind=text canvas=1920x1080 "
        f"content=480x108 extent={extent} pixelAspect={aspect}"
    )


class SubtitlePixelScaleTests(unittest.TestCase):
    def test_every_requested_presentation_has_square_pixels(self) -> None:
        result = verifier.verify_probe(
            "\n".join(mapping(mode) for mode in ("window", "docked", "portal", "panorama")),
            ["window", "docked", "portal", "panorama"],
        )
        self.assertEqual(result["passed"], True)
        self.assertEqual(result["presentations"]["panorama"], {
            "samples": 1, "minPixelAspect": 1.0, "maxPixelAspect": 1.0,
        })
        self.assertEqual(result["failures"], [])

    def test_recomputes_distortion_instead_of_trusting_reported_aspect(self) -> None:
        result = verifier.verify_probe(mapping(extent="0.96x0.108", aspect="1.0"), ["window"])
        self.assertEqual(result["passed"], False)
        self.assertEqual(result["failures"], [
            {"line": 1, "presentation": "window", "kind": "text", "pixelAspect": 2.0},
        ])

    def test_checks_all_samples_and_requires_each_requested_presentation(self) -> None:
        result = verifier.verify_probe(mapping() + "\n" + mapping(extent="0.96x0.108"), ["window", "portal"])
        self.assertEqual(result["passed"], False)
        self.assertEqual(result["presentations"]["window"]["samples"], 2)
        self.assertEqual(result["failures"][-1], {"presentation": "portal", "error": "no valid samples"})

    def test_ignores_unrequested_presentations(self) -> None:
        result = verifier.verify_probe(mapping() + "\n" + mapping("portal", "0x0"), ["window"])
        self.assertEqual(result["passed"], True)
        self.assertEqual(set(result["presentations"]), {"window"})

    def test_rejects_invalid_numeric_fields_and_malformed_records(self) -> None:
        invalid = [
            mapping(extent="0x0.108"),
            mapping(extent="-0.48x0.108"),
            mapping(extent="nanx0.108"),
            mapping(extent="infx0.108"),
            mapping(aspect="nan"),
            mapping(aspect="0"),
            mapping().replace("content=480x108", "content=480x0"),
            mapping().replace("canvas=1920x1080", "canvas=nanx1080"),
            mapping().replace("extent=0.48x0.108", "extent=invalid"),
            "subtitlePixelMapping presentation=window kind=text",
        ]
        for probe in invalid:
            with self.subTest(probe=probe):
                result = verifier.verify_probe(probe, ["window"])
                self.assertEqual(result["passed"], False)
                self.assertEqual(result["presentations"]["window"]["samples"], 0)
                json.dumps(result, allow_nan=False)

    def test_tolerance_is_inclusive(self) -> None:
        for ratio in (0.999, 1.001):
            result = verifier.verify_probe(
                mapping(extent=f"{ratio}x1").replace("content=480x108", "content=1x1"),
                ["window"],
            )
            self.assertEqual(result["passed"], True)
        result = verifier.verify_probe(
            mapping(extent="1.0011x1").replace("content=480x108", "content=1x1"),
            ["window"],
        )
        self.assertEqual(result["passed"], False)

    def test_cli_returns_json_and_failure_exit_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            probe = Path(directory) / "probe.log"
            for extent, exit_status in (("0.48x0.108", 0), ("0.96x0.108", 1)):
                probe.write_text(mapping(extent=extent), encoding="utf-8")
                result = subprocess.run(
                    [sys.executable, verifier.__file__, str(probe), "--presentation", "window"],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, exit_status)
                self.assertEqual(json.loads(result.stdout)["passed"], exit_status == 0)
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
