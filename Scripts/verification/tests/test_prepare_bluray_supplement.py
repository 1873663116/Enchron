from __future__ import annotations

from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "Scripts"))
from Scripts.regression.core.catalog import load_catalog
from Scripts.regression.core.frontmatter import load_frontmatter
from Scripts.verification.prepare_bluray_supplement import prepare


class BluRaySupplementTests(unittest.TestCase):
    def test_supplement_is_separate_and_catalog_loads_with_twelve_simulator_cases(self) -> None:
        scratch = ROOT / ".scratch"
        scratch.mkdir(exist_ok=True)
        with TemporaryDirectory(prefix="bluray-supplement-test-", dir=scratch) as temporary:
            output = Path(temporary) / "catalog"
            result = prepare(output)
            catalog = load_catalog(output)
            self.assertEqual(result["scenarios"], 12)
            self.assertEqual(len(catalog.promises), 2)
            self.assertEqual(len(catalog.scenarios), 12)
            self.assertEqual({item.lane.value for item in catalog.scenarios}, {"simulator"})
            self.assertFalse((ROOT / "Regression" / "bluray-disc").exists())

            avs_iso = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/avs-iso.md"
            ).metadata
            avs_directory = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/avs-directory.md"
            ).metadata
            fel_iso = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/fel-iso.md"
            ).metadata
            fel_directory = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/fel-directory.md"
            ).metadata
            sintel_iso = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/sintel-iso.md"
            ).metadata
            sintel_directory = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/sintel-directory.md"
            ).metadata
            editions_iso = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/sintel-editions-iso.md"
            ).metadata
            editions_directory = load_frontmatter(
                output / "journeys/bluray-disc/scenarios/sintel-editions-directory.md"
            ).metadata
            self.assertEqual(self._count_expectations(output, avs_iso), ["3 items", "2 items"])
            self.assertEqual(
                self._count_expectations(output, avs_directory),
                ["4 items", "4 items", "2 items"],
            )
            self.assertEqual(self._count_expectations(output, fel_iso), ["1 items"])
            self.assertEqual(self._count_expectations(output, fel_directory), ["2 items", "2 items"])
            self.assertEqual(self._count_expectations(output, sintel_iso), ["2 items"])
            self.assertEqual(
                self._count_expectations(output, sintel_directory), ["3 items", "3 items"]
            )
            self.assertEqual(self._count_expectations(output, editions_iso), ["3 items"])
            self.assertEqual(
                self._count_expectations(output, editions_directory), ["4 items", "4 items"]
            )
            editions_requested = [
                call.get("arguments", {}).get("identifier")
                for call in editions_iso["operations"]
                if call["operation"] == "operation:accessibility.inspect@2"
            ]
            self.assertIn("FileBrowsing-grid-bluray-content-1", editions_requested)
            self.assertIn("FileBrowsing-grid-bluray-content-0", editions_requested)
            self.assertIn("FileBrowsing-grid-bluray-group-additional", editions_requested)

            operations = avs_iso["operations"]
            identifiers = [
                identifier
                for call in operations
                for identifier in call.get("arguments", {}).get("identifiers", [])
            ]
            requested = [
                call.get("arguments", {}).get("identifier")
                for call in operations
                if call["operation"] == "operation:accessibility.inspect@2"
            ]
            self.assertIn("FileBrowsing-grid-bluray-group-sequences", identifiers)
            sequence_inspect = next(
                index for index, call in enumerate(operations)
                if call.get("arguments", {}).get("identifier")
                == "FileBrowsing-grid-bluray-group-sequences"
            )
            sequence_activate = next(
                index for index, call in enumerate(operations)
                if "FileBrowsing-grid-bluray-group-sequences"
                in call.get("arguments", {}).get("identifiers", [])
            )
            self.assertLess(
                sequence_inspect,
                sequence_activate,
            )
            self.assertIn("FileBrowsing-grid-bluray-content-99", requested)
            self.assertNotIn("FileBrowsing-grid-bluray-playlist-99", requested)

            rendered = "\n".join(
                path.read_text(encoding="utf-8") for path in output.rglob("*.md")
            )
            self.assertNotIn("complete playlist cards", rendered)
            self.assertNotIn("expose playlist cards", rendered)
            self.assertNotIn("Playlist ID 99", rendered)
            scenario_operations = "\n".join(
                str(load_frontmatter(path).metadata["operations"])
                for path in (output / "journeys/bluray-disc/scenarios").glob("*.md")
            )
            self.assertNotIn("grid-bluray-playlist", scenario_operations)
            self.assertIn("grid-bluray-playlist identifier", rendered)
            self.assertIn("default page shows content groups instead of 110 raw playlist cards", rendered)

    @staticmethod
    def _count_expectations(output: Path, scenario: dict) -> list[str]:
        calls = {call["callId"]: call for call in scenario["operations"]}
        values: list[str] = []
        for obligation in scenario["obligations"]:
            call = calls[obligation["producedByCall"]]
            if call["arguments"].get("identifier") != "FileBrowsing-FilesScreen-itemCount":
                continue
            rubric = next(
                load_frontmatter(path).metadata
                for path in (output / "rubrics").glob("*.md")
                if load_frontmatter(path).metadata["id"] == obligation["rubric"]
            )
            values.extend(
                value.split("'")[1]
                for value in rubric["criteria"]
                if "exactly '" in value
            )
        return values


if __name__ == "__main__":
    unittest.main()
