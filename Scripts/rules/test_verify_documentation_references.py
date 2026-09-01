#!/usr/bin/env python3

"""The extractor has to tell a path from a slash-separated enumeration.

Prose about codecs and URL schemes is full of tokens like `hvcC/avcC` that a
naive reader turns into a missing file, and a check that cries wolf gets
switched off. These cases are the ones that decide whether a candidate counts.
"""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "rules"))

import verify_documentation_references as checker
from verify_documentation_references import (
    REPOSITORY_ROOT,
    absolute_candidates,
    repository_candidates,
    strip_locator,
    tracked_text_files,
)

DOCUMENT = REPOSITORY_ROOT / "docs/archive/plans/04-regression-journeys/supported-formats.md"


class RepositoryCandidates(unittest.TestCase):
    def test_repository_anchored_path_counts(self) -> None:
        found = repository_candidates("see `Modules/Emby/EmbyClient.swift`", DOCUMENT)
        self.assertEqual(found, {"Modules/Emby/EmbyClient.swift"})

    def test_enumeration_is_not_a_path(self) -> None:
        prose = "containers `hvcC/avcC/av1C`, schemes `file/http/https`, subs `srt/vtt/ass`"
        self.assertEqual(repository_candidates(prose, DOCUMENT), set())

    def test_relative_link_resolves_against_the_document(self) -> None:
        found = repository_candidates("[byte stream](../../adr/README.md)", DOCUMENT)
        self.assertEqual(found, {"docs/archive/adr/README.md"})

    def test_sibling_without_a_marker_is_left_alone(self) -> None:
        self.assertEqual(repository_candidates("see `overview.md`", DOCUMENT), set())

    def test_non_markdown_call_is_not_a_link(self) -> None:
        source = REPOSITORY_ROOT / "Scripts/regression/core/ids.py"
        self.assertEqual(repository_candidates("return TYPES[kind](value)", source), set())

    def test_glob_and_placeholder_are_skipped(self) -> None:
        prose = "`Packages/*/Headers/x.h` and `Scripts/verification/<name>.py`"
        self.assertEqual(repository_candidates(prose, DOCUMENT), set())


class Locators(unittest.TestCase):
    def test_line_range_is_stripped(self) -> None:
        self.assertEqual(strip_locator("Modules/Emby/EmbyScreens.swift:433-447"), "Modules/Emby/EmbyScreens.swift")

    def test_anchor_is_stripped(self) -> None:
        self.assertEqual(strip_locator("docs/archive/adr/README.md#status"), "docs/archive/adr/README.md")

    def test_trailing_chinese_punctuation_is_stripped(self) -> None:
        self.assertEqual(
            strip_locator("Scripts/verification/regression_operation_adapter.py）"),
            "Scripts/verification/regression_operation_adapter.py",
        )


class AbsoluteCandidates(unittest.TestCase):
    def test_volume_path_is_found(self) -> None:
        found = absolute_candidates("built into /Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedData now")
        self.assertIn("/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedData", found)

    def test_placeholder_volume_path_is_skipped(self) -> None:
        self.assertEqual(absolute_candidates("/Volumes/Cortisol/<topic>/DerivedData"), set())


class TheCheckItself(unittest.TestCase):
    def test_repository_root_is_this_checkout(self) -> None:
        self.assertTrue((REPOSITORY_ROOT / "AGENTS.md").exists())
        self.assertEqual(REPOSITORY_ROOT, Path(__file__).resolve().parents[2])

    def test_deleted_tracked_files_are_not_scanned(self) -> None:
        self.assertTrue(all(path.is_file() for path in tracked_text_files()))


