#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import reachability_matrix as matrix

PRESENTATION = "main-window-browser"
OPERATION = 'accessibility:Emby-Episode-{metadata.id.rawValue}'
IDENTIFIER = "Emby-Episode-473"


class EmbyHangRecoveryTests(unittest.TestCase):
    def make_run(self, *, session_ok: bool, health_passed: bool, status_ok: bool):
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.cells = {
            (PRESENTATION, OPERATION): {"verdict": "unmeasured", "reason": "", "evidence": []}
        }
        run.events = [{"evidence": "raw/900-snapshot.json"}]
        run.channel_failures = [{"action": "tap", "kind": "response-timeout"}]
        run.history = [object()]
        run.halted = True
        run.salvaging = False
        run.probe_status = {}
        run.provable = lambda *a, **k: None
        run.mark_driven = lambda *a, **k: None
        run.mark_observation = lambda *a, **k: None
        run.controller = lambda *a, **k: {"success": True}
        run.ensure_session = lambda: session_ok
        run.relaunch = lambda *a, **k: None
        run.channel_health_probe = lambda *a, **k: {"passed": health_passed}
        run.read_probe_status = lambda: {"success": status_ok}
        return run

    def test_healthy_recovery_marks_known_defect_and_clears_only_after_proof(self) -> None:
        run = self.make_run(session_ok=True, health_passed=True, status_ok=True)
        recovered = run._recover_emby_playback_timeout(PRESENTATION, OPERATION, IDENTIFIER)
        self.assertTrue(recovered)
        self.assertEqual(run.cells[(PRESENTATION, OPERATION)]["verdict"], "known-defect")
        self.assertEqual(run.channel_failures, [])
        self.assertFalse(run.halted)

    def test_dead_channel_records_defect_but_never_clears(self) -> None:
        for label, kwargs in (
            ("session lost", dict(session_ok=False, health_passed=True, status_ok=True)),
            ("health failed", dict(session_ok=True, health_passed=False, status_ok=True)),
            ("status unreadable", dict(session_ok=True, health_passed=True, status_ok=False)),
        ):
            with self.subTest(label):
                run = self.make_run(**kwargs)
                recovered = run._recover_emby_playback_timeout(PRESENTATION, OPERATION, IDENTIFIER)
                self.assertFalse(recovered)
                self.assertEqual(
                    run.cells[(PRESENTATION, OPERATION)]["verdict"], "known-defect"
                )
                self.assertEqual(
                    run.channel_failures, [{"action": "tap", "kind": "response-timeout"}]
                )

    def test_salvaging_is_lowered_on_every_path(self) -> None:
        for kwargs in (
            dict(session_ok=True, health_passed=True, status_ok=True),
            dict(session_ok=False, health_passed=True, status_ok=True),
            dict(session_ok=True, health_passed=False, status_ok=True),
        ):
            with self.subTest(str(kwargs)):
                run = self.make_run(**kwargs)
                run._recover_emby_playback_timeout(PRESENTATION, OPERATION, IDENTIFIER)
                self.assertFalse(run.salvaging)


if __name__ == "__main__":
    unittest.main()
