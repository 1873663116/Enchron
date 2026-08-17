import json
import sys
from collections import Counter
from pathlib import Path
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import verify_playback_surface_structure as structure


class PlaybackSurfaceStructureBaselineTests(unittest.TestCase):
    def test_matching_gap_names_and_counts_pass(self) -> None:
        new, resolved = structure.compare_with_baseline(
            ["window camera is missing", "executor bypass", "executor bypass"],
            Counter({"window camera is missing": 1, "executor bypass": 2}),
        )

        self.assertEqual(new, Counter())
        self.assertEqual(resolved, Counter())

    def test_new_name_and_extra_occurrence_are_reported(self) -> None:
        new, resolved = structure.compare_with_baseline(
            ["known", "known", "new"],
            Counter({"known": 1}),
        )

        self.assertEqual(new, Counter({"known": 1, "new": 1}))
        self.assertEqual(resolved, Counter())

    def test_resolved_gap_requests_a_baseline_update_without_a_new_gap(self) -> None:
        new, resolved = structure.compare_with_baseline(
            ["still open"],
            Counter({"still open": 1, "now resolved": 1}),
        )

        self.assertEqual(new, Counter())
        self.assertEqual(resolved, Counter({"now resolved": 1}))

    def test_baseline_rejects_duplicate_names(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            path.write_text(json.dumps({
                "version": 1,
                "knownGaps": [
                    {"name": "duplicate", "count": 1},
                    {"name": "duplicate", "count": 1},
                ],
            }))

            with self.assertRaisesRegex(ValueError, "declared more than once"):
                structure.read_baseline(path)


if __name__ == "__main__":
    unittest.main()
