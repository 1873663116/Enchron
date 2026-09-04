#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import replace
from io import BytesIO
import json
from pathlib import Path
import shlex
import sys
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from typing import Mapping
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1]
RULES = Path(__file__).resolve().parent
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

from regression import completion
from regression.completion import (
    CompletionError,
    CompletionPaths,
    CompletionReport,
    EXPECTED_COUNTS,
    EXPECTED_OPERATION_IDS,
    PREDICATE_NAMES,
    PredicateResult,
    REQUIRED_PREPARATION_OPERATIONS,
    REQUIRED_PRODUCERS,
    REQUIRED_PRODUCT_OPERATIONS,
    artifact_record,
    validate_audit_manifest,
    validate_configuration_receipt,
    verification_log_records,
    verify_completion,
)
from regression.core.contracts import BoundLane
from regression.core.digest import (
    canonical_bytes,
    canonical_digest,
    digest_bytes,
)
from regression.core.plan import (
    BuildIdentity,
    LaneBuildArtifact,
    ToolchainIdentity,
)
from regression.materialize_catalog_v2 import materialize
import verify_regression_refactor_complete as command


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT_PATH = REPOSITORY_ROOT / "Config/regression/catalog-v2.json"
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
TOOLCHAIN_PAYLOAD = {
    "xcodeVersion": "27.0",
    "xcodeBuild": "17A5308f",
    "visionOSSDKVersion": "27.0",
    "visionOSSDKBuild": "24N5300a",
    "visionOSSimulatorSDKVersion": "27.0",
    "visionOSSimulatorSDKBuild": "24N5300a",
}


class AcceptedArtifactIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.full_run = Path(self.temporary.name).resolve() / "full-run"
        self.full_run.mkdir()
        self.lease_id = "lease:node-runtime-01"

    def _write(self, path: Path, data: bytes) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def _fixture(
        self,
        *,
        attachment_path: Path | None = None,
        attachment_bytes: bytes = b"png-bytes",
        attachment_length: int | None = None,
        attachment_digest: str | None = None,
        evidence_bytes: bytes | None = None,
    ) -> SimpleNamespace:
        attachment = attachment_path or (
            self.full_run
            / "assignments"
            / self.lease_id
            / "evidence"
            / "attachments"
            / "frame.png"
        )
        self._write(attachment, attachment_bytes)
        attachment_record = {
            "role": "visual.frame[0]",
            "mediaType": "image/png",
            "path": str(attachment.resolve()),
            "byteLength": (
                len(attachment_bytes)
                if attachment_length is None
                else attachment_length
            ),
            "digest": attachment_digest or str(digest_bytes(attachment_bytes)),
        }
        object_bytes = evidence_bytes
        if object_bytes is None:
            object_bytes = canonical_bytes(
                {
                    "schema": "enchron.regression.typed-evidence",
                    "attachments": [attachment_record],
                }
            ) + b"\n"
        object_digest = str(digest_bytes(object_bytes))
        object_relative = f"objects/sha256/{object_digest[7:]}"
        object_path = self._write(self.full_run / object_relative, object_bytes)
        receipt_value = {
            "leaseId": self.lease_id,
            "evidenceSchema": "frame-sequence@2",
            "relativePath": "evidence/obligation.json",
            "byteLength": len(object_bytes),
            "digest": object_digest,
            "objectPath": object_relative,
        }
        receipt_digest = str(canonical_digest(receipt_value))
        receipt_path = self._write(
            self.full_run
            / "receipts"
            / "artifacts"
            / f"{receipt_digest[7:]}.json",
            canonical_bytes(receipt_value) + b"\n",
        )
        artifact = SimpleNamespace(
            evidence_schema="frame-sequence@2",
            relative_path="evidence/obligation.json",
            byte_length=len(object_bytes),
            digest=object_digest,
            object_path=object_relative,
            receipt_digest=receipt_digest,
        )
        view = SimpleNamespace(
            leases=(
                SimpleNamespace(
                    lease_id=self.lease_id,
                    evidence=(artifact,),
                ),
            )
        )
        return SimpleNamespace(
            attachment_path=attachment,
            object_bytes=object_bytes,
            object_path=object_path,
            receipt_path=receipt_path,
            receipt_value=receipt_value,
            artifact=artifact,
            view=view,
        )

    def test_current_accepted_artifact_and_attachment_are_revalidated(self) -> None:
        fixture = self._fixture()

        completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_canonicalized_system_temp_ancestor_matches_stored_attachment(self) -> None:
        original_full_run = self.full_run
        try:
            with TemporaryDirectory(dir="/tmp") as temporary:
                self.full_run = Path(temporary) / "full-run"
                self.full_run.mkdir()
                fixture = self._fixture()

                completion._validate_accepted_artifacts(
                    self.full_run, fixture.view
                )
        finally:
            self.full_run = original_full_run

    def test_symlinked_full_run_ancestor_escape_fails_closed(self) -> None:
        with TemporaryDirectory() as outside_temporary:
            outside_parent = Path(outside_temporary).resolve()
            linked_parent = self.full_run.parent / "linked-run-parent"
            linked_parent.symlink_to(outside_parent, target_is_directory=True)
            self.full_run = linked_parent / "full-run"
            self.full_run.mkdir()
            fixture = self._fixture()

            with self.assertRaisesRegex(CompletionError, "symbolic link"):
                completion._validate_accepted_artifacts(
                    self.full_run, fixture.view
                )

    def test_missing_or_tampered_cas_object_fails_closed(self) -> None:
        fixture = self._fixture()
        fixture.object_path.unlink()
        with self.assertRaisesRegex(CompletionError, "CAS evidence object"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        fixture = self._fixture()
        fixture.object_path.write_bytes(b"x" * len(fixture.object_bytes))
        with self.assertRaisesRegex(CompletionError, "digest"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_cas_object_length_must_match_the_ledger(self) -> None:
        fixture = self._fixture()
        changed_artifact = SimpleNamespace(
            **{
                **vars(fixture.artifact),
                "byte_length": fixture.artifact.byte_length + 1,
            }
        )
        changed_view = SimpleNamespace(
            leases=(
                SimpleNamespace(
                    lease_id=self.lease_id,
                    evidence=(changed_artifact,),
                ),
            )
        )

        with self.assertRaisesRegex(CompletionError, "byte length"):
            completion._validate_accepted_artifacts(self.full_run, changed_view)

    def test_cas_object_symlink_and_path_escape_fail_closed(self) -> None:
        fixture = self._fixture()
        outside = self.full_run.parent / "outside-evidence.json"
        outside.write_bytes(fixture.object_bytes)
        fixture.object_path.unlink()
        fixture.object_path.symlink_to(outside)
        with self.assertRaisesRegex(CompletionError, "symbolic link"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        escaped_artifact = SimpleNamespace(
            **{**vars(fixture.artifact), "object_path": "../outside-evidence.json"}
        )
        escaped_view = SimpleNamespace(
            leases=(
                SimpleNamespace(
                    lease_id=self.lease_id,
                    evidence=(escaped_artifact,),
                ),
            )
        )
        with self.assertRaisesRegex(CompletionError, "inside FullRun"):
            completion._validate_accepted_artifacts(self.full_run, escaped_view)

    def test_receipt_must_canonically_bind_every_ledger_field(self) -> None:
        fixture = self._fixture()
        replacements = {
            "leaseId": "lease:node-other-01",
            "evidenceSchema": "frame-sequence@1",
            "relativePath": "evidence/other.json",
            "byteLength": fixture.artifact.byte_length + 1,
            "digest": "sha256:" + "0" * 64,
            "objectPath": "objects/sha256/" + "0" * 64,
        }
        for field, replacement in replacements.items():
            with self.subTest(field=field):
                changed = {**fixture.receipt_value, field: replacement}
                fixture.receipt_path.write_bytes(canonical_bytes(changed) + b"\n")
                with self.assertRaisesRegex(CompletionError, "receipt"):
                    completion._validate_accepted_artifacts(
                        self.full_run, fixture.view
                    )
                fixture.receipt_path.write_bytes(
                    canonical_bytes(fixture.receipt_value) + b"\n"
                )

        fixture.receipt_path.write_bytes(
            json.dumps(fixture.receipt_value, indent=2).encode("utf-8") + b"\n"
        )
        with self.assertRaisesRegex(CompletionError, "canonical"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_missing_or_symlinked_receipt_fails_closed(self) -> None:
        fixture = self._fixture()
        receipt_bytes = fixture.receipt_path.read_bytes()
        fixture.receipt_path.unlink()
        with self.assertRaisesRegex(CompletionError, "artifact receipt"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        outside = self.full_run.parent / "outside-receipt.json"
        outside.write_bytes(receipt_bytes)
        fixture.receipt_path.symlink_to(outside)
        with self.assertRaisesRegex(CompletionError, "symbolic link"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_cas_evidence_must_parse_as_json_with_attachments(self) -> None:
        fixture = self._fixture(evidence_bytes=b"not-json")
        with self.assertRaisesRegex(CompletionError, "valid JSON"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        noncanonical = json.dumps(
            {"schema": "enchron.regression.typed-evidence", "attachments": []},
            indent=2,
        ).encode("utf-8") + b"\n"
        fixture = self._fixture(evidence_bytes=noncanonical)
        with self.assertRaisesRegex(CompletionError, "canonical JSON"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_missing_or_tampered_attachment_fails_closed(self) -> None:
        fixture = self._fixture()
        fixture.attachment_path.unlink()
        with self.assertRaisesRegex(CompletionError, "attachment"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        fixture = self._fixture()
        fixture.attachment_path.write_bytes(b"bad-bytes")
        with self.assertRaisesRegex(CompletionError, "attachment.*digest"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_attachment_path_escape_and_symlink_fail_closed(self) -> None:
        outside = self.full_run.parent / "outside-frame.png"
        fixture = self._fixture(attachment_path=outside)
        with self.assertRaisesRegex(CompletionError, "attachment.*directory"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        fixture = self._fixture()
        outside.write_bytes(fixture.attachment_path.read_bytes())
        fixture.attachment_path.unlink()
        fixture.attachment_path.symlink_to(outside)
        with self.assertRaisesRegex(CompletionError, "symbolic link"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_symlinked_object_and_attachment_parent_directories_fail_closed(
        self,
    ) -> None:
        fixture = self._fixture()
        attachment_directory = fixture.attachment_path.parent
        outside_attachments = self.full_run.parent / "outside-attachments"
        outside_attachment = outside_attachments / fixture.attachment_path.name
        self._write(outside_attachment, fixture.attachment_path.read_bytes())
        fixture.attachment_path.unlink()
        attachment_directory.rmdir()
        attachment_directory.symlink_to(
            outside_attachments, target_is_directory=True
        )
        with self.assertRaisesRegex(CompletionError, "symbolic link"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        attachment_directory.unlink()
        self._write(fixture.attachment_path, outside_attachment.read_bytes())
        object_directory = fixture.object_path.parent
        outside_objects = self.full_run.parent / "outside-objects"
        outside_object = outside_objects / fixture.object_path.name
        self._write(outside_object, fixture.object_bytes)
        fixture.object_path.unlink()
        object_directory.rmdir()
        object_directory.symlink_to(outside_objects, target_is_directory=True)
        with self.assertRaisesRegex(CompletionError, "symbolic link"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_attachment_length_and_digest_must_match_evidence_json(self) -> None:
        fixture = self._fixture(attachment_length=999)
        with self.assertRaisesRegex(CompletionError, "attachment.*length"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

        fixture = self._fixture(attachment_digest="sha256:" + "0" * 64)
        with self.assertRaisesRegex(CompletionError, "attachment.*digest"):
            completion._validate_accepted_artifacts(self.full_run, fixture.view)

    def test_full_run_loading_propagates_integrity_failure(self) -> None:
        summary = {
            "schema": "enchron.regression.full-run-summary",
            "schemaVersion": 1,
            "catalogDigest": "sha256:" + "1" * 64,
            "catalogGateDigest": "sha256:" + "2" * 64,
            "buildIdentityDigest": "sha256:" + "3" * 64,
            "evidenceEnvironmentDigest": "sha256:" + "4" * 64,
            "completedByLane": {"simulator": 1, "device": 1},
            "executionErrors": [],
            "run": {},
        }
        self._write(
            self.full_run / "summary.json", canonical_bytes(summary) + b"\n"
        )
        plan = SimpleNamespace(
            catalog_digest=summary["catalogDigest"],
            catalog_gate_digest=summary["catalogGateDigest"],
            build_identity=SimpleNamespace(digest=summary["buildIdentityDigest"]),
            evidence_environment_identity=SimpleNamespace(
                digest=summary["evidenceEnvironmentDigest"]
            ),
            plan_digest="sha256:" + "5" * 64,
        )
        view = SimpleNamespace(plan_digest=plan.plan_digest)
        context = completion._CompletionContext(
            SimpleNamespace(full_run_directory=self.full_run)
        )
        context.plan = lambda: SimpleNamespace(plan=plan)

        with (
            patch.object(completion, "replay", return_value=view),
            patch.object(completion, "_view_payload", return_value={}),
            patch.object(
                completion,
                "_validate_accepted_artifacts",
                side_effect=CompletionError("artifact integrity failure"),
            ) as validate,
            self.assertRaisesRegex(CompletionError, "artifact integrity failure"),
        ):
            context.run()
        validate.assert_called_once_with(self.full_run, view)


class FinalBuildIdentityCompletionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        self.final_root = self.repository / "final"
        self.final_root.mkdir()

    def _identity(
        self,
        *,
        source_digest: str = SOURCE_DIGEST,
        toolchain_build: str = "17A5308f",
        simulator_xctestrun_digest: str = "sha256:" + "6" * 64,
    ) -> BuildIdentity:
        toolchain = ToolchainIdentity(
            xcode_version="27.0",
            xcode_build=toolchain_build,
            visionos_sdk_version="27.0",
            visionos_sdk_build="24N5300a",
            visionos_simulator_sdk_version="27.0",
            visionos_simulator_sdk_build="24N5300a",
        )
        artifacts = (
            LaneBuildArtifact(
                lane=BoundLane.SIMULATOR,
                xctestrun_digest=simulator_xctestrun_digest,
                test_products_digest="sha256:" + "7" * 64,
                application_code_digest="sha256:" + "8" * 64,
            ),
            LaneBuildArtifact(
                lane=BoundLane.DEVICE,
                xctestrun_digest="sha256:" + "9" * 64,
                test_products_digest="sha256:" + "a" * 64,
                application_code_digest="sha256:" + "b" * 64,
            ),
        )
        return BuildIdentity(
            bundle_identifier="com.example.Enchron",
            git_revision="abc123",
            source_tree_digest=source_digest,
            configuration_digest="sha256:" + "c" * 64,
            toolchain=toolchain,
            lane_artifacts=artifacts,
        )

    def _context(
        self,
        *,
        execution_identity: BuildIdentity,
        plan_identity: BuildIdentity | None = None,
        nodes: tuple[SimpleNamespace, ...] | None = None,
        main_gates: tuple[SimpleNamespace, ...] | None = None,
        source_digest: str = SOURCE_DIGEST,
    ) -> SimpleNamespace:
        identity = plan_identity or execution_identity
        environment = SimpleNamespace(digest="sha256:" + "d" * 64)
        if nodes is None:
            nodes = (
                SimpleNamespace(
                    id="node:main-gate-simulator",
                    build_identity=identity,
                ),
                SimpleNamespace(
                    id="node:main-gate-device",
                    build_identity=identity,
                ),
                SimpleNamespace(
                    id="node:full-run",
                    build_identity=identity,
                ),
            )
        if main_gates is None:
            main_gates = (
                SimpleNamespace(
                    lane=BoundLane.SIMULATOR,
                    node_id="node:main-gate-simulator",
                ),
                SimpleNamespace(
                    lane=BoundLane.DEVICE,
                    node_id="node:main-gate-device",
                ),
            )
        execution = SimpleNamespace(
            build_identity=execution_identity,
            evidence_environment_identity=environment,
        )
        plan = SimpleNamespace(
            build_identity=identity,
            evidence_environment_identity=environment,
            nodes=nodes,
            main_gates=main_gates,
        )
        run = SimpleNamespace(
            summary={"buildIdentityDigest": str(execution_identity.digest)}
        )
        return SimpleNamespace(
            plan=lambda: SimpleNamespace(plan=plan, execution=execution),
            run=lambda: run,
            source_digest=lambda: source_digest,
        )

    def test_execution_input_bytes_cannot_drift_while_the_loader_revalidates(
        self,
    ) -> None:
        execution_path = self.final_root / "execution-input.json"
        execution_path.write_bytes(b"first\n")
        configuration_path = self.final_root / "configuration-receipt.json"
        configuration_path.write_bytes(b"configuration\n")
        paths = SimpleNamespace(
            repository_root=self.repository,
            final_root=self.final_root,
            execution_input_path=execution_path,
        )
        context = completion._CompletionContext(paths)
        context.configuration = lambda: SimpleNamespace(
            receipt_path=configuration_path
        )
        execution = SimpleNamespace(
            configuration_receipt=configuration_path,
            artifact_root=self.final_root,
            bootstrap=False,
        )

        with (
            patch.object(
                completion,
                "_read_boundary_path",
                side_effect=(
                    (execution_path, b"first\n"),
                    (execution_path, b"changed\n"),
                ),
            ),
            patch.object(
                completion,
                "load_execution_input",
                return_value=execution,
            ) as load,
            self.assertRaisesRegex(
                CompletionError,
                "execution input changed during schema-v2 revalidation",
            ),
        ):
            context.execution()
        load.assert_called_once_with(execution_path)

    def test_plan_rejects_source_toolchain_and_lane_artifact_identity_drift(
        self,
    ) -> None:
        frozen = self._identity()
        drifts = (
            (
                "source tree",
                self._identity(source_digest="sha256:" + "e" * 64),
            ),
            ("toolchain", self._identity(toolchain_build="17A9999z")),
            (
                "lane artifacts",
                self._identity(
                    simulator_xctestrun_digest="sha256:" + "f" * 64
                ),
            ),
        )
        for detail, changed in drifts:
            with self.subTest(detail=detail):
                context = self._context(
                    execution_identity=frozen,
                    plan_identity=changed,
                )
                with self.assertRaisesRegex(CompletionError, detail):
                    completion._immutable_run(context)

    def test_current_source_must_still_match_the_frozen_identity(self) -> None:
        frozen = self._identity()
        context = self._context(
            execution_identity=frozen,
            source_digest="sha256:" + "e" * 64,
        )

        with self.assertRaisesRegex(CompletionError, "current source"):
            completion._immutable_run(context)

    def test_main_gate_and_full_run_evidence_keep_the_frozen_identity(
        self,
    ) -> None:
        frozen = self._identity()
        lane_drift = self._identity(
            simulator_xctestrun_digest="sha256:" + "f" * 64
        )
        toolchain_drift = self._identity(toolchain_build="17A9999z")
        nodes = (
            SimpleNamespace(
                id="node:main-gate-simulator",
                build_identity=lane_drift,
            ),
            SimpleNamespace(
                id="node:main-gate-device",
                build_identity=frozen,
            ),
            SimpleNamespace(
                id="node:full-run",
                build_identity=frozen,
            ),
        )
        context = self._context(execution_identity=frozen, nodes=nodes)
        with self.assertRaisesRegex(
            CompletionError, "simulator MainGate evidence lane artifacts"
        ):
            completion._immutable_run(context)

        nodes = (
            SimpleNamespace(
                id="node:main-gate-simulator",
                build_identity=frozen,
            ),
            SimpleNamespace(
                id="node:main-gate-device",
                build_identity=frozen,
            ),
            SimpleNamespace(
                id="node:full-run",
                build_identity=toolchain_drift,
            ),
        )
        context = self._context(execution_identity=frozen, nodes=nodes)
        with self.assertRaisesRegex(
            CompletionError, "FullRun evidence node node:full-run toolchain"
        ):
            completion._immutable_run(context)

    def test_main_gate_launch_rejects_frozen_lane_artifact_drift(self) -> None:
        frozen = self._identity()
        execution_input_path = self.final_root / "execution-input.json"
        targets = {
            BoundLane.SIMULATOR: "SIMULATOR-UDID",
            BoundLane.DEVICE: "DEVICE-UDID",
        }
        artifacts = {item.lane: item for item in frozen.lane_artifacts}
        gates = (
            SimpleNamespace(
                lane=BoundLane.SIMULATOR,
                node_id="node:main-gate-simulator",
            ),
            SimpleNamespace(
                lane=BoundLane.DEVICE,
                node_id="node:main-gate-device",
            ),
        )

        def launch(lane: BoundLane) -> SimpleNamespace:
            return SimpleNamespace(
                lane=lane,
                target_id=targets[lane],
                xctestrun_path=self.final_root / f"{lane.value}.xctestrun",
                destination_specifier=(
                    f"platform=visionOS Simulator,id={targets[lane]}"
                    if lane is BoundLane.SIMULATOR
                    else f"platform=visionOS,id={targets[lane]}"
                ),
                lane_artifact=artifacts[lane],
            )

        launches = {lane: launch(lane) for lane in targets}

        def provenance(lane: BoundLane) -> dict[str, object]:
            selected = launches[lane]
            artifact = artifacts[lane]
            return {
                "executionInputPath": str(execution_input_path),
                "lane": lane.value,
                "targetId": targets[lane],
                "xctestrunPath": str(selected.xctestrun_path),
                "destinationSpecifier": selected.destination_specifier,
                "xctestrunDigest": str(artifact.xctestrun_digest),
                "testProductsDigest": str(artifact.test_products_digest),
                "applicationCodeDigest": str(artifact.application_code_digest),
                "processId": 123,
            }

        simulator_provenance = provenance(BoundLane.SIMULATOR)
        simulator_provenance["xctestrunDigest"] = "sha256:" + "0" * 64

        def lease(lane: BoundLane, value: Mapping[str, object]) -> SimpleNamespace:
            outputs = SimpleNamespace(
                payload=lambda: {
                    "succeeded": True,
                    "session": {"launchProvenance": dict(value)},
                }
            )
            invocation = SimpleNamespace(
                operation="operation:harness.ensure-session@1",
                completed=True,
                succeeded=True,
                outputs=outputs,
            )
            return SimpleNamespace(
                node_id=f"node:main-gate-{lane.value}",
                envelope_status="accepted",
                evidence=(SimpleNamespace(),),
                invocations=(invocation,),
            )

        view = SimpleNamespace(
            leases=(
                lease(BoundLane.SIMULATOR, simulator_provenance),
                lease(BoundLane.DEVICE, provenance(BoundLane.DEVICE)),
            )
        )
        execution = SimpleNamespace(
            build_identity=frozen,
            lane_targets=targets,
        )
        plan = SimpleNamespace(main_gates=gates)

        with (
            patch.object(
                completion,
                "load_frozen_test_launch",
                side_effect=lambda _path, lane, _target: launches[lane],
            ),
            self.assertRaisesRegex(
                CompletionError,
                "simulator MainGate launch xctestrunDigest differs",
            ),
        ):
            completion._validate_main_gate_launch_provenance(
                execution,
                plan,
                view,
                execution_input_path,
            )

    def test_product_build_proof_must_match_frozen_toolchain_launch_and_lane_artifacts(self) -> None:
        identity = self._identity()
        artifacts = {item.lane: item for item in identity.lane_artifacts}
        destinations = {
            BoundLane.SIMULATOR: "platform=visionOS Simulator,id=SIMULATOR-UDID",
            BoundLane.DEVICE: "platform=visionOS,id=DEVICE-UDID",
        }
        launches = tuple(
            SimpleNamespace(
                lane=lane,
                destination_specifier=destinations[lane],
                xctestrun_path=self.final_root / f"{lane.value}.xctestrun",
            )
            for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
        )
        proofs = {
            lane.value: completion.BuildResultProof(
                self.final_root / f"{lane.value}-result.json",
                lane,
                SOURCE_DIGEST,
                ("xcodebuild", "build-for-testing"),
                destinations[lane],
                DEVELOPER_DIRECTORY,
                identity.toolchain,
                self.final_root / f"{lane.value}.xctestrun",
                artifacts[lane],
                self.final_root / f"{lane.value}.log",
            )
            for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
        }

        def context(build_results: Mapping[str, object]) -> SimpleNamespace:
            return SimpleNamespace(
                configuration=lambda: SimpleNamespace(build_results=build_results),
                execution=lambda: SimpleNamespace(
                    build_identity=identity,
                    launches=launches,
                ),
            )

        completion._product_builds(context(proofs))
        simulator = proofs["simulator"]
        changed_toolchain = ToolchainIdentity(
            **{
                **vars(identity.toolchain),
                "xcode_build": "17A9999z",
            }
        )
        mutations = (
            ("toolchain", replace(simulator, toolchain=changed_toolchain), "toolchain"),
            (
                "destination",
                replace(
                    simulator,
                    destination="platform=visionOS Simulator,id=OTHER",
                ),
                "destination",
            ),
            (
                "xctestrun",
                replace(simulator, xctestrun_path=self.final_root / "other.xctestrun"),
                "xctestrun",
            ),
            (
                "lane-artifact",
                replace(
                    simulator,
                    lane_artifact=LaneBuildArtifact(
                        BoundLane.SIMULATOR,
                        "sha256:" + "0" * 64,
                        str(artifacts[BoundLane.SIMULATOR].test_products_digest),
                        str(artifacts[BoundLane.SIMULATOR].application_code_digest),
                    ),
                ),
                "lane artifacts",
            ),
        )
        for name, mutation, expected in mutations:
            with self.subTest(name=name), self.assertRaisesRegex(
                CompletionError, expected
            ):
                completion._product_builds(
                    context({**proofs, "simulator": mutation})
                )


class CompletionVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        self.final_root = self.repository / "final"
        self.final_root.mkdir()

    def write_bytes(self, relative: str, source: bytes) -> Path:
        path = self.final_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(source)
        return path

    def write_json(self, relative: str, payload: object) -> Path:
        return self.write_bytes(relative, canonical_bytes(payload) + b"\n")

    def passing_verification_summary(self) -> dict[str, object]:
        return {
            "version": 1,
            "startedAt": "2026-08-29T00:00:00+00:00",
            "finishedAt": "2026-08-29T00:10:00+00:00",
            "mode": "full",
            "repository": str(self.repository),
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
                {
                    "name": "PlaybackCore tests",
                    "state": "PASS",
                    "detail": "passed",
                    "logs": [],
                },
                {
                    "name": "Guard self-tests",
                    "state": "PASS",
                    "detail": "passed",
                    "logs": [],
                },
                {
                    "name": "Domain tests",
                    "state": "PASS",
                    "detail": "passed",
                    "logs": ["domain-tests.log"],
                },
                {
                    "name": "Git hook installation",
                    "state": "PASS",
                    "detail": "passed",
                    "logs": [],
                },
                {
                    "name": "Source parity",
                    "state": "PASS",
                    "detail": "passed",
                    "logs": [],
                },
                {
                    "name": "Media discovery capability matrix",
                    "state": "PASS",
                    "detail": "passed",
                    "logs": [],
                },
                {
                    "name": "Feature evidence coverage",
                    "state": "PASS",
                    "detail": "passed",
                    "logs": [],
                },
            ],
            "verdict": "passed",
        }

    def receipt_range(self) -> dict[str, str]:
        return {
            "expression": "base..HEAD",
            "baseCommit": BASE_COMMIT,
            "headCommit": HEAD_COMMIT,
            "diffSha256": DIFF_DIGEST,
        }

    def audit_result(self, name: str, *, source_digest: str) -> Path:
        return self.write_json(
            f"audits/{name}.json",
            {
                "schema": "enchron.regression.audit-result",
                "schemaVersion": 1,
                "audit": name,
                "sourceDigest": source_digest,
                "verdict": "passed",
            },
        )

    def write_verification_logs(self) -> None:
        summary = self.passing_verification_summary()
        for layer in summary["layers"]:
            for log in layer["logs"]:
                source = (
                    b"$ python3 focused.py\nMediaFormatInterpreterTests passed\n"
                    if log == "domain-tests.log"
                    else f"$ python3 {log}\npassed\n".encode()
                )
                self.write_bytes(log, source)

    def build_result(
        self,
        lane: str,
        target: str,
        products_fill: str,
        code_fill: str,
    ) -> Path:
        derived_data = self.final_root / "lanes" / lane / "DerivedData"
        xctestrun = self.write_bytes(
            (
                derived_data
                / "Build/Products"
                / f"Enchron-{lane}.xctestrun"
            ).relative_to(self.final_root).as_posix(),
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
            str(self.repository / "Enchron.xcodeproj"),
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
        return self.write_json(
            f"build/{lane}-result.json",
            {
                "schema": "enchron.regression.xcode-build-result",
                "schemaVersion": 1,
                "lane": lane,
                "sourceDigest": SOURCE_DIGEST,
                "command": command,
                "destination": destination,
                "developerDirectory": DEVELOPER_DIRECTORY,
                "toolchain": TOOLCHAIN_PAYLOAD,
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

    def prepare_audit_manifest(self, *, source_digest: str = SOURCE_DIGEST) -> Path:
        verification = self.write_json(
            "verification-summary.json", self.passing_verification_summary()
        )
        self.write_verification_logs()
        evidence = {}
        for name in ("no-comments", "interrogate", "blast-radius", "vp-e2e"):
            path = self.audit_result(name, source_digest=source_digest)
            evidence[name] = artifact_record(path, self.final_root)
        write_set = self.write_json(
            "actual-write-set.json",
            {
                "schema": "enchron.regression.actual-write-set-receipt",
                "schemaVersion": 1,
                "sourceDigest": source_digest,
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
        coverage = self.write_json(
            "product-swift-coverage.json",
            {
                "schema": "enchron.regression.product-swift-coverage",
                "schemaVersion": 1,
                "sourceDigest": source_digest,
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
        return self.write_json(
            "audit-manifest.json",
            {
                "schema": "enchron.regression.final-audit-manifest",
                "schemaVersion": 2,
                "sourceDigest": source_digest,
                "preFreezeVerification": artifact_record(
                    verification, self.final_root
                ),
                "verificationLogs": list(
                    verification_log_records(verification, self.final_root)
                ),
                "evidence": evidence,
                "writeSetReceipt": artifact_record(write_set, self.final_root),
                "productSwiftCoverage": artifact_record(
                    coverage, self.final_root
                ),
            },
        )

    def prepare_configuration_receipt(
        self,
    ) -> tuple[Path, object, Path, Path]:
        manifest = self.prepare_audit_manifest()
        audit = validate_audit_manifest(manifest, self.final_root, SOURCE_DIGEST)
        merge_receipt = self.write_json(
            "merge-run-receipt.json", {"fixture": True}
        )
        simulator_result = self.build_result(
            "simulator", "SIMULATOR-UDID", "7", "8"
        )
        device_result = self.build_result("device", "DEVICE-UDID", "a", "b")
        receipt = self.write_json(
            "configuration-receipt.json",
            {
                "schema": "enchron.regression.configuration-receipt",
                "schemaVersion": 1,
                "sourceDigest": SOURCE_DIGEST,
                "blueprintDigest": BLUEPRINT_DIGEST,
                "catalogDigest": CATALOG_DIGEST,
                "reviewCompletionDigest": REVIEW_DIGEST,
                "semanticAuthorityDigest": SEMANTIC_DIGEST,
                "preFreezeVerification": audit.verification_record,
                "mergeRunReceipt": artifact_record(
                    merge_receipt, self.final_root
                ),
                "buildLogs": {
                    "simulator": artifact_record(
                        simulator_result, self.final_root
                    ),
                    "device": artifact_record(device_result, self.final_root),
                },
            },
        )
        return receipt, audit, simulator_result, device_result

    def validate_configuration(self, receipt: Path, audit: object) -> object:
        return validate_configuration_receipt(
            receipt,
            self.final_root,
            expected_source_digest=SOURCE_DIGEST,
            expected_blueprint_digest=BLUEPRINT_DIGEST,
            expected_catalog_digest=CATALOG_DIGEST,
            expected_review_digest=REVIEW_DIGEST,
            expected_semantic_authority_digest=SEMANTIC_DIGEST,
            expected_verification_record=audit.verification_record,
            expected_developer_directory=DEVELOPER_DIRECTORY,
        )

    def test_symlinked_final_root_ancestor_escape_fails_closed(self) -> None:
        with TemporaryDirectory() as outside_temporary:
            outside_root = Path(outside_temporary).resolve()
            escaped_final_root = outside_root / "final"
            escaped_final_root.mkdir()
            source = escaped_final_root / "audit.txt"
            source.write_bytes(b"outside\n")
            linked_parent = self.repository / "linked-final-parent"
            linked_parent.symlink_to(outside_root, target_is_directory=True)
            record = {
                "path": "audit.txt",
                "sha256": str(digest_bytes(source.read_bytes())),
            }

            with self.assertRaisesRegex(CompletionError, "symbolic link"):
                completion._resolve_artifact(
                    record,
                    linked_parent / "final",
                    "escaped final artifact",
                )

    def test_completion_paths_do_not_resolve_away_final_root_symlinks(
        self,
    ) -> None:
        real_parent = self.repository / "real-final-parent"
        real_final_root = real_parent / "final"
        real_final_root.mkdir(parents=True)
        source = real_final_root / "audit.txt"
        source.write_bytes(b"inside\n")
        linked_parent = self.repository / "linked-final-parent"
        linked_parent.symlink_to(real_parent, target_is_directory=True)
        paths = CompletionPaths.for_tests(
            self.repository, linked_parent / "final"
        )
        record = {
            "path": "audit.txt",
            "sha256": str(digest_bytes(source.read_bytes())),
        }

        with self.assertRaisesRegex(CompletionError, "symbolic link"):
            completion._resolve_artifact(
                record,
                paths.final_root,
                "linked final artifact",
            )

    @staticmethod
    def _retired_journey_root() -> str:
        return next(
            relative
            for relative in completion.RETIRED_PATHS
            if relative.endswith("/journeys")
        )

    def _retired_surface_repository(self) -> Path:
        repository = self.repository / "retired-surface"
        registry = repository / "Config/retired_documents.json"
        registry.parent.mkdir(parents=True, exist_ok=True)
        registry.write_text(
            json.dumps(
                {
                    "retired": [
                        {
                            "path": self._retired_journey_root() + "/",
                            "replacement": "Regression/journeys/",
                        }
                    ]
                }
            )
            + "\n",
            encoding="utf-8",
        )
        skill = repository / self._retired_journey_root()
        skill = skill.parent / "device-reserve.md"
        skill.parent.mkdir(parents=True, exist_ok=True)
        skill.write_text("# 真机保留\n", encoding="utf-8")
        return repository

    def _retired_surface_verdict(self, repository: Path) -> str:
        context = SimpleNamespace(
            paths=SimpleNamespace(repository_root=repository)
        )
        return completion._retired_surfaces(context)

    def test_retired_surface_guard_passes_when_no_active_document_names_one(
        self,
    ) -> None:
        repository = self._retired_surface_repository()

        self.assertIn("absent from active paths", self._retired_surface_verdict(repository))

    def test_retired_surface_guard_rejects_an_active_document_naming_one(self) -> None:
        repository = self._retired_surface_repository()
        skill = (repository / self._retired_journey_root()).parent / "device-reserve.md"
        skill.write_text(
            f"见 {self._retired_journey_root()}/index.md。\n",
            encoding="utf-8",
        )

        with self.assertRaisesRegex(
            CompletionError, "still reference retired legacy surfaces"
        ):
            self._retired_surface_verdict(repository)

    def test_retired_surface_guard_rejects_a_resurrected_retired_path(self) -> None:
        repository = self._retired_surface_repository()
        resurrected = repository / self._retired_journey_root() / "J13.md"
        resurrected.parent.mkdir(parents=True, exist_ok=True)
        resurrected.write_text("# J13\n", encoding="utf-8")

        with self.assertRaisesRegex(CompletionError, "retired legacy path"):
            self._retired_surface_verdict(repository)

    def test_retired_surface_guard_rejects_an_unregistered_journey_retirement(
        self,
    ) -> None:
        repository = self._retired_surface_repository()
        registry = repository / "Config/retired_documents.json"
        registry.write_text(json.dumps({"retired": []}) + "\n", encoding="utf-8")

        with self.assertRaisesRegex(CompletionError, "not recorded in retired"):
            self._retired_surface_verdict(repository)

    def test_predicate_population_is_the_exact_definition_of_done(self) -> None:
        self.assertEqual(
            PREDICATE_NAMES,
            (
                "catalog_target_shape",
                "no_legacy_active_contracts",
                "autonomous_semantic_authority",
                "executable_operations_and_oracles",
                "current_review_receipts",
                "governance_guardrails",
                "target_source_topology",
                "retired_legacy_surfaces",
                "comment_boundary",
                "deterministic_checks_green",
                "product_builds_green",
                "both_runtime_lanes_proven",
                "immutable_final_full_run",
                "no_unverified_product_diff",
            ),
        )

    def test_completion_shape_pins_final_subtitle_operations(self) -> None:
        self.assertEqual(EXPECTED_COUNTS["operations"], 35)
        self.assertEqual(EXPECTED_COUNTS["preparations"], 18)
        self.assertEqual(len(EXPECTED_OPERATION_IDS), 35)
        self.assertIn(
            "operation:playback.select-subtitle@1", REQUIRED_PRODUCT_OPERATIONS
        )
        self.assertEqual(
            REQUIRED_PREPARATION_OPERATIONS,
            {
                "operation:preparation.local-directory-subtitle-source@1": (
                    (
                        ("directoryName", "string", True),
                        ("mediaFileName", "string", True),
                        ("memberFileNames", "string-list", True),
                    ),
                    ("library.command", "library-command@1"),
                )
            },
        )
        self.assertNotIn(
            "operation:diagnostics.emby-range-log@1", EXPECTED_OPERATION_IDS
        )
        self.assertNotIn(
            "operation:diagnostics.emby-range-log@1", REQUIRED_PRODUCERS
        )

    def test_completion_keeps_two_of_three_quorums_forbidden(self) -> None:
        self.assertTrue(
            completion._contains_two_of_three(
                {"atLeast": {"count": 2, "of": ["a", "b", "c"]}}
            )
        )
        self.assertFalse(
            completion._contains_two_of_three(
                {"all": ["a", "b", "c"]}
            )
        )

    def test_missing_artifacts_fail_closed_with_every_result_present(self) -> None:
        paths = CompletionPaths.for_tests(self.repository, self.final_root)
        report = verify_completion(paths)

        self.assertFalse(report.done)
        self.assertEqual(tuple(item.name for item in report.predicates), PREDICATE_NAMES)
        self.assertEqual(len(report.predicates), 14)
        self.assertTrue(all(not item.passed for item in report.predicates))
        self.assertTrue(all(item.detail for item in report.predicates))

    def test_completion_report_rejects_an_incomplete_predicate_population(self) -> None:
        with self.assertRaisesRegex(CompletionError, "exact DoD predicates"):
            CompletionReport(
                tuple(
                    PredicateResult(name, False, "missing")
                    for name in PREDICATE_NAMES[:-1]
                )
            )

    def test_catalog_predicate_ignores_but_does_not_trust_review_outputs(self) -> None:
        blueprint = self.repository / "Config/regression/catalog-v2.json"
        blueprint.parent.mkdir(parents=True)
        blueprint.write_bytes(BLUEPRINT_PATH.read_bytes())
        catalog = self.repository / "Regression"
        materialize(
            BLUEPRINT_PATH,
            catalog,
            self.repository / "materialization-report.json",
            None,
        )
        reviews = catalog / "reviews"
        for relative in (
            "deterministic/receipt.json",
            "agent-operability/receipt.json",
            "reports/report.md",
        ):
            destination = reviews / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text("opaque runtime review output\n", encoding="utf-8")

        paths = CompletionPaths.for_tests(self.repository, self.final_root)
        self.assertEqual(paths.reviews_root, catalog / "reviews")
        report = verify_completion(paths)
        predicates = {item.name: item for item in report.predicates}
        self.assertTrue(predicates["catalog_target_shape"].passed)
        self.assertFalse(predicates["current_review_receipts"].passed)

    def test_audit_manifest_rejects_stale_source_and_tampered_evidence(self) -> None:
        stale = self.prepare_audit_manifest(source_digest="sha256:" + "0" * 64)
        with self.assertRaisesRegex(CompletionError, "source digest"):
            validate_audit_manifest(stale, self.final_root, SOURCE_DIGEST)

        current = self.prepare_audit_manifest()
        (self.final_root / "audits/vp-e2e.json").write_text(
            "changed\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(CompletionError, "digest"):
            validate_audit_manifest(current, self.final_root, SOURCE_DIGEST)

    def test_audit_manifest_opens_and_digest_checks_every_named_log(self) -> None:
        manifest = self.prepare_audit_manifest()
        missing = self.final_root / "structure/package-membership.log"
        missing.unlink()
        with self.assertRaisesRegex(CompletionError, "verification log"):
            validate_audit_manifest(manifest, self.final_root, SOURCE_DIGEST)

        manifest = self.prepare_audit_manifest()
        log = self.final_root / "domain-tests.log"
        log.write_bytes(b"$ python3 focused.py\nforged passed\n")
        with self.assertRaisesRegex(CompletionError, "digest"):
            validate_audit_manifest(manifest, self.final_root, SOURCE_DIGEST)

    def test_audit_results_are_typed_and_source_identified(self) -> None:
        manifest = self.prepare_audit_manifest()
        evidence_path = self.final_root / "audits/interrogate.json"
        evidence = json.loads(evidence_path.read_bytes())
        evidence["audit"] = "no-comments"
        self.write_json("audits/interrogate.json", evidence)
        payload = json.loads(manifest.read_bytes())
        payload["evidence"]["interrogate"] = artifact_record(
            evidence_path, self.final_root
        )
        self.write_json("audit-manifest.json", payload)
        with self.assertRaisesRegex(CompletionError, "wrong audit type"):
            validate_audit_manifest(manifest, self.final_root, SOURCE_DIGEST)

        manifest = self.prepare_audit_manifest()
        evidence_path = self.final_root / "audits/vp-e2e.json"
        evidence = json.loads(evidence_path.read_bytes())
        evidence["sourceDigest"] = "sha256:" + "0" * 64
        self.write_json("audits/vp-e2e.json", evidence)
        payload = json.loads(manifest.read_bytes())
        payload["evidence"]["vp-e2e"] = artifact_record(
            evidence_path, self.final_root
        )
        self.write_json("audit-manifest.json", payload)
        with self.assertRaisesRegex(CompletionError, "source digest is stale"):
            validate_audit_manifest(manifest, self.final_root, SOURCE_DIGEST)

    def test_audit_schema_rejects_signature_fields(self) -> None:
        manifest = self.prepare_audit_manifest()
        evidence_path = self.final_root / "audits/no-comments.json"
        evidence = json.loads(evidence_path.read_bytes())
        evidence["signature"] = "not-part-of-the-contract"
        self.write_json("audits/no-comments.json", evidence)
        payload = json.loads(manifest.read_bytes())
        payload["evidence"]["no-comments"] = artifact_record(
            evidence_path, self.final_root
        )
        self.write_json("audit-manifest.json", payload)
        with self.assertRaisesRegex(CompletionError, "unknown field.*signature"):
            validate_audit_manifest(manifest, self.final_root, SOURCE_DIGEST)

    def test_write_set_and_product_coverage_receipts_reject_stale_source(self) -> None:
        for field, relative in (
            ("writeSetReceipt", "actual-write-set.json"),
            ("productSwiftCoverage", "product-swift-coverage.json"),
        ):
            with self.subTest(field=field):
                manifest = self.prepare_audit_manifest()
                receipt_path = self.final_root / relative
                receipt = json.loads(receipt_path.read_bytes())
                receipt["sourceDigest"] = "sha256:" + "0" * 64
                self.write_json(relative, receipt)
                payload = json.loads(manifest.read_bytes())
                payload[field] = artifact_record(receipt_path, self.final_root)
                self.write_json("audit-manifest.json", payload)
                with self.assertRaisesRegex(CompletionError, "source digest is stale"):
                    validate_audit_manifest(
                        manifest, self.final_root, SOURCE_DIGEST
                    )

    def test_actual_write_set_must_equal_the_merge_diff(self) -> None:
        audit = validate_audit_manifest(
            self.prepare_audit_manifest(), self.final_root, SOURCE_DIGEST
        )
        merge_receipt = {
            "range": self.receipt_range(),
            "classifications": [
                {"path": PRODUCT_PATH, "tier": "W3", "rule": "Modules/Playback/"},
                {"path": "Scripts/rules/check.py", "tier": "W1", "rule": "Scripts/"},
            ],
        }
        with self.assertRaisesRegex(CompletionError, "missing=.*check.py"):
            completion._validate_actual_write_set(audit.write_set, merge_receipt)

    def test_product_swift_population_rejects_missing_and_extra_files(self) -> None:
        audit = validate_audit_manifest(
            self.prepare_audit_manifest(), self.final_root, SOURCE_DIGEST
        )
        missing = {
            "range": self.receipt_range(),
            "classifications": [
                {
                    "path": "Apps/Enchron/New.swift",
                    "tier": "W3",
                    "rule": "Apps/Enchron/",
                },
                {"path": PRODUCT_PATH, "tier": "W3", "rule": "Modules/Playback/"},
            ],
        }
        with self.assertRaisesRegex(CompletionError, "missing=.*New.swift"):
            completion._validate_product_swift_population(
                audit.product_swift_coverage, missing
            )

        no_product = {
            "range": self.receipt_range(),
            "classifications": [
                {"path": "Scripts/rules/check.py", "tier": "W1", "rule": "Scripts/"}
            ],
        }
        with self.assertRaisesRegex(CompletionError, "extra=.*MediaFormatInterpreter"):
            completion._validate_product_swift_population(
                audit.product_swift_coverage, no_product
            )

    def test_product_runtime_observation_must_exist_in_accepted_full_run_evidence(self) -> None:
        audit = validate_audit_manifest(
            self.prepare_audit_manifest(), self.final_root, SOURCE_DIGEST
        )
        view = SimpleNamespace(
            nodes=(
                SimpleNamespace(node_id="node:format", status=completion.NodeStatus.PASSED),
            ),
            leases=(
                SimpleNamespace(
                    node_id="node:format",
                    envelope_status="accepted",
                    evidence=(SimpleNamespace(digest="sha256:" + "0" * 64),),
                ),
            ),
        )
        with self.assertRaisesRegex(CompletionError, "absent from accepted"):
            completion._validate_product_runtime_observations(
                audit.product_swift_coverage, view
            )

    def test_build_result_rejects_marker_only_log_and_destination_forgery(self) -> None:
        for mutation, expected in (("log", "exact command"), ("destination", "destination differs")):
            with self.subTest(mutation=mutation):
                receipt, audit, simulator_result, _ = self.prepare_configuration_receipt()
                result = json.loads(simulator_result.read_bytes())
                if mutation == "log":
                    log = self.final_root / result["log"]["path"]
                    log.write_bytes(b"** BUILD SUCCEEDED **\n")
                    result["log"] = artifact_record(log, self.final_root)
                else:
                    result["destination"] = "platform=visionOS Simulator,id=FORGED"
                self.write_json(
                    simulator_result.relative_to(self.final_root).as_posix(), result
                )
                receipt_payload = json.loads(receipt.read_bytes())
                receipt_payload["buildLogs"]["simulator"] = artifact_record(
                    simulator_result, self.final_root
                )
                self.write_json("configuration-receipt.json", receipt_payload)
                with self.assertRaisesRegex(CompletionError, expected):
                    self.validate_configuration(receipt, audit)

    def test_pure_manifest_and_configuration_validators_accept_bound_artifacts(self) -> None:
        receipt, audit, _, _ = self.prepare_configuration_receipt()
        configuration = self.validate_configuration(receipt, audit)
        self.assertEqual(configuration.source_digest, SOURCE_DIGEST)

    def test_json_output_and_exit_status_are_exact(self) -> None:
        passing = CompletionReport(
            tuple(PredicateResult(name, True, "passed") for name in PREDICATE_NAMES)
        )
        failing = CompletionReport(
            (
                PredicateResult(PREDICATE_NAMES[0], False, "failed"),
                *(
                    PredicateResult(name, True, "passed")
                    for name in PREDICATE_NAMES[1:]
                ),
            )
        )
        arguments = [
            "--json",
            "--test-repository-root",
            str(self.repository),
            "--test-final-root",
            str(self.final_root),
        ]

        for report, expected_status in ((passing, 0), (failing, 1)):
            with self.subTest(done=report.done):
                output = BytesIO()
                with patch.object(command, "verify_completion", return_value=report):
                    status = command.main(arguments, stdout=output)
                self.assertEqual(status, expected_status)
                self.assertEqual(
                    output.getvalue(), canonical_bytes(report.payload()) + b"\n"
                )


if __name__ == "__main__":
    unittest.main()
