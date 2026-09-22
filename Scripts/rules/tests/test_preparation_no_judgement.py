#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

RULES = Path(__file__).resolve().parents[1]
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import check_preparation_no_judgement as checker

class PreparationNoJudgementTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher2 = patch.object(checker, "PREPARATIONS_ROOT", self.repository / "Regression/preparations")
        patcher2.start()
        self.addCleanup(patcher2.stop)
        (self.repository / "Regression/preparations").mkdir(parents=True, exist_ok=True)

    def write(self, filename: str, data: dict) -> None:
        path = self.repository / "Regression/preparations" / filename
        text = "---\n" + json.dumps(data) + "\n---\nBody"
        path.write_text(text, encoding="utf-8")

    def test_clean_passes(self) -> None:
        self.write("clean.md", {"readiness": "ready", "operations": [{"operation": "operation:harness.reset-product-state@2", "arguments": {}}]})
        self.assertEqual(checker.failures(), [])

    def test_terminal_inspect_is_rejected(self) -> None:
        self.write("bad.md", {"readiness": "ready", "operations": [{"operation": "operation:accessibility.inspect@2", "arguments": {"requireMatchedElement": True}}]})
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bad.md" in line for line in found))

    def test_nonterminal_inspect_with_readiness_is_rejected(self) -> None:
        self.write("bad2.md", {"readiness": "ready", "operations": [{"operation": "operation:accessibility.inspect@2", "arguments": {"requireMatchedElement": True}}, {"operation": "operation:host.preflight@1", "arguments": {}}]})
        found = checker.failures()
        self.assertTrue(found)

    def test_real_repository_has_no_violations(self) -> None:
        original_root = Path(__file__).resolve().parents[3]
        with patch.object(checker, "REPOSITORY_ROOT", original_root), patch.object(checker, "PREPARATIONS_ROOT", original_root / "Regression/preparations"):
            self.assertEqual(checker.failures(), [])

if __name__ == "__main__":
    unittest.main()
