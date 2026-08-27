import subprocess
import sys
from pathlib import Path
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import capture_validation_manifest as manifest


class ValidationManifestRepositoryFilesTests(unittest.TestCase):
    def test_repository_files_include_tracked_and_untracked_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"],
                cwd=repository,
                check=True,
            )
            (repository / "Sources").mkdir()
            (repository / "Sources" / "Tracked.swift").write_text("tracked\n")
            subprocess.run(
                ["git", "add", "Sources/Tracked.swift"],
                cwd=repository,
                check=True,
            )
            (repository / "Sources" / "Untracked.swift").write_text("untracked\n")

            files = {
                path.as_posix()
                for path in manifest.repository_files(repository)
            }

            self.assertIn("Sources/Tracked.swift", files)
            self.assertIn("Sources/Untracked.swift", files)


if __name__ == "__main__":
    unittest.main()
