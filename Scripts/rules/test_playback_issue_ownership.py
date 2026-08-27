import sys
from pathlib import Path
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import verify_playback_issue_ownership as ownership


class PlaybackIssueOwnershipTests(unittest.TestCase):
    def create_owner(self, root: Path, declaration: str = "public private(set)") -> None:
        owner = root / ownership.OWNER
        owner.parent.mkdir(parents=True, exist_ok=True)
        owner.write_text(
            f"""public final class PlaybackRuntime {{
    {declaration} var userVisibleIssue: PlaybackUserVisibleIssue?

    public func setUserVisibleIssue(_ issue: PlaybackUserVisibleIssue?) {{
        userVisibleIssue = issue
    }}
}}
""",
            encoding="utf-8",
        )

    def test_accepts_the_single_read_only_owner(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_owner(root)

            self.assertEqual(ownership.audit_repository(root), [])

    def test_rejects_a_second_writer(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_owner(root)
            source = root / "Apps/Enchron/UnexpectedWriter.swift"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("runtime.userVisibleIssue = issue\n", encoding="utf-8")

            rules = {violation.rule for violation in ownership.audit_repository(root)}

            self.assertIn("playback-issue-write-outside-owner", rules)

    def test_ignores_assignments_in_comments_and_strings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_owner(root)
            source = root / "Apps/Enchron/NonCode.swift"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(
                """// runtime.userVisibleIssue = issue
let example = "runtime.userVisibleIssue = issue"
""",
                encoding="utf-8",
            )

            self.assertEqual(ownership.audit_repository(root), [])

    def test_rejects_a_legacy_channel_in_playback_scope(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_owner(root)
            source = root / "Modules/Playback/Legacy.swift"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("var subtitleErrorMessage: String?\n", encoding="utf-8")

            rules = {violation.rule for violation in ownership.audit_repository(root)}

            self.assertIn("legacy-playback-error-channel", rules)


if __name__ == "__main__":
    unittest.main()
