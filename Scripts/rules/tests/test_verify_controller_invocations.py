#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RULES = Path(__file__).resolve().parents[1]
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_controller_invocations as checker


CONTROLLER_SOURCE = '''
import argparse

def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--output-directory")
    parser.add_argument("--execution-input")
    parser.add_argument("action", choices=["snapshot", "tap", "halt"])
    return parser.parse_args()
'''

CALLER_SOURCE = '''
import subprocess
import sys
from pathlib import Path

CONTROLLER = Path("Scripts/verification/interactive_visionpro_ui.py")

def drive(action):
    command = [
        sys.executable,
        str(CONTROLLER),
        "--device",
        "device-id",
        "--execution-input",
        "input.json",
        action,
    ]
    return subprocess.run(command)
'''


class ControllerInvocationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.write(checker.CONTROLLER, CONTROLLER_SOURCE)
        self.caller(CALLER_SOURCE)

    def write(self, relative: str, contents: str) -> None:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def caller(self, contents: str) -> None:
        self.write("Scripts/verification/driver.py", contents)

    def test_a_caller_passing_declared_options_passes(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_a_caller_passing_a_removed_option_fails(self) -> None:
        self.caller(CALLER_SOURCE.replace("--execution-input", "--derived-data-path"))

        self.assertIn("passes --derived-data-path", " ".join(checker.failures()))

    def test_a_caller_passing_a_misspelled_option_fails(self) -> None:
        self.caller(CALLER_SOURCE.replace("--output-directory", "--output-dir"))
        self.caller(CALLER_SOURCE.replace("--device", "--devise"))

        self.assertIn("passes --devise", " ".join(checker.failures()))

    def test_a_literal_controller_path_is_also_checked(self) -> None:
        literal = CALLER_SOURCE.replace(
            'str(CONTROLLER),', '"Scripts/verification/interactive_visionpro_ui.py",'
        ).replace("--execution-input", "--gone")

        self.caller(literal)

        self.assertIn("passes --gone", " ".join(checker.failures()))

    def test_an_option_list_unrelated_to_the_controller_is_ignored(self) -> None:
        self.caller(
            CALLER_SOURCE
            + '\n\ndef other():\n    return ["xcodebuild", "--derived-data-path", "x"]\n'
        )

        self.assertEqual(checker.failures(), [])

    def test_a_file_that_never_names_the_controller_is_ignored(self) -> None:
        self.write(
            "Scripts/verification/unrelated.py",
            'COMMAND = ["tool", "--derived-data-path", "x"]\n',
        )

        self.assertEqual(checker.failures(), [])

    def test_an_absent_controller_fails(self) -> None:
        (self.repository / checker.CONTROLLER).unlink()

        self.assertIn("is absent", " ".join(checker.failures()))

    def test_a_controller_declaring_no_options_fails(self) -> None:
        self.write(checker.CONTROLLER, "print('no parser here')\n")

        self.assertIn("declares no options", " ".join(checker.failures()))


class RepositoryTests(unittest.TestCase):
    def test_every_shipped_caller_uses_current_controller_options(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_the_controller_still_declares_execution_input(self) -> None:
        source = (checker.REPOSITORY_ROOT / checker.CONTROLLER).read_text(encoding="utf-8")

        self.assertIn("--execution-input", checker.declared_options(source))


if __name__ == "__main__":
    unittest.main()
