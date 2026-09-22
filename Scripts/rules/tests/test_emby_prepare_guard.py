import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

import Scripts.verification.reachability_matrix as matrix


def _replace_emby_provisioning_with_an_offline_stub() -> None:
    stub = ModuleType("regression_emby_source")
    stub.EmbySourceConfiguration = Mock()
    stub.provision_runtime_identity = Mock()
    sys.modules["regression_emby_source"] = stub


_replace_emby_provisioning_with_an_offline_stub()


def _digest_query_succeeded_with(device_identity: list[str]) -> dict[str, object]:
    return {"success": True, "ok": True, "payload": device_identity}


class EmbyPrepareGuardTests(unittest.TestCase):
    def _make_run(self, device_digest, server_digest):
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.arguments = Mock()
        creds = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        creds.write(json.dumps({"address": "http://127.0.0.1:8096", "username": "u", "password": "p"}).encode())
        creds.close()
        run.arguments.emby_credentials = Path(creds.name)
        run.raw = Path(tempfile.mkdtemp())
        run.events = []
        run.cells = {}
        run.out_of_context_observations = {}
        run.relaunch = Mock()
        run.tap = Mock(return_value={"success": True})
        run.segment = None
        run.session_id = "REACH-EMBY-GUARD"
        run.copy_probe = Mock(return_value=[])
        run.wait_for_identifier = Mock(return_value={"matchedElement": {}})
        run.mark_observation = Mock()
        run.delivered = Mock()
        run.tapped_cells = set()
        run.policy = Mock()
        run.tools = Mock()
        run.tools.call = Mock(return_value=Mock(returncode=0, stderr=""))
        run.controller = Mock()
        def controller_side_effect(verb, *args, **kwargs):
            if verb == "app-command" and "--verb" in args:
                idx = list(args).index("--verb")
                v = args[idx+1] if idx+1 < len(args) else ""
                if v == "embyServerIdentityDigest":
                    if device_digest is None:
                        return _digest_query_succeeded_with([])
                    return _digest_query_succeeded_with([device_digest])
                if v == "prepareEmbyAccount":
                    return {"success": True}
                if v == "embySignIn":
                    return {"success": True, "ok": True}
            return {"success": True}
        run.controller.side_effect = controller_side_effect
        run.sensitive_values = ()
        return run

    def test_staging_skipped_when_already_authenticated(self) -> None:
        server_digest = "abc123" * 10 + "abcd"
        device_digest = server_digest
        run = self._make_run(device_digest, server_digest)
        with patch.object(matrix, "verify_emby_recovery_credentials", return_value={"serverIdentityDigest": server_digest, "passed": True, "publicStatus": 200, "authenticationStatus": 200, "accessTokenPresent": True}):
            with patch.object(matrix.ReachabilityRun, "ensure_emby_staged_identity", wraps=run.ensure_emby_staged_identity) as mock_stage:
                mock_stage_mock = Mock(return_value={"success": True})
                with patch.object(run, "ensure_emby_staged_identity", mock_stage_mock):
                    run.emby_session_recovery_scenario()
                    mock_stage_mock.assert_not_called()
        Path(run.arguments.emby_credentials).unlink(missing_ok=True)

    def test_staging_invoked_when_no_identity(self) -> None:
        server_digest = "abc123" * 10 + "abcd"
        device_digest = None
        run = self._make_run(device_digest, server_digest)
        with patch.object(matrix, "verify_emby_recovery_credentials", return_value={"serverIdentityDigest": server_digest, "passed": True, "publicStatus": 200, "authenticationStatus": 200, "accessTokenPresent": True}):
            with patch.object(run, "ensure_emby_staged_identity", return_value={"success": True}) as mock_stage:
                run.emby_session_recovery_scenario()
                mock_stage.assert_called_once()
                args, _ = mock_stage.call_args
                self.assertEqual(args[0], run.arguments.emby_credentials)
                self.assertEqual(args[1], server_digest)
        Path(run.arguments.emby_credentials).unlink(missing_ok=True)

if __name__ == "__main__":
    unittest.main()
