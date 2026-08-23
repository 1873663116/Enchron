from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import playback_mode_matrix as matrix


class SimulatorContainerTests(unittest.TestCase):
    def test_push_to_inbox_copies_media_into_simulator_container(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            container = root / "container"
            media_path = root / "clip.mp4"
            media_path.write_bytes(b"simulator media")

            with (
                patch.object(matrix.enchron_target, "is_simulator", return_value=True),
                patch.object(
                    matrix.enchron_target,
                    "simulator_container",
                    return_value=container,
                ),
                patch.object(matrix.subprocess, "run") as run,
            ):
                error = matrix.push_to_inbox(media_path)

            self.assertIsNone(error)
            self.assertEqual(
                (container / "Documents/TestMediaInbox/clip.mp4").read_bytes(),
                b"simulator media",
            )
            run.assert_not_called()

    def test_copy_probe_lines_once_uses_simulator_container_copy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            cell_directory = Path(temporary_directory)

            def copy_probe(
                *, destination: Path, **_: object
            ) -> subprocess.CompletedProcess[str]:
                destination.write_text("first\nsecond\n", encoding="utf-8")
                return subprocess.CompletedProcess(
                    [], returncode=0, stdout="", stderr=""
                )

            with (
                patch.object(matrix.enchron_target, "is_simulator", return_value=True),
                patch.object(
                    matrix.enchron_target,
                    "copy_from_container",
                    side_effect=copy_probe,
                ) as copy_from_container,
                patch.object(matrix.subprocess, "run") as run,
            ):
                lines, error = matrix.copy_probe_lines_once(cell_directory)

            self.assertEqual(lines, ["first", "second"])
            self.assertIsNone(error)
            copy_from_container.assert_called_once()
            run.assert_not_called()


class PhysicalContainerTests(unittest.TestCase):
    def test_push_to_inbox_keeps_using_core_device_copy(self) -> None:
        media_path = Path("/tmp/clip.mp4")
        completed = subprocess.CompletedProcess(
            [], returncode=0, stdout="", stderr=""
        )

        with (
            patch.object(matrix.enchron_target, "is_simulator", return_value=False),
            patch.object(matrix.subprocess, "run", return_value=completed) as run,
        ):
            error = matrix.push_to_inbox(media_path)

        self.assertIsNone(error)
        command = run.call_args.args[0]
        self.assertEqual(
            command[:6],
            ["xcrun", "devicectl", "device", "copy", "to", "--device"],
        )
        self.assertEqual(command[6], matrix.CORE_DEVICE)

    def test_copy_probe_lines_once_keeps_physical_copy_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            cell_directory = Path(temporary_directory)

            def copy_probe(
                command: list[str], **_: object
            ) -> subprocess.CompletedProcess[str]:
                Path(command[-1]).write_text("physical\n", encoding="utf-8")
                return subprocess.CompletedProcess(
                    [], returncode=0, stdout="", stderr=""
                )

            with (
                patch.object(matrix.enchron_target, "is_simulator", return_value=False),
                patch.object(matrix.subprocess, "run", side_effect=copy_probe) as run,
            ):
                lines, error = matrix.copy_probe_lines_once(cell_directory)

            self.assertEqual(lines, ["physical"])
            self.assertIsNone(error)
            command = run.call_args.args[0]
            self.assertEqual(
                command[:6],
                ["xcrun", "devicectl", "device", "copy", "from", "--device"],
            )
            self.assertEqual(command[6], matrix.CORE_DEVICE)
            self.assertEqual(
                run.call_args.kwargs["timeout"],
                matrix.PROBE_COPY_TIMEOUT_SECONDS,
            )


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
