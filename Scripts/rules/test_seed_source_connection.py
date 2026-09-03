#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/verification"))

import reachability_matrix as matrix
import regression_remote_source as remote
import regression_smb_source as smb
from harness.controller import CompletedInvocation, RunnerResponse
from harness.replay import RecordingTap


FEATURE_PASSWORD = "seed-source-feature-password"
FEATURE_USER = "seed-source-feature-user"
SOURCE_UUID = "11111111-2222-3333-4444-555555555555"


class SecretMarkerTests(unittest.TestCase):
    def test_marker_names_the_secret_length(self) -> None:
        redacted = matrix.redact_sensitive_values(
            {"value": f"typed {FEATURE_PASSWORD} here"},
            (FEATURE_PASSWORD,),
        )
        encoded = json.dumps(redacted)
        self.assertNotIn(FEATURE_PASSWORD, encoded)
        self.assertIn(f"<redacted secret, {len(FEATURE_PASSWORD)} chars>", encoded)


def bare_run(root: Path) -> matrix.ReachabilityRun:
    run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
    run.lane = "simulator"
    run.sensitive_values = ()
    run.sequence = 0
    run.events = []
    output = root / "output"
    run.raw = output / "raw"
    run.raw.mkdir(parents=True, exist_ok=True)
    run.output = output
    run.controller_output = output
    run.segment = None
    run.halted = False
    run.salvaging = False
    run.channel_failures = []
    run.history = []
    run.policy = matrix.RecoveryPolicy()
    run.budgets = matrix.BudgetProvider()
    run.operations = {}
    run.cells = {}
    run.driven_cells = set()
    run.tapped_cells = set()
    run.silent_taps = []
    run.out_of_context_observations = {}
    run.last_controller_document = {}
    run.arguments = SimpleNamespace(contexts=[])
    return run


class ControllerRedactionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="seed-source-redact-")
        self.addCleanup(self.temporary.cleanup)
        self.run = bare_run(Path(self.temporary.name))

    def test_event_arguments_hide_the_password(self) -> None:
        def invoke(verb: str, arguments: list[str]) -> RunnerResponse:
            return RunnerResponse(
                document={
                    "success": True,
                    "matchedElement": {"value": ""},
                    "elementAfterAction": {"value": FEATURE_PASSWORD},
                },
                failure=None,
            )

        self.run.client = type("FakeClient", (), {"invoke": staticmethod(invoke)})()
        self.run.sensitive_values = (FEATURE_PASSWORD,)
        self.run.controller(
            "typeText",
            "--identifier", "FileBrowsing-SourceConnection-webDAV-password",
            "--text", FEATURE_PASSWORD,
            "--no-screenshot",
        )
        self.assertNotIn(FEATURE_PASSWORD, json.dumps(self.run.events))
        raw_text = "\n".join(
            path.read_text(encoding="utf-8") for path in self.run.raw.glob("*.json")
        )
        self.assertNotIn(FEATURE_PASSWORD, raw_text)

    def test_stdout_carries_no_password(self) -> None:
        def invoke(verb: str, arguments: list[str]) -> RunnerResponse:
            return RunnerResponse(document={"success": True}, failure=None)

        self.run.client = type("FakeClient", (), {"invoke": staticmethod(invoke)})()
        self.run.sensitive_values = (FEATURE_PASSWORD,)
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            self.run.controller("snapshot", "--no-screenshot")
        self.assertNotIn(FEATURE_PASSWORD, buffer.getvalue())


class TranscriptRedactionTests(unittest.TestCase):
    def test_transcript_hides_command_and_response_secrets(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="seed-source-transcript-")
        self.addCleanup(temporary.cleanup)
        transcript = Path(temporary.name) / "controller-transcript.jsonl"

        def inner(command: object, timeout: float) -> CompletedInvocation:
            return CompletedInvocation(
                returncode=0,
                stdout=json.dumps({
                    "success": True,
                    "elementAfterAction": {"value": FEATURE_PASSWORD},
                }),
                stderr="",
            )

        tap = RecordingTap(inner, transcript, redact=(FEATURE_PASSWORD,))
        tap(["typeText", "--text", FEATURE_PASSWORD], 30.0)
        encoded = transcript.read_text(encoding="utf-8")
        self.assertNotIn(FEATURE_PASSWORD, encoded)


class KeyedEnvironmentReaderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="seed-source-env-")
        self.addCleanup(self.temporary.cleanup)
        self.environment_file = Path(self.temporary.name) / ".env"
        self.environment_file.write_text(
            "# fixture\n"
            "SMB_USER=someone-else\n"
            "SMB_PASSWORD=someone-else-password\n"
            f"export WEBDAV_USER={FEATURE_USER}\n"
            f'WEBDAV_PASSWORD="{FEATURE_PASSWORD}"\n',
            encoding="utf-8",
        )

    def test_reads_named_keys_and_ignores_other_services(self) -> None:
        credentials = smb.read_environment_credentials(
            self.environment_file,
            user_key="WEBDAV_USER",
            password_key="WEBDAV_PASSWORD",
        )
        self.assertEqual(credentials.user, FEATURE_USER)
        self.assertEqual(credentials.password, FEATURE_PASSWORD)

    def test_missing_password_names_its_key(self) -> None:
        self.environment_file.write_text("WEBDAV_USER=someone\n", encoding="utf-8")
        with self.assertRaisesRegex(smb.SMBSourceConfigurationError, "WEBDAV_PASSWORD"):
            smb.read_environment_credentials(
                self.environment_file,
                user_key="WEBDAV_USER",
                password_key="WEBDAV_PASSWORD",
            )

    def test_legacy_reader_still_reads_smb_keys(self) -> None:
        credentials = smb.read_environment_credentials(
            self.environment_file,
            user_key="SMB_USER",
            password_key="SMB_PASSWORD",
        )
        self.assertEqual(credentials.user, "someone-else")


class DaemonEnvironmentCredentialTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="seed-source-daemon-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment_file = self.root / ".env"
        self.environment_file.write_text(
            f"WEBDAV_USER={FEATURE_USER}\nWEBDAV_PASSWORD={FEATURE_PASSWORD}\n",
            encoding="utf-8",
        )
        self.registry = self.root / "fixture-registry.json"
        self.registry.write_text(
            json.dumps({"schemaVersion": 2, "deviceMediaRoot": "$WORKSPACE/TestMedia", "fixtures": []}),
            encoding="utf-8",
        )
        self.source_root = self.root / "TestMedia"
        self.source_root.mkdir()
        self.configuration = remote.ServiceConfiguration(
            runtime_root=self.root / "runtime",
            registry_path=self.registry,
            source_root=self.source_root,
            bind_host="127.0.0.1",
            port=0,
            allow_loopback=True,
            environment_file=self.environment_file,
        )
        self.controller = remote.RemoteSourceController(self.configuration)

    def test_daemon_identity_comes_from_the_environment_file(self) -> None:
        user, password = self.controller._credentials()
        self.assertEqual((user, password), (FEATURE_USER, FEATURE_PASSWORD))

    def test_missing_environment_file_fails_closed(self) -> None:
        missing = remote.ServiceConfiguration(
            runtime_root=self.root / "other-runtime",
            registry_path=self.registry,
            source_root=self.source_root,
            bind_host="127.0.0.1",
            port=0,
            allow_loopback=True,
            environment_file=self.root / "no-such-env",
        )
        with self.assertRaises(remote.RemoteSourceConfigurationError):
            remote.RemoteSourceController(missing)._credentials()

    def test_rotating_environment_credentials_restarts_the_daemon(self) -> None:
        live = remote.ServiceConfiguration(
            runtime_root=self.root / "live-runtime",
            registry_path=REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json",
            source_root=REPOSITORY_ROOT.parent / "TestMedia",
            bind_host="127.0.0.1",
            port=0,
            allow_loopback=True,
            environment_file=self.environment_file,
        )
        controller = remote.RemoteSourceController(live)
        controller.ensure()
        self.addCleanup(controller.stop)
        first = json.loads(live.runtime_file.read_text(encoding="utf-8"))
        self.assertEqual((first["user"], first["password"]), (FEATURE_USER, FEATURE_PASSWORD))
        self.environment_file.write_text(
            "WEBDAV_USER=rotated-user\nWEBDAV_PASSWORD=rotated-password\n",
            encoding="utf-8",
        )
        controller.ensure()
        second = json.loads(live.runtime_file.read_text(encoding="utf-8"))
        self.assertEqual((second["user"], second["password"]), ("rotated-user", "rotated-password"))


