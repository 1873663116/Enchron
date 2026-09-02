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

import check_precondition_contract_alignment as checker

class PreconditionContractAlignmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher2 = patch.object(checker, "CHANNEL_PATH", self.repository / "Apps/Enchron/TestCommandChannel.swift")
        patcher2.start()
        self.addCleanup(patcher2.stop)
        patcher3 = patch.object(checker, "OPERATIONS_ROOT", self.repository / "Regression/operations")
        patcher3.start()
        self.addCleanup(patcher3.stop)
        (self.repository / "Apps/Enchron").mkdir(parents=True, exist_ok=True)
        (self.repository / "Regression/operations").mkdir(parents=True, exist_ok=True)

    def write_channel(self, contents: str) -> None:
        path = self.repository / "Apps/Enchron/TestCommandChannel.swift"
        path.write_text(contents, encoding="utf-8")

    def write_operation(self, filename: str, contents: str) -> None:
        path = self.repository / "Regression/operations" / filename
        path.write_text(contents, encoding="utf-8")

    def test_clean_passes(self) -> None:
        self.write_channel('''
        case "armTransitionTrace":
            guard let x = active else { throw CommandError(message: "armTransitionTrace requires active playback.") }
        case "resetState":
            if let d = err { throw CommandError(message: "requires folder creation") }
        ''')
        self.write_operation("transition-trace-arm-v1.md", "armTransitionTrace requires active playback.")
        self.write_operation("harness-reset-product-state-v2.md", "requires folder creation")
        self.write_operation("media-import-staged-v2.md", "")
        self.write_operation("preparation-local-directory-subtitle-source-v1.md", "")
        self.write_operation("transition-trace-fetch-v1.md", "")
        self.assertEqual(checker.failures(), [])

    def test_missing_precondition_is_rejected(self) -> None:
        self.write_channel('''
        case "armTransitionTrace":
            guard let x = active else { throw CommandError(message: "armTransitionTrace requires active playback.") }
        ''')
        self.write_operation("transition-trace-arm-v1.md", "no requires here")
        self.write_operation("harness-reset-product-state-v2.md", "")
        self.write_operation("media-import-staged-v2.md", "")
        self.write_operation("preparation-local-directory-subtitle-source-v1.md", "")
        self.write_operation("transition-trace-fetch-v1.md", "")
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("armTransitionTrace" in line for line in found))

    def test_real_repository_has_no_violations(self) -> None:
        original_root = Path(__file__).resolve().parents[2]
        with patch.object(checker, "REPOSITORY_ROOT", original_root), patch.object(checker, "CHANNEL_PATH", original_root / "Apps/Enchron/TestCommandChannel.swift"), patch.object(checker, "OPERATIONS_ROOT", original_root / "Regression/operations"):
            self.assertEqual(checker.failures(), [])

if __name__ == "__main__":
    unittest.main()
