import unittest
from pathlib import Path

class LibraryRenameGridGuardTests(unittest.TestCase):
    def test_library_editing_handles_both_grid_and_list_identifiers(self) -> None:
        text = (Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find('def library_editing_scenario')
        self.assertNotEqual(idx, -1)
        snippet = text[idx: idx + 4000]
        self.assertIn('MediaLibrary-grid-folder-', snippet)
        self.assertIn('library-folder-', snippet)
        self.assertIn('Reachability Fixture', snippet)
        self.assertNotIn('tap", "--label", "Grid"', snippet)
        self.assertNotIn('tap", "--label", "List"', snippet)

    def test_grid_press_fallback_uses_hierarchy_scan(self) -> None:
        text = (Path(__file__).resolve().parents[3] / "Scripts/verification/reachability_matrix.py").read_text(encoding="utf-8")
        idx = text.find('def library_editing_scenario')
        snippet = text[idx: idx + 5000]
        grid = snippet.find('MediaLibrary-grid-folder-')
        first_press = snippet.find('"press", "--identifier", folder_identifier')
        hierarchy = snippet.find('hierarchy.splitlines')
        second_press = snippet.find('"press", "--identifier", list_identifier')
        self.assertNotEqual(grid, -1)
        self.assertNotEqual(first_press, -1)
        self.assertNotEqual(hierarchy, -1)
        self.assertNotEqual(second_press, -1)
        self.assertLess(grid, first_press)
        self.assertLess(first_press, hierarchy)
        self.assertLess(hierarchy, second_press)

if __name__ == "__main__":
    unittest.main()
