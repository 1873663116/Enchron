#!/usr/bin/env python3

"""The extractor has to tell a path from a slash-separated enumeration.

Prose about codecs and URL schemes is full of tokens like `hvcC/avcC` that a
naive reader turns into a missing file, and a check that cries wolf gets
switched off. These cases are the ones that decide whether a candidate counts.
"""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "rules"))

from verify_documentation_references import (
    REPOSITORY_ROOT,
    absolute_candidates,
    repository_candidates,
    strip_locator,
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

    def test_glob_and_placeholder_are_skipped(self) -> None:
        prose = "`Packages/*/Headers/x.h` and `Scripts/verification/<name>.py`"
        self.assertEqual(repository_candidates(prose, DOCUMENT), set())


class Locators(unittest.TestCase):
    def test_line_range_is_stripped(self) -> None:
        self.assertEqual(strip_locator("Modules/Emby/EmbyScreens.swift:433-447"), "Modules/Emby/EmbyScreens.swift")

    def test_anchor_is_stripped(self) -> None:
        self.assertEqual(strip_locator("docs/archive/adr/README.md#status"), "docs/archive/adr/README.md")

    def test_trailing_chinese_punctuation_is_stripped(self) -> None:
        self.assertEqual(strip_locator("Scripts/verification/journey_units.py）"), "Scripts/verification/journey_units.py")


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


if __name__ == "__main__":
    unittest.main()
