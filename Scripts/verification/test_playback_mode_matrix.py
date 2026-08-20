import unittest

import playback_mode_matrix as matrix


class ProbeCursorTests(unittest.TestCase):
    def test_sequence_cursor_survives_compaction(self) -> None:
        cursor = matrix.probe_cursor(
            [
                "2026-08-19T00:00:00Z probeSequence=10 old-a",
                "2026-08-19T00:00:01Z probeSequence=11 old-b",
            ]
        )

        delta, next_cursor, error = matrix.probe_lines_since(
            [
                "2026-08-19T00:00:01Z probeSequence=11 old-b",
                "2026-08-19T00:00:02Z probeSequence=12 new-c",
            ],
            cursor,
        )

        self.assertEqual(delta, ["2026-08-19T00:00:02Z probeSequence=12 new-c"])
        self.assertEqual(next_cursor.sequence, 12)
        self.assertIsNone(error)

    def test_legacy_cursor_reports_backward_line_count(self) -> None:
        cursor = matrix.probe_cursor(["old-a", "old-b"])

        delta, next_cursor, error = matrix.probe_lines_since(["old-b"], cursor)

        self.assertEqual(delta, [])
        self.assertEqual(next_cursor.line_count, 1)
        self.assertEqual(error, "Probe line count moved backwards from 2 to 1.")


if __name__ == "__main__":
    unittest.main()
