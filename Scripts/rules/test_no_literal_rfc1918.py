#!/usr/bin/env python3
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import check_no_literal_rfc1918 as checker


class NoLiteralRFC1918Tests(unittest.TestCase):
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

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_clean_file_passes(self) -> None:
        self.write("Scripts/verification/clean.py", "host = \"Mac-mini.local\"\n")
        self.write("Config/example.json", "{\"host\": \"Mac-mini.local\"}")
        self.assertEqual(checker.failures(), [])

    def test_192_168_is_rejected(self) -> None:
        self.write("Scripts/verification/bad.py", "server = \"http://192.168.5.20:8096\"\n")
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bad.py" in line for line in found))

    def test_10_network_is_rejected(self) -> None:
        self.write("Scripts/regression/bad.py", "addr = \"10.0.0.5\"\n")
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bad.py" in line for line in found))

    def test_172_16_is_rejected(self) -> None:
        self.write("Config/bad.json", "{\"addr\": \"172.16.5.10\"}")
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bad.json" in line for line in found))

    def test_172_31_is_rejected(self) -> None:
        self.write("Scripts/verification/another.py", "x = \"172.31.255.1\"\n")
        self.assertTrue(checker.failures())

    def test_172_15_is_allowed(self) -> None:
        self.write("Scripts/verification/ok.py", "x = \"172.15.0.1\"\n")
        self.assertEqual(checker.failures(), [])

    def test_192_167_is_allowed(self) -> None:
        self.write("Scripts/verification/ok2.py", "x = \"192.167.1.1\"\n")
        self.assertEqual(checker.failures(), [])

    def test_real_repository_has_no_violations(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_real_repository_with_actual_roots_has_no_violations(self) -> None:
        import check_no_literal_rfc1918 as real_checker
        real_failures = real_checker.failures()
        self.assertEqual(real_failures, [])


if __name__ == "__main__":
    unittest.main()
