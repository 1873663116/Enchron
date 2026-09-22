#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import replace
from io import BytesIO
import json
from pathlib import Path
import shlex
import sys
from tempfile import TemporaryDirectory
import unittest


SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.completion import (
    CompletionError,
    artifact_record,
    validate_audit_manifest,
    validate_configuration_receipt,
)
from regression.core.digest import canonical_bytes, digest_bytes
from regression.final_artifacts import (
    FinalArtifactError,
    FinalArtifactInputs,
    main,
    write_final_artifacts,
)


SOURCE_DIGEST = "sha256:" + "1" * 64
BLUEPRINT_DIGEST = "sha256:" + "2" * 64
CATALOG_DIGEST = "sha256:" + "3" * 64
REVIEW_DIGEST = "sha256:" + "4" * 64
SEMANTIC_DIGEST = "sha256:" + "5" * 64
BASE_COMMIT = "a" * 40
HEAD_COMMIT = "b" * 40
DIFF_DIGEST = "sha256:" + "d" * 64
PRODUCT_PATH = "Modules/Playback/Domain/MediaFormatInterpreter.swift"
DEVELOPER_DIRECTORY = "/Applications/Xcode-beta.app/Contents/Developer"
TOOLCHAIN = {
    "xcodeVersion": "27.0",
    "xcodeBuild": "17A5308f",
    "visionOSSDKVersion": "27.0",
    "visionOSSDKBuild": "24N5300a",
    "visionOSSimulatorSDKVersion": "27.0",
    "visionOSSimulatorSDKBuild": "24N5300a",
}


class FinalArtifactWriterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.final_root = Path(self.temporary.name).resolve() / "final"
        self.final_root.mkdir()

        self.verification = self.write_json(
            "verification-summary.json", self.passing_verification_summary()
        )
        for log in self.verification_logs():
            source = (
                b"$ python3 focused.py\nMediaFormatInterpreterTests passed\n"
                if log == "domain-tests.log"
                else f"$ python3 {log}\npassed\n".encode()
            )
            self.write_bytes(log, source)
        self.no_comments = self.write_bytes(
            "audits/no-comments.json", self.audit_result("no-comments")
        )
        self.interrogate = self.write_bytes(
            "audits/interrogate.json", self.audit_result("interrogate")
        )
        self.blast_radius = self.write_bytes(
            "audits/blast-radius.json", self.audit_result("blast-radius")
        )
        self.vp_e2e = self.write_bytes(
            "audits/vp-e2e.json", self.audit_result("vp-e2e")
        )
        self.write_set = self.write_json(
            "actual-write-set.json",
            {
                "schema": "enchron.regression.actual-write-set-receipt",
                "schemaVersion": 1,
                "sourceDigest": SOURCE_DIGEST,
                "range": self.receipt_range(),
                "tasks": [
                    {
                        "id": "product",
                        "dependsOn": [],
                        "writes": ["Modules/Playback/**"],
                        "actualPaths": [PRODUCT_PATH],
                    }
                ],
            },
        )
        self.product_coverage = self.write_json(
            "product-swift-coverage.json",
            {
                "schema": "enchron.regression.product-swift-coverage",
                "schemaVersion": 1,
                "sourceDigest": SOURCE_DIGEST,
                "range": self.receipt_range(),
                "files": [
                    {
                        "path": PRODUCT_PATH,
                        "focusedTest": {
                            "identifier": "MediaFormatInterpreterTests",
                            "log": artifact_record(
                                self.final_root / "domain-tests.log",
                                self.final_root,
                            ),
                        },
                        "runtimeObservation": {
                            "nodeId": "node:format",
                            "evidenceDigest": "sha256:" + "e" * 64,
                        },
                    }
                ],
            },
        )
        self.merge_receipt = self.write_json(
            "merge-run-receipt.json", {"fixture": "current"}
        )
        self.simulator_result, self.simulator_log, self.simulator_xctestrun = (
            self.build_result("simulator", "SIMULATOR-UDID", "7", "8")
        )
        self.device_result, self.device_log, self.device_xctestrun = self.build_result(
            "device", "DEVICE-UDID", "a", "b"
        )
        self.inputs = FinalArtifactInputs(
            final_root=self.final_root,
            source_digest=SOURCE_DIGEST,
            verification_summary=self.verification,
            no_comments_evidence=self.no_comments,
            interrogate_evidence=self.interrogate,
            blast_radius_evidence=self.blast_radius,
            vp_e2e_evidence=self.vp_e2e,
            write_set_receipt=self.write_set,
            product_swift_coverage=self.product_coverage,
            blueprint_digest=BLUEPRINT_DIGEST,
            catalog_digest=CATALOG_DIGEST,
            review_completion_digest=REVIEW_DIGEST,
            semantic_authority_digest=SEMANTIC_DIGEST,
            merge_run_receipt=self.merge_receipt,
            simulator_build_result=self.simulator_result,
            device_build_result=self.device_result,
        )

    def write_bytes(self, relative: str, source: bytes) -> Path:
        path = self.final_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(source)
        return path

    def write_json(self, relative: str, payload: object) -> Path:
        return self.write_bytes(relative, canonical_bytes(payload) + b"\n")

    def audit_result(self, name: str) -> bytes:
        return canonical_bytes(
            {
                "schema": "enchron.regression.audit-result",
                "schemaVersion": 1,
                "audit": name,
                "sourceDigest": SOURCE_DIGEST,
                "verdict": "passed",
            }
        ) + b"\n"

    def receipt_range(self) -> dict[str, str]:
        return {
            "expression": "base..HEAD",
            "baseCommit": BASE_COMMIT,
            "headCommit": HEAD_COMMIT,
            "diffSha256": DIFF_DIGEST,
        }

    def verification_logs(self) -> tuple[str, ...]:
        return (
            "domain-tests.log",
            "structure/documentation-references.log",
            "structure/package-membership.log",
            "structure/playback-surface-structure.log",
            "structure/product-source-comments.log",
            "structure/release-test-channel-absent.log",
            "structure/regression-core-layering.log",
            "structure/scripts-inventory.log",
            "structure/test-merge-authority.log",
            "structure/test-regression-write-set.log",
        )

    def build_result(
        self,
        lane: str,
        target: str,
        products_fill: str,
        code_fill: str,
    ) -> tuple[Path, Path, Path]:
        derived_data = self.final_root / "lanes" / lane / "DerivedData"
        xctestrun = self.write_bytes(
            str(
                (
                    derived_data
                    / "Build/Products"
                    / f"Enchron-{lane}.xctestrun"
                ).relative_to(self.final_root)
            ),
            f"{lane}-xctestrun\n".encode(),
        )
        destination = (
            f"platform=visionOS Simulator,id={target}"
            if lane == "simulator"
            else f"platform=visionOS,id={target}"
        )
        command = [
            "xcodebuild",
            "build-for-testing",
            "-project",
            str(self.final_root.parent / "Enchron.xcodeproj"),
            "-scheme",
            "Enchron",
            "-destination",
            destination,
            "-derivedDataPath",
            str(derived_data),
        ]
        log = self.write_bytes(
            f"build/{lane}.log",
            ("$ " + shlex.join(command) + "\n** BUILD SUCCEEDED **\n").encode(),
        )
        result = self.write_json(
            f"build/{lane}-result.json",
            {
                "schema": "enchron.regression.xcode-build-result",
                "schemaVersion": 1,
                "lane": lane,
                "sourceDigest": SOURCE_DIGEST,
                "command": command,
                "destination": destination,
                "developerDirectory": DEVELOPER_DIRECTORY,
                "toolchain": TOOLCHAIN,
                "xctestrun": artifact_record(xctestrun, self.final_root),
                "laneArtifact": {
                    "xctestrunDigest": str(digest_bytes(xctestrun.read_bytes())),
                    "testProductsDigest": "sha256:" + products_fill * 64,
                    "applicationCodeDigest": "sha256:" + code_fill * 64,
                },
                "log": artifact_record(log, self.final_root),
                "verdict": "passed",
            },
        )
        return result, log, xctestrun

    def passing_verification_summary(self) -> dict[str, object]:
        return {
            "version": 1,
            "startedAt": "2026-08-29T00:00:00+00:00",
            "finishedAt": "2026-08-29T00:10:00+00:00",
            "mode": "full",
            "repository": str(self.final_root.parent),
            "developerDirectory": DEVELOPER_DIRECTORY,
            "layers": [
                {
                    "name": "Structure checks",
                    "state": "PASS",
                    "detail": "all checks passed",
                    "logs": [
                        "structure/package-membership.log",
                        "structure/playback-surface-structure.log",
                        "structure/product-source-comments.log",
                        "structure/release-test-channel-absent.log",
                        "structure/regression-core-layering.log",
                        "structure/documentation-references.log",
                        "structure/scripts-inventory.log",
                        "structure/test-merge-authority.log",
                        "structure/test-regression-write-set.log",
                    ],
                },
                *(
                    {
                        "name": name,
                        "state": "PASS",
                        "detail": "passed",
                        "logs": ["domain-tests.log"] if name == "Domain tests" else [],
                    }
                    for name in (
                        "PlaybackCore tests",
                        "Guard self-tests",
                        "Domain tests",
                        "Git hook installation",
                        "Source parity",
                        "Media discovery capability matrix",
                        "Feature evidence coverage",
                    )
                ),
            ],
            "verdict": "passed",
        }

    def assert_no_outputs(self) -> None:
        self.assertFalse((self.final_root / "audit-manifest.json").exists())
        self.assertFalse(
            (self.final_root / "configuration-receipt.json").exists()
        )

    def assert_no_temporary_files(self) -> None:
        self.assertFalse(
            any(path.name.endswith(".tmp") for path in self.final_root.iterdir())
        )

    def test_writes_canonical_bound_artifacts_and_reruns_idempotently(self) -> None:
        first = write_final_artifacts(self.inputs)
        audit_source = first.audit_manifest.read_bytes()
        configuration_source = first.configuration_receipt.read_bytes()
        audit_inode = first.audit_manifest.stat().st_ino
        configuration_inode = first.configuration_receipt.stat().st_ino

        audit_payload = json.loads(audit_source)
        configuration_payload = json.loads(configuration_source)
        self.assertEqual(audit_source, canonical_bytes(audit_payload) + b"\n")
        self.assertEqual(
            configuration_source, canonical_bytes(configuration_payload) + b"\n"
        )
        self.assertEqual(
            audit_payload["evidence"]["vp-e2e"],
            artifact_record(self.vp_e2e, self.final_root),
        )
        self.assertEqual(
            configuration_payload["buildLogs"]["device"],
            artifact_record(self.device_result, self.final_root),
        )

        audit = validate_audit_manifest(
            first.audit_manifest, self.final_root, SOURCE_DIGEST
        )
        configuration = validate_configuration_receipt(
            first.configuration_receipt,
            self.final_root,
            expected_source_digest=SOURCE_DIGEST,
            expected_blueprint_digest=BLUEPRINT_DIGEST,
            expected_catalog_digest=CATALOG_DIGEST,
            expected_review_digest=REVIEW_DIGEST,
            expected_semantic_authority_digest=SEMANTIC_DIGEST,
            expected_verification_record=audit.verification_record,
            expected_developer_directory=DEVELOPER_DIRECTORY,
        )
        self.assertEqual(configuration.verification_record, audit.verification_record)

        second = write_final_artifacts(self.inputs)
        self.assertEqual(second, first)
        self.assertEqual(second.audit_manifest.stat().st_ino, audit_inode)
        self.assertEqual(
            second.configuration_receipt.stat().st_ino, configuration_inode
        )
        self.assertEqual(
            second.audit_manifest_digest, str(digest_bytes(audit_source))
        )
        self.assertEqual(
            second.configuration_receipt_digest,
            str(digest_bytes(configuration_source)),
        )
        self.assert_no_temporary_files()

    def test_cli_accepts_paths_relative_to_final_root(self) -> None:
        output = BytesIO()
        status = main(
            [
                "--final-root",
                str(self.final_root),
                "--source-digest",
                SOURCE_DIGEST,
                "--verification-summary",
                "verification-summary.json",
                "--no-comments-evidence",
                "audits/no-comments.json",
                "--interrogate-evidence",
                "audits/interrogate.json",
                "--blast-radius-evidence",
                "audits/blast-radius.json",
                "--vp-e2e-evidence",
                "audits/vp-e2e.json",
                "--write-set-receipt",
                "actual-write-set.json",
                "--product-swift-coverage",
                "product-swift-coverage.json",
                "--blueprint-digest",
                BLUEPRINT_DIGEST,
                "--catalog-digest",
                CATALOG_DIGEST,
                "--review-completion-digest",
                REVIEW_DIGEST,
                "--semantic-authority-digest",
                SEMANTIC_DIGEST,
                "--merge-run-receipt",
                "merge-run-receipt.json",
                "--simulator-build-result",
                "build/simulator-result.json",
                "--device-build-result",
                "build/device-result.json",
            ],
            stdout=output,
        )

        self.assertEqual(status, 0)
        payload = json.loads(output.getvalue())
        self.assertEqual(output.getvalue(), canonical_bytes(payload) + b"\n")
        self.assertEqual(
            payload["auditManifest"]["path"],
            str(self.final_root / "audit-manifest.json"),
        )

    def test_rejects_reused_audit_evidence_before_publishing(self) -> None:
        with self.assertRaisesRegex(FinalArtifactError, "must be distinct"):
            write_final_artifacts(
                replace(self.inputs, vp_e2e_evidence=self.no_comments)
            )
        self.assert_no_outputs()

    def test_rejects_empty_input_before_publishing(self) -> None:
        self.vp_e2e.write_bytes(b"")
        with self.assertRaisesRegex(FinalArtifactError, "must not be empty"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()

    def test_rejects_missing_named_verification_log_before_publishing(self) -> None:
        (self.final_root / "structure/package-membership.log").unlink()
        with self.assertRaisesRegex(CompletionError, "verification log"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()

    def test_rejects_untyped_or_stale_audit_result_before_publishing(self) -> None:
        self.interrogate.write_bytes(b"interrogate passed\n")
        with self.assertRaisesRegex(CompletionError, "valid JSON"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()

        self.interrogate.write_bytes(self.audit_result("interrogate"))
        stale = json.loads(self.vp_e2e.read_bytes())
        stale["sourceDigest"] = "sha256:" + "0" * 64
        self.write_json("audits/vp-e2e.json", stale)
        with self.assertRaisesRegex(CompletionError, "source digest is stale"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()

    def test_rejects_stale_actual_write_set_before_publishing(self) -> None:
        receipt = json.loads(self.write_set.read_bytes())
        receipt["sourceDigest"] = "sha256:" + "0" * 64
        self.write_json("actual-write-set.json", receipt)
        with self.assertRaisesRegex(CompletionError, "source digest is stale"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()

    def test_rejects_forged_build_destination_before_publishing(self) -> None:
        result = json.loads(self.simulator_result.read_bytes())
        result["destination"] = "platform=visionOS Simulator,id=FORGED"
        self.write_json("build/simulator-result.json", result)
        with self.assertRaisesRegex(CompletionError, "destination differs"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()

    def test_rejects_missing_input_before_publishing(self) -> None:
        missing = self.final_root / "merge-run-receipt-missing.json"
        with self.assertRaisesRegex(CompletionError, "missing current artifact"):
            write_final_artifacts(replace(self.inputs, merge_run_receipt=missing))
        self.assert_no_outputs()

    def test_rejects_non_full_verification_before_publishing(self) -> None:
        summary = self.passing_verification_summary()
        summary["mode"] = "quick"
        self.write_json("verification-summary.json", summary)

        with self.assertRaisesRegex(CompletionError, "version 1 full mode"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()
        self.assert_no_temporary_files()

    def test_rejects_build_log_without_success_marker_before_publishing(self) -> None:
        self.device_log.write_bytes(b"** BUILD FAILED **\n")
        with self.assertRaisesRegex(CompletionError, "digest"):
            write_final_artifacts(self.inputs)
        self.assert_no_outputs()

    def test_rejects_reused_build_result_before_publishing(self) -> None:
        with self.assertRaisesRegex(FinalArtifactError, "build results must be distinct"):
            write_final_artifacts(
                replace(self.inputs, device_build_result=self.simulator_result)
            )
        self.assert_no_outputs()

    def test_rejects_artifact_outside_final_root(self) -> None:
        outside = self.final_root.parent / "outside.txt"
        outside.write_text("audit\n", encoding="utf-8")
        with self.assertRaisesRegex(CompletionError, "inside final root"):
            write_final_artifacts(
                replace(self.inputs, no_comments_evidence=outside)
            )
        self.assert_no_outputs()

    def test_existing_different_output_is_never_overwritten(self) -> None:
        destination = self.final_root / "configuration-receipt.json"
        original = b"existing bytes\n"
        destination.write_bytes(original)

        with self.assertRaisesRegex(FinalArtifactError, "different bytes"):
            write_final_artifacts(self.inputs)
        self.assertEqual(destination.read_bytes(), original)
        self.assertFalse((self.final_root / "audit-manifest.json").exists())
        self.assert_no_temporary_files()

    def test_rejects_invalid_authority_digest(self) -> None:
        with self.assertRaisesRegex(FinalArtifactError, "semantic authority digest"):
            write_final_artifacts(
                replace(self.inputs, semantic_authority_digest="not-a-digest")
            )
        self.assert_no_outputs()


if __name__ == "__main__":
    unittest.main()