class CurrentRepositoryFiles(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.repository_root = Path(self.temporary_directory.name).resolve()
        subprocess.run(["git", "init", "--quiet"], cwd=self.repository_root, check=True)
        self.write("Config/retired_documents.json", '{"retired": []}\n')

        checker_patch = patch.multiple(
            checker,
            REPOSITORY_ROOT=self.repository_root,
            INSTRUCTION_ROOTS=("Config", "docs"),
            HISTORY_ROOTS=(),
            SELF=(),
            RETIRED_DOCUMENTS_PATH=self.repository_root / "Config/retired_documents.json",
            TOP_LEVEL_SEGMENTS=frozenset({"Config", "docs"}),
        )
        checker_patch.start()
        self.addCleanup(checker_patch.stop)

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def track(self, *relative: str) -> None:
        subprocess.run(["git", "add", "--", *relative], cwd=self.repository_root, check=True)

    def test_untracked_instruction_document_with_dead_link_is_reported(self) -> None:
        tracked = self.write("docs/tracked.md", "# Tracked\n")
        self.track("docs/tracked.md")
        untracked = self.write("docs/untracked.md", "[dead](./missing.md)\n")

        files = checker.tracked_text_files()
        self.assertIn(tracked, files)
        self.assertIn(untracked, files)
        errors, _ = checker.unresolved_references()
        self.assertEqual(errors, ["docs/untracked.md: docs/missing.md does not exist"])

    def test_missing_gitignored_reference_is_provisioned_not_stale(self) -> None:
        self.write(".gitignore", "*.local.json\n")
        self.track(".gitignore")
        self.write("docs/setup.md", "Read `docs/Credentials.local.json` first.\n")
        self.track("docs/setup.md")

        errors, _ = checker.unresolved_references()
        self.assertEqual(errors, [])

    def test_missing_tracked_style_reference_still_fails_beside_ignored_one(self) -> None:
        self.write(".gitignore", "*.local.json\n")
        self.track(".gitignore")
        self.write(
            "docs/setup.md",
            "Read `docs/Credentials.local.json` then `docs/absent.md`.\n",
        )
        self.track("docs/setup.md")

        errors, _ = checker.unresolved_references()
        self.assertEqual(errors, ["docs/setup.md: docs/absent.md does not exist"])

    def test_sibling_file_link_resolves_from_containing_document(self) -> None:
        document = self.write("docs/journeys/index.md", "[J13](J13.md)\n")
        self.write("docs/journeys/J13.md", "# J13\n")

        self.assertEqual(
            checker.repository_candidates(document.read_text(encoding="utf-8"), document),
            {"docs/journeys/J13.md"},
        )
        self.assertEqual(checker.unresolved_references()[0], [])

    def test_sibling_directory_link_resolves_from_containing_document(self) -> None:
        document = self.write("docs/README.md", "[journeys](journeys/index.md)\n")
        self.write("docs/journeys/index.md", "# Journeys\n")

        self.assertEqual(
            checker.repository_candidates(document.read_text(encoding="utf-8"), document),
            {"docs/journeys/index.md"},
        )
        self.assertEqual(checker.unresolved_references()[0], [])

    def test_external_url_is_not_a_repository_reference(self) -> None:
        document = self.write("docs/external.md", "[site](https://example.com/J13.md#details)\n")

        self.assertEqual(
            checker.repository_candidates(document.read_text(encoding="utf-8"), document),
            set(),
        )
        self.assertEqual(checker.unresolved_references()[0], [])

    def test_ignored_instruction_document_is_not_scanned(self) -> None:
        self.write(".gitignore", "docs/ignored.md\n")
        ignored = self.write("docs/ignored.md", "[dead](./missing.md)\n")

        self.assertNotIn(ignored, checker.tracked_text_files())
        self.assertEqual(checker.unresolved_references()[0], [])

    def test_instruction_link_below_retired_directory_fails(self) -> None:
        self.write(
            "Config/retired_documents.json",
            '{"retired": [{"path": "docs/journeys/", "replacement": "Regression/journeys/"}]}\n',
        )
        self.write("docs/index.md", "[J13](journeys/J13.md)\n")

        errors, notes = checker.unresolved_references()
        self.assertEqual(
            errors,
            ["docs/index.md: docs/journeys/J13.md retired, now Regression/journeys/"],
        )
        self.assertEqual(notes, [])

    def test_history_link_below_retired_directory_stays_a_note(self) -> None:
        self.write(
            "Config/retired_documents.json",
            '{"retired": [{"path": "docs/journeys/", "replacement": "Regression/journeys/"}]}\n',
        )
        self.write("docs/archive/index.md", "[J13](../journeys/J13.md)\n")

        with patch.multiple(checker, HISTORY_ROOTS=("docs/archive",)):
            errors, notes = checker.unresolved_references()
        self.assertEqual(errors, [])
        self.assertEqual(
            notes,
            ["docs/archive/index.md: docs/journeys/J13.md retired, now Regression/journeys/"],
        )

    def test_catalog_source_link_resolves_from_materialized_regression_location(self) -> None:
        document = self.write(
            "Config/regression/catalog-root/execution-protocol.md",
            "[skill](../.agents/skills/vp-e2e/SKILL.md)\n",
        )
        self.write(".agents/skills/vp-e2e/SKILL.md", "# Skill\n")

        self.assertEqual(
            checker.repository_candidates(
                document.read_text(encoding="utf-8"),
                checker.materialized_document(document),
            ),
            {".agents/skills/vp-e2e/SKILL.md"},
        )
        self.assertEqual(checker.unresolved_references()[0], [])

    def test_only_repository_build_outputs_are_exempt_from_absolute_path_checks(self) -> None:
        document = self.write("docs/generated-output.md", "Runtime output paths.\n")
        build_output = str(self.repository_root / ".build/regression/runtime.json")
        missing_path = str(self.repository_root / "missing/runtime.json")

        with patch.object(
            checker,
            "absolute_candidates",
            side_effect=lambda text: {build_output, missing_path} if text == "Runtime output paths.\n" else set(),
        ):
            errors, _ = checker.unresolved_references()

        self.assertEqual(errors, [f"docs/generated-output.md: {missing_path} does not exist"])


if __name__ == "__main__":
    unittest.main()


class EvidencePopulationTests(unittest.TestCase):
    """Review artifacts are evidence, and the materialised Catalog is not.

    A reviewer's rationale quotes paths as prose does, abbreviations included,
    and an accepted assessment is bound by digest -- a rule that could only be
    satisfied by rewriting it would force the receipt citing it to go stale.
    The Catalog documents under the same Regression/ root stay in scope.
    """

    def population_of(self, relative: str) -> str | None:
        return checker.population(checker.REPOSITORY_ROOT / relative)

    def test_review_assessments_and_reports_are_out_of_scope(self) -> None:
        for relative in (
            "Regression/reviews/assessments/sha256/a.json",
            "Regression/reviews/reports/sha256/b.md",
            "Regression/reviews/human-coverage/c.json",
        ):
            self.assertIsNone(self.population_of(relative), relative)

    def test_the_materialised_catalog_stays_an_instruction(self) -> None:
        for relative in (
            "Regression/oracle-protocol.md",
            "Regression/journeys/local-media-lifecycle/journey.md",
            "Regression/operations/playback-seek-v2.md",
        ):
            self.assertEqual(self.population_of(relative), "instruction", relative)
