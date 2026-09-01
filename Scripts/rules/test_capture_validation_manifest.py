import os
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest


GIT_REDIRECTS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_QUARANTINE_PATH",
)


def unredirected_environment() -> dict[str, str]:
    """An environment that lets git believe the directory it was handed.

    These variables outrank cwd, so a fixture built with `git init` in a
    temporary directory lands in whatever repository they name instead. A
    pre-push hook exports GIT_DIR, so a run started by pushing would build no
    fixture, write core.bare onto the repository doing the pushing, and report
    the damage as this check failing.
    """
    return {
        name: value
        for name, value in os.environ.items()
        if name not in GIT_REDIRECTS
    }


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import capture_validation_manifest as manifest


class GitRedirectIsolationTests(unittest.TestCase):
    def test_a_fixture_repository_is_built_where_it_was_asked_for(self) -> None:
        """GIT_DIR outranks cwd, and a pre-push hook exports it.

        Without the stripped environment `git init` walks away with the
        repository GIT_DIR names, leaves the temporary directory empty, and
        writes core.bare onto whatever it re-initialised. Both temporary
        directories here are throwaway, so a regression damages neither.
        """
        with tempfile.TemporaryDirectory() as wanted, \
                tempfile.TemporaryDirectory() as decoy:
            subprocess.run(["git", "init", "--quiet"], cwd=decoy, check=True,
                           env=unredirected_environment())
            hostile = dict(os.environ, GIT_DIR=str(Path(decoy) / ".git"))
            environment = {
                name: value
                for name, value in hostile.items()
                if name not in GIT_REDIRECTS
            }

            subprocess.run(["git", "init", "--quiet"], cwd=wanted, check=True,
                           env=environment)

            self.assertTrue((Path(wanted) / ".git").is_dir())
            bare = subprocess.run(
                ["git", "config", "--file", str(Path(decoy) / ".git" / "config"),
                 "--get", "core.bare"],
                capture_output=True, text=True,
            )
            self.assertNotEqual(bare.stdout.strip(), "true")


class ValidationManifestRepositoryFilesTests(unittest.TestCase):
    def test_repository_files_include_tracked_and_untracked_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"],
                cwd=repository,
                check=True,
                env=unredirected_environment(),
            )
            (repository / "Sources").mkdir()
            (repository / "Sources" / "Tracked.swift").write_text("tracked\n")
            subprocess.run(
                ["git", "add", "Sources/Tracked.swift"],
                cwd=repository,
                check=True,
                env=unredirected_environment(),
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