class FakeClient:
    def __init__(self, run: matrix.ReachabilityRun, runtime_file: Path) -> None:
        self.run = run
        self.runtime_file = runtime_file
        self.calls: list[tuple[str, tuple[str, ...]]] = []
        self.phase = "form"
        self.taps: list[str] = []

    def invoke(self, verb: str, arguments: list[str]) -> RunnerResponse:
        self.calls.append((verb, tuple(arguments)))
        if verb == "tap":
            if "--identifier" in arguments:
                identifier = arguments[arguments.index("--identifier") + 1]
            elif "--label" in arguments:
                identifier = arguments[arguments.index("--label") + 1]
            else:
                identifier = " ".join(arguments)
            self.taps.append(identifier)
            if identifier == "FileBrowsing-CertificateTrust-trust":
                self.phase = "connected"
            if identifier in ("Not Now", "以后") and self.phase == "cert":
                self.phase = "cert-ready"
            if identifier == "Delete selected sources":
                self.phase = "clean"
            return RunnerResponse(
                document={
                    "success": True,
                    "matchedElement": {"isHittable": True, "isEnabled": True, "value": ""},
                },
                failure=None,
            )
        if verb in ("typeText", "replaceText"):
            if "--text-file" in arguments:
                path = Path(arguments[arguments.index("--text-file") + 1])
                key = arguments[arguments.index("--text-json-key") + 1]
                typed = json.loads(path.read_text(encoding="utf-8"))[key]
                echoed = "<redacted-input>" if "--redact-response-text" in arguments else typed
            else:
                typed = arguments[arguments.index("--text") + 1]
                echoed = typed
            return RunnerResponse(
                document={
                    "success": True,
                    "matchedElement": {"value": ""},
                    "elementAfterAction": {"value": echoed},
                },
                failure=None,
            )
        if verb == "snapshot":
            return RunnerResponse(
                document={"success": True, "hierarchy": self.hierarchy()},
                failure=None,
            )
        if verb in ("swipeUp", "relaunch", "activate"):
            return RunnerResponse(document={"success": True}, failure=None)
        if verb == "app-command":
            if "listMenuItems" in arguments:
                return RunnerResponse(
                    document={"success": True, "payload": ["webDAV", "delete", "local", "refresh", "0"]},
                    failure=None,
                )
            if "resetState" in arguments:
                return RunnerResponse(
                    document={"success": True, "ok": True, "payload": []},
                    failure=None,
                )
            return RunnerResponse(document={"success": True}, failure=None)
        return RunnerResponse(document={"success": True}, failure=None)

    def hierarchy(self) -> str:
        if self.phase == "form":
            return "identifier: 'FileBrowsing-SourceConnection-webDAV-address'\n"
        if self.phase == "cert":
            return (
                "Alert, label: 'Save Password?'\n"
                "  Button, label: 'Save'\n"
                "  Button, label: 'Not Now'\n"
            )
        if self.phase == "cert-ready":
            return (
                "identifier: 'FileBrowsing-CertificateTrust-trust'\n"
                "identifier: 'FileBrowsing-CertificateTrust-cancel'\n"
            )
        if self.phase == "clean":
            return "identifier: 'FileBrowsing-SourcesSidebar-source-media-library'\n"
        return (
            "identifier: 'FileBrowsing-SourcesSidebar-source-media-library'\n"
            f"identifier: 'FileBrowsing-SourcesSidebar-source-{SOURCE_UUID}'\n"
            "identifier: 'FileBrowsing-Breadcrumb-current'\n"
        )


def scenario_run(root: Path) -> matrix.ReachabilityRun:
    run = bare_run(root)
    run.service_hosts = {"webdav": "Mac-mini.local"}
    run.service_receipts = {
        "webdav": {"address": "https://Mac-mini.local:8443/dav/regression/"}
    }
    run.copy_probe = lambda label: []  # noqa: E731
    run.wait_for_probe = lambda label, offset, needle, **kwargs: []  # noqa: E731
    run.wait_for_identifier = lambda identifier, **kwargs: {  # noqa: E731
        "matchedElement": {"isHittable": True, "isEnabled": True, "value": ""}
    }
    run.wait_for_any_identifier = lambda identifiers, **kwargs: (  # noqa: E731
        "FileBrowsing-CertificateTrust-trust",
        {"matchedElement": {"isHittable": True, "isEnabled": True, "value": ""}},
    )
    run.hold = lambda *args, **kwargs: None  # noqa: E731
    return run


def scan_output(root: Path, secrets: tuple[str, ...]) -> list[str]:
    hits = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for secret in secrets:
            if secret and secret in text:
                hits.append(f"{path.relative_to(root)} leaks {len(secret)} secret chars")
    return hits


class WebDAVConnectionScenarioTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="seed-source-scenario-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment_file = self.root / ".env"
        self.environment_file.write_text(
            f"WEBDAV_USER={FEATURE_USER}\nWEBDAV_PASSWORD={FEATURE_PASSWORD}\n",
            encoding="utf-8",
        )
        self.runtime_file = self.root / "webdav-runtime.json"
        self.runtime_file.write_text(
            json.dumps({"address": "https://Mac-mini.local:8443/dav/regression/", "user": FEATURE_USER, "password": FEATURE_PASSWORD}),
            encoding="utf-8",
        )
        self.run = scenario_run(self.root)
        self.run.webdav_environment_file = self.environment_file
        self.run.webdav_runtime_file = self.runtime_file
        self.client = FakeClient(self.run, self.runtime_file)
        self.run.client = self.client
        self.client.phase = "cert"

    def test_connect_uses_the_environment_identity_without_fake_credentials(self) -> None:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            self.run.source_connection_scenario("webDAV")
        argv = [token for _, tokens in self.client.calls for token in tokens]
        self.assertNotIn("not-a-secret", argv)
        password_calls = [
            tokens for verb, tokens in self.client.calls
            if verb in ("typeText", "replaceText") and "password" in " ".join(tokens)
        ]
        self.assertTrue(password_calls, "the password field must be typed")
        for tokens in password_calls:
            self.assertIn("--text-file", tokens)
            self.assertIn("--redact-response-text", tokens)
            self.assertNotIn(FEATURE_PASSWORD, tokens)
        address_calls = [
            tokens for verb, tokens in self.client.calls
            if verb == "typeText" and "webDAV-address" in " ".join(tokens)
        ]
        self.assertTrue(address_calls, "the address field must be typed")
        self.assertIn("https://Mac-mini.local:8443/dav/regression/", " ".join(address_calls[0]))

    def test_certificate_trust_is_tapped_and_cancel_is_not(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.run.source_connection_scenario("webDAV")
        self.assertIn("FileBrowsing-CertificateTrust-trust", self.client.taps)
        self.assertNotIn("FileBrowsing-CertificateTrust-cancel", self.client.taps)

    def test_save_password_sheet_is_dismissed_before_trust(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.run.source_connection_scenario("webDAV")
        taps = self.client.taps
        self.assertIn("Not Now", taps)
        self.assertLess(
            taps.index("Not Now"),
            taps.index("FileBrowsing-CertificateTrust-trust"),
        )

    def test_missing_prompt_fails_without_trust(self) -> None:
        self.client.phase = "form"
        with contextlib.redirect_stdout(io.StringIO()):
            self.run.source_connection_scenario("webDAV")
        actions = [event.get("action") for event in self.run.events]
        self.assertIn("webdavCertificateTrustMissing", actions)
        self.assertNotIn("FileBrowsing-CertificateTrust-trust", self.client.taps)

    def test_connected_source_is_required_and_recorded(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.run.source_connection_scenario("webDAV")
        self.assertEqual(self.run.last_connected_webdav_source, SOURCE_UUID)

    def test_password_never_reaches_outputs_or_stdout(self) -> None:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            self.run.source_connection_scenario("webDAV")
        self.assertEqual(scan_output(self.run.output, (FEATURE_PASSWORD, FEATURE_USER)), [])
        self.assertNotIn(FEATURE_PASSWORD, buffer.getvalue())
        self.assertNotIn(FEATURE_USER, buffer.getvalue())

    def test_missing_environment_file_fails_without_typing(self) -> None:
        self.run.webdav_environment_file = self.root / "no-such-env"
        with contextlib.redirect_stdout(io.StringIO()):
            self.run.source_connection_scenario("webDAV")
        typing = [verb for verb, _ in self.client.calls if verb in ("typeText", "replaceText")]
        self.assertEqual(typing, [])
        actions = [event.get("action") for event in self.run.events]
        self.assertIn("webdavCredentialsMissing", actions)


class SidebarCleanupScenarioTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="seed-source-sidebar-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.run = scenario_run(self.root)
        self.client = FakeClient(self.run, self.root / "unused.json")
        self.run.client = self.client
        self.client.phase = "connected"
        self.run.last_connected_webdav_source = SOURCE_UUID

    def test_real_delete_removes_the_connected_source(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.run.source_sidebar_scenario()
        self.assertIn("Delete selected sources", self.client.taps)
        self.assertIn(SOURCE_UUID, self.run.last_removed_remote_sources)
        resets = [
            tokens for verb, tokens in self.client.calls
            if verb == "app-command" and "resetState" in tokens
        ]
        self.assertEqual(resets, [])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
