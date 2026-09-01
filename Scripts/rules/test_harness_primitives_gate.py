#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import harness_primitives_gate as checker


class HarnessPrimitivesGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        (self.repository / "Scripts/verification").mkdir(parents=True, exist_ok=True)
        (self.repository / "Scripts/regression").mkdir(parents=True, exist_ok=True)
        (self.repository / "Config").mkdir(parents=True, exist_ok=True)
        (self.repository / "Config/harness_primitives_allowlist.json").write_text("[]", encoding="utf-8")

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def allowlist(self, entries: list[str]) -> None:
        path = self.repository / "Config/harness_primitives_allowlist.json"
        path.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")

    def test_clean_file_passes(self) -> None:
        self.write("Scripts/verification/clean.py", "def run():\n    return 42\n")
        self.write("Scripts/regression/clean2.py", "value = 1\n")
        self.assertEqual(checker.failures(), [])

    def test_file_with_subprocess_fails(self) -> None:
        self.write("Scripts/verification/bad.py", "import subprocess\nsubprocess.run(['x'])\n")
        found = checker.failures()
        self.assertTrue(any("subprocess" in line for line in found))
        self.assertTrue(any("bad.py" in line for line in found))

    def test_file_with_timeout_equals_fails(self) -> None:
        self.write("Scripts/verification/bad_timeout.py", "result = call(timeout=5)\n")
        found = " ".join(checker.failures())
        self.assertIn("timeout=", found)

    def test_file_with_time_sleep_fails(self) -> None:
        self.write("Scripts/regression/sleepy.py", "import time\ntime.sleep(1)\n")
        found = " ".join(checker.failures())
        self.assertIn("time.sleep", found)

    def test_file_with_time_monotonic_fails(self) -> None:
        self.write("Scripts/verification/monotonic.py", "import time\ntime.monotonic()\n")
        found = " ".join(checker.failures())
        self.assertIn("time.monotonic", found)

    def test_file_with_devicectl_fails(self) -> None:
        self.write("Scripts/verification/dev.py", "cmd = ['xcrun', 'devicectl', 'list']\n")
        found = " ".join(checker.failures())
        self.assertIn("devicectl", found)

    def test_allowlisted_file_is_exempt(self) -> None:
        self.write("Scripts/verification/needs_allow.py", "import subprocess\n")
        self.allowlist(["Scripts/verification/needs_allow.py"])
        self.assertEqual(checker.failures(), [])

    def test_harness_directory_is_exempt(self) -> None:
        self.write("Scripts/verification/harness/internal.py", "import subprocess\n")
        self.assertEqual(checker.failures(), [])

    def test_interactive_visionpro_ui_is_exempt(self) -> None:
        self.write("Scripts/verification/interactive_visionpro_ui.py", "import subprocess\n")
        self.assertEqual(checker.failures(), [])

    def test_enchron_target_is_exempt(self) -> None:
        self.write("Scripts/verification/enchron_target.py", "import subprocess\ndevicectl = 1\n")
        self.assertEqual(checker.failures(), [])

    def test_regression_file_is_scanned(self) -> None:
        self.write("Scripts/regression/harness_user.py", "timeout=30\n")
        found = checker.failures()
        self.assertTrue(any("harness_user.py" in line for line in found))

    def test_allowlist_object_form_is_respected(self) -> None:
        self.write("Scripts/verification/needs_allow2.py", "import subprocess\n")
        path = self.repository / "Config/harness_primitives_allowlist.json"
        path.write_text(json.dumps({"allowlist": ["Scripts/verification/needs_allow2.py"]}), encoding="utf-8")
        self.assertEqual(checker.failures(), [])

    def test_clean_file_with_allowlist_still_passes(self) -> None:
        self.write("Scripts/verification/clean3.py", "x = 1\n")
        self.allowlist(["Scripts/verification/other.py"])
        self.assertEqual(checker.failures(), [])


class RepositoryTests(unittest.TestCase):
    def test_real_repository_with_allowlist_has_no_unallowlisted_violations(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_allowlist_covers_all_current_violations(self) -> None:
        allowlist = checker.load_allowlist()
        self.assertGreater(len(allowlist), 0)
        for entry in allowlist:
            path = checker.REPOSITORY_ROOT / entry
            self.assertTrue(path.is_file(), entry)

    def test_forbidden_tokens_are_the_expected_set(self) -> None:
        self.assertEqual(
            set(checker.FORBIDDEN_TOKENS),
            {"subprocess", "timeout=", "time.sleep", "time.monotonic", "devicectl"},
        )


if __name__ == "__main__":
    unittest.main()
