#!/usr/bin/env python3
from __future__ import annotations
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))
import reachability_matrix as matrix
import enchron_target

def immediate_tools():
    return SimpleNamespace(call=lambda verb, action: action(matrix.Budget(120.0, "test")))

class EmbyPlaybackRecoveryTests(unittest.TestCase):
    def make_run(self):
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.operations = {
            "accessibility:Emby-Episode-{metadata.id.rawValue}": {"kind": "activate"},
            "accessibility:Emby-Detail-{action == .resume ? \"Resume\" : \"PlayFromBeginning\"}": {"kind": "activate"},
        }
        run.cells = {
            ("main-window-browser", "accessibility:Emby-Episode-{metadata.id.rawValue}"): {
                "context": "main-window-browser",
                "operation": "accessibility:Emby-Episode-{metadata.id.rawValue}",
                "kind": "activate",
                "identifierTemplate": "Emby-Episode-{metadata.id.rawValue}",
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "unmeasured",
                "reason": matrix.UNMEASURED_REASON,
                "evidence": [],
            },
            ("main-window-browser", "accessibility:Emby-Detail-{action == .resume ? \"Resume\" : \"PlayFromBeginning\"}"): {
                "context": "main-window-browser",
                "operation": "accessibility:Emby-Detail-{action == .resume ? \"Resume\" : \"PlayFromBeginning\"}",
                "kind": "activate",
                "identifierTemplate": "Emby-Detail-{action == .resume ? \"Resume\" : \"PlayFromBeginning\"}",
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "unmeasured",
                "reason": matrix.UNMEASURED_REASON,
                "evidence": [],
            },
        }
        run.driven_cells = set()
        run.tapped_cells = set()
        run.events = [{"evidence": "raw/000-snapshot.json"}]
        run.channel_failures = [{"at": "2026-09-03T00:00:00+00:00", "action": "tap", "kind": "response-timeout", "error": "instrument fault response-timeout: subsequent observations are untrusted (budget p95 6.95s × 1.5, lane=simulator, n=20, censored=0, raised to the declared floor 75s)"}]
        run.history = [matrix.FaultRecord(location="tap", kind="response-timeout", censored=True), matrix.FaultRecord(location="tap", kind="response-timeout", censored=True)]
        run.halted = True
        run.policy = matrix.RecoveryPolicy()
        run.policy.action_count = 10
        run.policy.fault_count = 2
        run.salvaging = False
        run.segment = {"id": "probe-main-window-browser", "context": "main-window-browser"}
        run.session_id = "test-session"
        run.evidence_session = "evidence-session"
        run.probe_status = {"passed": True, "byteLimit": 196608}
        run.raw = Path(tempfile.mkdtemp())
        run.budgets = Mock()
        run.tools = immediate_tools()
        run.lane = "simulator"
        return run

    def test_recover_clears_channel_failure_after_proven_health(self):
        run = self.make_run()
        run.controller = Mock(side_effect=[
            {"success": True, "hierarchy": "identifier: 'Emby-Episode-473'", "matchedElement": {"identifier": "Emby-Episode-473"}},
            {"success": True},
            {"success": True},
        ])
        run.channel_health_probe = Mock(return_value={"passed": True})
        run.read_probe_status = Mock(return_value={"success": True, "ok": True, "payload": ["byteLimit=196608", "fileBytes=1000", "peakFileBytes=1000", "compactionCount=0", "evidenceOverflowed=false", "writeFailed=false"]})
        run.ensure_session = Mock(return_value=True)
        run.relaunch = Mock()
        with patch.object(matrix, "utc_now", return_value="2026-09-03T00:00:00+00:00"):
            result = run._recover_emby_playback_timeout("main-window-browser", "accessibility:Emby-Episode-{metadata.id.rawValue}", "Emby-Episode-473")
        self.assertTrue(result)
        self.assertEqual(run.channel_failures, [])
        self.assertFalse(run.halted)
        self.assertEqual(run.cells[("main-window-browser", "accessibility:Emby-Episode-{metadata.id.rawValue}")]["verdict"], "known-defect")
        self.assertIn("response-timeout", run.cells[("main-window-browser", "accessibility:Emby-Episode-{metadata.id.rawValue}")]["reason"])
        self.assertTrue(any(e.get("action") == "productHang" for e in run.events))

    def test_recover_returns_false_when_health_fails(self):
        run = self.make_run()
        run.controller = Mock(return_value={"success": True, "hierarchy": "", "matchedElement": {"identifier": "Emby-Episode-473"}})
        run.channel_health_probe = Mock(return_value={"passed": False})
        run.read_probe_status = Mock(return_value={"success": False})
        run.ensure_session = Mock(return_value=True)
        run.relaunch = Mock()
        with patch.object(matrix, "utc_now", return_value="2026-09-03T00:00:00+00:00"):
            result = run._recover_emby_playback_timeout("main-window-browser", "accessibility:Emby-Episode-{metadata.id.rawValue}", "Emby-Episode-473")
        self.assertFalse(result)
        self.assertEqual(len(run.channel_failures), 1)

    def test_emby_content_episode_handles_timeout_with_recovery(self):
        text = Path(__file__).resolve().parents[1].joinpath("verification/reachability_matrix.py").read_text(encoding="utf-8")
        self.assertIn("_recover_emby_playback_timeout", text)
        self.assertIn("accessibility:Emby-Episode-{metadata.id.rawValue}", text)
        self.assertIn("response-timeout", text)
        self.assertIn("Emby-Detail-{action == .resume", text)

    def test_no_broad_except_in_recovery(self):
        text = Path(__file__).resolve().parents[1].joinpath("verification/reachability_matrix.py").read_text(encoding="utf-8")
        start = text.find("def _recover_emby_playback_timeout")
        segment = text[start:start+4000] if start != -1 else ""
        self.assertNotIn("except Exception", segment)
        self.assertNotIn("except:", segment)

if __name__ == "__main__":
    unittest.main()
