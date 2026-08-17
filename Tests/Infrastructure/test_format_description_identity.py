import sys
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts" / "verification"))
import verify_format_description_identity as identity


class FormatDescriptionIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = identity.load_baseline(identity.DEFAULT_BASELINE)

    def test_baseline_uses_declaration_shapes_and_expected_counts(self) -> None:
        self.assertEqual(
            self.baseline.expected_counts,
            {
                "prores-limited-range-default": 8,
                "prores-frame-matrix": 5,
                "h264-unspecified-range-default": 1,
                "unsupported-prores-raw": 1,
                "unsupported-mpeg4-part-2": 1,
            },
        )
        for rule in (
            *self.baseline.exemptions,
            *self.baseline.capability_boundaries,
        ):
            self.assertNotIn("path", rule.declaration)
            self.assertTrue(rule.reason)

    def test_prores_limited_range_exemption_matches_only_its_shape(self) -> None:
        rule = next(
            rule for rule in self.baseline.exemptions
            if rule.identifier == "prores-limited-range-default"
        )
        difference = identity.Difference("full_range", "0", "none")
        prores = identity.Declaration(
            Path("arbitrary.mov"),
            {"codec_name": "prores", "color_range": "tv"},
            None,
        )
        h264 = identity.Declaration(
            Path("arbitrary.mp4"),
            {"codec_name": "h264", "color_range": "tv"},
            None,
        )

        self.assertTrue(rule.matches(prores, difference))
        self.assertFalse(rule.matches(h264, difference))

    def test_capability_boundary_requires_codec_and_error_shape(self) -> None:
        rule = next(
            rule for rule in self.baseline.capability_boundaries
            if rule.identifier == "unsupported-mpeg4-part-2"
        )
        declaration = identity.Declaration(
            Path("arbitrary.avi"),
            {"codec_name": "mpeg4"},
            None,
        )

        self.assertTrue(rule.matches(
            declaration,
            "Unsupported codec: mpeg4 is not available for compressed sample "
            "rendering on this device",
        ))
        self.assertFalse(rule.matches(declaration, "probe timed out"))


if __name__ == "__main__":
    unittest.main()
