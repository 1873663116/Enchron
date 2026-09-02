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

import check_one_verb_one_action as checker

class OneVerbOneActionTests(unittest.TestCase):
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
        (self.repository / "Apps/Enchron").mkdir(parents=True, exist_ok=True)

    def write(self, contents: str) -> None:
        path = self.repository / "Apps/Enchron/TestCommandChannel.swift"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def test_clean_file_passes(self) -> None:
        self.write('''
        private func execute(_ request: Request) async throws -> Response {
            switch request.verb {
            case "ping":
                return Response(id: request.id, ok: true, detail: nil, payload: nil)
            case "prepareEmbyAccount":
                let x = client.authenticate()
                return Response(ok: true)
            case "verifyFixture":
                let y = client.item(itemID: "123")
                return Response(ok: true)
            }
        }
        ''')
        self.assertEqual(checker.failures(), [])

    def test_bundled_verb_is_rejected(self) -> None:
        self.write('''
        private func execute(_ request: Request) async throws -> Response {
            switch request.verb {
            case "bundledVerb":
                let a = client.authenticate()
                let b = fixture.externalSubtitleStreamIndex
                let c = client.item(itemID: itemID)
                return Response(ok: true)
            }
        }
        ''')
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bundledVerb" in line for line in found))

    def test_prepareEmbyAccount_is_exempt_pending_split(self) -> None:
        self.write('''
        private func execute(_ request: Request) async throws -> Response {
            switch request.verb {
            case "prepareEmbyAccount":
                let a = client.authenticate()
                let b = externalSubtitleStreamIndex
                return Response(ok: true)
            }
        }
        ''')
        self.assertEqual(checker.failures(), [])

    def test_real_repository_has_no_violations_except_exempted(self) -> None:
        original_root = Path(__file__).resolve().parents[2]
        with patch.object(checker, "REPOSITORY_ROOT", original_root), patch.object(checker, "CHANNEL_PATH", original_root / "Apps/Enchron/TestCommandChannel.swift"):
            self.assertEqual(checker.failures(), [])

if __name__ == "__main__":
    unittest.main()
