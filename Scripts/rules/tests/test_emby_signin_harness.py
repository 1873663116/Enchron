#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))
import reachability_matrix as matrix
import enchron_target
class EmbySignInHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="emby-signin-")
        self.addCleanup(self.temporary.cleanup)
        self.raw = Path(self.temporary.name) / "raw"
        self.raw.mkdir(parents=True, exist_ok=True)
        self.credentials = Path(self.temporary.name) / "EmbyServerCredentials.local.json"
        self.credentials.write_text(json.dumps({"address": "http://example.test:8096", "username": "user", "password": "pass", "serverID": "pending", "userID": "pending"}), encoding="utf-8")
    def make_run(self, controller_responses, local_returncode=0):
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.arguments = SimpleNamespace(emby_credentials=self.credentials)
        run.cells = {("main-window-browser", "accessibility:Emby-Connection-Connect"): {"reason": "", "verdict": "unmeasured", "evidence": []}}
        run.events = []
        run.raw = self.raw
        responses = list(controller_responses)
        def controller_side_effect(*args, **kwargs):
            if responses:
                return responses.pop(0)
            return {"success": True, "ok": True, "payload": ["0" * 64]}
        run.controller = Mock(side_effect=controller_side_effect)
        run.local_call = Mock(return_value=Mock(returncode=local_returncode, stderr="", stdout=""))
        return run
    def test_staging_and_sign_in_when_no_identity(self) -> None:
        no_identity = {"success": False, "ok": False, "detail": "No authenticated Emby server is configured.", "payload": []}
        sign_in_ok = {"success": True, "ok": True, "detail": None, "payload": None, "embySignInReceipt": {"schema": "enchron.regression.emby-sign-in@1", "serverID": "s", "userID": "u", "identityDigest": "sha256:" + "0" * 64, "persisted": True}}
        digest_ok = {"success": True, "ok": True, "payload": ["1" * 64]}
        run = self.make_run([no_identity, sign_in_ok, digest_ok])
        with patch("regression_emby_source.provision_runtime_identity") as provision, patch.object(enchron_target, "copy_to_container", return_value=Mock(returncode=0, stderr="", stdout="")) as copy, patch.object(enchron_target, "is_simulator", return_value=False):
            provision.return_value = {"schema": "enchron.regression.emby-runtime-identity@1", "serverID": "s", "userID": "u", "mode": "0600"}
            result = run.ensure_emby_sign_in()
            self.assertTrue(result)
            provision.assert_called_once()
            self.assertTrue(run.local_call.called)
            controller_calls = [call.args for call in run.controller.call_args_list]
            verbs = [args[1] if len(args) > 1 else "" for args in controller_calls]
            self.assertIn("embyServerIdentityDigest", str(controller_calls))
            self.assertIn("embySignIn", str(controller_calls))
    def test_skipped_when_already_authenticated(self) -> None:
        already = {"success": True, "ok": True, "payload": ["a" * 64]}
        run = self.make_run([already])
        with patch("regression_emby_source.provision_runtime_identity") as provision, patch.object(enchron_target, "copy_to_container") as copy:
            result = run.ensure_emby_sign_in()
            self.assertTrue(result)
            provision.assert_not_called()
            copy.assert_not_called()
            self.assertEqual(run.controller.call_count, 1)
    def test_refusal_recorded(self) -> None:
        no_identity = {"success": False, "ok": False, "detail": "No authenticated Emby server is configured."}
        refusal = {"success": False, "ok": False, "detail": "embySignIn requires a canonical identity digest."}
        second_no_identity = {"success": False, "ok": False, "detail": "No authenticated Emby server is configured."}
        run = self.make_run([no_identity, refusal, second_no_identity])
        with patch("regression_emby_source.provision_runtime_identity") as provision, patch.object(enchron_target, "copy_to_container", return_value=Mock(returncode=0, stderr="", stdout="")) as copy, patch.object(enchron_target, "is_simulator", return_value=False):
            provision.return_value = {"schema": "enchron.regression.emby-runtime-identity@1", "serverID": "s", "userID": "u", "mode": "0600"}
            result = run.ensure_emby_sign_in()
            self.assertFalse(result)
            self.assertTrue(any(event.get("action") == "embySignIn" and event.get("success") is False for event in run.events))
            self.assertIn("refused", run.cells[("main-window-browser", "accessibility:Emby-Connection-Connect")]["reason"])
if __name__ == "__main__":
    unittest.main()
