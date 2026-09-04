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
                "h264-unspecified-range-default": 3,
                "playback-behaviour-truncated-clip": 1,
                "unsupported-prores-raw": 1,
                "unsupported-mpeg4-part-2": 3,
                "unsupported-mpeg2-video": 1,
                "unsupported-vp9": 1,
            },
        )
        for rule in (
            *self.baseline.exemptions,
            *self.baseline.capability_boundaries,
        ):
            self.assertNotIn("path", rule.declaration)
            self.assertTrue(rule.reason)
            self.assertTrue(rule.evidence)

    def test_expected_facts_preserve_declared_srgb_transfer(self) -> None:
        declaration = identity.Declaration(
            Path("arbitrary.mov"),
            {
                "codec_name": "h264",
                "codec_tag_string": "avc1",
                "color_transfer": "iec61966-2-1",
            },
            None,
        )

        self.assertEqual(
            identity.expected_facts(declaration)["transfer"],
            "IEC_sRGB",
        )

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


    def test_an_unreadable_fixture_is_named_by_path_and_nothing_else(self) -> None:
        rule = next(
            item for item in self.baseline.unreadable_fixtures
            if item.identifier == "playback-behaviour-truncated-clip"
        )

        self.assertTrue(rule.matches(rule.path))
        self.assertFalse(rule.matches(rule.path + ".bak"))
        self.assertFalse(
            rule.matches("TestVectors/Enchron/PlaybackBehavior/other.mp4")
        )
        self.assertTrue(rule.reason)
        self.assertTrue(rule.evidence)

    def test_a_fixture_entry_without_its_reason_is_refused(self) -> None:
        import json
        from tempfile import TemporaryDirectory

        payload = json.loads(identity.DEFAULT_BASELINE.read_text(encoding="utf-8"))
        payload["knownUnreadableFixtures"][0].pop("reason")
        with TemporaryDirectory() as temporary:
            path = Path(temporary) / "baseline.json"
            path.write_text(json.dumps(payload), encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "non-empty reason"):
                identity.load_baseline(path)


if __name__ == "__main__":
    unittest.main()
