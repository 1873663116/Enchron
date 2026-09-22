#!/usr/bin/env python3
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

RULES = Path(__file__).resolve().parents[1]
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import check_orphan_verbs as checker

class OrphanVerbsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher2 = patch.object(checker, "CHANNEL_PATH", self.repository / "Apps/Enchron/DebugSupport/TestCommandChannel.swift")
        patcher2.start()
        self.addCleanup(patcher2.stop)
        patcher3 = patch.object(checker, "INVENTORY_PATH", self.repository / "Config/reachability_operation_inventory.json")
        patcher3.start()
        self.addCleanup(patcher3.stop)
        (self.repository / "Apps/Enchron").mkdir(parents=True, exist_ok=True)
        (self.repository / "Scripts").mkdir(parents=True, exist_ok=True)
        (self.repository / "Regression/operations").mkdir(parents=True, exist_ok=True)
        (self.repository / "Config").mkdir(parents=True, exist_ok=True)

    def write_channel(self, contents: str) -> None:
        path = self.repository / "Apps/Enchron/DebugSupport/TestCommandChannel.swift"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def write_script(self, relative: str, contents: str) -> None:
        p = self.repository / relative
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(contents, encoding="utf-8")

    def test_clean_passes(self) -> None:
        self.write_channel('case "ping":\ncase "probeStatus":\n')
        self.write_script("Scripts/verification/foo.py", 'call("ping")')
        self.write_script("Regression/operations/harness-assert-channels-v2.md", 'ping')
        self.write_script("Config/reachability_operation_inventory.json", '"probeStatus"')
        self.assertEqual(checker.failures(), [])

    def test_orphan_is_rejected(self) -> None:
        self.write_channel('case "orphanVerb":\n')
        self.write_script("Scripts/verification/foo.py", 'nothing')
        self.write_script("Regression/operations/other.md", 'nothing')
        self.write_script("Config/reachability_operation_inventory.json", 'nothing')
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("orphanVerb" in line for line in found))

    def test_exempt_verbs_are_exempt(self) -> None:
        for verb in checker.EXEMPT_VERBS:
            self.write_channel(f'case "{verb}":\n')
            self.write_script("Scripts/verification/foo.py", 'nothing')
            self.write_script("Regression/operations/other.md", 'nothing')
            self.write_script("Config/reachability_operation_inventory.json", 'nothing')
            self.assertEqual(checker.failures(), [])

    def test_real_repository_has_no_violations(self) -> None:
        original_root = Path(__file__).resolve().parents[3]
        with patch.object(checker, "REPOSITORY_ROOT", original_root), patch.object(checker, "CHANNEL_PATH", original_root / "Apps/Enchron/DebugSupport/TestCommandChannel.swift"), patch.object(checker, "INVENTORY_PATH", original_root / "Config/reachability_operation_inventory.json"):
            self.assertEqual(checker.failures(), [])

if __name__ == "__main__":
    unittest.main()
