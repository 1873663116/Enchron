import hashlib
import json
from pathlib import Path, PurePosixPath
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = REPOSITORY_ROOT / "Tests" / "Fixtures" / "fixture-registry.json"
TEST_MEDIA_ROOT = (REPOSITORY_ROOT.parent / "TestMedia").resolve()
REGRESSION_SETS = frozenset(
    {
        "audio-only",
        "dynamic-range",
        "format-corpus",
        "presentation-tour",
        "projection-stereo",
        "remote-aggregate",
        "system-import",
        "viewing-storage",
    }
)
EXPECTED_MEMBERSHIPS = {
    "generated-sdr-avc-bframe-multiaudio-avsync-30s-v1": (
        "system-import",
        "viewing-storage",
    ),
    "generated-hlg-hevc10-avsync-10s-v1": ("dynamic-range",),
    "generated-pq-hevc10-avsync-10s-v1": ("dynamic-range",),
    "generated-sdr-avc-bframe-multiaudio-subtitles-30s-v3": ("format-corpus",),
    "generated-sdr-avc-bframe-aggregate-30s-v1": (
        "remote-aggregate",
        "viewing-storage",
    ),
    "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1": (
        "presentation-tour",
        "viewing-storage",
    ),
    "generated-sdr-avc-bframe-video-only-15s-v1": ("format-corpus",),
    "generated-sdr-avc-bframe-audio-codec-matrix-15s-v1": ("format-corpus",),
    "generated-sdr-avc-bframe-duplicate-label-audio-30s-v1": ("format-corpus",),
    "generated-av1-flac-avsync-10s-v1": ("format-corpus",),
    "generated-external-subrip-zh-cn-v1": ("format-corpus",),
    "generated-external-ass-styled-v1": ("format-corpus",),
    "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1": (
        "remote-aggregate",
    ),
    "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1": (
        "remote-aggregate",
    ),
    "internal-fate-alac-cover-art-v1": ("audio-only",),
    "internal-fate-mpeg4-part2-packed-bframes-v1": ("format-corpus",),
    "internal-fate-dts-es-matroska-v1": ("audio-only", "format-corpus"),
    "internal-fate-truehd-atmos-matroska-v1": ("audio-only", "format-corpus"),
    "internal-fate-vorbis-v1": ("audio-only", "format-corpus"),
    "internal-dolby-vision-p5-hd-v1": ("dynamic-range",),
    "internal-dolby-vision-p7-fel-v1": ("dynamic-range",),
    "internal-dolby-vision-p81-hdr10-hd-v1": ("dynamic-range",),
    "internal-dolby-vision-p84-hlg-hd-v1": ("dynamic-range",),
    "internal-dolby-vision-p100-av1-v1": ("dynamic-range",),
    "internal-dolby-vision-p101-av1-v1": ("dynamic-range",),
    "internal-dolby-vision-p104-av1-v1": ("dynamic-range",),
    "internal-apple-dolby-vision-p20-3d-v1": (
        "dynamic-range",
        "projection-stereo",
    ),
    "internal-spatial-180-sbs-v1": ("presentation-tour", "projection-stereo"),
    "internal-spatial-180-tb-v1": ("projection-stereo",),
    "internal-spatial-360-mono-v1": ("presentation-tour", "projection-stereo"),
    "internal-apple-mvhevc-short-v1": ("format-corpus", "projection-stereo"),
    "internal-apple-apmp-180-v1": ("format-corpus", "projection-stereo"),
    "internal-apple-apmp-360-v1": ("projection-stereo",),
    "internal-apple-immersive-video-beach-v1": ("projection-stereo",),
    "generated-viewing-storage-h264-16m01s-v1": ("viewing-storage",),
    "generated-viewing-storage-h264-16m01s-b-v1": ("viewing-storage",),
}
EXPECTED_INTERNAL_PATHS = {
    "TestVectors/Upstream/FATE/ALAC/inside.m4a",
    "TestVectors/Upstream/FATE/MPEG4-Part2/packed_bframes.avi",
    "TestVectors/Upstream/FATE/DTS/dts_es.mkv",
    "TestVectors/Upstream/FATE/TrueHD/atmos.mkv",
    "TestVectors/Upstream/FATE/Vorbis/1.0-test_small.ogg",
    "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
    "Samples/DynamicRange/DolbyVision/Profile7.6/FEL_test_for_AVS.mp4",
    "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
    "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
    "Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.0/media-video-dav1-dav1-1.mp4",
    "Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.1/media-video-av01-dav1-db1p-1.mp4",
    "Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.4/media-video-av01-dav1-db4h-1.mp4",
    "Samples/DynamicRange/DolbyVision/Profile20/Apple-Streaming-Examples/3D-example.mp4",
    "Samples/Spatial/Stereo180/180_3D.mp4",
    "Samples/Spatial/Stereo180/180_3D_TB.mp4",
    "Samples/Spatial/Panorama/360.mp4",
    "Samples/Spatial/MVHEVC-Apple-Official/spatial_lighthouse_flowers_waves_short.mov",
    "Samples/Spatial/Stereo180/Apple-Streaming-Examples/APMP-180-example.mp4",
    "Samples/Spatial/Panorama/Apple-Streaming-Examples/APMP-360-example.mp4",
    "Samples/Spatial/Apple-Immersive/Apple-Streaming-Examples/Immersive-Video-example.f99766.mp4",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


class FixtureRegistryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        self.fixtures = self.registry["fixtures"]
        self.stageable = [item for item in self.fixtures if "deviceImportPath" in item]
        self.by_id = {item["id"]: item for item in self.fixtures}
        self.eligible_generated = [
            item
            for item in self.fixtures
            if item["acceptanceEligibility"] == "eligible-local-generated"
        ]

    def fixtures_for(self, regression_set: str) -> list[dict[str, object]]:
        return [
            item
            for item in self.stageable
            if regression_set in item["regressionSets"]
        ]

    def test_population_ids_and_workspace_source_root_are_exact(self) -> None:
        self.assertEqual(self.registry["schemaVersion"], 2)
        self.assertEqual(self.registry["deviceMediaRoot"], "$WORKSPACE/TestMedia")
        self.assertEqual(len(self.fixtures), 37)
        self.assertEqual(len(self.stageable), 36)
        self.assertEqual(len(self.by_id), 37)

    def test_every_stageable_fixture_has_a_safe_digest_bound_path(self) -> None:
        for fixture in self.stageable:
            with self.subTest(fixture=fixture["id"]):
                raw_path = fixture["deviceImportPath"]
                path = PurePosixPath(raw_path)
                self.assertFalse(path.is_absolute())
                self.assertNotIn("\\", raw_path)
                self.assertNotIn("..", path.parts)
                self.assertNotIn(path.name, ("", ".", ".."))
                self.assertRegex(fixture["sha256"], r"^[0-9a-f]{64}$")
                self.assertGreater(fixture["durationSeconds"], 0)
                self.assertIn("matrix", fixture)

    def test_every_registered_stageable_digest_matches_workspace_bytes(self) -> None:
        if not TEST_MEDIA_ROOT.is_dir():
            self.skipTest("workspace TestMedia is not available")
        for fixture in self.stageable:
            with self.subTest(fixture=fixture["id"]):
                source = (TEST_MEDIA_ROOT / fixture["deviceImportPath"]).resolve()
                self.assertTrue(source.is_relative_to(TEST_MEDIA_ROOT))
                self.assertTrue(source.is_file(), source)
                self.assertEqual(sha256(source), fixture["sha256"])

    def test_regression_set_membership_is_closed_and_exact(self) -> None:
        self.assertNotIn("fixtureSets", self.registry)
        self.assertNotIn("regressionSets", self.registry)
        actual = {
            fixture["id"]: tuple(fixture["regressionSets"])
            for fixture in self.stageable
        }
        self.assertEqual(actual, EXPECTED_MEMBERSHIPS)
        observed_sets = {
            regression_set
            for memberships in actual.values()
            for regression_set in memberships
        }
        self.assertEqual(observed_sets, REGRESSION_SETS)
        for fixture_id, memberships in actual.items():
            with self.subTest(fixture=fixture_id):
                self.assertTrue(memberships)
                self.assertEqual(len(memberships), len(set(memberships)))
                self.assertEqual(memberships, tuple(sorted(memberships)))

    def test_internal_corpus_paths_license_and_eligibility_are_exact(self) -> None:
        internal = [
            fixture
            for fixture in self.stageable
            if fixture["id"].startswith("internal-")
        ]
        self.assertEqual(len(internal), 20)
        self.assertEqual(
            {fixture["deviceImportPath"] for fixture in internal},
            EXPECTED_INTERNAL_PATHS,
        )
        for fixture in internal:
            with self.subTest(fixture=fixture["id"]):
                self.assertEqual(fixture["license"], "internal-test-media-only")
                self.assertEqual(
                    fixture["acceptanceEligibility"], "eligible-internal-only"
                )

    def test_audio_only_set_covers_exact_candidates_and_cover_art(self) -> None:
        fixtures = self.fixtures_for("audio-only")
        self.assertEqual(
            {fixture["id"] for fixture in fixtures},
            {
                "internal-fate-alac-cover-art-v1",
                "internal-fate-dts-es-matroska-v1",
                "internal-fate-truehd-atmos-matroska-v1",
                "internal-fate-vorbis-v1",
            },
        )

    def test_duplicate_label_audio_fixture_binds_stable_tracks_and_pulses(self) -> None:
        fixture = self.by_id[
            "generated-sdr-avc-bframe-duplicate-label-audio-30s-v1"
        ]
        self.assertEqual(
            fixture["oracle"],
            {
                "audioTrackCount": 3,
                "tracks": [
                    {"streamIndex": 1, "title": "Primary", "pulseFrequencyHz": 880},
                    {"streamIndex": 2, "title": "Alternate", "pulseFrequencyHz": 440},
                    {"streamIndex": 3, "title": "Alternate", "pulseFrequencyHz": 660},
                ],
            },
        )
        self.assertEqual(
            self.by_id["internal-fate-alac-cover-art-v1"]["oracle"],
            {
                "audioProfile": "ALAC 16-bit",
                "sampleRateHz": 44100,
                "channels": 2,
                "channelLayout": "stereo",
                "attachedPictureCodec": "png",
                "attachedPictureWidth": 200,
                "attachedPictureHeight": 200,
                "attachedPictureDisposition": True,
            },
        )

    def test_dynamic_range_set_covers_required_profiles_and_transfers(self) -> None:
        fixtures = self.fixtures_for("dynamic-range")
        profiles = {
            fixture["oracle"]["dolbyVisionProfile"]
            for fixture in fixtures
            if "dolbyVisionProfile" in fixture.get("oracle", {})
        }
        transfers = {
            fixture["oracle"]["transferFunction"]
            for fixture in fixtures
            if "transferFunction" in fixture.get("oracle", {})
        }
        compatibility_ids = {
            fixture["oracle"]["dolbyVisionCompatibilityID"]
            for fixture in fixtures
            if "dolbyVisionCompatibilityID" in fixture.get("oracle", {})
        }
        self.assertEqual(len(fixtures), 10)
        self.assertEqual(profiles, {5, 7, 8, 10, 20})
        self.assertGreaterEqual(transfers, {"smpte2084", "arib-std-b67"})
        self.assertGreaterEqual(compatibility_ids, {0, 1, 4, 6})

    def test_projection_set_covers_required_projection_and_stereo_facts(self) -> None:
        fixtures = self.fixtures_for("projection-stereo")
        projections = {fixture["oracle"]["projection"] for fixture in fixtures}
        stereo_layouts = {fixture["oracle"]["stereoLayout"] for fixture in fixtures}
        horizontal_coverage = {
            fixture["oracle"]["horizontalFieldOfViewDegrees"]
            for fixture in fixtures
            if "horizontalFieldOfViewDegrees" in fixture["oracle"]
        }
        self.assertEqual(len(fixtures), 8)
        self.assertEqual(
            projections,
            {
                "rectilinear",
                "equirectangular180",
                "equirectangular360",
                "appleImmersiveVideo",
            },
        )
        self.assertEqual(
            stereo_layouts,
            {"mono", "multiview", "sideBySide", "topBottom"},
        )
        self.assertGreaterEqual(horizontal_coverage, {180, 360})
        self.assertEqual(
            {
                fixture["id"]
                for fixture in fixtures
                if fixture["id"].startswith("internal-apple-apmp-")
            },
            {"internal-apple-apmp-180-v1", "internal-apple-apmp-360-v1"},
        )

    def test_format_presentation_storage_import_and_remote_sets_are_exact(self) -> None:
        format_fixtures = self.fixtures_for("format-corpus")
        audio_codecs = {
            codec
            for fixture in format_fixtures
            for codec in fixture["matrix"]["audioCodecs"]
        }
        subtitle_codecs = {
            codec
            for fixture in format_fixtures
            for codec in fixture["matrix"]["subtitleCodecs"]
        }
        self.assertGreaterEqual(
            audio_codecs,
            {"aac", "ac3", "eac3", "dts", "truehd", "vorbis", "flac"},
        )
        self.assertGreaterEqual(subtitle_codecs, {"subrip", "ass", "dvb_subtitle"})
        self.assertEqual(
            {fixture["id"] for fixture in self.fixtures_for("remote-aggregate")},
            {
                "generated-sdr-avc-bframe-aggregate-30s-v1",
                "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
                "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
            },
        )
        self.assertEqual(
            [fixture["id"] for fixture in self.fixtures_for("system-import")],
            ["generated-sdr-avc-bframe-multiaudio-avsync-30s-v1"],
        )
        self.assertTrue(
            all(
                fixture["durationSeconds"] >= 30
                for fixture in self.fixtures_for("presentation-tour")
            )
        )
        viewing = self.fixtures_for("viewing-storage")
        self.assertEqual(
            [fixture["id"] for fixture in viewing],
            [
                "generated-sdr-avc-bframe-multiaudio-avsync-30s-v1",
                "generated-sdr-avc-bframe-aggregate-30s-v1",
                "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
                "generated-viewing-storage-h264-16m01s-v1",
                "generated-viewing-storage-h264-16m01s-b-v1",
            ],
        )
        self.assertTrue(
            all(fixture["durationSeconds"] == 961.0 for fixture in viewing[-2:])
        )
        self.assertTrue(
            all(fixture["durationSeconds"] > 15 * 60 for fixture in viewing[-2:])
        )
        self.assertEqual(
            {round(fixture["durationSeconds"]) for fixture in viewing[:-2]},
            {30, 120},
        )

    def test_generated_fixtures_have_stable_device_import_contracts(self) -> None:
        for fixture in self.eligible_generated:
            with self.subTest(fixture=fixture["id"]):
                self.assertTrue(
                    fixture["deviceImportPath"].startswith(
                        "TestVectors/Enchron/PlaybackBehavior/"
                    )
                )
                self.assertEqual(
                    fixture["license"], "project-generated-no-external-media"
                )
                self.assertIn("acceptanceCriteria", fixture)

    def test_generated_matrix_covers_required_video_and_audio_inputs(self) -> None:
        video_codecs = {
            fixture["matrix"]["videoCodec"] for fixture in self.eligible_generated
        }
        audio_codecs = {
            codec
            for fixture in self.eligible_generated
            for codec in fixture["matrix"]["audioCodecs"]
        }
        self.assertGreaterEqual(video_codecs, {"h264", "hevc", "av1"})
        self.assertGreaterEqual(
            audio_codecs,
            {"aac", "ac3", "eac3", "mp2", "mp3", "alac", "opus", "flac"},
        )
        self.assertTrue(
            any(
                fixture["matrix"]["hasAudio"] is False
                for fixture in self.eligible_generated
            )
        )


if __name__ == "__main__":
    unittest.main()
