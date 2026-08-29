#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import replace
from http.client import IncompleteRead
import hashlib
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import regression_environment_preflight as preflight
import regression_remote_source as remote


FIXTURES = (
    (
        "generated-sdr-avc-bframe-aggregate-30s-v1",
        "sdr-bframe-aggregate-30s.mkv",
        bytes(range(256)) * 8,
    ),
    (
        "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
        "sdr-bframe-aggregate-30s.zh-CN.srt",
        b"1\n00:00:00,000 --> 00:00:01,000\nRemote subtitle\n",
    ),
    (
        "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
        "sdr-bframe-aggregate-30s.styled.ass",
        b"[Script Info]\nTitle: Remote styled subtitle\n",
    ),
)


class RegressionEnvironmentPreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="environment-preflight-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source_root = self.root / "TestMedia"
        self.source_root.mkdir()
        entries: list[dict[str, object]] = []
        for identifier, name, content in FIXTURES:
            relative = Path("TestVectors/Enchron/PlaybackBehavior") / name
            source = self.source_root / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(content)
            entries.append(
                {
                    "id": identifier,
                    "deviceImportPath": relative.as_posix(),
                    "sha256": hashlib.sha256(content).hexdigest(),
                }
            )
        self.registry = self.root / "fixture-registry.json"
        self.registry.write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "deviceMediaRoot": "$WORKSPACE/TestMedia",
                    "fixtures": entries,
                }
            ),
            encoding="utf-8",
        )
        service = remote.ServiceConfiguration(
            runtime_root=self.root / "runtime",
            registry_path=self.registry,
            source_root=self.source_root,
            bind_host="127.0.0.1",
            port=0,
            allow_loopback=True,
        )
        self.configuration = preflight.PreflightConfiguration(
            service=service,
            request_timeout_seconds=2.0,
        )
        self.addCleanup(remote.RemoteSourceController(service).stop)

    def test_check_registry_is_closed_and_exact(self) -> None:
        self.assertEqual(
            tuple(preflight.CHECKS),
            ("webdav-regression", "remote-faults", "emby-aggregate"),
        )

    def test_emby_aggregate_delegates_to_the_typed_owned_source_preflight(self) -> None:
        expected = {
            "schema": "enchron.regression.emby-source-preflight@1",
            "check": "emby-aggregate",
            "ready": True,
            "receipt": {
                "schema": "enchron.regression.emby-seed-receipt@1",
                "receiptID": "receipt:emby-regression",
                "status": "active",
            },
        }
        with patch.object(preflight.emby, "run_preflight", return_value=expected) as run:
            report = preflight.run_checks(["emby-aggregate"], self.configuration)

        self.assertTrue(report["ready"])
        self.assertEqual(report["checks"], [expected])
        run.assert_called_once_with(preflight.DEFAULT_EMBY_CONFIGURATION)

    def test_webdav_regression_ensures_service_and_proves_registered_hashes(self) -> None:
        report = preflight.run_checks(["webdav-regression"], self.configuration)
        self.assertTrue(report["ready"])
        self.assertEqual(report["schema"], "enchron.regression.environment-preflight@1")
        check = report["checks"][0]
        self.assertEqual(check["check"], "webdav-regression")
        self.assertTrue(check["ready"])
        self.assertEqual(check["propfindStatus"], 207)
        self.assertEqual(check["rangeStatus"], 206)
        self.assertEqual(check["rangeDigest"], check["expectedRangeDigest"])
        self.assertEqual(set(check["objectManifestHashes"]), {item[0] for item in FIXTURES})

        controller = remote.RemoteSourceController(self.configuration.service)
        self.assertEqual(controller.ensure(), controller.status())
        runtime_path = self.configuration.service.runtime_file
        self.assertEqual(stat.S_IMODE(runtime_path.stat().st_mode), 0o600)

        runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
        rendered = preflight.render_report(report)
        self.assertNotIn(str(runtime["user"]), rendered)
        self.assertNotIn(str(runtime["password"]), rendered)

    def test_remote_faults_verifies_every_closed_recipe_and_restores_each(self) -> None:
        report = preflight.run_checks(["remote-faults"], self.configuration)
        self.assertTrue(report["ready"])
        check = report["checks"][0]
        self.assertEqual(check["check"], "remote-faults")
        self.assertEqual(
            [item["recipe"] for item in check["recipes"]], list(remote.RECIPE_NAMES)
        )
        self.assertTrue(all(item["verified"] for item in check["recipes"]))
        for item in check["recipes"]:
            receipt = item["receipt"]
            self.assertRegex(receipt["restoredStateDigest"], r"^sha256:[0-9a-f]{64}$")
            self.assertRegex(receipt["logDigest"], r"^sha256:[0-9a-f]{64}$")

        runtime = json.loads(
            self.configuration.service.runtime_file.read_text(encoding="utf-8")
        )
        rendered = preflight.render_report(report)
        self.assertNotIn(str(runtime["user"]), rendered)
        self.assertNotIn(str(runtime["password"]), rendered)

    def test_single_recipe_actuation_has_an_idempotent_verified_restore_receipt(self) -> None:
        activation = preflight.activate_remote_recipe(
            self.configuration,
            "recoverable-read-interruption",
        )
        self.assertEqual(
            activation["schema"],
            "enchron.regression.remote-source-receipt@1",
        )
        self.assertEqual(activation["recipe"], "recoverable-read-interruption")
        self.assertIsNone(activation["restoredStateDigest"])

        manifest = remote.FixtureManifest.load(self.configuration.service)
        with self.assertRaises(IncompleteRead):
            preflight._range_request(
                self.configuration,
                manifest.primary.name,
                0,
                63,
            )
        recovered = preflight._range_request(
            self.configuration,
            manifest.primary.name,
            0,
            63,
        )
        self.assertEqual((recovered.status, len(recovered.body)), (206, 64))

        restoration = preflight.restore_remote_recipe(
            self.configuration,
            str(activation["receiptID"]),
        )
        self.assertEqual(
            restoration["schema"],
            "enchron.regression.remote-source-restoration@1",
        )
        self.assertTrue(restoration["verified"])
        self.assertEqual(
            restoration["activationReceiptID"], activation["receiptID"]
        )
        self.assertEqual(restoration["restoredRecipe"], "healthy")
        self.assertGreater(
            restoration["restoredGeneration"], activation["generation"]
        )
        self.assertEqual(restoration["propfindStatus"], 207)
        self.assertEqual(restoration["rangeStatus"], 206)
        self.assertEqual(
            restoration["rangeDigest"], restoration["expectedRangeDigest"]
        )
        self.assertEqual(
            restoration,
            preflight.restore_remote_recipe(
                self.configuration,
                str(activation["receiptID"]),
            ),
        )
        receipt_path = Path(str(restoration["receiptPath"]))
        self.assertTrue(receipt_path.is_file())
        self.assertEqual(
            restoration["receiptDigest"],
            "sha256:" + hashlib.sha256(receipt_path.read_bytes()).hexdigest(),
        )
        runtime = json.loads(
            self.configuration.service.runtime_file.read_text(encoding="utf-8")
        )
        rendered = preflight.render_report(restoration)
        self.assertNotIn(str(runtime["user"]), rendered)
        self.assertNotIn(str(runtime["password"]), rendered)

    def test_single_recipe_actuation_rejects_free_form_recipe_names(self) -> None:
        with self.assertRaisesRegex(preflight.PreflightError, "closed recipe"):
            preflight.activate_remote_recipe(
                self.configuration,
                "drop-any-packet",
            )

    def test_missing_or_digest_mismatched_fixture_fails_closed(self) -> None:
        missing_source = self.source_root / "TestVectors/Enchron/PlaybackBehavior" / FIXTURES[1][1]
        missing_source.unlink()
        failed_service = replace(
            self.configuration.service,
            runtime_root=self.root / "failed-runtime",
        )
        failed = preflight.run_checks(
            ["webdav-regression"],
            replace(self.configuration, service=failed_service),
        )
        self.assertFalse(failed["ready"])
        self.assertFalse(failed["checks"][0]["ready"])
        self.assertIn("missing", failed["checks"][0]["reason"])
        self.assertNotIn("password", preflight.render_report(failed).lower())

    def test_unknown_check_and_nonliteral_endpoint_are_rejected_at_the_boundary(self) -> None:
        with self.assertRaisesRegex(preflight.PreflightError, "unknown fixed check"):
            preflight.run_checks(["configure-anything"], self.configuration)
        bad_service = replace(self.configuration.service, bind_host="localhost")
        failed = preflight.run_checks(
            ["webdav-regression"], replace(self.configuration, service=bad_service)
        )
        self.assertFalse(failed["ready"])
        self.assertIn("literal", failed["checks"][0]["reason"])


if __name__ == "__main__":
    unittest.main()
