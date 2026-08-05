import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = REPOSITORY_ROOT / "docs" / "acceptance" / "fixture-registry.json"


class FixtureRegistryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        self.eligible = [
            fixture
            for fixture in self.registry["fixtures"]
            if fixture["acceptanceEligibility"] == "eligible-local-generated"
        ]

    def test_generated_fixtures_have_stable_device_import_contracts(self) -> None:
        self.assertEqual(self.registry["schemaVersion"], 2)
        for fixture in self.eligible:
            with self.subTest(fixture=fixture["id"]):
                self.assertRegex(fixture["sha256"], r"^[0-9a-f]{64}$")
                self.assertTrue(fixture["deviceImportPath"].startswith("Generated/"))
                self.assertNotIn("..", Path(fixture["deviceImportPath"]).parts)
                self.assertEqual(fixture["license"], "project-generated-no-external-media")
                self.assertIn("matrix", fixture)
                self.assertIn("acceptanceCriteria", fixture)

    def test_generated_matrix_covers_required_video_and_audio_inputs(self) -> None:
        video_codecs = {fixture["matrix"]["videoCodec"] for fixture in self.eligible}
        audio_codecs = {
            codec
            for fixture in self.eligible
            for codec in fixture["matrix"]["audioCodecs"]
        }
        has_video_only_fixture = any(
            fixture["matrix"]["hasAudio"] is False for fixture in self.eligible
        )

        self.assertGreaterEqual(video_codecs, {"h264", "hevc", "av1"})
        self.assertGreaterEqual(
            audio_codecs,
            {"aac", "ac3", "eac3", "mp2", "mp3", "alac", "opus", "flac"},
        )
        self.assertTrue(has_video_only_fixture)


if __name__ == "__main__":
    unittest.main()
