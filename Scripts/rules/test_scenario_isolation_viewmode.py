#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

RULES = Path(__file__).resolve().parent
sys.path.insert(0, str(RULES.parent / "verification"))

import reachability_matrix as matrix
from harness.failures import InstrumentFault


REPO = Path(__file__).resolve().parents[2]
MATRIX_SOURCE = REPO / "Scripts/verification/reachability_matrix.py"
CHANNEL_SOURCE = REPO / "Apps/Enchron/TestCommandChannel.swift"

REQUIRED_CHAINS = (
    "browser-new-folder",
    "browser-library-folder-open",
    "browser-navigation",
    "browser-multiselect",
)

GRID_HIERARCHY = (
    "window identifier: 'FileBrowsing-FilesScreen' "
    "card identifier: 'MediaLibrary-grid-folder-Reachability Fixture' "
    "tab identifier: 'Navigation-Ornament-tab-files'"
)

LIST_HIERARCHY = (
    "window identifier: 'FileBrowsing-FilesScreen' "
    "container identifier: 'FileBrowsing-FilesScreen-list' "
    "row identifier: 'library-folder-0CD44262-9F8A-4D1B-8E2C-7A6B5C4D3E2F' "
    "tab identifier: 'Navigation-Ornament-tab-files'"
)


def function_body(source: str, name: str) -> str:
    start = source.find(f"def {name}")
    assert start != -1, f"missing function {name}"
    rest = source[start:]
    next_def = rest.find("\n    def ", 1)
    return rest if next_def == -1 else rest[:next_def]


def scripted_run(hierarchies: list[str]) -> SimpleNamespace:
    documents = iter([{"hierarchy": text} for text in hierarchies])
    fake = SimpleNamespace(
        controller=lambda action, *extra: next(documents),
        events=[{"evidence": "raw/fake-snapshot.json"}],
        hierarchy_identifiers=matrix.ReachabilityRun.hierarchy_identifiers,
    )
    return fake


class ViewModeRestoreTests(unittest.TestCase):
    def test_browser_conditions_restores_grid_after_view_mode_toggle(self) -> None:
        body = function_body(
            MATRIX_SOURCE.read_text(encoding="utf-8"),
            "browser_condition_scenario",
        )
        first_toggle = body.find("FileBrowsing-FilesScreen-viewMode")
        self.assertNotEqual(first_toggle, -1)
        create = body.find("MediaLibrary-NewFolder-create")
        self.assertNotEqual(create, -1)
        between = body[first_toggle:create]
        self.assertIn("0.25", between)
        self.assertIn("require_library_grid_mode", between)

    def test_grid_precondition_guards_every_grid_dependent_chain(self) -> None:
        source = MATRIX_SOURCE.read_text(encoding="utf-8")
        self.assertIn("def require_library_grid_mode", source)
        body = function_body(source, "browser_condition_scenario")
        for chain in REQUIRED_CHAINS:
            self.assertIn(chain, body)

    def test_grid_guard_fails_on_list_hierarchy(self) -> None:
        fake = scripted_run([LIST_HIERARCHY])
        with self.assertRaises(InstrumentFault) as raised:
            matrix.ReachabilityRun.require_library_grid_mode(
                fake, "main-window-browser", chain="browser-new-folder"
            )
        self.assertEqual(raised.exception.kind, "library-view-mode-not-grid")
        self.assertIn("browser-new-folder", str(raised.exception.evidence))

    def test_grid_guard_passes_on_grid_hierarchy(self) -> None:
        fake = scripted_run([GRID_HIERARCHY])
        document = matrix.ReachabilityRun.require_library_grid_mode(
            fake, "main-window-browser", chain="browser-new-folder"
        )
        self.assertIn("MediaLibrary-grid-folder", document["hierarchy"])

    def test_view_mode_sequence_leaves_grid_for_later_chains(self) -> None:
        fake = scripted_run([LIST_HIERARCHY, GRID_HIERARCHY, GRID_HIERARCHY])
        with self.assertRaises(InstrumentFault):
            matrix.ReachabilityRun.require_library_grid_mode(
                fake, "main-window-browser", chain="browser-new-folder"
            )
        matrix.ReachabilityRun.require_library_grid_mode(
            fake, "main-window-browser", chain="browser-library-folder-open"
        )
        matrix.ReachabilityRun.require_library_grid_mode(
            fake, "main-window-browser", chain="browser-navigation"
        )


class ResetStateViewModeTests(unittest.TestCase):
    def test_reset_state_restores_view_mode_in_memory(self) -> None:
        source = CHANNEL_SOURCE.read_text(encoding="utf-8")
        reset = source.find('case "resetState"')
        self.assertNotEqual(reset, -1)
        region = source[reset: reset + 4000]
        self.assertIn("viewMode = .grid", region)


if __name__ == "__main__":
    unittest.main()
