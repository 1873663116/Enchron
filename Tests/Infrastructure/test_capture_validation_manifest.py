import subprocess
import sys
from pathlib import Path
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import capture_validation_manifest as manifest


class ValidationManifestRepositoryFilesTests(unittest.TestCase):
    def test_evidence_records_do_not_change_the_product_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"],
                cwd=repository,
                check=True,
            )
            (repository / "Sources").mkdir()
            (repository / "Sources" / "Product.swift").write_text("product\n")
            (repository / "docs" / "acceptance" / "evidence").mkdir(parents=True)
            (repository / "docs" / "acceptance" / "evidence.md").write_text(
                "current evidence\n"
            )
            (repository / "docs" / "acceptance" / "evidence" / "run.json").write_text(
                "{}\n"
            )
            (repository / "docs" / "acceptance" / "evidence-notes.md").write_text(
                "product documentation\n"
            )

            files = {
                path.as_posix()
                for path in manifest.repository_files(repository)
            }

            self.assertIn("Sources/Product.swift", files)
            self.assertIn("docs/acceptance/evidence-notes.md", files)
            self.assertNotIn("docs/acceptance/evidence.md", files)
            self.assertNotIn("docs/acceptance/evidence/run.json", files)


if __name__ == "__main__":
    unittest.main()
