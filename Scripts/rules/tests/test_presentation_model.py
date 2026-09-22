#!/usr/bin/env python3

"""Holds the Python mirror to the Swift that owns the presentation model.

Reading the Swift is the point. A test that only checked the mirror against
itself would have stayed green through exactly the drift that put whole matrix
paths on a button portal does not have.
"""

from pathlib import Path
import re
import unittest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

from presentation_model import (
    CONTENT_FAMILY,
    IMMERSIVE_PRESENTATION,
    MAIN_WINDOW_PRESENTATION,
    edge,
    lands_in_main_window,
)

SWIFT = (
    Path(__file__).resolve().parents[3]
    / "Modules/Playback/Model/PlaybackPresentation.swift"
)

SWIFT_CASE_ARROW = re.compile(r"case\s+([^\n:]+):\s*\n\s*\.(\w+)")


def swift_mapping(function_body: str) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for sources, target in SWIFT_CASE_ARROW.findall(function_body):
        for source in sources.split(","):
            mapping[source.strip().lstrip(".")] = target
    return mapping


def swift_body(marker: str) -> str:
    text = SWIFT.read_text(encoding="utf-8")
    start = text.index(marker)
    return text[start : text.index("\n    }", start)]


class MirrorsTheSwift(unittest.TestCase):
    def test_content_family(self) -> None:
        self.assertEqual(swift_mapping(swift_body("var contentFamily")), CONTENT_FAMILY)

    def test_main_window_presentation(self) -> None:
        self.assertEqual(
            swift_mapping(swift_body("var mainWindowPresentation")),
            MAIN_WINDOW_PRESENTATION,
        )

    def test_immersive_presentation(self) -> None:
        self.assertEqual(
            swift_mapping(swift_body("var immersivePresentation")),
            IMMERSIVE_PRESENTATION,
        )

    def test_every_presentation_the_swift_declares_is_mirrored(self) -> None:
        declared = set(re.findall(r"^    case (\w+)$", SWIFT.read_text(), re.MULTILINE))
        self.assertTrue(set(CONTENT_FAMILY) <= declared)
        self.assertEqual(set(CONTENT_FAMILY), {"window", "portal", "docked", "panorama"})


class TheEdgesThePlanNamed(unittest.TestCase):
    def test_panoramic_content_lands_in_portal_not_panorama(self) -> None:
        self.assertEqual(lands_in_main_window("panoramic"), "portal")

    def test_flat_content_lands_in_window(self) -> None:
        self.assertEqual(lands_in_main_window("flat"), "window")

    def test_entering_a_space_of_another_family_is_illegal(self) -> None:
        for source, target in (("window", "panorama"), ("portal", "docked")):
            self.assertEqual(edge(source, target), "illegal", f"{source} to {target}")

    def test_leaving_a_space_may_cross_families(self) -> None:
        for source, target in (("panorama", "window"), ("docked", "portal")):
            self.assertEqual(edge(source, target), "exit-immersive", f"{source} to {target}")

    def test_the_three_legal_kinds(self) -> None:
        self.assertEqual(edge("window", "docked"), "enter-immersive")
        self.assertEqual(edge("panorama", "portal"), "exit-immersive")
        self.assertEqual(edge("window", "portal"), "projection-swap")
        self.assertEqual(edge("panorama", "panorama"), "in-place")


if __name__ == "__main__":
    unittest.main()
