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

import check_readiness_gate_hidden_coverage as checker

class ReadinessGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher2 = patch.object(checker, "MATRIX_PATH", self.repository / "Scripts/verification/reachability_matrix.py")
        patcher2.start()
        self.addCleanup(patcher2.stop)
        (self.repository / "Scripts/verification").mkdir(parents=True, exist_ok=True)

    def write(self, contents: str) -> None:
        path = self.repository / "Scripts/verification/reachability_matrix.py"
        path.write_text(contents, encoding="utf-8")

    def test_clean_passes(self) -> None:
        self.write('''
    def some_scenario(self):
        if readiness["passed"] is not True:
            self.mark_observation("known-defect")
            return
        self.mark_observation("pass")
''')
        self.assertEqual(checker.failures(), [])

    def test_early_return_without_product_failure_is_rejected(self) -> None:
        self.write('''
    def my_scenario(self):
        if credentials_path is None:
            return
        if readiness["passed"] is not True:
            return
''')
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("my_scenario" in line for line in found))

    def test_emby_session_recovery_is_exempt_pending_fix(self) -> None:
        self.write('''
    def emby_session_recovery_scenario(self):
        if credentials_path is None:
            return
        if readiness["passed"] is not True:
            return
''')
        self.assertEqual(checker.failures(), [])

    def test_real_repository_has_no_violations_except_exempted(self) -> None:
        original_root = Path(__file__).resolve().parents[2]
        with patch.object(checker, "REPOSITORY_ROOT", original_root), patch.object(checker, "MATRIX_PATH", original_root / "Scripts/verification/reachability_matrix.py"):
            self.assertEqual(checker.failures(), [])

if __name__ == "__main__":
    unittest.main()
