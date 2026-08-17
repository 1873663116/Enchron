import sys
from pathlib import Path
import tempfile
import textwrap
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import verify_media_discovery_admission as admission


OWNER = """
nonisolated extension FileBrowsingDomain {
    public struct MediaDiscoveryAdmissionPolicy {
        public static let mediaFiles = MediaDiscoveryAdmissionPolicy(
            allowedExtensions: ["mp4", "mkv", "iso"]
        )
    }
}
"""


class MediaDiscoveryAdmissionCheckTests(unittest.TestCase):
    def repository(self, extra_sources: dict[str, str] | None = None) -> tempfile.TemporaryDirectory:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        owner = root / admission.ALLOWED_SUFFIX_ARRAY.path
        owner.parent.mkdir(parents=True)
        owner.write_text(textwrap.dedent(OWNER), encoding="utf-8")
        for relative, source in (extra_sources or {}).items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(textwrap.dedent(source), encoding="utf-8")
        return temporary

    def test_exact_owner_without_duplicates_passes(self) -> None:
        with self.repository() as directory:
            self.assertEqual(admission.audit_repository(Path(directory)), [])

    def test_video_suffix_array_outside_owner_fails(self) -> None:
        with self.repository({
            "Apps/Enchron/Files.swift": 'let extensions = ["mp4", "srt"]',
        }) as directory:
            violations = admission.audit_repository(Path(directory))

        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].rule, "duplicate-media-suffix-array")
        self.assertIn("mp4", violations[0].message)

    def test_comments_and_subtitle_suffixes_do_not_fail(self) -> None:
        with self.repository({
            "Modules/Feature/Source.swift": """
                // let oldVideoExtensions = ["mp4", "mkv"]
                let subtitleExtensions = ["srt", "vtt", "ass"]
            """,
        }) as directory:
            self.assertEqual(admission.audit_repository(Path(directory)), [])

    def test_missing_owner_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "Apps").mkdir()
            violations = admission.audit_repository(Path(directory))

        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].rule, "media-discovery-owner")


if __name__ == "__main__":
    unittest.main()
