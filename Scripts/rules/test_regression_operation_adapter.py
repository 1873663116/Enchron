#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import regression_operation_adapter as adapter
import regression_smb_source as smb
import regression_system_import as system_import


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class FakeBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object, object]] = []

    def execute(self, operation_id, arguments, context):
        self.calls.append((operation_id, arguments, context))
        return {"ok": True}


VALID_ARGUMENTS: dict[str, dict[str, object]] = {
    "operation:harness.ensure-session@1": {},
    "operation:app.relaunch@1": {},
    "operation:evidence.capture-frames@1": {"count": 3, "minimumIntervalMillis": 1000, "context": "open"},
    "operation:navigation.select-tab@1": {"tab": "files"},
    "operation:accessibility.activate@2": {"context": "window", "identifiers": ["Navigation-Ornament-tab-files"]},
    "operation:accessibility.inspect@2": {"context": "window", "identifier": "PlayerUI-window-control-plane"},
    "operation:accessibility.type@2": {"context": "main-window-browser", "identifier": "Emby-Connection-Address", "mode": "replace", "text": "http://server", "secret": False},
    "operation:harness.assert-channels@2": {},
    "operation:harness.reset-product-state@2": {},
    "operation:host.preflight@1": {"check": "webdav-regression"},
    "operation:diagnostics.surface-probe@1": {},
    "operation:diagnostics.browse-hierarchy@1": {
        "context": "main-window-browser",
        "sourceLabel": "Enchron Regression SMB",
        "pathComponents": ["Media", "TestVectors"],
    },
    "operation:issue.present@1": {"category": "mediaOpeningFailed"},
    "operation:media.stage-fixture@2": {"fixtureID": "fixture", "sourceRoot": "/tmp/media"},
    "operation:media.import-staged@2": {"fileName": "fixture.mp4"},
    "operation:preparation.local-directory-subtitle-source@1": {
        "directoryName": "Aggregate Source",
        "mediaFileName": "Aggregate.mkv",
        "memberFileNames": [
            "Aggregate.mkv",
            "Aggregate.zh-CN.srt",
            "Aggregate.styled.ass",
        ],
    },
    "operation:media.open@2": {"identifier": "MediaLibrary-grid-video-Fixture", "expectedLanding": "window", "deadlineSeconds": 45},
    "operation:library.snapshot@1": {},
    "operation:storage.clear@1": {"target": "playback-progress"},
    "operation:diagnostics.playback-state@1": {},
    "operation:playback.await-window-state@1": {"presentation": "window", "lifecycle": "playing", "controls": "either", "deadlineSeconds": 45},
    "operation:playback.wait-position@2": {"minimumPositionMillis": 1000, "minimumRemainingMillis": 0, "deadlineSeconds": 30},
    "operation:playback.seek@2": {"positionMillionths": 500000},
    "operation:playback.select-subtitle@1": {
        "host": "playerUI",
        "sourceKind": "local-sidecar",
        "trackLabel": "sdr-bframe-aggregate-30s.zh-CN.srt",
        "deadlineSeconds": 30,
    },
    "operation:format.apply@2": {"projection": "flat", "stereoLayout": "mono", "deadlineSeconds": 30},
    "operation:presentation.enter-docked-skybox@1": {"deadlineSeconds": 30},
    "operation:presentation.enter-panorama@1": {"deadlineSeconds": 30},
    "operation:presentation.exit-spatial@1": {"from": "panorama", "deadlineSeconds": 30},
    "operation:transition-trace.arm@1": {},
    "operation:transition-trace.fetch@1": {"generationToken": "1"},
    "operation:transition-trace.disarm@1": {"generationToken": "result://call:a:b/generationToken"},
    "operation:evidence.capture-audio@2": {"durationMillis": 6000, "inputDevice": "Input", "wavPath": "audio/capture.wav"},
    "operation:input.device-hub-prepare@1": {},
    "operation:input.device-hub-pinch@2": {"shotX": 100, "shotY": 100, "shotWidth": 1200, "shotHeight": 900},
    "operation:evidence.structural-test@1": {"check": "format-description-identity"},
}

SEMANTIC_OUTPUTS = {
    "operation:evidence.capture-frames@1": (
        ("visual.frames", "frame-sequence@2"),
        ("window.control-plane", "window-control-plane@1"),
    ),
    "operation:accessibility.inspect@2": (
        ("accessibility.tree", "accessibility-tree@1"),
        ("emby.evidence", "emby-evidence@1"),
    ),
    "operation:diagnostics.surface-probe@1": (
        ("interaction.trace", "interaction-trace@1"),
        ("spatial.input", "spatial-input@1"),
        ("window.control-plane", "window-control-plane@1"),
    ),
    "operation:diagnostics.browse-hierarchy@1": (
        ("accessibility.tree", "accessibility-tree@1"),
    ),
    "operation:media.import-staged@2": (("library.command", "library-command@1"),),
    "operation:preparation.local-directory-subtitle-source@1": (
        ("library.command", "library-command@1"),
    ),
    "operation:library.snapshot@1": (("library.command", "library-command@1"),),
    "operation:diagnostics.playback-state@1": (
        ("playback.probe", "playback-probe@1"),
        ("window.control-plane", "window-control-plane@1"),
    ),
    "operation:playback.await-window-state@1": (
        ("window.control-plane", "window-control-plane@1"),
    ),
    "operation:transition-trace.fetch@1": (("transition.trace", "transition-trace@1"),),
    "operation:evidence.capture-audio@2": (("audio.measurement", "audio-measurement@2"),),
    "operation:evidence.structural-test@1": (("structural.test", "structural-test@2"),),
    "operation:media.open@2": (("window.control-plane", "window-control-plane@1"),),
    "operation:presentation.enter-panorama@1": (
        ("window.control-plane", "window-control-plane@1"),
    ),
    "operation:presentation.exit-spatial@1": (
        ("window.control-plane", "window-control-plane@1"),
    ),
}


def playback_probe_result(
    *,
    session: str = "session-a",
    audio_track: str = "1",
    media_name: str = "fixture.mkv",
) -> dict[str, object]:
    fields = {
        "session": session,
        "audioTrack": audio_track,
        "mediaName": media_name,
    }
    return {
        "succeeded": True,
        **fields,
        "fields": fields,
        "response": {"success": True},
    }


def remote_playback_fields(
    *,
    session: str = "session-a",
    position: str = "12.5",
    reconnects: str = "3",
) -> dict[str, str]:
    return {
        "session": session,
        "audioTrack": "1",
        "mediaName": "sdr-bframe-aggregate-30s.mkv",
        "lifecycle": "Playing",
        "position": position,
        "playbackAddressKind": "loopback",
        "collectionOrigin": "sourceDirectory",
        "sourceIdentity": "sha256:" + "1" * 64,
        "contentRevision": "sha256:" + "2" * 64,
        "providerProjectionKind": "rectilinear",
        "sampleProjectionKind": "rectilinear",
        "rendererProjectionKind": "rectilinear",
        "rendererViewPackingKind": "mono",
        "hasAudio": "true",
        "demuxReconnects": reconnects,
        "error": "none",
    }


def library_snapshot_result() -> dict[str, object]:
    return {
        "folders": [
            {
                "id": "11111111-1111-4111-8111-111111111111",
                "parentID": None,
                "name": "Destination",
            }
        ],
        "references": [
            {
                "id": "22222222-2222-4222-8222-222222222222",
                "folderID": "11111111-1111-4111-8111-111111111111",
                "name": "fixture.mp4",
                "locatorKind": "file",
                "sourceIdentity": "sha256:" + "1" * 64,
                "sourcePath": "/private/tmp/fixture.mp4",
                "sourceExists": True,
                "sourceDigest": "sha256:" + "2" * 64,
                "sizeInBytes": 4096,
            },
            {
                "id": "33333333-3333-4333-8333-333333333333",
                "folderID": None,
                "name": "remote.mkv",
                "locatorKind": "sourceItem",
                "sourceIdentity": "sha256:" + "3" * 64,
                "sourcePath": "/library/remote.mkv",
                "sourceExists": None,
                "sourceDigest": None,
                "sizeInBytes": 8192,
            },
        ],
        "stagedFiles": [
            {
                "name": "fixture.mp4",
                "sizeInBytes": 4096,
                "digest": "sha256:" + "4" * 64,
            }
        ],
    }


def empty_library_snapshot_result(
    *, root_folder_name: str | None = None
) -> dict[str, object]:
    folders: list[dict[str, object]] = []
    if root_folder_name is not None:
        folders.append(
            {
                "id": "11111111-1111-4111-8111-111111111111",
                "parentID": None,
                "name": root_folder_name,
            }
        )
    return {"folders": folders, "references": [], "stagedFiles": []}


def product_state_reset_receipt(
    *, root_folder_name: str | None = None
) -> dict[str, object]:
    created_folder_names = [] if root_folder_name is None else [root_folder_name]
    return {
        "schema": "enchron.regression.product-state-reset@1",
        "removedReferenceCount": 2,
        "removedFolderCount": 1,
        "removedManagedDefaultKeys": [
            "enchron.playback.progress",
            "server-certificate-fingerprint.example",
        ],
        "remainingReferenceCount": 0,
        "remainingFolderCount": len(created_folder_names),
        "remainingManagedDefaultKeys": [],
        "createdFolderNames": created_folder_names,
    }
class OperationAllowlistTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        self.adapter = adapter.RegressionOperationAdapter(self.backend)
        self.temporary = tempfile.TemporaryDirectory(prefix="operation-adapter-test-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name).resolve()
        self.simulator = adapter.OperationContext("simulator", "sim", root, root / "controller")
        self.device = adapter.OperationContext("device", "device", root, root / "controller")

    def test_exact_35_operation_set_is_closed(self) -> None:
        self.assertEqual(set(adapter.SPECS), set(VALID_ARGUMENTS))
        self.assertEqual(len(adapter.SPECS), 35)
        self.assertNotIn("operation:host.query@1", adapter.SPECS)
        self.assertNotIn("operation:menu.select@1", adapter.SPECS)
        for retired in (
            "operation:accessibility.swipe@2",
            "operation:diagnostics.emby-range-log@1",
            "operation:diagnostics.window-control-plane@1",
            "operation:evidence.archive@2",
        ):
            self.assertNotIn(retired, adapter.SPECS)

    def test_every_operation_accepts_its_exact_representative_shape(self) -> None:
        for identifier, arguments in VALID_ARGUMENTS.items():
            context = self.device if identifier == "operation:evidence.capture-audio@2" else self.simulator
            with self.subTest(operation=identifier):
                result = self.adapter.invoke(identifier, arguments, context)
                self.assertEqual(result.operation_id, identifier)
        self.assertEqual(len(self.backend.calls), 35)

    def test_only_semantic_producers_declare_oracle_input_pairs(self) -> None:
        actual = {
            identifier: spec.outputs
            for identifier, spec in adapter.SPECS.items()
            if spec.outputs
        }
        self.assertEqual(actual, SEMANTIC_OUTPUTS)

    def test_resident_backend_implements_every_allowlisted_operation(self) -> None:
        backend = adapter.ResidentOperationBackend()
        missing = []
        for identifier in adapter.SPECS:
            handler_name = adapter.resident_handler_name(identifier)
            if not callable(getattr(backend, handler_name, None)):
                missing.append(identifier)
        self.assertEqual(missing, [])

    def test_catalog_shapes_are_derived_from_the_runtime_allowlist(self) -> None:
        shapes = {
            shape["id"]: shape for shape in adapter.catalog_operation_shapes()
        }
        self.assertEqual(set(shapes), set(adapter.SPECS))
        for identifier, spec in adapter.SPECS.items():
            with self.subTest(operation=identifier):
                shape = shapes[identifier]
                self.assertEqual(shape["lanes"], sorted(spec.lanes))
                self.assertEqual(
                    shape["evidenceSchemas"],
                    [
                        {
                            "evidenceType": evidence_type,
                            "evidenceSchema": evidence_schema,
                        }
                        for evidence_type, evidence_schema in spec.outputs
                    ],
                )
                self.assertEqual(
                    shape["implementation"]["locator"],
                    "Scripts/verification/regression_operation_adapter.py",
                )
                self.assertTrue(
                    (REPOSITORY_ROOT / shape["implementation"]["locator"]).is_file()
                )
                self.assertRegex(
                    shape["implementation"]["digest"], r"^sha256:[0-9a-f]{64}$"
                )

    def test_resident_backend_reads_the_app_command_wire_shape(self) -> None:
        backend = adapter.ResidentOperationBackend()
        response = {
            "success": True,
            "payload": ["generation=7", "capacity=2048", "fault=none"],
        }
        self.assertEqual(
            backend._response_payload_pairs(response),
            {"generation": "7", "capacity": "2048", "fault": "none"},
        )
        preflight = {
            "success": True,
            "transitionTraceSnapshot": {"generation": 6, "isArmed": False},
        }
        with mock.patch.object(
            backend, "_app_command", side_effect=[preflight, response]
        ):
            self.assertEqual(
                backend._transition_trace_arm_1({}, self.simulator)[
                    "generationToken"
                ],
                "7",
            )
        fault_response = {
            **response,
            "payload": [
                "generation=7",
                "capacity=2048",
                "fault=settlement-timeout",
            ],
        }
        with mock.patch.object(
            backend,
            "_app_command",
            side_effect=[preflight, fault_response],
        ) as app_command:
            result = backend._transition_trace_arm_1(
                {"fault": "settlement-timeout"}, self.simulator
            )
        self.assertEqual(result["generationToken"], "7")
        self.assertEqual(
            app_command.call_args_list,
            [
                mock.call(self.simulator, "fetchTransitionTraceSnapshot"),
                mock.call(
                    self.simulator,
                    "armTransitionTrace",
                    "fault=settlement-timeout",
                ),
            ],
        )

    def test_transition_trace_fault_allowlist_is_closed(self) -> None:
        spec = adapter.SPECS["operation:transition-trace.arm@1"]
        self.assertEqual(
            dict(
                spec.validate(
                    "device",
                    {"fault": "settlement-timeout"},
                )
            ),
            {"fault": "settlement-timeout"},
        )
        with self.assertRaises(adapter.OperationAdapterError):
            spec.validate("device", {"fault": "skip-settlement"})

    def test_issue_present_category_allowlist_is_closed(self) -> None:
        spec = adapter.SPECS["operation:issue.present@1"]
        for category in ("mediaOpeningFailed", "playbackControlFailed"):
            with self.subTest(category=category):
                self.assertEqual(
                    dict(spec.validate("device", {"category": category})),
                    {"category": category},
                )
                self.assertEqual(
                    dict(spec.validate("simulator", {"category": category})),
                    {"category": category},
                )
        with self.assertRaises(adapter.OperationAdapterError):
            spec.validate("device", {"category": "unsupportedVideoCodec"})

    def test_media_open_rejection_expectation_has_exact_landing_shape(self) -> None:
        spec = adapter.SPECS["operation:media.open@2"]
        expected = {
            **VALID_ARGUMENTS["operation:media.open@2"],
            "expectedIssueCategory": "unsupportedVideoCodec",
        }
        self.assertEqual(dict(spec.validate("device", expected)), expected)
        with self.assertRaises(adapter.OperationAdapterError):
            spec.validate(
                "device",
                {**expected, "expectedLanding": "portal"},
            )
        with self.assertRaises(adapter.OperationAdapterError):
            spec.validate(
                "device",
                {**expected, "expectedIssueCategory": "any-error"},
            )

    def test_subtitle_selection_shape_is_typed_and_closed(self) -> None:
        spec = adapter.SPECS["operation:playback.select-subtitle@1"]
        for lane in ("simulator", "device"):
            with self.subTest(lane=lane):
                self.assertEqual(
                    dict(spec.validate(lane, VALID_ARGUMENTS[spec.identifier])),
                    VALID_ARGUMENTS[spec.identifier],
                )
        without_label = {
            "host": "playerPanel",
            "sourceKind": "emby-external-stream",
            "deadlineSeconds": 45,
        }
        self.assertEqual(dict(spec.validate("device", without_label)), without_label)
        for field, value in (
            ("host", "mediaLibrary"),
            ("sourceKind", "webdav-sidecar"),
            ("deadlineSeconds", 0),
        ):
            with self.subTest(field=field), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate(
                    "device",
                    {**VALID_ARGUMENTS[spec.identifier], field: value},
                )

    def test_local_directory_subtitle_source_shape_requires_associated_sidecars(self) -> None:
        spec = adapter.SPECS[
            "operation:preparation.local-directory-subtitle-source@1"
        ]
        valid = VALID_ARGUMENTS[spec.identifier]
        for lane in ("simulator", "device"):
            with self.subTest(lane=lane):
                self.assertEqual(dict(spec.validate(lane, valid)), valid)
        invalid = (
            {**valid, "directoryName": "../escape"},
            {**valid, "mediaFileName": "missing.mkv"},
            {
                **valid,
                "memberFileNames": ["Aggregate.mkv", "Aggregate.mkv"],
            },
            {
                **valid,
                "memberFileNames": ["Aggregate.mkv", "Unrelated.srt"],
            },
            {**valid, "directoryName": "Aggregate.mkv"},
        )
        for arguments in invalid:
            with self.subTest(arguments=arguments), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", arguments)

    def test_transition_trace_fetch_binds_terminal_product_state(self) -> None:
        backend = adapter.ResidentOperationBackend()
        response = {
            "success": True,
            "transitionTraceSnapshot": {
                "generation": 7,
                "isArmed": True,
                "records": [],
            },
            "transitionTraceAnalysis": {"switches": []},
        }
        terminal = {
            "presentation": "portal",
            "transition": "none",
            "pendingSpatialEffect": "none",
            "error": "surfaceAttachmentFailed",
            "liveTechnicalSessions": "1",
            "retiringTechnicalSessions": "0",
        }
        with (
            mock.patch.object(backend, "_app_command", return_value=response),
            mock.patch.object(
                backend,
                "_read_control_plane",
                return_value=(terminal, {"success": True}),
            ),
        ):
            result = backend._transition_trace_fetch_1(
                {"generationToken": "7"}, self.device
            )

        self.assertEqual(result["terminalState"], terminal)
        self.assertTrue(result["terminalStateAvailable"])

        with (
            mock.patch.object(backend, "_app_command", return_value=response),
            mock.patch.object(
                backend,
                "_read_control_plane",
                return_value=(None, {"success": False, "reason": "not-visible"}),
            ),
        ):
            unavailable = backend._transition_trace_fetch_1(
                {"generationToken": "7"}, self.device
            )
        self.assertTrue(unavailable["succeeded"])
        self.assertIsNone(unavailable["terminalState"])
        self.assertFalse(unavailable["terminalStateAvailable"])

    def test_panorama_entry_accepts_only_the_named_rollback_expectation(self) -> None:
        spec = adapter.SPECS["operation:presentation.enter-panorama@1"]
        arguments = {
            "deadlineSeconds": 30,
            "expectedResult": "rollback-after-settlement-timeout",
        }
        self.assertEqual(dict(spec.validate("device", arguments)), arguments)
        with self.assertRaises(adapter.OperationAdapterError):
            spec.validate(
                "device",
                {
                    "deadlineSeconds": 30,
                    "expectedResult": "any-failure",
                },
            )

    def test_panorama_timeout_path_requires_a_complete_rollback_terminal(self) -> None:
        backend = adapter.ResidentOperationBackend()
        terminal = {
            "presentation": "portal",
            "transition": "none",
            "pendingSpatialEffect": "none",
            "attached": "portal",
            "rendererConsumer": "portal",
            "rendererConsumerEntity": "present",
            "lastPlatformOperation": "spatial-surface-settlement-failed",
            "lastExecutionCheckpoint": "presentation-rollback-settled-portal",
            "lastExecutionResolution": "failed-presentationRolledBack",
            "conversionDiagnostic": (
                "operation=spatial-surface-settlement-failed,"
                "runtime=surfaceAttachmentFailed"
            ),
            "error": "surfaceAttachmentFailed",
            "liveTechnicalSessions": "1",
            "retiringTechnicalSessions": "0",
            "lifecycle": "Playing",
        }
        matrix = mock.Mock(PASS="pass", STALL_TIMEOUT="stall-timeout")
        summon = {"success": True, "payload": ["true"]}
        trace = {
            "success": True,
            "transitionTraceSnapshot": {"generation": 7, "records": []},
        }
        with (
            mock.patch.object(backend, "_matrix", return_value=matrix),
            mock.patch.object(
                backend,
                "_app_command",
                side_effect=[summon, trace],
            ) as app_command,
            mock.patch.object(
                backend,
                "_controller",
                return_value={"success": True},
            ) as controller,
            mock.patch.object(
                backend,
                "_read_control_plane",
                return_value=(terminal, {"success": True}),
            ),
            mock.patch.object(
                adapter.time,
                "monotonic",
                side_effect=[0.0, 0.0, 0.1],
            ),
        ):
            result = backend._presentation_enter_panorama_1(
                {
                    "deadlineSeconds": 30,
                    "expectedResult": "rollback-after-settlement-timeout",
                },
                self.device,
            )

        self.assertTrue(result["succeeded"])
        self.assertEqual(result["settlement"]["terminal"], terminal)
        self.assertEqual(
            app_command.call_args_list,
            [
                mock.call(self.device, "toggleControls", "visible=true"),
                mock.call(self.device, "fetchTransitionTraceSnapshot"),
            ],
        )
        controller.assert_called_once_with(
            self.device,
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-resumePanorama",
        )

    def test_ensure_session_uses_the_lease_context_as_its_only_target_authority(self) -> None:
        backend = adapter.ResidentOperationBackend()
        response = {"success": True, "payload": []}
        with (
            mock.patch.object(backend, "_developer_dir", return_value="/Developer"),
            mock.patch.object(backend, "_controller", return_value=response) as controller,
        ):
            result = backend._harness_ensure_session_1({}, self.simulator)
        self.assertTrue(result["succeeded"])
        controller.assert_called_once_with(
            self.simulator,
            "ensure-session",
            "--destination-id",
            self.simulator.target,
            "--developer-dir",
            "/Developer",
            timeout=420,
            environment=None,
        )

        with (
            mock.patch.object(backend, "_developer_dir", return_value="/Developer"),
            mock.patch.object(backend, "_controller", return_value=response) as controller,
        ):
            result = backend._harness_ensure_session_1(
                {"controlsAutoHideSeconds": 8}, self.simulator
            )
        self.assertEqual(result["controlsAutoHideSeconds"], 8)
        self.assertEqual(
            controller.call_args.kwargs["environment"],
            {"ENCHRON_CONTROLS_AUTO_HIDE_SECONDS": "8"},
        )

    def test_unknown_operation_and_field_fail_before_backend_access(self) -> None:
        with self.assertRaises(adapter.OperationAdapterError):
            self.adapter.invoke("operation:host.query@1", {}, self.simulator)
        with self.assertRaises(adapter.OperationAdapterError):
            self.adapter.invoke("operation:app.relaunch@1", {"verb": "anything"}, self.simulator)
        self.assertEqual(self.backend.calls, [])

    def test_lane_mismatch_fails_before_backend_access(self) -> None:
        with self.assertRaises(adapter.OperationAdapterError):
            self.adapter.invoke(
                "operation:evidence.capture-audio@2",
                VALID_ARGUMENTS["operation:evidence.capture-audio@2"],
                self.simulator,
            )
        with self.assertRaises(adapter.OperationAdapterError):
            self.adapter.invoke(
                "operation:input.device-hub-pinch@2",
                VALID_ARGUMENTS["operation:input.device-hub-pinch@2"],
                self.device,
            )
        self.assertEqual(self.backend.calls, [])

    def test_accessibility_requires_current_inventory_identifiers(self) -> None:
        arguments = dict(VALID_ARGUMENTS["operation:accessibility.activate@2"])
        arguments["identifiers"] = ["semantic-alias"]
        with self.assertRaisesRegex(adapter.OperationAdapterError, "inventory"):
            self.adapter.invoke("operation:accessibility.activate@2", arguments, self.simulator)
        self.assertEqual(self.backend.calls, [])

    def test_accessibility_activate_requires_identifier_or_label(self) -> None:
        spec = adapter.SPECS["operation:accessibility.activate@2"]
        shape = adapter.catalog_operation_shape(spec.identifier)
        fields = {
            item["name"]: item for item in shape["argumentFields"]
        }
        self.assertFalse(fields["identifiers"]["required"])
        self.assertFalse(fields["labels"]["required"])
        for arguments in (
            {"context": "window"},
            {"context": "window", "identifiers": []},
            {"context": "window", "labels": []},
            {"context": "window", "identifiers": [], "labels": []},
        ):
            with self.subTest(arguments=arguments):
                with self.assertRaisesRegex(
                    adapter.OperationAdapterError, "identifier or label"
                ):
                    spec.validate("simulator", arguments)

    def test_accessibility_activate_drives_identifiers_then_each_label(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = {
            "context": "main-window-browser",
            "identifiers": ["FileBrowsing-SourcesSidebar-addSMB"],
            "labels": ["Connect", "TestMedia"],
            "index": 2,
        }
        validated = adapter.SPECS["operation:accessibility.activate@2"].validate(
            "device", arguments
        )
        with mock.patch.object(
            backend,
            "_controller",
            side_effect=(
                {
                    "success": True,
                    "path": "identifier",
                    "appState": "runningForeground",
                    "hierarchy": "identifier state",
                },
                {
                    "success": True,
                    "path": "label-1",
                    "appState": "runningForeground",
                    "hierarchy": "first label state",
                },
                {
                    "success": True,
                    "path": "label-2",
                    "appState": "runningForeground",
                    "hierarchy": "second label state",
                },
            ),
        ) as controller:
            result = backend._accessibility_activate_2(validated, self.device)
        self.assertTrue(result["succeeded"])
        self.assertEqual(
            controller.call_args_list,
            [
                mock.call(
                    self.device,
                    "tap",
                    "--identifier",
                    "FileBrowsing-SourcesSidebar-addSMB",
                    "--index",
                    "2",
                ),
                mock.call(self.device, "tap", "--label", "Connect"),
                mock.call(self.device, "tap", "--label", "TestMedia"),
            ],
        )
        self.assertEqual(len(result["labelResponses"]), 2)

    def test_accessibility_activate_labels_require_each_controller_success(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = {
            "context": "main-window-browser",
            "labels": ["First", "Second"],
        }
        validated = adapter.SPECS["operation:accessibility.activate@2"].validate(
            "device", arguments
        )
        with mock.patch.object(
            backend,
            "_controller",
            side_effect=(
                {
                    "success": True,
                    "appState": "runningForeground",
                    "hierarchy": "first label state",
                },
                {"success": False, "reason": "not-found"},
            ),
        ):
            with self.assertRaisesRegex(
                adapter.OperationAdapterError, "accessibility label Second"
            ):
                backend._accessibility_activate_2(validated, self.device)

    def test_browse_hierarchy_contract_is_closed_to_one_browser_context(self) -> None:
        spec = adapter.SPECS["operation:diagnostics.browse-hierarchy@1"]
        arguments = {
            "context": "main-window-browser",
            "sourceLabel": "Family NAS",
            "pathComponents": [
                "Shared Movies",
                "TestVectors",
                "Enchron",
                "PlaybackBehavior",
                "Archive",
            ],
        }
        self.assertEqual(dict(spec.validate("device", arguments)), arguments)
        self.assertEqual(dict(spec.validate("simulator", arguments)), arguments)
        for invalid in (
            {**arguments, "context": "window"},
            {**arguments, "sourceLabel": " Family NAS"},
            {**arguments, "pathComponents": []},
            {**arguments, "pathComponents": ["Shared Movies", ""]},
            {**arguments, "pathComponents": ["Shared Movies", "."]},
            {**arguments, "pathComponents": ["Shared Movies", ".."]},
            {**arguments, "pathComponents": ["Shared Movies/TestVectors"]},
            {**arguments, "pathComponents": ["Shared Movies", " Enchron"]},
        ):
            with self.subTest(arguments=invalid), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", invalid)

    def test_browse_hierarchy_keeps_each_requested_level(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = {
            "context": "main-window-browser",
            "sourceLabel": "Family NAS",
            "pathComponents": ["Shared Movies", "TestVectors"],
        }
        response = {
            "success": True,
            "hierarchy": (
                "StaticText, identifier: 'FileBrowsing-FilesScreen-itemCount', "
                "label: '1 item'\n"
                "Button, identifier: 'FileBrowsing-grid-folder-Shared Movies', "
                "label: 'Shared Movies'"
            ),
            "matchedElement": None,
        }
        with mock.patch.object(
            backend, "_controller", return_value=response
        ) as controller:
            result = backend._diagnostics_browse_hierarchy_1(
                arguments, self.device
            )

        self.assertEqual(
            controller.call_args_list,
            [
                mock.call(self.device, "tap", "--label", "Family NAS"),
                mock.call(self.device, "snapshot"),
                mock.call(
                    self.device,
                    "tap",
                    "--identifier",
                    "FileBrowsing-grid-folder-Shared Movies",
                ),
                mock.call(self.device, "snapshot"),
                mock.call(
                    self.device,
                    "tap",
                    "--identifier",
                    "FileBrowsing-grid-folder-TestVectors",
                ),
                mock.call(self.device, "snapshot"),
            ],
        )
        self.assertEqual(result["observationMode"], "navigated-requested-hierarchy")
        self.assertEqual(len(result["stages"]), 3)
        self.assertEqual(
            result["stages"][-1]["pathComponents"],
            ["Shared Movies", "TestVectors"],
        )
        self.assertEqual(result["stages"][0]["facts"]["itemCount"], 1)
        self.assertEqual(
            result["stages"][0]["facts"]["visibleCards"],
            [
                {
                    "identifier": "FileBrowsing-grid-folder-Shared Movies",
                    "kind": "folder",
                    "name": "Shared Movies",
                }
            ],
        )

    def test_accessibility_activate_press_is_one_closed_identifier_gesture(self) -> None:
        backend = adapter.ResidentOperationBackend()
        spec = adapter.SPECS["operation:accessibility.activate@2"]
        arguments = {
            "context": "main-window-browser",
            "identifiers": ["MediaLibrary-grid-video-fixture.mkv"],
            "gesture": "press",
            "durationMillis": 1_000,
        }
        validated = spec.validate("device", arguments)
        with mock.patch.object(
            backend,
            "_controller",
            return_value={
                "success": True,
                "appState": "runningForeground",
                "hierarchy": "pressed media card state",
            },
        ) as controller:
            result = backend._accessibility_activate_2(validated, self.device)
        self.assertTrue(result["succeeded"])
        controller.assert_called_once_with(
            self.device,
            "press",
            "--identifier",
            "MediaLibrary-grid-video-fixture.mkv",
            "--duration",
            "1.000",
        )

        invalid = (
            {**arguments, "durationMillis": 0},
            {**arguments, "labels": ["fixture"]},
            {**arguments, "identifiers": arguments["identifiers"] * 2},
            {
                "context": "main-window-browser",
                "identifiers": arguments["identifiers"],
                "durationMillis": 1_000,
            },
            {
                "context": "main-window-browser",
                "labels": ["fixture"],
                "gesture": "press",
                "durationMillis": 1_000,
            },
        )
        for candidate in invalid:
            with self.subTest(candidate=candidate), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", candidate)

    def test_storage_clear_has_one_exact_artwork_cache_route(self) -> None:
        spec = adapter.SPECS["operation:storage.clear@1"]
        self.assertEqual(
            dict(spec.validate("device", {"target": "artwork-cache"})),
            {"target": "artwork-cache"},
        )
        backend = adapter.ResidentOperationBackend()
        protected = {"digest": "sha256:" + "a" * 64}
        before = {
            "snapshot": {
                "viewingState": {"viewingRecordCount": 0, "persistedBytes": 0},
                "containerIndex": {"entryCount": 0, "totalBytes": 0},
                "artwork": {"entryCount": 1, "totalBytes": 1024},
                "protectedState": protected,
            },
            "response": {"success": True},
        }
        after = {
            "snapshot": {
                **before["snapshot"],
                "artwork": {"entryCount": 0, "totalBytes": 0},
            },
            "response": {"success": True},
        }
        with (
            mock.patch.object(
                backend, "_viewing_storage_observation", return_value=before
            ),
            mock.patch.object(
                backend, "_await_viewing_storage_observation", return_value=after
            ),
            mock.patch.object(
                backend,
                "_controller",
                return_value={"success": True},
            ) as controller,
        ):
            result = backend._storage_clear_1(
                {"target": "artwork-cache"}, self.device
            )
        self.assertTrue(result["succeeded"])
        controller.assert_called_once_with(
            self.device,
            "tapSequence",
            "--identifiers",
            "Navigation-Ornament-tab-settings",
            "Settings-category-storagePrivacy",
            "Settings-action-clear-artwork-cache",
        )

    def test_secret_text_requires_file_source(self) -> None:
        arguments = dict(VALID_ARGUMENTS["operation:accessibility.type@2"])
        arguments["secret"] = True
        with self.assertRaisesRegex(adapter.OperationAdapterError, "secret"):
            self.adapter.invoke("operation:accessibility.type@2", arguments, self.simulator)

    def test_paths_and_coordinates_cannot_escape_the_attempt(self) -> None:
        cases = (
            ("operation:media.import-staged@2", {"fileName": "../escape.mp4"}),
            ("operation:input.device-hub-pinch@2", {"shotX": 1200, "shotY": 1, "shotWidth": 1200, "shotHeight": 900}),
        )
        for identifier, arguments in cases:
            with self.subTest(operation=identifier), self.assertRaises(adapter.OperationAdapterError):
                self.adapter.invoke(identifier, arguments, self.simulator)

    def test_device_hub_input_has_closed_canvas_and_system_toolbar_variants(self) -> None:
        spec = adapter.SPECS["operation:input.device-hub-pinch@2"]
        self.assertEqual(
            dict(
                spec.validate(
                    "simulator",
                    {"targetDomain": "system-toolbar", "systemControl": "home"},
                )
            ),
            {"targetDomain": "system-toolbar", "systemControl": "home"},
        )
        invalid = (
            {"targetDomain": "system-toolbar"},
            {
                "targetDomain": "system-toolbar",
                "systemControl": "home",
                "shotX": 1,
            },
            {"targetDomain": "canvas", "systemControl": "home"},
            {"targetDomain": "canvas", "shotX": 1},
        )
        for arguments in invalid:
            with self.subTest(arguments=arguments), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("simulator", arguments)

    def test_device_hub_backend_routes_system_toolbar_without_canvas_coordinates(self) -> None:
        backend = adapter.ResidentOperationBackend()
        with (
            mock.patch.object(
                backend,
                "_run_json",
                return_value={
                    "control": "home",
                    "point": [10, 20],
                    "targetBinding": {"device": self.simulator.target},
                },
            ) as run_json,
            mock.patch.object(
                backend,
                "_controller",
                return_value={
                    "success": True,
                    "appState": "runningBackground",
                    "hierarchy": "SpringBoard",
                },
            ) as controller,
        ):
            result = backend._input_device_hub_pinch_2(
                {"targetDomain": "system-toolbar", "systemControl": "home"},
                self.simulator,
            )
        self.assertTrue(result["succeeded"])
        run_json.assert_called_once_with(
            [
                sys.executable,
                "Scripts/verification/device_hub_canvas.py",
                "--device",
                self.simulator.target,
                "system-control",
                "--control",
                "home",
            ],
            timeout=120,
        )
        controller.assert_called_once_with(
            self.simulator, "snapshot", "--no-screenshot"
        )

    def test_structural_test_name_is_a_closed_command_allowlist(self) -> None:
        self.assertEqual(
            {
                key: command[-1]
                for key, command in adapter.STRUCTURAL_CHECKS.items()
                if key.startswith("audio-retirement-")
            },
            {
                "audio-retirement-open": "audioOpenFailureRetiresAudioButVideoStillDelivers",
                "audio-retirement-prewarm": "audioPrerollFailureRetiresAudioButVideoStillDelivers",
                "audio-retirement-playback": "audioReadFailureRetiresAudioButVideoStillDelivers",
                "audio-retirement-seek": "audioSeekOpenFailureRetiresAudioButVideoStillDelivers",
                "audio-retirement-renderer": "audioRendererFailureRetiresAudioAndVideoContinues",
            },
        )
        with self.assertRaisesRegex(adapter.OperationAdapterError, "allowlist"):
            self.adapter.invoke(
                "operation:evidence.structural-test@1",
                {"check": "python-arbitrary-command"},
                self.simulator,
            )

    def test_structural_test_preserves_a_nonzero_test_result_as_evidence(self) -> None:
        backend = adapter.ResidentOperationBackend()
        completed = mock.Mock(
            returncode=1,
            stdout="selected test failed\n",
            stderr="failure detail\n",
        )
        with (
            mock.patch.object(adapter.subprocess, "run", return_value=completed),
            mock.patch.object(backend, "_developer_dir", return_value="/Developer"),
        ):
            result = backend._evidence_structural_test_1(
                {"check": "format-description-identity"},
                self.simulator,
            )

        self.assertTrue(result["succeeded"])
        self.assertEqual(result["returnCode"], 1)
        artifact = self.simulator.attempt_root / result["artifactPath"]
        self.assertEqual(
            artifact.read_text(),
            "selected test failed\nfailure detail\n",
        )

    def test_library_snapshot_is_exact_structured_source_evidence(self) -> None:
        backend = adapter.ResidentOperationBackend()
        response = {
            "success": True,
            "payload": ["folder=Destination", "reference=fixture.mp4"],
            "librarySnapshot": library_snapshot_result(),
        }
        with mock.patch.object(backend, "_app_command", return_value=response):
            result = backend._library_snapshot_1({}, self.simulator)
        self.assertIs(result["snapshot"], response["librarySnapshot"])
        self.assertEqual(
            result["entries"],
            [
                {"kind": "folder", "name": "Destination"},
                {"kind": "reference", "name": "fixture.mp4"},
            ],
        )
        self.assertEqual(result["referenceComparisons"], [])

    def test_media_import_returns_one_reference_identity_for_later_comparison(self) -> None:
        backend = adapter.ResidentOperationBackend()
        after = library_snapshot_result()
        before = json.loads(json.dumps(after))
        before["references"] = [
            item
            for item in before["references"]
            if item["id"] != "22222222-2222-4222-8222-222222222222"
        ]
        responses = [
            {
                "success": True,
                "payload": [],
                "librarySnapshot": before,
            },
            {"success": True, "payload": ["fixture.mp4"]},
            {
                "success": True,
                "payload": ["reference=fixture.mp4"],
                "librarySnapshot": after,
            },
        ]
        with mock.patch.object(
            backend, "_app_command", side_effect=responses
        ) as command:
            result = backend._media_import_staged_2(
                {"fileName": "fixture.mp4"}, self.simulator
            )
        self.assertEqual(command.call_count, 3)
        self.assertEqual(
            result["referenceID"],
            "22222222-2222-4222-8222-222222222222",
        )
        self.assertEqual(
            result["folderID"],
            "11111111-1111-4111-8111-111111111111",
        )
        self.assertEqual(result["sourceIdentity"], "sha256:" + "1" * 64)
        self.assertEqual(result["sourceDigest"], "sha256:" + "2" * 64)
        self.assertEqual(result["fileName"], "fixture.mp4")

    def test_local_directory_subtitle_source_binds_real_bookmark_topology(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = VALID_ARGUMENTS[
            "operation:preparation.local-directory-subtitle-source@1"
        ]
        member_names = sorted(arguments["memberFileNames"])
        staged_files = [
            {
                "name": name,
                "sizeInBytes": index + 1,
                "digest": "sha256:" + str(index + 1) * 64,
            }
            for index, name in enumerate(member_names)
        ]
        before = {
            "folders": [],
            "references": [],
            "stagedFiles": staged_files,
        }
        folder_id = "11111111-1111-4111-8111-111111111111"
        reference_id = "22222222-2222-4222-8222-222222222222"
        root_path = "/private/app/Documents/TestMediaInbox/Aggregate Source"
        source_path = root_path + "/Aggregate.mkv"
        after = {
            "folders": [
                {"id": folder_id, "parentID": None, "name": "Aggregate Source"}
            ],
            "references": [
                {
                    "id": reference_id,
                    "folderID": folder_id,
                    "name": "Aggregate.mkv",
                    "locatorKind": "file",
                    "sourceIdentity": "sha256:" + "a" * 64,
                    "sourcePath": source_path,
                    "sourceExists": True,
                    "sourceDigest": "sha256:" + "b" * 64,
                    "sizeInBytes": 4096,
                }
            ],
            "stagedFiles": staged_files,
        }
        receipt = {
            "schema": "enchron.regression.directory-media-import@1",
            "directoryName": "Aggregate Source",
            "mediaFileName": "Aggregate.mkv",
            "memberFileNames": member_names,
            "referenceID": reference_id,
            "bookmarkRootPath": root_path,
            "bookmarkRootIsDirectory": True,
            "mediaRelativePath": "Aggregate.mkv",
            "mediaSourcePath": source_path,
        }
        responses = [
            {"success": True, "librarySnapshot": before},
            {
                "success": True,
                "payload": ["Aggregate.mkv"],
                "directoryMediaImportReceipt": receipt,
            },
            {"success": True, "librarySnapshot": after},
        ]

        with mock.patch.object(
            backend, "_app_command", side_effect=responses
        ) as command:
            result = backend._preparation_local_directory_subtitle_source_1(
                arguments, self.simulator
            )

        self.assertEqual(
            command.call_args_list,
            [
                mock.call(self.simulator, "listLibrary"),
                mock.call(
                    self.simulator,
                    "importMediaDirectory",
                    "directory=Aggregate Source",
                    "media=Aggregate.mkv",
                    'files=["Aggregate.mkv","Aggregate.zh-CN.srt","Aggregate.styled.ass"]',
                ),
                mock.call(self.simulator, "listLibrary"),
            ],
        )
        self.assertEqual(result["directoryMediaImportReceipt"], receipt)
        self.assertEqual(result["referenceID"], reference_id)
        self.assertEqual(result["folderID"], folder_id)
        self.assertEqual(result["mediaRelativePath"], "Aggregate.mkv")
        self.assertEqual(result["bookmarkRootPath"], root_path)

    def test_library_snapshot_compares_current_reference_and_staged_source_as_raw_facts(self) -> None:
        backend = adapter.ResidentOperationBackend()
        snapshot = library_snapshot_result()
        response = {
            "success": True,
            "payload": ["reference=fixture.mp4"],
            "librarySnapshot": snapshot,
        }
        arguments = {
            "baselineReferenceIDs": [
                "22222222-2222-4222-8222-222222222222"
            ],
            "baselineFolderIDs": [
                "11111111-1111-4111-8111-111111111111"
            ],
            "baselineSourceIdentities": ["sha256:" + "1" * 64],
            "baselineSourcePaths": ["/private/tmp/fixture.mp4"],
            "baselineSourceDigests": ["sha256:" + "2" * 64],
            "baselineFileNames": ["fixture.mp4"],
        }
        validated = adapter.SPECS["operation:library.snapshot@1"].validate(
            "simulator", arguments
        )
        with mock.patch.object(backend, "_app_command", return_value=response):
            result = backend._library_snapshot_1(validated, self.simulator)
        comparison = result["referenceComparisons"][0]
        self.assertEqual(comparison["baseline"]["folderID"], arguments["baselineFolderIDs"][0])
        self.assertEqual(comparison["currentReference"], snapshot["references"][0])
        self.assertEqual(comparison["stagedFile"], snapshot["stagedFiles"][0])

        response["librarySnapshot"] = {
            **snapshot,
            "references": [snapshot["references"][1]],
        }
        with mock.patch.object(backend, "_app_command", return_value=response):
            deleted = backend._library_snapshot_1(validated, self.simulator)
        self.assertIsNone(deleted["referenceComparisons"][0]["currentReference"])
        self.assertEqual(
            deleted["referenceComparisons"][0]["stagedFile"],
            snapshot["stagedFiles"][0],
        )

    def test_library_snapshot_baseline_contract_is_complete_and_result_bound(self) -> None:
        spec = adapter.SPECS["operation:library.snapshot@1"]
        valid = {
            "baselineReferenceIDs": ["result://call:library:a:01/referenceID"],
            "baselineFolderIDs": ["result://call:library:a:01/folderID"],
            "baselineSourceIdentities": [
                "result://call:library:a:01/sourceIdentity"
            ],
            "baselineSourcePaths": ["result://call:library:a:01/sourcePath"],
            "baselineSourceDigests": [
                "result://call:library:a:01/sourceDigest"
            ],
            "baselineFileNames": ["result://call:library:a:01/fileName"],
        }
        self.assertEqual(dict(spec.validate("simulator", valid)), valid)
        invalid = (
            {"baselineReferenceIDs": valid["baselineReferenceIDs"]},
            {**valid, "baselineFolderIDs": []},
            {
                **valid,
                "baselineSourceDigests": [
                    "result://call:library:a:01/sourceIdentity"
                ],
            },
        )
        for arguments in invalid:
            with self.subTest(arguments=arguments), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("simulator", arguments)

    def test_library_snapshot_binds_each_system_picker_to_its_runtime_fixture(self) -> None:
        spec = adapter.SPECS["operation:library.snapshot@1"]
        self.assertEqual(
            dict(
                spec.validate(
                    "simulator", {"systemImportExpectation": "files"}
                )
            ),
            {"systemImportExpectation": "files"},
        )
        baseline = {
            "baselineReferenceIDs": [
                "22222222-2222-4222-8222-222222222222"
            ],
            "baselineFolderIDs": ["root"],
            "baselineSourceIdentities": ["sha256:" + "1" * 64],
            "baselineSourcePaths": ["/private/tmp/fixture.mp4"],
            "baselineSourceDigests": ["sha256:" + "2" * 64],
            "baselineFileNames": ["fixture.mp4"],
            "systemImportExpectation": "files",
        }
        with self.assertRaisesRegex(
            adapter.OperationAdapterError, "separate variants"
        ):
            spec.validate("simulator", baseline)

        backend = adapter.ResidentOperationBackend()
        snapshot = library_snapshot_result()
        snapshot["references"][0]["name"] = system_import.VISIBLE_FILENAME
        snapshot["references"][0]["sourceDigest"] = "sha256:" + "2" * 64
        response = {
            "success": True,
            "payload": [f"reference={system_import.VISIBLE_FILENAME}"],
            "librarySnapshot": snapshot,
            "systemImportDeliverySnapshot": {
                "schema": "enchron.regression.system-import-delivery@1",
                "requestID": "11111111-1111-4111-8111-111111111111",
                "routeIdentity": (
                    "files-provider-security-scope:"
                    "11111111-1111-4111-8111-111111111111"
                ),
                "deliveryDomain": "files-provider-security-scope",
                "items": [
                    {
                        "returnedIdentityKind": "files-provider-url",
                        "returnedIdentity": (
                            "/provider/Enchron-System-Import-30s.mp4"
                        ),
                        "deliveredName": system_import.VISIBLE_FILENAME,
                        "byteCount": snapshot["references"][0]["sizeInBytes"],
                        "sha256": "sha256:" + "2" * 64,
                    }
                ],
                "persistentLibraryDelivery": {
                    "outcome": "persisted",
                    "references": [
                        {
                            "id": snapshot["references"][0]["id"],
                            "name": system_import.VISIBLE_FILENAME,
                            "locatorKind": "file",
                            "sizeInBytes": snapshot["references"][0][
                                "sizeInBytes"
                            ],
                        }
                    ],
                },
            },
        }
        runtime_file = self.simulator.attempt_root / "system-import.json"
        configuration = type(
            "Configuration", (), {"runtime_file": runtime_file}
        )()
        runtime = {
            "environmentIdentity": "system-import:" + "a" * 24,
            "fixture": {
                "id": system_import.FIXTURE_ID,
                "digest": "sha256:" + "2" * 64,
                "size": 4096,
                "durationSeconds": 30.0,
            },
            "filesPicker": {
                "authorizationMode": "system-picker-security-scoped",
                "provider": "local-storage",
                "displayName": system_import.VISIBLE_FILENAME,
                "path": "/provider/Enchron-System-Import-30s.mp4",
                "digest": "sha256:" + "2" * 64,
            },
            "photosPicker": {
                "authorizationMode": "system-picker-no-library-authorization",
                "assetUUID": "11111111-1111-4111-8111-111111111111",
                "originalFilename": system_import.VISIBLE_FILENAME,
                "storedRelativePath": "DCIM/100APPLE/fixture.mp4",
                "digest": "sha256:" + "2" * 64,
                "durationSeconds": 30.0,
            },
        }
        with (
            mock.patch.object(backend, "_app_command", return_value=response),
            mock.patch.object(
                adapter._system_import,
                "SystemImportConfiguration",
                return_value=configuration,
            ),
            mock.patch.object(
                adapter._system_import,
                "validate_runtime",
                return_value=runtime,
            ),
        ):
            result = backend._library_snapshot_1(
                {"systemImportExpectation": "files"}, self.simulator
            )
        observation = result["systemImportObservation"]
        self.assertEqual(observation["expectation"], "files")
        self.assertEqual(
            observation["expectedDeliveryDomain"],
            "files-provider-security-scope",
        )
        self.assertEqual(
            observation["deliverySnapshot"],
            response["systemImportDeliverySnapshot"],
        )
        self.assertEqual(
            observation["persistentReferenceObservations"],
            [
                {
                    "deliveredReference": response[
                        "systemImportDeliverySnapshot"
                    ]["persistentLibraryDelivery"]["references"][0],
                    "currentReference": snapshot["references"][0],
                }
            ],
        )
        self.assertEqual(result["referenceComparisons"], [])

    def test_library_snapshot_rejects_unbound_or_invented_integrity(self) -> None:
        cases: list[tuple[str, object]] = []
        missing = library_snapshot_result()
        del missing["references"][0]["sourceIdentity"]
        cases.append(("wrong fields", missing))

        unknown_folder = library_snapshot_result()
        unknown_folder["references"][0]["folderID"] = (
            "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        )
        cases.append(("identify a folder", unknown_folder))

        invented_remote_digest = library_snapshot_result()
        invented_remote_digest["references"][1]["sourceExists"] = True
        invented_remote_digest["references"][1]["sourceDigest"] = (
            "sha256:" + "9" * 64
        )
        cases.append(("invent local integrity", invented_remote_digest))

        unsorted = library_snapshot_result()
        unsorted["references"].reverse()
        cases.append(("ascending order", unsorted))

        for message, snapshot in cases:
            with self.subTest(message=message), self.assertRaisesRegex(
                adapter.OperationAdapterError, message
            ):
                adapter.validate_library_snapshot(snapshot)

        with self.assertRaisesRegex(
            adapter.OperationAdapterError, "librarySnapshot must be a JSON object"
        ):
            adapter.validate_library_snapshot(None)

    def test_product_state_reset_receipt_is_closed_and_rejects_residue(self) -> None:
        receipt = product_state_reset_receipt(root_folder_name="Regression")
        self.assertEqual(
            dict(adapter.validate_product_state_reset_receipt(receipt)),
            receipt,
        )

        cases: list[tuple[str, dict[str, object]]] = []
        remaining_key = json.loads(json.dumps(receipt))
        remaining_key["remainingManagedDefaultKeys"] = ["enchron.playback.progress"]
        cases.append(("left managed defaults", remaining_key))

        unknown_field = json.loads(json.dumps(receipt))
        unknown_field["verified"] = True
        cases.append(("wrong fields", unknown_field))

        unsorted_keys = json.loads(json.dumps(receipt))
        unsorted_keys["removedManagedDefaultKeys"] = ["z", "a"]
        cases.append(("sorted unique strings", unsorted_keys))

        for message, malformed in cases:
            with self.subTest(message=message), self.assertRaisesRegex(
                adapter.OperationAdapterError, message
            ):
                adapter.validate_product_state_reset_receipt(malformed)

    def test_product_state_reset_requires_typed_receipt_and_observed_empty_library(self) -> None:
        backend = adapter.ResidentOperationBackend()
        receipt = product_state_reset_receipt(root_folder_name="Regression")
        snapshot = empty_library_snapshot_result(root_folder_name="Regression")
        responses = [
            {"success": True, "productStateResetReceipt": receipt},
            {"success": True, "librarySnapshot": snapshot},
        ]
        with (
            mock.patch.object(
                backend, "_controller", return_value={"success": True}
            ) as controller,
            mock.patch.object(
                backend, "_app_command", side_effect=responses
            ) as app_command,
        ):
            result = backend._harness_reset_product_state_2(
                {"rootFolderName": "Regression"}, self.simulator
            )

        self.assertEqual(result["resetReceipt"], receipt)
        self.assertEqual(result["librarySnapshot"], snapshot)
        controller.assert_called_once_with(self.simulator, "relaunch")
        self.assertEqual(
            app_command.call_args_list,
            [
                mock.call(self.simulator, "resetState", "libraryFolder=Regression"),
                mock.call(self.simulator, "listLibrary"),
            ],
        )

    def test_product_state_reset_rejects_receipt_or_library_mismatch(self) -> None:
        cases = (
            (
                product_state_reset_receipt(root_folder_name="Unexpected"),
                empty_library_snapshot_result(root_folder_name="Regression"),
            ),
            (
                product_state_reset_receipt(root_folder_name="Regression"),
                empty_library_snapshot_result(),
            ),
        )
        for receipt, snapshot in cases:
            backend = adapter.ResidentOperationBackend()
            with (
                self.subTest(receipt=receipt, snapshot=snapshot),
                mock.patch.object(
                    backend, "_controller", return_value={"success": True}
                ),
                mock.patch.object(
                    backend,
                    "_app_command",
                    side_effect=[
                        {"success": True, "productStateResetReceipt": receipt},
                        {"success": True, "librarySnapshot": snapshot},
                    ],
                ),
                self.assertRaisesRegex(
                    adapter.OperationAdapterError,
                    "requested empty library root|differs from the observed library root",
                ),
            ):
                backend._harness_reset_product_state_2(
                    {"rootFolderName": "Regression"}, self.simulator
                )

    def test_remote_preflight_names_are_closed_without_fault_or_query_aliases(self) -> None:
        import regression_environment_preflight as preflight

        self.assertEqual(adapter.REMOTE_PREFLIGHT_CHECKS, frozenset(preflight.CHECKS))
        spec = adapter.SPECS["operation:host.preflight@1"]
        for check in ("webdav-regression", "remote-faults"):
            self.assertEqual(dict(spec.validate("device", {"check": check})), {"check": check})
        for check in ("healthy", "certificate-rotation", "host.configure-fault"):
            with self.subTest(check=check), self.assertRaises(adapter.OperationAdapterError):
                spec.validate("device", {"check": check})
        self.assertNotIn("operation:host.configure-fault@1", adapter.SPECS)
        self.assertNotIn("operation:host.query@1", adapter.SPECS)

    def test_remote_recipe_actuation_is_a_closed_host_preflight_phase(self) -> None:
        spec = adapter.SPECS["operation:host.preflight@1"]
        accepted = (
            {"check": "remote-faults", "phase": "ensure"},
            {
                "check": "remote-faults",
                "phase": "activate",
                "recipe": "recoverable-read-interruption",
            },
            {
                "check": "remote-faults",
                "phase": "restore",
                "receiptID": "result://call:network-resilience:recovery:03/receiptID",
            },
        )
        for arguments in accepted:
            with self.subTest(arguments=arguments):
                self.assertEqual(dict(spec.validate("device", arguments)), arguments)

        rejected = (
            {"check": "remote-faults", "phase": "activate"},
            {
                "check": "remote-faults",
                "phase": "activate",
                "recipe": "drop-any-packet",
            },
            {
                "check": "webdav-regression",
                "phase": "activate",
                "recipe": "healthy",
            },
            {
                "check": "remote-faults",
                "phase": "restore",
                "receiptID": "receipt:anything",
            },
            {
                "check": "remote-faults",
                "recipe": "healthy",
            },
        )
        for arguments in rejected:
            with self.subTest(arguments=arguments), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", arguments)

    def test_remote_service_and_preflight_implementations_are_digest_bound(self) -> None:
        expected = {
            "remote-source-service": Path(
                "Scripts/verification/regression_remote_source.py"
            ),
            "remote-environment-preflight": Path(
                "Scripts/verification/regression_environment_preflight.py"
            ),
        }
        self.assertEqual(set(adapter.REMOTE_IMPLEMENTATION_IDENTITIES), set(expected))
        for identity, relative_path in expected.items():
            with self.subTest(identity=identity):
                binding = adapter.REMOTE_IMPLEMENTATION_IDENTITIES[identity]
                self.assertEqual(binding["path"], relative_path.as_posix())
                self.assertEqual(
                    binding["digest"],
                    "sha256:"
                    + hashlib.sha256((adapter.REPOSITORY_ROOT / relative_path).read_bytes()).hexdigest(),
                )

    def test_emby_preflight_uses_the_typed_environment_report(self) -> None:
        backend = adapter.ResidentOperationBackend()
        direct = {
            "schema": "enchron.regression.emby-source-preflight@1",
            "check": "emby-aggregate",
            "ready": True,
            "receipt": {"status": "active"},
        }
        envelope = {
            "schema": "enchron.regression.environment-preflight@1",
            "ready": True,
            "checks": [direct],
        }
        with (
            mock.patch.object(backend, "_run_json", return_value=envelope) as run_json,
            mock.patch.object(
                adapter._emby_source,
                "validate_preflight_report",
                return_value=True,
            ) as validate,
            mock.patch.object(
                adapter, "_literal_lan_address", return_value="192.168.64.1"
            ),
        ):
            result = backend._host_preflight_1(
                {"check": "emby-aggregate"}, self.device
            )
        self.assertIs(result["report"], direct)
        self.assertNotIn("emby_probe.py", " ".join(run_json.call_args.args[0]))
        self.assertIn(
            "regression_environment_preflight.py",
            " ".join(run_json.call_args.args[0]),
        )
        validate.assert_called_once()

    def test_system_import_preflight_binds_simulator_assets_and_enlarged_device_hub(self) -> None:
        backend = adapter.ResidentOperationBackend()
        target = "3dd8e196-0fc4-42c5-bf8f-060e025664fc"
        context = adapter.OperationContext(
            "simulator",
            target,
            self.simulator.attempt_root,
            self.simulator.controller_directory,
        )
        runtime_file = self.simulator.attempt_root / "system-import-runtime.json"
        report = {
            "schema": system_import.REPORT_SCHEMA,
            "check": "system-import-fixtures",
            "ready": True,
            "runtimeIdentity": {"path": str(runtime_file), "mode": "0600"},
        }
        device_hub = {
            "window": {"width": 2200, "height": 1180},
            "canvas": {"width": 1729, "height": 972},
            "pointerMode": [100, 100],
            "targetBinding": {
                "device": target.upper(),
                "name": "Apple Vision Pro",
                "runtime": "com.apple.CoreSimulator.SimRuntime.xrOS-27-0",
            },
        }
        configuration = type(
            "Configuration", (), {"runtime_file": runtime_file}
        )()
        with (
            mock.patch.object(
                adapter._system_import,
                "SystemImportConfiguration",
                return_value=configuration,
            ),
            mock.patch.object(
                adapter._system_import,
                "validate_preflight_report",
                return_value=True,
            ) as validate,
            mock.patch.object(
                backend, "_run_json", side_effect=[report, device_hub]
            ) as run_json,
        ):
            result = backend._host_preflight_1(
                {"check": "system-import-fixtures"}, context
            )
        self.assertEqual(result["runtimePath"], str(runtime_file))
        self.assertEqual(result["deviceHub"]["canvas"]["width"], 1729)
        self.assertEqual(
            set(result["implementations"]),
            set(adapter.SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES),
        )
        self.assertEqual(run_json.call_count, 2)
        self.assertIn(target, run_json.call_args_list[0].args[0])
        self.assertEqual(run_json.call_args_list[1].args[0][-1], "enlarge")
        self.assertIn(target, run_json.call_args_list[1].args[0])
        validate.assert_called_once_with(
            report,
            device_identifier=target,
            runtime_file=runtime_file,
        )

        with self.assertRaisesRegex(
            adapter.OperationAdapterError, "Simulator lane"
        ):
            backend._host_preflight_1(
                {"check": "system-import-fixtures"}, self.device
            )

    def test_smb_preflight_is_digest_bound_and_returns_only_runtime_references(self) -> None:
        expected = {
            "smb-source-preflight": Path(
                "Scripts/verification/regression_smb_source.py"
            ),
        }
        self.assertEqual(set(adapter.SMB_IMPLEMENTATION_IDENTITIES), set(expected))
        for identity, relative_path in expected.items():
            binding = adapter.SMB_IMPLEMENTATION_IDENTITIES[identity]
            self.assertEqual(binding["path"], relative_path.as_posix())
            self.assertEqual(
                binding["digest"],
                "sha256:"
                + hashlib.sha256(
                    (adapter.REPOSITORY_ROOT / relative_path).read_bytes()
                ).hexdigest(),
            )

        backend = adapter.ResidentOperationBackend()
        with tempfile.TemporaryDirectory(prefix="smb-operation-test-") as directory:
            runtime_file = Path(directory).resolve() / "runtime.json"
            secret_user = "smb-user-must-not-cross-result"
            secret_password = "smb-password-must-not-cross-result"
            manifest_hashes = {
                "aggregate-mkv": "sha256:" + "a" * 64,
                "aggregate-srt": "sha256:" + "b" * 64,
                "aggregate-ass": "sha256:" + "c" * 64,
            }
            aggregate_paths = [
                "TestVectors/aggregate.mkv",
                "TestVectors/aggregate.srt",
                "TestVectors/aggregate.ass",
            ]
            aggregate_digest = smb._digest(
                {
                    "manifestHashes": manifest_hashes,
                    "paths": aggregate_paths,
                }
            )
            source_identity = "smb-source:" + smb._digest(
                {
                    "address": "192.168.64.1",
                    "shareName": "TestMedia",
                    "aggregateDigest": aggregate_digest,
                }
            ).removeprefix("sha256:")[:24]
            runtime = {
                "address": "192.168.64.1",
                "user": secret_user,
                "password": secret_password,
                "shareName": "TestMedia",
                "sourceIdentity": source_identity,
                "aggregateDigest": aggregate_digest,
                "aggregateManifestHashes": manifest_hashes,
                "aggregatePaths": aggregate_paths,
            }
            runtime_file.write_text(json.dumps(runtime), encoding="utf-8")
            os.chmod(runtime_file, 0o600)
            reference = lambda key: {
                "textFile": str(runtime_file),
                "textJSONKey": key,
            }
            report = {
                "schema": smb.REPORT_SCHEMA,
                "check": "smb-aggregate",
                "ready": True,
                "runtimeIdentity": {
                    "path": str(runtime_file),
                    "mode": "0600",
                    "addressReference": reference("address"),
                    "userReference": reference("user"),
                    "passwordReference": reference("password"),
                    "shareName": runtime["shareName"],
                    "sourceIdentity": runtime["sourceIdentity"],
                    "aggregateDigest": runtime["aggregateDigest"],
                },
                "aggregateManifestHashes": manifest_hashes,
                "aggregatePaths": runtime["aggregatePaths"],
            }
            with (
                mock.patch.object(adapter, "SMB_RUNTIME_FILE", runtime_file),
                mock.patch.object(
                    adapter, "_literal_lan_address", return_value="192.168.64.1"
                ),
                mock.patch.object(backend, "_run_json", return_value=report) as run_json,
            ):
                result = backend._host_preflight_1(
                    {"check": "smb-aggregate"}, self.device
                )
            command = run_json.call_args.args[0]
            self.assertIn("regression_smb_source.py", " ".join(command))
            self.assertEqual(
                command[command.index("--address") + 1], "192.168.64.1"
            )
            self.assertNotIn(secret_user, json.dumps(command))
            self.assertNotIn(secret_password, json.dumps(command))
            encoded = json.dumps(result, sort_keys=True)
            self.assertNotIn(secret_user, encoded)
            self.assertNotIn(secret_password, encoded)
            self.assertEqual(result["runtimeIdentity"]["path"], str(runtime_file))
            self.assertEqual(result["runtimeIdentity"]["mode"], "0600")
            self.assertEqual(
                set(result["implementations"]),
                set(adapter.SMB_IMPLEMENTATION_IDENTITIES),
            )

            os.chmod(runtime_file, 0o644)
            with self.assertRaisesRegex(adapter.OperationAdapterError, "0600"):
                adapter.validate_smb_preflight_report(report, runtime_file)

    def test_remote_preflight_consumes_fixed_cli_and_returns_no_secret_bytes(self) -> None:
        backend = adapter.ResidentOperationBackend()
        with tempfile.TemporaryDirectory(prefix="remote-operation-test-") as directory:
            runtime_file = Path(directory).resolve() / "runtime.json"
            secret = "this-must-never-cross-the-operation-result"
            runtime = {
                "address": "https://192.168.64.1:8443/generation-1/healthy/",
                "user": "enchron-regression",
                "password": secret,
                "serviceID": "remote-source:unit-test",
                "generation": 1,
                "requestLogPath": str(runtime_file.parent / "generation-1.jsonl"),
                "manifestPath": str(runtime_file.parent / "generation-1.json"),
                "certificateFingerprint": "sha256:" + "a" * 64,
            }
            runtime_file.write_text(json.dumps(runtime), encoding="utf-8")
            os.chmod(runtime_file, 0o600)
            report = {
                "schema": "enchron.regression.environment-preflight@1",
                "ready": True,
                "checks": [
                    {
                        "check": "webdav-regression",
                        "ready": True,
                        "serviceID": runtime["serviceID"],
                        "generation": 1,
                        "endpointDigest": "sha256:" + "b" * 64,
                        "certificateFingerprint": runtime["certificateFingerprint"],
                        "requestLogPath": runtime["requestLogPath"],
                        "requestLogDigest": "sha256:" + "c" * 64,
                        "objectManifestHashes": {"fixture": "sha256:" + "d" * 64},
                        "propfindStatus": 207,
                        "rangeStatus": 206,
                        "rangeDigest": "sha256:" + "e" * 64,
                        "expectedRangeDigest": "sha256:" + "e" * 64,
                    }
                ],
            }
            with (
                mock.patch.object(adapter, "REMOTE_RUNTIME_FILE", runtime_file),
                mock.patch(
                    "Scripts.verification.journey_preflight.host_address",
                    return_value="192.168.64.1",
                ),
                mock.patch.object(backend, "_run_json", return_value=report) as run_json,
            ):
                result = backend._host_preflight_1(
                    {"check": "webdav-regression"}, self.device
                )
        command = run_json.call_args.args[0]
        self.assertIn("regression_environment_preflight.py", " ".join(command))
        self.assertIn("--bind-host", command)
        self.assertEqual(command[command.index("--bind-host") + 1], "192.168.64.1")
        self.assertIn("webdav-regression", command)
        encoded = json.dumps(result, sort_keys=True)
        self.assertNotIn(secret, encoded)
        self.assertEqual(result["runtimePath"], str(runtime_file))
        self.assertEqual(result["generationToken"], "1")
        self.assertEqual(result["requestLogPath"], runtime["requestLogPath"])
        self.assertEqual(
            result["missingPathAddress"],
            runtime["address"].rstrip("/") + "/__missing__/",
        )
        self.assertEqual(
            result["httpAddress"],
            runtime["address"].replace("https://", "http://", 1),
        )
        self.assertEqual(
            result["unreachableAddress"],
            "https://192.168.64.1:1/",
        )
        self.assertEqual(result["runtimeIdentity"]["path"], str(runtime_file))
        self.assertEqual(result["runtimeIdentity"]["mode"], "0600")
        self.assertEqual(
            set(result["implementations"]), set(adapter.REMOTE_IMPLEMENTATION_IDENTITIES)
        )

    def test_remote_fault_preflight_requires_every_restored_closed_recipe(self) -> None:
        import regression_remote_source as remote

        report = {
            "schema": "enchron.regression.environment-preflight@1",
            "ready": True,
            "checks": [
                {
                    "check": "remote-faults",
                    "ready": True,
                    "serviceID": "remote-source:unit-test",
                    "recipes": [
                        {
                            "recipe": recipe,
                            "verified": True,
                            "receipt": {
                                "schema": "enchron.regression.remote-source-receipt@1",
                                "receiptID": f"receipt:{recipe}",
                                "recipe": recipe,
                                "generation": 1,
                                "endpointDigest": "sha256:" + "a" * 64,
                                "activationTime": "2026-08-29T00:00:00.000000Z",
                                "priorStateDigest": "sha256:" + "b" * 64,
                                "terminalStateDigest": "sha256:" + "c" * 64,
                                "restoredStateDigest": "sha256:" + "e" * 64,
                                "logPath": f"/tmp/{recipe}.jsonl",
                                "logDigest": "sha256:" + "f" * 64,
                                "objectManifestHashes": {
                                    "fixture": "sha256:" + "d" * 64
                                },
                                "priorCertificateFingerprint": "sha256:" + "a" * 64,
                                "certificateFingerprint": "sha256:" + "a" * 64,
                            },
                        }
                        for recipe in remote.RECIPE_NAMES
                    ],
                    "terminalState": {
                        "generation": 10,
                        "recipe": "healthy",
                        "endpointDigest": "sha256:" + "a" * 64,
                        "certificateFingerprint": "sha256:" + "b" * 64,
                    },
                }
            ],
        }
        adapter.validate_remote_preflight_report("remote-faults", report)
        report["checks"][0]["recipes"][3]["receipt"]["restoredStateDigest"] = None
        with self.assertRaisesRegex(adapter.OperationAdapterError, "restored"):
            adapter.validate_remote_preflight_report("remote-faults", report)

    def test_remote_recipe_activate_and_restore_return_only_referenceable_receipts(self) -> None:
        backend = adapter.ResidentOperationBackend()
        with tempfile.TemporaryDirectory(prefix="remote-actuator-test-") as directory:
            runtime_file = Path(directory).resolve() / "runtime.json"
            secret = "remote-actuator-secret"
            runtime = {
                "address": "https://192.168.64.1:8443/dav/g-000002/",
                "user": "enchron-regression",
                "password": secret,
                "serviceID": "remote-source:unit-test",
                "generation": 2,
                "requestLogPath": str(runtime_file.parent / "generation-2.jsonl"),
                "manifestPath": str(runtime_file.parent / "generation-2.json"),
                "certificateFingerprint": "sha256:" + "a" * 64,
            }
            runtime_file.write_text(json.dumps(runtime), encoding="utf-8")
            os.chmod(runtime_file, 0o600)
            activation = {
                "schema": "enchron.regression.remote-source-receipt@1",
                "receiptID": "receipt:g-000002:finite-reconnect",
                "recipe": "finite-reconnect",
                "generation": 2,
                "endpointDigest": "sha256:" + "b" * 64,
                "activationTime": "2026-08-29T00:00:00.000000Z",
                "priorStateDigest": "sha256:" + "c" * 64,
                "terminalStateDigest": "sha256:" + "d" * 64,
                "restoredStateDigest": None,
                "logPath": runtime["requestLogPath"],
                "logDigest": "sha256:" + "e" * 64,
                "objectManifestHashes": {"fixture": "sha256:" + "f" * 64},
                "priorCertificateFingerprint": "sha256:" + "a" * 64,
                "certificateFingerprint": runtime["certificateFingerprint"],
            }
            restoration = {
                "schema": "enchron.regression.remote-source-restoration@1",
                "receiptID": "restore:g-000003:abcdef",
                "activationReceiptID": activation["receiptID"],
                "activationRecipe": activation["recipe"],
                "activationGeneration": 2,
                "activationEndpointDigest": activation["endpointDigest"],
                "activationLogPath": activation["logPath"],
                "activationLogDigest": "sha256:" + "1" * 64,
                "restoredAt": "2026-08-29T00:00:01.000000Z",
                "restoredRecipe": "healthy",
                "restoredGeneration": 3,
                "restoredStateDigest": "sha256:" + "2" * 64,
                "restoredEndpointDigest": "sha256:" + "3" * 64,
                "restoredCertificateFingerprint": "sha256:" + "4" * 64,
                "restoredRequestLogPath": str(runtime_file.parent / "generation-3.jsonl"),
                "restoredRequestLogDigest": "sha256:" + "5" * 64,
                "objectManifestHashes": activation["objectManifestHashes"],
                "propfindStatus": 207,
                "rangeStatus": 206,
                "range": "bytes=16-63",
                "rangeDigest": "sha256:" + "6" * 64,
                "expectedRangeDigest": "sha256:" + "6" * 64,
                "verified": True,
                "receiptPath": str(runtime_file.parent / "restore.json"),
                "receiptDigest": "sha256:" + "7" * 64,
            }
            with (
                mock.patch.object(adapter, "REMOTE_RUNTIME_FILE", runtime_file),
                mock.patch.object(
                    adapter, "_literal_lan_address", return_value="192.168.64.1"
                ),
                mock.patch.object(
                    adapter._remote_preflight,
                    "activate_remote_recipe",
                    return_value=activation,
                ) as activate,
                mock.patch.object(
                    adapter._remote_preflight,
                    "restore_remote_recipe",
                    return_value=restoration,
                ) as restore,
            ):
                activated = backend._host_preflight_1(
                    {
                        "check": "remote-faults",
                        "phase": "activate",
                        "recipe": "finite-reconnect",
                    },
                    self.device,
                )
                restored = backend._host_preflight_1(
                    {
                        "check": "remote-faults",
                        "phase": "restore",
                        "receiptID": activation["receiptID"],
                    },
                    self.device,
                )

        self.assertEqual(activated["receiptID"], activation["receiptID"])
        self.assertEqual(activated["generationToken"], "2")
        self.assertEqual(activated["runtimePath"], str(runtime_file))
        self.assertEqual(restored["receiptID"], activation["receiptID"])
        self.assertEqual(restored["restoredGenerationToken"], "3")
        self.assertTrue(restored["restorationReceipt"]["verified"])
        self.assertNotIn(secret, json.dumps(activated, sort_keys=True))
        self.assertNotIn(secret, json.dumps(restored, sort_keys=True))
        activate.assert_called_once()
        restore.assert_called_once()

    def test_runtime_credential_reference_must_be_absolute_owner_only_json(self) -> None:
        backend = adapter.ResidentOperationBackend()
        with tempfile.TemporaryDirectory(prefix="credential-reference-test-") as directory:
            path = Path(directory).resolve() / "runtime.json"
            path.write_text(json.dumps({"password": "hidden"}), encoding="utf-8")
            os.chmod(path, 0o600)
            arguments = {
                "context": "main-window-browser",
                "identifier": "FileBrowsing-SourceConnection-webDAV-password",
                "mode": "replace",
                "textFile": str(path),
                "textJSONKey": "password",
                "secret": True,
            }
            adapter.SPECS["operation:accessibility.type@2"].validate(
                "device", arguments
            )
            with mock.patch.object(
                backend,
                "_controller",
                return_value={
                    "success": True,
                    "appState": "runningForeground",
                    "hierarchy": "SecureTextField value: '<redacted>'",
                },
            ) as controller:
                result = backend._accessibility_type_2(arguments, self.device)
            command = controller.call_args.args
            self.assertIn("--redact-response-text", command)
            self.assertNotIn("hidden", json.dumps(result))
            os.chmod(path, 0o644)
            with self.assertRaisesRegex(adapter.OperationAdapterError, "0600"):
                backend._accessibility_type_2(arguments, self.device)
        relative = dict(arguments)
        relative["textFile"] = "runtime.json"
        with self.assertRaisesRegex(adapter.OperationAdapterError, "absolute"):
            adapter.SPECS["operation:accessibility.type@2"].validate("device", relative)
        reference = dict(arguments)
        reference["textFile"] = (
            "result://call:webdav-source-lifecycle:webdav-add-source:01/runtimePath"
        )
        self.assertEqual(
            dict(
                adapter.SPECS["operation:accessibility.type@2"].validate(
                    "device", reference
                )
            ),
            reference,
        )

    def test_surface_probe_has_closed_receipt_bound_remote_expectations(self) -> None:
        spec = adapter.SPECS["operation:diagnostics.surface-probe@1"]
        healthy = {
            "cursorToken": "1:2",
            "remoteExpectation": "webdav-playback-range",
            "remoteGenerationToken": "result://call:webdav-source-lifecycle:open:01/generationToken",
            "productBindingDigest": "result://call:webdav-source-lifecycle:open:08/bindingDigest",
        }
        fault = {
            "cursorToken": "1:2",
            "remoteExpectation": "finite-backoff",
            "remoteReceiptID": "result://call:network-resilience:finite:03/receiptID",
            "restoredGenerationToken": "result://call:network-resilience:finite:09/restoredGenerationToken",
            "productBindingDigest": "result://call:network-resilience:finite:08/bindingDigest",
        }
        certificate = {
            "cursorToken": "result://call:network-resilience:certificate:06/cursorToken",
            "remoteExpectation": "certificate-change",
            "remoteReceiptID": "result://call:network-resilience:certificate:08/receiptID",
            "restoredGenerationToken": "result://call:network-resilience:certificate:10/restoredGenerationToken",
        }
        healthy_with_request_cursor = {
            **healthy,
            "includeViewingStorage": True,
            "remoteRequestCursor": (
                "result://call:viewing-state-and-storage:remote-index:04/"
                "remoteRequestCursor"
            ),
        }
        self.assertEqual(dict(spec.validate("device", healthy)), healthy)
        self.assertEqual(dict(spec.validate("device", fault)), fault)
        self.assertEqual(dict(spec.validate("device", certificate)), certificate)
        self.assertEqual(
            dict(spec.validate("device", healthy_with_request_cursor)),
            healthy_with_request_cursor,
        )
        for invalid in (
            {"remoteExpectation": "anything"},
            {"remoteExpectation": "webdav-playback-range"},
            {
                "remoteExpectation": "finite-backoff",
                "remoteReceiptID": fault["remoteReceiptID"],
            },
            {
                **fault,
                "remoteGenerationToken": healthy["remoteGenerationToken"],
            },
            {
                key: value
                for key, value in healthy.items()
                if key != "productBindingDigest"
            },
            {
                key: value
                for key, value in certificate.items()
                if key != "cursorToken"
            },
            {**healthy, "remoteRequestCursor": "0"},
        ):
            with self.subTest(arguments=invalid), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", invalid)

    def test_frame_capture_preserves_complete_state_and_records_context_mismatch(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = {
            "count": 3,
            "minimumIntervalMillis": 1000,
            "context": "portal",
            "includeHDRFallback": True,
        }
        playback_states = [
            {
                "session": "session-a",
                "streamEpoch": str(41 + index),
                "presentation": presentation,
                "lifecycle": "Playing",
                "providerProjectionKind": "HalfEquirectangular",
                "sampleProjectionKind": "HalfEquirectangular",
                "rendererProjectionKind": renderer_projection,
                "rendererViewPackingKind": "SideBySide",
                "displayedPixel": displayed_pixel,
                "error": issue,
                "futurePlaybackField": f"preserved-{index}",
            }
            for index, (presentation, renderer_projection, displayed_pixel, issue) in enumerate(
                (
                    ("portal", "HalfEquirectangular", "true", "none"),
                    ("window", "Rectangular", "false", "decodeFailed"),
                    ("portal", "HalfEquirectangular", "true", "none"),
                )
            )
        ]
        control_planes = [
            {
                "session": "session-a",
                "streamEpoch": str(41 + index),
                "presentation": presentation,
                "projection": projection,
                "sourceContentKind": source_kind,
                "providerProjectionKind": "HalfEquirectangular",
                "sampleProjectionKind": "HalfEquirectangular",
                "rendererProjectionKind": renderer_projection,
                "rendererViewPackingKind": packing,
                "corePresentationDisplayedPixel": displayed_pixel,
                "error": issue,
                "futureControlPlaneField": f"preserved-{index}",
            }
            for index, (
                presentation,
                projection,
                source_kind,
                renderer_projection,
                packing,
                displayed_pixel,
                issue,
            ) in enumerate(
                (
                    (
                        "portal",
                        "equirectangular180",
                        "halfEquirectangular",
                        "HalfEquirectangular",
                        "SideBySide",
                        "true",
                        "none",
                    ),
                    (
                        "window",
                        "flat",
                        "rectilinear",
                        "Rectangular",
                        "Mono",
                        "false",
                        "decodeFailed",
                    ),
                    (
                        "portal",
                        "equirectangular180",
                        "halfEquirectangular",
                        "HalfEquirectangular",
                        "SideBySide",
                        "true",
                        "none",
                    ),
                )
            )
        ]
        responses: list[dict[str, object]] = []
        for index, (playback_state, control_plane) in enumerate(
            zip(playback_states, control_planes, strict=True)
        ):
            responses.extend(
                (
                    {
                        "success": True,
                        "localScreenshotPath": f"frame-{index}.png",
                        "matchedElement": {
                            "label": ";".join(
                                f"{key}={value}" for key, value in playback_state.items()
                            )
                        },
                    },
                    {
                        "success": True,
                        "matchedElement": {
                            "value": ";".join(
                                f"{key}={value}" for key, value in control_plane.items()
                            )
                        },
                    },
                )
            )
        responses.append({"success": True, "matchedElement": None})

        with (
            mock.patch.object(backend, "_controller", side_effect=responses) as controller,
            mock.patch.object(adapter.time, "monotonic", return_value=1.0),
            mock.patch.object(adapter.time, "sleep"),
        ):
            result = backend._evidence_capture_frames_1(arguments, self.device)

        self.assertTrue(result["succeeded"])
        self.assertEqual(len(result["frames"]), 3)
        for index, frame in enumerate(result["frames"]):
            self.assertEqual(frame["playbackState"]["fields"], playback_states[index])
            self.assertEqual(frame["controlPlane"]["fields"], control_planes[index])
            self.assertTrue(frame["playbackState"]["available"])
            self.assertTrue(frame["controlPlane"]["available"])
            self.assertEqual(frame["record"], frame["playbackState"]["response"])
            self.assertEqual(
                frame["record"]["localScreenshotPath"], f"frame-{index}.png"
            )
            self.assertEqual(
                frame["presentationObservation"],
                {
                    "expected": "portal",
                    "observed": playback_states[index]["presentation"],
                },
            )
        self.assertEqual(result["frames"][1]["playbackState"]["fields"]["error"], "decodeFailed")
        self.assertEqual(result["frames"][1]["controlPlane"]["fields"]["projection"], "flat")
        self.assertFalse(result["hdrFallback"]["available"])
        self.assertEqual(
            controller.call_args_list,
            [
                call
                for _ in range(3)
                for call in (
                    mock.call(
                        self.device,
                        "snapshot",
                        "--identifier",
                        "PlayerUI-playback-state",
                    ),
                    mock.call(
                        self.device,
                        "snapshot",
                        "--identifier",
                        "PlayerUI-window-control-plane",
                        "--no-screenshot",
                    ),
                )
            ]
            + [
                mock.call(
                    self.device,
                    "snapshot",
                    "--identifier",
                    "PlayerUI-VideoFormat-HDRFallback",
                    "--no-screenshot",
                )
            ],
        )

    def test_frame_capture_can_bind_only_the_closed_webdav_playback_observation(self) -> None:
        spec = adapter.SPECS["operation:evidence.capture-frames@1"]
        arguments = {
            **VALID_ARGUMENTS["operation:evidence.capture-frames@1"],
            "remoteExpectation": "webdav-playback-range",
            "remoteGenerationToken": "result://call:webdav-source-lifecycle:open:01/generationToken",
            "productBindingDigest": "result://call:webdav-source-lifecycle:open:08/bindingDigest",
        }
        self.assertEqual(dict(spec.validate("device", arguments)), arguments)
        for invalid in (
            {**arguments, "remoteExpectation": "finite-backoff"},
            {
                **VALID_ARGUMENTS["operation:evidence.capture-frames@1"],
                "includeHDRFallback": False,
            },
            {
                key: value
                for key, value in arguments.items()
                if key != "productBindingDigest"
            },
            {
                **VALID_ARGUMENTS["operation:evidence.capture-frames@1"],
                "remoteGenerationToken": arguments["remoteGenerationToken"],
            },
        ):
            with self.subTest(arguments=invalid), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", invalid)

        backend = adapter.ResidentOperationBackend()
        runtime_arguments = {
            **arguments,
            "remoteGenerationToken": "7",
            "productBindingDigest": "sha256:" + "8" * 64,
        }
        remote_observation = {
            "expectation": "webdav-playback-range",
            "traceLines": ["remoteBinding {}"],
        }
        with (
            mock.patch.object(
                backend, "_controller", return_value={"success": True}
            ),
            mock.patch.object(
                backend,
                "_remote_observation",
                return_value=remote_observation,
            ) as remote,
            mock.patch.object(adapter.time, "monotonic", return_value=1.0),
            mock.patch.object(adapter.time, "sleep"),
        ):
            result = backend._evidence_capture_frames_1(
                runtime_arguments, self.device
            )
        self.assertEqual(result["remoteObservation"], remote_observation)
        for frame in result["frames"]:
            self.assertFalse(frame["playbackState"]["available"])
            self.assertFalse(frame["controlPlane"]["available"])
            self.assertEqual(frame["playbackState"]["fields"], {})
            self.assertEqual(frame["controlPlane"]["fields"], {})
            self.assertEqual(
                frame["presentationObservation"],
                {"expected": "open", "observed": None},
            )
        remote.assert_called_once_with(runtime_arguments)

    def test_frame_capture_artwork_variant_is_read_only(self) -> None:
        spec = adapter.SPECS["operation:evidence.capture-frames@1"]
        arguments = {
            "count": 4,
            "minimumIntervalMillis": 0,
            "context": "window",
            "artworkExpectation": "exit-replaces-current-frame",
        }
        self.assertEqual(dict(spec.validate("device", arguments)), arguments)
        for invalid in (
            {**arguments, "count": 3},
            {**arguments, "remoteExpectation": "webdav-playback-range"},
            {
                **VALID_ARGUMENTS["operation:evidence.capture-frames@1"],
                "artworkExpectation": "anything",
            },
        ):
            with self.subTest(arguments=invalid), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", invalid)

        key = "media-" + "1" * 64
        first = "sha256:" + "2" * 64
        second = "sha256:" + "3" * 64

        def probe(
            *, current: str = "none", stored: str = "none"
        ) -> dict[str, object]:
            return {
                "success": True,
                "payload": [
                    "schema=enchron.regression.artwork-probe@1",
                    f"artworkKey={key}",
                    f"currentDigest={current}",
                    f"storedDigest={stored}",
                    "currentWidth=1920",
                    "currentHeight=1080",
                    "storedBytes=0" if stored == "none" else "storedBytes=8192",
                    "byteStreamScope=none",
                    "byteStreamRequestCount=none",
                ],
            }

        backend = adapter.ResidentOperationBackend()
        with (
            mock.patch.object(
                backend,
                "_app_command",
                side_effect=(
                    probe(current=first),
                    probe(current=first, stored=second),
                ),
            ) as app_command,
            mock.patch.object(
                backend, "_controller", return_value={"success": True}
            ) as controller,
            mock.patch.object(adapter.time, "monotonic", return_value=1.0),
        ):
            result = backend._evidence_capture_frames_1(arguments, self.device)

        self.assertTrue(result["succeeded"])
        self.assertEqual(len(result["frames"]), 4)
        self.assertTrue(result["artworkObservation"]["readOnly"])
        self.assertEqual(
            result["artworkObservation"]["before"]["currentDigest"], first
        )
        self.assertEqual(
            result["artworkObservation"]["after"]["storedDigest"], second
        )
        self.assertNotEqual(first, second)
        self.assertEqual(
            [call.args[1] for call in app_command.call_args_list],
            ["artworkProbe", "artworkProbe"],
        )
        self.assertEqual(
            sum(call.args[1] == "snapshot" for call in controller.call_args_list),
            8,
        )
        self.assertEqual(
            {call.args[1] for call in controller.call_args_list}, {"snapshot"}
        )

    def test_finite_backoff_surface_observation_binds_receipt_log_and_restore(self) -> None:
        backend = adapter.ResidentOperationBackend()
        with tempfile.TemporaryDirectory(prefix="surface-remote-test-") as directory:
            root = Path(directory).resolve()
            log_path = root / "generation-4.jsonl"
            entries = []
            for index, (status, clock, backoff) in enumerate(
                (
                    (503, 1_000, 250),
                    (503, 1_250, 500),
                    (503, 1_750, 1_000),
                    (206, 2_750, None),
                ),
                start=1,
            ):
                entries.append(
                    {
                        "schema": "enchron.regression.remote-source-request@1",
                        "sequence": index,
                        "generation": 4,
                        "recipe": "finite-reconnect",
                        "time": f"2026-08-29T00:00:0{index}.000000Z",
                        "monotonicMillis": clock,
                        "method": "GET",
                        "path": "/dav/g-000004/fixture.mkv",
                        "range": "bytes=0-63",
                        "status": status,
                        "declaredBytes": 0 if status == 503 else 64,
                        "responseBytes": 0 if status == 503 else 64,
                        "condition": (
                            "first-three-ranged-reads" if status == 503 else "none"
                        ),
                        "triggered": status == 503,
                        "recipeReadOrdinal": index,
                        "expectedBackoffMillis": backoff,
                        "disconnectOwner": (
                            "remote-source-recipe" if status == 503 else "none"
                        ),
                    }
                )
            log_path.write_text(
                "".join(json.dumps(item, sort_keys=True) + "\n" for item in entries),
                encoding="utf-8",
            )
            receipt = {
                "schema": "enchron.regression.remote-source-receipt@1",
                "receiptID": "receipt:g-000004:finite-reconnect",
                "recipe": "finite-reconnect",
                "generation": 4,
                "endpointDigest": "sha256:" + "1" * 64,
                "activationTime": "2026-08-29T00:00:00.000000Z",
                "priorStateDigest": "sha256:" + "2" * 64,
                "terminalStateDigest": "sha256:" + "3" * 64,
                "restoredStateDigest": "sha256:" + "4" * 64,
                "logPath": str(log_path),
                "logDigest": "sha256:" + hashlib.sha256(log_path.read_bytes()).hexdigest(),
                "objectManifestHashes": {"fixture": "sha256:" + "5" * 64},
                "priorCertificateFingerprint": "sha256:" + "6" * 64,
                "certificateFingerprint": "sha256:" + "6" * 64,
            }
            terminal = {
                "recipe": "healthy",
                "generation": 5,
                "endpointDigest": "sha256:" + "7" * 64,
                "certificateFingerprint": "sha256:" + "6" * 64,
            }
            controller = mock.Mock()
            controller.receipt.return_value = receipt
            controller.status.return_value = terminal
            with mock.patch.object(
                adapter._remote_preflight.remote,
                "RemoteSourceController",
                return_value=controller,
            ), mock.patch.object(
                backend,
                "_remote_preflight_configuration",
                return_value=mock.Mock(service=object()),
            ):
                observation = backend._remote_observation(
                    {
                        "remoteExpectation": "finite-backoff",
                        "remoteReceiptID": receipt["receiptID"],
                        "restoredGenerationToken": "5",
                        "productBindingDigest": "sha256:" + "8" * 64,
                    }
                )

            self.assertEqual(observation["recipe"], "finite-reconnect")
            self.assertEqual(observation["generation"], 4)
            self.assertEqual(observation["restoredGeneration"], 5)
            self.assertEqual(observation["backoffMillis"], [250, 500, 1000])
            self.assertEqual(
                observation["observedRequestIntervalsMillis"], [250, 500, 1000]
            )
            self.assertEqual(observation["rangeRequests"], ["bytes=0-63"] * 4)
            self.assertEqual(
                observation["productBindingDigest"], "sha256:" + "8" * 64
            )
            self.assertTrue(
                all(
                    "Authorization" not in line
                    for line in observation["traceLines"]
                )
            )

            entries[2]["monotonicMillis"] = 1_300
            log_path.write_text(
                "".join(json.dumps(item, sort_keys=True) + "\n" for item in entries),
                encoding="utf-8",
            )
            receipt["logDigest"] = (
                "sha256:" + hashlib.sha256(log_path.read_bytes()).hexdigest()
            )
            with (
                mock.patch.object(
                    adapter._remote_preflight.remote,
                    "RemoteSourceController",
                    return_value=controller,
                ),
                mock.patch.object(
                    backend,
                    "_remote_preflight_configuration",
                    return_value=mock.Mock(service=object()),
                ),
            ):
                drifted = backend._remote_observation(
                    {
                        "remoteExpectation": "finite-backoff",
                        "remoteReceiptID": receipt["receiptID"],
                        "restoredGenerationToken": "5",
                        "productBindingDigest": "sha256:" + "8" * 64,
                    }
                )
            self.assertEqual(
                drifted["expectationObservation"]["expectedBackoffMillis"],
                [250, 500, 1000],
            )
            self.assertEqual(
                drifted["expectationObservation"][
                    "observedRequestIntervalsMillis"
                ],
                [250, 50, 1450],
            )

    def test_format_apply_accepts_only_exact_custom_angle_coverage(self) -> None:
        spec = adapter.SPECS["operation:format.apply@2"]
        for degrees in range(180, 361, 10):
            expected = {
                "projection": "customAngle",
                "horizontalCoverageDegrees": degrees,
                "stereoLayout": "mono",
                "deadlineSeconds": 30,
            }
            with self.subTest(degrees=degrees):
                self.assertEqual(dict(spec.validate("device", expected)), expected)

        invalid = (
            {key: value for key, value in expected.items() if key != "horizontalCoverageDegrees"},
            {**expected, "horizontalCoverageDegrees": 179},
            {**expected, "horizontalCoverageDegrees": 361},
            {**expected, "horizontalCoverageDegrees": 205},
            {
                **expected,
                "projection": "flat",
                "horizontalCoverageDegrees": 200,
            },
        )
        for arguments in invalid:
            with self.subTest(arguments=arguments), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", arguments)

    def test_format_apply_summons_hidden_chrome_and_preserves_mismatched_observation(self) -> None:
        backend = adapter.ResidentOperationBackend()
        before_fields = {
            "presentation": "window",
            "lifecycle": "Playing",
            "controls": "hidden",
            "transition": "none",
            "projection": "flat",
            "horizontalFieldOfViewDegrees": "200",
            "stereoLayout": "mono",
        }
        observed_fields = {
            **before_fields,
            "controls": "shown",
            "projection": "equirectangular360",
            "horizontalFieldOfViewDegrees": "360",
        }
        before = {
            "succeeded": True,
            "fields": before_fields,
            "response": {"success": True, "commandID": "before"},
        }
        after = {
            "succeeded": True,
            "fields": observed_fields,
            "response": {"success": True, "commandID": "after"},
        }
        settlement = {
            "succeeded": False,
            "reason": "deadline-expired",
            "observations": [{"elapsedMillis": 10, "fields": observed_fields}],
            "lastController": {"success": True, "commandID": "settlement"},
        }
        arguments = {
            "projection": "equirectangular180",
            "stereoLayout": "sideBySide",
            "deadlineSeconds": 30,
        }
        with (
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                side_effect=[before, after],
            ) as diagnostics,
            mock.patch.object(
                backend,
                "_app_command",
                return_value={"ok": True, "payload": ["true"]},
            ) as app_command,
            mock.patch.object(
                backend, "_controller", return_value={"success": True}
            ) as controller,
            mock.patch.object(
                backend, "_wait_for_window", return_value=settlement
            ) as wait_for_window,
        ):
            result = backend._format_apply_2(arguments, self.device)

        self.assertEqual(diagnostics.call_count, 2)
        app_command.assert_called_once_with(
            self.device,
            "toggleControls",
            "visible=true",
        )
        controller.assert_called_once_with(
            self.device,
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-videoFormat",
            "PlayerUI-VideoFormat-Projection-180°",
            "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side",
            "PlayerUI-VideoFormat-apply",
        )
        wait_for_window.assert_called_once_with(
            self.device,
            presentation="either-main-window",
            lifecycle="any-steady",
            controls="either",
            deadline_seconds=30,
        )
        self.assertTrue(result["succeeded"])
        self.assertEqual(result["requested"]["projection"], "equirectangular180")
        self.assertEqual(result["before"], before)
        self.assertEqual(result["after"], after)
        self.assertEqual(
            result["formatObservation"],
            {
                "expected": {
                    "presentation": "portal",
                    "projection": "equirectangular180",
                    "horizontalFieldOfViewDegrees": "180",
                    "stereoLayout": "sideBySide",
                },
                "observed": {
                    "presentation": "window",
                    "projection": "equirectangular360",
                    "horizontalFieldOfViewDegrees": "360",
                    "stereoLayout": "mono",
                },
            },
        )

    def test_format_apply_drives_the_real_custom_angle_picker_and_verifies_terminal_format(self) -> None:
        backend = adapter.ResidentOperationBackend()
        before = {
            "presentation": "window",
            "lifecycle": "Playing",
            "controls": "shown",
            "transition": "none",
            "projection": "flat",
            "horizontalFieldOfViewDegrees": "200",
            "stereoLayout": "mono",
        }
        terminal = {
            **before,
            "presentation": "portal",
            "projection": "customAngle",
            "horizontalFieldOfViewDegrees": "240",
            "stereoLayout": "sideBySide",
        }
        before_observation = {
            "succeeded": True,
            "fields": before,
            "response": {"success": True, "commandID": "before"},
        }
        terminal_observation = {
            "succeeded": True,
            "fields": terminal,
            "response": {"success": True, "commandID": "after"},
        }
        arguments = {
            "projection": "customAngle",
            "horizontalCoverageDegrees": 240,
            "stereoLayout": "sideBySide",
            "deadlineSeconds": 30,
        }
        with (
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                side_effect=[before_observation, terminal_observation],
            ),
            mock.patch.object(
                backend,
                "_app_command",
                return_value={"ok": True, "payload": ["true"]},
            ) as app_command,
            mock.patch.object(
                backend, "_controller", return_value={"success": True}
            ) as controller,
            mock.patch.object(
                backend,
                "_wait_for_window",
                return_value={
                    "succeeded": True,
                    "terminal": terminal,
                    "observations": [],
                },
            ),
        ):
            result = backend._format_apply_2(arguments, self.device)

        self.assertTrue(result["succeeded"])
        self.assertEqual(result["settlement"]["terminal"], terminal)
        self.assertEqual(result["after"], terminal_observation)
        app_command.assert_called_once_with(
            self.device,
            "toggleControls",
            "visible=true",
        )
        self.assertEqual(
            controller.call_args_list,
            [
                mock.call(
                    self.device,
                    "tapSequence",
                    "--identifiers",
                    "PlayerUI-TopAction-videoFormat",
                    "PlayerUI-VideoFormat-CustomAngle",
                    "PlayerUI-VideoFormat-CustomAngle-240",
                    "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side",
                    "PlayerUI-VideoFormat-apply",
                ),
            ],
        )

    def test_format_apply_preserves_terminal_projection_or_coverage_difference_for_oracle(self) -> None:
        backend = adapter.ResidentOperationBackend()
        before = {
            "presentation": "window",
            "lifecycle": "Playing",
            "controls": "shown",
            "transition": "none",
            "projection": "flat",
            "horizontalFieldOfViewDegrees": "200",
            "stereoLayout": "mono",
        }
        wrong_terminals = (
            {
                **before,
                "presentation": "portal",
                "projection": "equirectangular360",
                "horizontalFieldOfViewDegrees": "240",
            },
            {
                **before,
                "presentation": "portal",
                "projection": "customAngle",
                "horizontalFieldOfViewDegrees": "230",
            },
        )
        for wrong_terminal in wrong_terminals:
            with (
                self.subTest(terminal=wrong_terminal),
                mock.patch.object(
                    backend,
                    "_window_control_plane_observation",
                    side_effect=[
                        {
                            "succeeded": True,
                            "fields": before,
                            "response": {"success": True, "commandID": "before"},
                        },
                        {
                            "succeeded": True,
                            "fields": wrong_terminal,
                            "response": {"success": True, "commandID": "after"},
                        },
                    ],
                ),
                mock.patch.object(
                    backend,
                    "_app_command",
                    return_value={"ok": True, "payload": ["true"]},
                ),
                mock.patch.object(
                    backend, "_controller", return_value={"success": True}
                ),
                mock.patch.object(
                    backend,
                    "_wait_for_window",
                    return_value={
                        "succeeded": True,
                        "terminal": wrong_terminal,
                        "observations": [],
                    },
                ),
            ):
                result = backend._format_apply_2(
                    {
                        "projection": "customAngle",
                        "horizontalCoverageDegrees": 240,
                        "stereoLayout": "mono",
                        "deadlineSeconds": 30,
                    },
                    self.device,
                )
            self.assertTrue(result["succeeded"])
            self.assertEqual(
                result["formatObservation"]["observed"]["projection"],
                wrong_terminal["projection"],
            )
            self.assertEqual(
                result["formatObservation"]["observed"][
                    "horizontalFieldOfViewDegrees"
                ],
                wrong_terminal["horizontalFieldOfViewDegrees"],
            )

    def test_playback_state_flattens_referenceable_identity_fields(self) -> None:
        backend = adapter.ResidentOperationBackend()
        fields = {
            "session": "session-a",
            "audioTrack": "2",
            "mediaName": "fixture.mkv",
            "position": "12.0",
        }
        with mock.patch.object(
            backend,
            "_read_control_plane",
            return_value=(fields, {"success": True}),
        ):
            result = backend._diagnostics_playback_state_1({}, self.device)
        self.assertEqual(result["session"], "session-a")
        self.assertEqual(result["audioTrack"], "2")
        self.assertEqual(result["mediaName"], "fixture.mkv")
        self.assertEqual(result["fields"], fields)

        del fields["audioTrack"]
        with mock.patch.object(
            backend,
            "_read_control_plane",
            return_value=(fields, {"success": True}),
        ):
            missing = backend._diagnostics_playback_state_1({}, self.device)
        self.assertEqual(missing["audioTrack"], "unavailable")
        self.assertEqual(missing["missingIdentityFields"], ["audioTrack"])

    def test_playback_state_flattens_remote_identity_before_fault_activation(self) -> None:
        backend = adapter.ResidentOperationBackend()
        fields = remote_playback_fields()
        expected_topology = adapter.playback_topology_digest(fields)
        with mock.patch.object(
            backend,
            "_read_control_plane",
            return_value=(fields, {"success": True}),
        ):
            result = backend._diagnostics_playback_state_1({}, self.device)

        self.assertEqual(result["sourceIdentity"], fields["sourceIdentity"])
        self.assertEqual(result["contentRevision"], fields["contentRevision"])
        self.assertEqual(result["topologyDigest"], expected_topology)

    def test_playback_state_remote_expectations_are_closed_and_reference_bound(self) -> None:
        spec = adapter.SPECS["operation:diagnostics.playback-state@1"]
        webdav = {
            "expectation": "webdav-loopback",
            "minimumPositionMillis": 1_000,
        }
        recovery = {
            "expectation": "recoverable-read",
            "expectedSession": "result://call:network-resilience:recoverable:07/session",
            "expectedSourceIdentity": "result://call:network-resilience:recoverable:07/sourceIdentity",
            "expectedContentRevision": "result://call:network-resilience:recoverable:07/contentRevision",
            "expectedTopologyDigest": "result://call:network-resilience:recoverable:07/topologyDigest",
            "minimumPositionMillis": 5_000,
            "minimumReconnects": 1,
        }
        finite = {
            **recovery,
            "expectation": "finite-reconnect",
            "minimumReconnects": 3,
        }
        for arguments in (webdav, recovery, finite):
            with self.subTest(arguments=arguments):
                self.assertEqual(dict(spec.validate("device", arguments)), arguments)

        invalid = (
            {"expectation": "arbitrary"},
            {"expectation": "recoverable-read", "minimumReconnects": 1},
            {**recovery, "minimumReconnects": 0},
            {**finite, "minimumReconnects": 2},
            {
                **recovery,
                "expectedSession": "result://call:network-resilience:recoverable:07/mediaName",
            },
            {"minimumPositionMillis": 1_000},
        )
        for arguments in invalid:
            with self.subTest(arguments=arguments), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", arguments)

    def test_playback_state_remote_binding_validates_product_identity_and_topology(self) -> None:
        backend = adapter.ResidentOperationBackend()
        fields = remote_playback_fields()
        topology = adapter.playback_topology_digest(fields)
        arguments = {
            "expectation": "finite-reconnect",
            "expectedSession": "session-a",
            "expectedSourceIdentity": fields["sourceIdentity"],
            "expectedContentRevision": fields["contentRevision"],
            "expectedTopologyDigest": topology,
            "minimumPositionMillis": 5_000,
            "minimumReconnects": 3,
        }
        with mock.patch.object(
            backend,
            "_read_control_plane",
            return_value=(fields, {"success": True}),
        ):
            result = backend._diagnostics_playback_state_1(arguments, self.device)

        self.assertEqual(result["session"], "session-a")
        self.assertEqual(result["sourceIdentity"], fields["sourceIdentity"])
        self.assertEqual(result["contentRevision"], fields["contentRevision"])
        self.assertEqual(result["topologyDigest"], topology)
        self.assertEqual(result["positionMillis"], 12_500)
        self.assertEqual(result["demuxReconnects"], 3)
        self.assertRegex(result["bindingDigest"], r"^sha256:[0-9a-f]{64}$")
        self.assertNotIn("http", json.dumps(result["binding"], sort_keys=True))

        failures = (
            ({**fields, "session": "session-b"}, "session", "session-b"),
            ({**fields, "playbackAddressKind": "remote-url"}, "playbackAddressKind", "remote-url"),
            ({**fields, "collectionOrigin": "mediaLibrary"}, "collectionOrigin", "mediaLibrary"),
            ({**fields, "position": "1.0"}, "positionMillis", 1_000),
            ({**fields, "demuxReconnects": "2"}, "demuxReconnects", 2),
            ({**fields, "error": "connection-interrupted"}, "issueCategory", "connection-interrupted"),
        )
        for wrong, field, value in failures:
            with self.subTest(field=field), mock.patch.object(
                backend,
                "_read_control_plane",
                return_value=(wrong, {"success": True}),
            ):
                observed = backend._diagnostics_playback_state_1(
                    arguments, self.device
                )
            self.assertTrue(observed["succeeded"])
            observation = observed["expectationObservation"]
            if field == "session":
                self.assertEqual(observation["observed"][field], value)
            else:
                self.assertEqual(observation[field], value)

    def test_main_view_playback_probe_exposes_narrow_remote_identity_fields(self) -> None:
        source = (adapter.REPOSITORY_ROOT / "Apps/Enchron/MainView.swift").read_text(
            encoding="utf-8"
        )
        for field in (
            "playbackAddressKind",
            "collectionOrigin",
            "sourceIdentity",
            "contentRevision",
        ):
            self.assertGreaterEqual(source.count(f'"{field}=\\('), 2, field)

    def test_certificate_boundary_probe_records_order_phase_and_redacted_identity(self) -> None:
        prompt = (
            adapter.REPOSITORY_ROOT / "Apps/Enchron/CertificateTrustPrompt.swift"
        ).read_text(encoding="utf-8")
        modal = (
            adapter.REPOSITORY_ROOT
            / "Apps/Enchron/AppModalPresentationCoordinator.swift"
        ).read_text(encoding="utf-8")
        application = (
            adapter.REPOSITORY_ROOT / "Apps/Enchron/EnchronApplication.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("certificateBoundary promptPresented", prompt)
        self.assertIn("certificateBoundary decision", prompt)
        self.assertIn("certificateBoundary modalDismissed", modal)
        self.assertIn("certificateBoundary promptRequested", application)
        self.assertIn('phase=\\(phase)', application)
        combined = prompt + modal + application
        self.assertNotIn("certificateBoundary password", combined)

    def test_certificate_change_observation_binds_issue_close_and_preserved_trust(self) -> None:
        previous = "sha256:" + "a" * 64
        current = "sha256:" + "b" * 64
        lines = [
            "certificateBoundary changed previous="
            + ":".join(["AA"] * 32)
            + " new="
            + ":".join(["BB"] * 32),
            "reachability playback issue delivered location=mainWindow action=close",
        ]
        remote = {
            "priorCertificateFingerprint": previous,
            "certificateFingerprint": current,
        }
        interruption = {
            "before": {
                "active": "true",
                "lifecycle": "Paused",
                "error": "server-certificate-changed",
                "transition": "none",
                "presentation": "window",
            },
            "after": {
                "active": "false",
                "lifecycle": "Idle",
                "error": "none",
                "session": "none",
                "transition": "none",
            },
            "trust": {
                "storedFingerprint": previous,
                "previousFingerprint": previous,
                "currentFingerprint": current,
                "currentFingerprintTrusted": "false",
            },
        }

        observation = adapter.certificate_change_observation(
            lines, remote, interruption
        )
        self.assertEqual(len(observation["deliveredCloseEvents"]), 1)
        self.assertEqual(observation["storedFingerprintAfterClose"], previous)
        self.assertEqual(observation["currentFingerprintTrustedAfterClose"], "false")

        prompt_observation = adapter.certificate_change_observation(
            lines
            + [
                "certificateBoundary promptRequested phase=playback "
                "address=host:8443 fingerprint=BB"
            ],
            remote,
            interruption,
        )
        self.assertEqual(
            prompt_observation["expectationObservation"]["observed"][
                "playbackPromptCount"
            ],
            1,
        )

        identity_observation = adapter.certificate_change_observation(
            lines,
            {**remote, "certificateFingerprint": "sha256:" + "c" * 64},
            interruption,
        )
        self.assertNotEqual(
            identity_observation["expectationObservation"]["expected"][
                "deliveredFingerprintPair"
            ],
            identity_observation["expectationObservation"]["observed"][
                "deliveredFingerprintPair"
            ],
        )

        trust_observation = adapter.certificate_change_observation(
            lines,
            remote,
            {
                **interruption,
                "trust": {
                    **interruption["trust"],
                    "currentFingerprintTrusted": "true",
                },
            },
        )
        self.assertEqual(
            trust_observation["expectationObservation"]["observed"][
                "currentFingerprintTrustedAfterClose"
            ],
            "true",
        )

    def test_test_command_channel_exposes_closed_certificate_trust_probe(self) -> None:
        source = (adapter.REPOSITORY_ROOT / "Apps/Enchron/TestCommandChannel.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn('case "certificateTrustProbe":', source)
        self.assertIn(
            "schema=enchron.regression.certificate-trust-probe@1", source
        )
        self.assertIn('"currentFingerprintTrusted=false"', source)

    def test_certificate_surface_observation_requires_two_connection_decisions_in_order(self) -> None:
        backend = adapter.ResidentOperationBackend()
        lines = [
            "probe-sequence=1",
            "certificateBoundary promptRequested phase=connection address=host:8443 fingerprint=A",
            "certificateBoundary modalDismissed id=source-connection",
            "certificateBoundary promptPresented address=host:8443 name=localhost fingerprint=A validFrom=1 validUntil=2",
            "certificateBoundary decision approved=false address=host:8443 fingerprint=A",
            "certificateBoundary promptRequested phase=connection address=host:8443 fingerprint=A",
            "certificateBoundary modalDismissed id=source-connection",
            "certificateBoundary promptPresented address=host:8443 name=localhost fingerprint=A validFrom=1 validUntil=2",
            "certificateBoundary decision approved=true address=host:8443 fingerprint=A",
            "openRequestForwarded",
        ]
        matrix = mock.Mock()
        cursor_type = type("Cursor", (), {})
        matrix.ProbeCursor.side_effect = lambda sequence, line_count: type(
            "CursorValue",
            (),
            {"sequence": sequence, "line_count": line_count},
        )()
        observed = cursor_type()
        observed.sequence = 1
        observed.line_count = len(lines)
        matrix.probe_cursor.return_value = observed
        matrix.probe_lines_since.return_value = (
            lines[1:],
            observed,
            None,
        )
        with (
            mock.patch.object(backend, "_matrix", return_value=matrix),
            mock.patch.object(backend, "_probe_lines", return_value=lines),
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                return_value={
                    "succeeded": True,
                    "fields": {"lifecycle": "Playing"},
                    "response": {"success": True},
                },
            ),
            mock.patch.object(
                backend,
                "_remote_observation",
                return_value={"traceLines": ["remoteBinding {}"]},
            ),
        ):
            result = backend._diagnostics_surface_probe_1(
                {
                    "cursorToken": "1:1",
                    "remoteExpectation": "certificate-trust-boundary",
                    "remoteGenerationToken": "2",
                },
                self.device,
            )
        self.assertEqual(result["certificateBoundary"]["decisions"], [False, True])
        self.assertEqual(
            result["certificateBoundary"]["orderedAttempts"],
            [True, True],
        )
        self.assertEqual(result["certificateBoundary"]["fingerprints"], ["A", "A"])

        bad = list(lines)
        bad[2], bad[3] = bad[3], bad[2]
        matrix.probe_lines_since.return_value = (
            bad[1:],
            observed,
            None,
        )
        with (
            mock.patch.object(backend, "_matrix", return_value=matrix),
            mock.patch.object(backend, "_probe_lines", return_value=bad),
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                return_value={
                    "succeeded": True,
                    "fields": {"lifecycle": "Playing"},
                    "response": {"success": True},
                },
            ),
            mock.patch.object(
                backend,
                "_remote_observation",
                return_value={"traceLines": ["remoteBinding {}"]},
            ),
        ):
            bad_result = backend._diagnostics_surface_probe_1(
                {
                    "cursorToken": "1:1",
                    "remoteExpectation": "certificate-trust-boundary",
                    "remoteGenerationToken": "2",
                },
                self.device,
            )
        self.assertFalse(
            bad_result["certificateBoundary"]["orderedAttempts"][0]
        )

    def test_finite_backoff_surface_probe_keeps_playback_binding(self) -> None:
        backend = adapter.ResidentOperationBackend()
        cursor = type("Cursor", (), {"sequence": 4, "line_count": 0})()
        matrix = mock.Mock()
        matrix.probe_cursor.return_value = cursor
        control_plane = {
            "succeeded": True,
            "fields": {"lifecycle": "Playing", "controls": "shown"},
            "response": {"success": True},
        }
        playback = {
            "succeeded": True,
            "fields": {
                "demuxReconnects": "3",
                "session": "session-a",
                "lifecycle": "Playing",
                "position": "12.5",
            },
            "response": {"success": True},
            "topologyDigest": "sha256:" + "1" * 64,
        }
        with (
            mock.patch.object(backend, "_matrix", return_value=matrix),
            mock.patch.object(backend, "_probe_lines", return_value=[]),
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                return_value=control_plane,
            ),
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                return_value=playback,
            ) as playback_state,
            mock.patch.object(
                backend,
                "_remote_observation",
                return_value={"traceLines": ["remoteBinding {}"]},
            ),
        ):
            result = backend._diagnostics_surface_probe_1(
                {"remoteExpectation": "finite-backoff"}, self.device
            )

        self.assertIs(result["playbackObservation"], playback)
        self.assertIs(result["fields"], control_plane["fields"])
        self.assertIs(result["response"], control_plane["response"])
        playback_state.assert_called_once_with({}, self.device)

    def test_surface_probe_captures_one_closed_viewing_storage_snapshot(self) -> None:
        spec = adapter.SPECS["operation:diagnostics.surface-probe@1"]
        self.assertEqual(
            dict(spec.validate("device", {"includeViewingStorage": True})),
            {"includeViewingStorage": True},
        )
        with self.assertRaises(adapter.OperationAdapterError):
            spec.validate("device", {"includeViewingStorage": "yes"})
        self.assertEqual(
            dict(
                spec.validate(
                    "device",
                    {
                        "includeViewingStorage": True,
                        "priorViewingStorageDigests": [
                            "result://call:viewing-storage:before:01/viewingStorageDigest"
                        ],
                        "awaitEmptyStores": ["artwork", "container-index"],
                        "deadlineSeconds": 30,
                    },
                )
            )["deadlineSeconds"],
            30,
        )
        for invalid in (
            {"includeViewingStorage": False},
            {"awaitEmptyStores": ["artwork"], "deadlineSeconds": 5},
            {
                "includeViewingStorage": True,
                "awaitEmptyStores": ["viewing-state"],
            },
            {
                "includeViewingStorage": True,
                "priorViewingStorageDigests": ["sha256:bad"],
            },
        ):
            with self.subTest(invalid=invalid), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", invalid)

        digest = "sha256:" + "1" * 64
        snapshot = {
            "schema": "enchron.regression.viewing-storage-state@1",
            "viewingState": {
                "schema": "enchron.regression.viewing-state-store@1",
                "storeIdentity": "user-defaults:test",
                "persistedRecordCount": 0,
                "persistedBytes": 0,
                "invalidRecordCount": 0,
                "viewingRecordCount": 0,
                "resumableCount": 0,
                "completedCount": 0,
                "entries": [],
                "protectedStateDigest": digest,
                "protectedEntries": [],
            },
            "containerIndex": {
                "schema": "enchron.regression.container-index-state@1",
                "cacheIdentity": digest,
                "digest": digest,
                "entryCount": 0,
                "entries": [],
                "totalBytes": 0,
            },
            "artwork": {
                "schema": "enchron.regression.artwork-store-state@1",
                "storeIdentity": digest,
                "digest": digest,
                "entryCount": 0,
                "entries": [],
                "totalBytes": 0,
                "invalidFileCount": 0,
            },
            "protectedState": {
                "schema": "enchron.regression.viewing-storage-protected-state@1",
                "digest": digest,
                "folders": [],
                "references": [],
                "playbackPreferences": {
                    "resumePolicy": "always-resume",
                    "endBehavior": "stop",
                    "defaultSpeed": 1.0,
                    "controlsAutoHideSeconds": 8,
                },
            },
        }
        response = {"success": True, "viewingStorageSnapshot": snapshot}
        backend = adapter.ResidentOperationBackend()
        with mock.patch.object(backend, "_app_command", return_value=response):
            observation = backend._viewing_storage_observation(self.device)
        self.assertEqual(observation["snapshot"], snapshot)
        self.assertIs(observation["response"], response)

        cursor = type("Cursor", (), {"sequence": 4, "line_count": 0})()
        matrix = mock.Mock()
        matrix.probe_cursor.return_value = cursor
        with (
            mock.patch.object(backend, "_matrix", return_value=matrix),
            mock.patch.object(backend, "_probe_lines", return_value=[]),
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                return_value={
                    "succeeded": True,
                    "fields": {"lifecycle": "Playing"},
                    "response": {"success": True},
                },
            ),
            mock.patch.object(
                backend,
                "_viewing_storage_observation",
                return_value=observation,
            ),
        ):
            result = backend._diagnostics_surface_probe_1(
                {"includeViewingStorage": True}, self.device
            )
        self.assertEqual(
            result["viewingStorageObservation"]["snapshot"], snapshot
        )
        self.assertRegex(
            result["viewingStorageDigest"], r"^sha256:[0-9a-f]{64}$"
        )
        self.assertIs(result["viewingStorageResponse"], response)
        for field in (
            "containerIndexOpenScope",
            "containerIndexOpenContentRevision",
            "containerIndexOpenFinished",
            "containerIndexOpenCacheHitRanges",
            "containerIndexOpenSourceReadRanges",
            "containerIndexOpenRecordedRanges",
        ):
            self.assertIsNone(result[field])

        open_revision = "sha256:" + "2" * 64
        remote_snapshot = json.loads(json.dumps(snapshot))
        remote_snapshot["containerIndexOpen"] = {
            "schema": "enchron.regression.media-byte-stream-container-index-open@1",
            "scope": "media-byte-stream:123e4567-e89b-42d3-a456-426614174000",
            "contentRevision": open_revision,
            "containerIndexFinished": True,
            "cacheHitRanges": [
                {
                    "lowerBound": 0,
                    "upperBoundExclusive": 1_024,
                    "bytes": 1_024,
                },
                {
                    "lowerBound": 1_024,
                    "upperBoundExclusive": 2_048,
                    "bytes": 1_024,
                },
            ],
            "sourceReadRanges": [
                {
                    "lowerBound": 8_192,
                    "upperBoundExclusive": 9_216,
                    "bytes": 1_024,
                }
            ],
            "recordedRanges": [
                {
                    "lowerBound": 8_192,
                    "upperBoundExclusive": 9_216,
                    "bytes": 1_024,
                }
            ],
        }
        remote_snapshot["activePlayback"] = {
            "sessionID": "session-first-open",
            "mediaIdentity": "sha256:" + "3" * 64,
            "contentRevision": open_revision,
            "viewingStateAuthority": "media-server",
            "lifecycle": "playing",
            "positionSeconds": 12.5,
            "durationSeconds": 60.0,
            "actualPlaybackSeconds": 12.0,
            "endedNaturally": False,
        }
        remote_response = {
            "success": True,
            "viewingStorageSnapshot": remote_snapshot,
        }
        with mock.patch.object(
            backend, "_app_command", return_value=remote_response
        ):
            remote_observation = backend._viewing_storage_observation(self.device)
        self.assertEqual(remote_observation["snapshot"], remote_snapshot)

        with (
            mock.patch.object(backend, "_matrix", return_value=matrix),
            mock.patch.object(backend, "_probe_lines", return_value=[]),
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                return_value={
                    "succeeded": True,
                    "fields": {"lifecycle": "Playing"},
                    "response": {"success": True},
                },
            ),
            mock.patch.object(
                backend,
                "_viewing_storage_observation",
                return_value=remote_observation,
            ),
        ):
            remote_result = backend._diagnostics_surface_probe_1(
                {"includeViewingStorage": True}, self.device
            )
        open_snapshot = remote_snapshot["containerIndexOpen"]
        self.assertEqual(
            remote_result["containerIndexOpenScope"], open_snapshot["scope"]
        )
        self.assertEqual(
            remote_result["containerIndexOpenContentRevision"], open_revision
        )
        self.assertIs(remote_result["containerIndexOpenFinished"], True)
        self.assertEqual(
            remote_result["containerIndexOpenCacheHitRanges"],
            open_snapshot["cacheHitRanges"],
        )
        self.assertEqual(
            remote_result["containerIndexOpenSourceReadRanges"],
            open_snapshot["sourceReadRanges"],
        )
        self.assertEqual(
            remote_result["containerIndexOpenRecordedRanges"],
            open_snapshot["recordedRanges"],
        )
        binding_lines = [
            line
            for line in remote_result["interactionTrace"]
            if line.startswith("viewingStorageBinding ")
        ]
        self.assertEqual(len(binding_lines), 1)
        binding = json.loads(binding_lines[0].split(" ", 1)[1])
        self.assertEqual(
            binding["snapshot"]["containerIndexOpen"], open_snapshot
        )

        malformed_open = json.loads(json.dumps(remote_snapshot))
        del malformed_open["containerIndexOpen"]["recordedRanges"]
        with (
            mock.patch.object(
                backend,
                "_app_command",
                return_value={
                    "success": True,
                    "viewingStorageSnapshot": malformed_open,
                },
            ),
            self.assertRaisesRegex(
                adapter.OperationAdapterError,
                "containerIndexOpen does not match its closed product schema",
            ),
        ):
            backend._viewing_storage_observation(self.device)

        invalid_range = json.loads(json.dumps(remote_snapshot))
        invalid_range["containerIndexOpen"]["cacheHitRanges"][0]["bytes"] = 512
        with (
            mock.patch.object(
                backend,
                "_app_command",
                return_value={
                    "success": True,
                    "viewingStorageSnapshot": invalid_range,
                },
            ),
            self.assertRaisesRegex(
                adapter.OperationAdapterError,
                "containerIndexOpen range bounds are inconsistent",
            ),
        ):
            backend._viewing_storage_observation(self.device)

        unsorted_ranges = json.loads(json.dumps(remote_snapshot))
        unsorted_ranges["containerIndexOpen"]["cacheHitRanges"].reverse()
        with (
            mock.patch.object(
                backend,
                "_app_command",
                return_value={
                    "success": True,
                    "viewingStorageSnapshot": unsorted_ranges,
                },
            ),
            self.assertRaisesRegex(
                adapter.OperationAdapterError,
                "containerIndexOpen.cacheHitRanges must be canonically sorted",
            ),
        ):
            backend._viewing_storage_observation(self.device)

        mismatched_revision = json.loads(json.dumps(remote_snapshot))
        mismatched_revision["activePlayback"]["contentRevision"] = digest
        with (
            mock.patch.object(
                backend,
                "_app_command",
                return_value={
                    "success": True,
                    "viewingStorageSnapshot": mismatched_revision,
                },
            ),
            self.assertRaisesRegex(
                adapter.OperationAdapterError,
                "containerIndexOpen.contentRevision does not bind activePlayback",
            ),
        ):
            backend._viewing_storage_observation(self.device)

        busy_snapshot = json.loads(json.dumps(snapshot))
        busy_snapshot["artwork"]["entryCount"] = 1
        busy_snapshot["artwork"]["totalBytes"] = 8
        with (
            mock.patch.object(
                backend,
                "_viewing_storage_observation",
                side_effect=[
                    {"snapshot": busy_snapshot, "response": {"success": True}},
                    observation,
                ],
            ) as probe,
            mock.patch.object(adapter.time, "sleep") as sleep,
        ):
            settled = backend._await_viewing_storage_observation(
                self.device, ("artwork",), 5
            )
        self.assertEqual(settled, observation)
        self.assertEqual(probe.call_count, 2)
        sleep.assert_called_once_with(0.2)

        malformed = json.loads(json.dumps(snapshot))
        malformed["containerIndex"]["entryCount"] = 1
        with (
            mock.patch.object(
                backend,
                "_app_command",
                return_value={
                    "success": True,
                    "viewingStorageSnapshot": malformed,
                },
            ),
            self.assertRaisesRegex(
                adapter.OperationAdapterError,
                "container-index entry count is inconsistent",
            ),
        ):
            backend._viewing_storage_observation(self.device)

    def test_container_index_probe_closes_local_absence_with_remote_positive_control(self) -> None:
        spec = adapter.SPECS["operation:diagnostics.surface-probe@1"]
        baseline = {"containerIndexExpectation": "baseline-empty"}
        local_active = {
            "containerIndexExpectation": "local-active-empty",
            "expectedBaselineDigest": "result://call:viewing-state-and-storage:index:02/containerIndexDigest",
        }
        local_after = {
            "containerIndexExpectation": "local-after-empty",
            "expectedBaselineDigest": local_active["expectedBaselineDigest"],
        }
        remote = {
            "containerIndexExpectation": "remote-positive-control",
            "expectedBaselineDigest": local_active["expectedBaselineDigest"],
            "expectedLocalActiveDigest": "result://call:viewing-state-and-storage:index:07/containerIndexDigest",
            "expectedLocalAfterDigest": "result://call:viewing-state-and-storage:index:09/containerIndexDigest",
        }
        for arguments in (baseline, local_active, local_after, remote):
            with self.subTest(arguments=arguments):
                self.assertEqual(dict(spec.validate("device", arguments)), arguments)
        for invalid in (
            {"containerIndexExpectation": "arbitrary"},
            {**baseline, "expectedBaselineDigest": "sha256:" + "1" * 64},
            {"containerIndexExpectation": "local-active-empty"},
            {**remote, "remoteExpectation": "webdav-connection"},
        ):
            with self.subTest(arguments=invalid), self.assertRaises(
                adapter.OperationAdapterError
            ):
                spec.validate("device", invalid)

        empty = "sha256:" + "1" * 64
        source = "sha256:" + "2" * 64
        revision = "sha256:" + "3" * 64

        def payload(
            *,
            digest: str,
            keys: str,
            address: str,
            current_source: str,
            current_revision: str,
            scope: str,
        ) -> dict[str, object]:
            return {
                "success": True,
                "payload": [
                    "schema=enchron.regression.container-index-probe@1",
                    f"cacheDigest={digest}",
                    f"entryKeys={keys}",
                    f"entryCount={0 if not keys else 1}",
                    f"totalBytes={0 if not keys else 4096}",
                    f"playbackAddressKind={address}",
                    f"sourceIdentity={current_source}",
                    f"contentRevision={current_revision}",
                    "session=session-a" if address != "none" else "session=none",
                    "mediaName=sdr-bframe-aggregate-30s.mkv" if address != "none" else "mediaName=none",
                    f"byteStreamScope={scope}",
                    "byteStreamRequestCount=4" if scope != "none" else "byteStreamRequestCount=none",
                ],
            }

        backend = adapter.ResidentOperationBackend()
        responses = (
            payload(
                digest=empty,
                keys="",
                address="none",
                current_source="none",
                current_revision="none",
                scope="none",
            ),
            payload(
                digest=empty,
                keys="",
                address="local-file",
                current_source=source,
                current_revision=revision,
                scope="none",
            ),
            payload(
                digest=empty,
                keys="",
                address="none",
                current_source="none",
                current_revision="none",
                scope="none",
            ),
            payload(
                digest="sha256:" + "4" * 64,
                keys=revision,
                address="loopback",
                current_source=source,
                current_revision=revision,
                scope="7",
            ),
        )
        with mock.patch.object(backend, "_app_command", side_effect=responses):
            before = backend._container_index_observation(baseline, self.device)
            active = backend._container_index_observation(
                {**local_active, "expectedBaselineDigest": empty}, self.device
            )
            after = backend._container_index_observation(
                {**local_after, "expectedBaselineDigest": empty}, self.device
            )
            positive = backend._container_index_observation(
                {
                    **remote,
                    "expectedBaselineDigest": empty,
                    "expectedLocalActiveDigest": active["containerIndexDigest"],
                    "expectedLocalAfterDigest": after["containerIndexDigest"],
                },
                self.device,
            )
        self.assertEqual(before["entryKeys"], [])
        self.assertEqual(active["playbackAddressKind"], "local-file")
        self.assertEqual(after["containerIndexDigest"], empty)
        self.assertEqual(positive["entryKeys"], [revision])
        self.assertEqual(positive["contentRevision"], revision)

        with mock.patch.object(
            backend,
            "_app_command",
            return_value=payload(
                digest="sha256:" + "4" * 64,
                keys=revision,
                address="loopback",
                current_source=source,
                current_revision=revision,
                scope="7",
            ),
        ):
            mismatch = backend._container_index_observation(baseline, self.device)
        self.assertTrue(
            mismatch["expectationObservation"]["expected"]["isEmpty"]
        )
        self.assertFalse(
            mismatch["expectationObservation"]["observed"]["isEmpty"]
        )

    def test_audio_capture_binds_and_preserves_exact_playback_identity(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = {
            **VALID_ARGUMENTS["operation:evidence.capture-audio@2"],
            "expectedSession": "session-a",
            "expectedAudioTrackID": "2",
        }
        spec = adapter.SPECS["operation:evidence.capture-audio@2"]
        self.assertEqual(dict(spec.validate("device", arguments)), arguments)
        before = playback_probe_result(audio_track="2")
        after = playback_probe_result(audio_track="2")
        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                side_effect=[before, after],
            ),
            mock.patch.object(
                backend, "_run_json", return_value={"dominantFrequencyHz": 880}
            ),
        ):
            result = backend._evidence_capture_audio_2(arguments, self.device)

        self.assertEqual(result["session"], "session-a")
        self.assertEqual(result["audioTrack"], "2")
        self.assertEqual(result["mediaName"], "fixture.mkv")
        self.assertEqual(
            result["measurement"],
            {
                "dominantFrequencyHz": 880,
                "session": "session-a",
                "audioTrack": "2",
                "mediaName": "fixture.mkv",
            },
        )
        self.assertEqual(result["beforePlaybackState"], before)
        self.assertEqual(result["afterPlaybackState"], after)

    def test_audio_capture_records_wrong_or_changed_playback_identity(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = {
            **VALID_ARGUMENTS["operation:evidence.capture-audio@2"],
            "expectedSession": "session-a",
            "expectedAudioTrackID": "2",
        }
        with mock.patch.object(
            backend,
            "_diagnostics_playback_state_1",
            return_value=playback_probe_result(audio_track="1"),
        ), mock.patch.object(
            backend, "_run_json", return_value={"peak": 1}
        ) as run_json:
            wrong = backend._evidence_capture_audio_2(arguments, self.device)
        run_json.assert_called_once()
        self.assertEqual(wrong["identityObservation"]["before"]["audioTrack"], "1")
        self.assertEqual(wrong["identityObservation"]["expected"]["audioTrack"], "2")

        with mock.patch.object(
            backend,
            "_diagnostics_playback_state_1",
            side_effect=[
                playback_probe_result(audio_track="2"),
                playback_probe_result(session="session-b", audio_track="2"),
            ],
        ), mock.patch.object(backend, "_run_json", return_value={"peak": 1}):
            changed = backend._evidence_capture_audio_2(arguments, self.device)
        self.assertEqual(changed["identityObservation"]["before"]["session"], "session-a")
        self.assertEqual(changed["identityObservation"]["after"]["session"], "session-b")

    def test_wait_position_matches_exact_media_and_a_different_session(self) -> None:
        spec = adapter.SPECS["operation:playback.wait-position@2"]
        reference = "result://call:local-media-lifecycle:play-next:24/session"
        arguments = {
            **VALID_ARGUMENTS["operation:playback.wait-position@2"],
            "expectedMediaName": "second.mkv",
            "differentSessionFrom": reference,
        }
        self.assertEqual(dict(spec.validate("device", arguments)), arguments)
        with self.assertRaises(adapter.OperationAdapterError):
            spec.validate(
                "device",
                {**arguments, "differentSessionFrom": reference + "/wrong"},
            )

        backend = adapter.ResidentOperationBackend()
        runtime_arguments = {**arguments, "differentSessionFrom": "session-a"}
        base = {
            "presentation": "window",
            "lifecycle": "Playing",
            "controls": "shown",
            "transition": "none",
            "position": "20",
            "duration": "100",
        }
        states = [
            {**base, "session": "session-b", "mediaName": "wrong.mkv"},
            {**base, "session": "session-a", "mediaName": "second.mkv"},
            {**base, "session": "session-b", "mediaName": "second.mkv"},
        ]
        with (
            mock.patch.object(
                backend,
                "_read_control_plane",
                side_effect=[(state, {"success": True}) for state in states],
            ),
            mock.patch.object(
                adapter.time,
                "monotonic",
                side_effect=[0.0, 0.0, 0.1, 0.2, 0.3, 0.4, 0.5],
            ),
            mock.patch.object(adapter.time, "sleep"),
        ):
            result = backend._playback_wait_position_2(
                runtime_arguments, self.device
            )
        self.assertTrue(result["succeeded"])
        self.assertEqual(result["terminal"]["session"], "session-b")
        self.assertEqual(len(result["observations"]), 3)

    def test_result_references_must_be_resolved_before_identity_bound_operations(self) -> None:
        backend = adapter.ResidentOperationBackend()
        with self.assertRaisesRegex(adapter.OperationAdapterError, "resolved"):
            backend._playback_wait_position_2(
                {
                    **VALID_ARGUMENTS["operation:playback.wait-position@2"],
                    "differentSessionFrom": "result://call:a:b/session",
                },
                self.device,
            )
        with self.assertRaisesRegex(adapter.OperationAdapterError, "resolved"):
            backend._evidence_capture_audio_2(
                {
                    **VALID_ARGUMENTS["operation:evidence.capture-audio@2"],
                    "expectedSession": "result://call:a:b/session",
                },
                self.device,
            )


class RuntimeSemanticClosureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(
            prefix="operation-runtime-closure-test-"
        )
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name).resolve()
        self.simulator = adapter.OperationContext(
            "simulator", "simulator-lease", root, root / "controller"
        )
        self.device = adapter.OperationContext(
            "device", "device-lease", root, root / "controller"
        )

    @staticmethod
    def action_response(hierarchy: str, **matched: object) -> dict[str, object]:
        return {
            "success": True,
            "appState": "runningForeground",
            "hierarchy": hierarchy,
            "matchedElement": matched or None,
        }

    @staticmethod
    def subtitle_playback_state(**overrides: str) -> dict[str, object]:
        fields = {
            "session": "session-a",
            "mediaName": "sdr-bframe-aggregate-30s.mkv",
            "sourceIdentity": "sha256:" + "1" * 64,
            "contentRevision": "sha256:" + "2" * 64,
            "collectionOrigin": "mediaLibrary",
            "playbackAddressKind": "local-file",
            "lifecycle": "Playing",
            "transition": "none",
            "subtitleTrack": "off",
            "error": "none",
        }
        fields.update(overrides)
        return {
            "succeeded": True,
            "session": fields["session"],
            "mediaName": fields["mediaName"],
            "sourceIdentity": fields["sourceIdentity"],
            "contentRevision": fields["contentRevision"],
            "fields": fields,
            "response": {"success": True},
            "missingIdentityFields": [],
        }

    @staticmethod
    def subtitle_menu(*items: tuple[str, str, bool]) -> dict[str, object]:
        return {
            "success": True,
            "menuItems": [
                {"id": identifier, "title": title, "isSelected": selected}
                for identifier, title, selected in items
            ],
        }

    def test_navigation_returns_interaction_and_destination_post_state(self) -> None:
        backend = adapter.ResidentOperationBackend()
        response = self.action_response(
            "Application, identifier: 'Settings-SettingsScreen'",
            identifier="Navigation-Ornament-tab-settings",
            isSelected=False,
        )
        with mock.patch.object(
            backend, "_controller", return_value=response
        ) as controller:
            result = backend._navigation_select_tab_1(
                {"tab": "settings"}, self.device
            )

        controller.assert_called_once_with(
            self.device,
            "tap",
            "--identifier",
            "Navigation-Ornament-tab-settings",
        )
        self.assertIs(result["interaction"], response)
        self.assertEqual(
            result["postActionState"]["destinationIdentifier"],
            "Settings-SettingsScreen",
        )
        self.assertTrue(result["postActionState"]["destinationVisible"])
        self.assertEqual(
            result["postActionState"]["appState"], "runningForeground"
        )

    def test_issue_present_dispatches_existing_product_command_without_inspection(self) -> None:
        backend = adapter.ResidentOperationBackend()
        response = {
            "success": True,
            "payload": ["mediaOpeningFailed"],
        }
        with mock.patch.object(
            backend, "_app_command", return_value=response
        ) as app_command:
            result = backend._issue_present_1(
                {"category": "mediaOpeningFailed"}, self.device
            )

        app_command.assert_called_once_with(
            self.device,
            "showPlaybackIssue",
            "category=mediaOpeningFailed",
        )
        self.assertEqual(
            result,
            {
                "succeeded": True,
                "category": "mediaOpeningFailed",
                "response": response,
            },
        )

    def test_subtitle_selection_discovers_dynamic_identity_and_waits_for_product_state(self) -> None:
        backend = adapter.ResidentOperationBackend()
        target_id = "external.subtitle.sha256-stable-source.0"
        discovery = self.subtitle_menu(
            ("ffmpeg.subtitle.4", "Enchron acceptance subtitles", False),
            (
                target_id,
                "sdr-bframe-aggregate-30s.zh-CN.srt",
                False,
            ),
            (
                "external.subtitle.sha256-second-source.0",
                "sdr-bframe-aggregate-30s.styled.ass",
                False,
            ),
            ("off", "Off", True),
        )
        selected = self.subtitle_menu(
            (target_id, "sdr-bframe-aggregate-30s.zh-CN.srt", False)
        )
        settled_menu = self.subtitle_menu(
            ("ffmpeg.subtitle.4", "Enchron acceptance subtitles", False),
            (target_id, "sdr-bframe-aggregate-30s.zh-CN.srt", True),
            (
                "external.subtitle.sha256-second-source.0",
                "sdr-bframe-aggregate-30s.styled.ass",
                False,
            ),
            ("off", "Off", False),
        )
        before = self.subtitle_playback_state()
        after = self.subtitle_playback_state(subtitleTrack=target_id)
        arguments = VALID_ARGUMENTS["operation:playback.select-subtitle@1"]
        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                side_effect=[before, after],
            ),
            mock.patch.object(
                backend,
                "_app_command",
                side_effect=[discovery, selected, settled_menu],
            ) as app_command,
            mock.patch.object(
                adapter.time, "monotonic", side_effect=[1.0, 1.1]
            ),
        ):
            result = backend._playback_select_subtitle_1(arguments, self.device)

        self.assertEqual(
            app_command.call_args_list,
            [
                mock.call(
                    self.device,
                    "listMenuItems",
                    "host=playerUI",
                    "family=subtitles",
                ),
                mock.call(
                    self.device,
                    "selectMenuItem",
                    "host=playerUI",
                    "family=subtitles",
                    f"target={target_id}",
                ),
                mock.call(
                    self.device,
                    "listMenuItems",
                    "host=playerUI",
                    "family=subtitles",
                ),
            ],
        )
        self.assertTrue(result["succeeded"])
        self.assertEqual(result["semanticOutcome"], "selected")
        self.assertTrue(result["selectionSettled"])
        self.assertEqual(
            result["selectedTrack"],
            {
                "id": target_id,
                "label": "sdr-bframe-aggregate-30s.zh-CN.srt",
                "sourceKind": "local-sidecar",
                "isSelectedBefore": False,
                "isSelectedAfter": True,
            },
        )
        self.assertIs(result["beforeState"], before)
        self.assertIs(result["postActionState"], after)
        self.assertEqual(result["postActionState"]["fields"]["subtitleTrack"], target_id)
        self.assertEqual(
            result["identityObservation"],
            {
                "session": "session-a",
                "mediaName": "sdr-bframe-aggregate-30s.mkv",
                "sourceIdentity": "sha256:" + "1" * 64,
                "contentRevision": "sha256:" + "2" * 64,
                "sessionPreserved": True,
                "mediaPreserved": True,
                "sourceIdentityPreserved": True,
                "contentRevisionPreserved": True,
            },
        )
        self.assertEqual(
            [track["sourceKind"] for track in result["discoveredTracks"]],
            ["embedded", "local-sidecar", "local-sidecar", "off"],
        )

    def test_subtitle_selection_dynamically_selects_each_srt_and_ass_candidate(self) -> None:
        candidates = (
            (
                "external.subtitle.sha256-srt-source.0",
                "sdr-bframe-aggregate-30s.zh-CN.srt",
            ),
            (
                "external.subtitle.sha256-ass-source.0",
                "sdr-bframe-aggregate-30s.styled.ass",
            ),
        )
        for target_id, target_label in candidates:
            with self.subTest(trackLabel=target_label):
                backend = adapter.ResidentOperationBackend()
                discovery = self.subtitle_menu(
                    (candidates[0][0], candidates[0][1], False),
                    (candidates[1][0], candidates[1][1], False),
                    ("off", "Off", True),
                )
                selection = self.subtitle_menu((target_id, target_label, False))
                settled_menu = self.subtitle_menu(
                    (candidates[0][0], candidates[0][1], target_id == candidates[0][0]),
                    (candidates[1][0], candidates[1][1], target_id == candidates[1][0]),
                    ("off", "Off", False),
                )
                before = self.subtitle_playback_state()
                after = self.subtitle_playback_state(subtitleTrack=target_id)
                arguments = {
                    "host": "playerUI",
                    "sourceKind": "local-sidecar",
                    "trackLabel": target_label,
                    "deadlineSeconds": 30,
                }
                with (
                    mock.patch.object(
                        backend,
                        "_diagnostics_playback_state_1",
                        side_effect=[before, after],
                    ),
                    mock.patch.object(
                        backend,
                        "_app_command",
                        side_effect=[discovery, selection, settled_menu],
                    ),
                    mock.patch.object(
                        adapter.time,
                        "monotonic",
                        side_effect=[1.0, 1.1],
                    ),
                ):
                    result = backend._playback_select_subtitle_1(
                        arguments,
                        self.device,
                    )

                self.assertTrue(result["succeeded"])
                self.assertEqual(result["semanticOutcome"], "selected")
                self.assertTrue(result["selectionSettled"])
                self.assertEqual(result["selectedTrack"]["id"], target_id)
                self.assertEqual(result["selectedTrack"]["label"], target_label)
                self.assertEqual(
                    result["postActionState"]["fields"]["subtitleTrack"],
                    target_id,
                )

    def test_subtitle_selection_requires_one_external_candidate_or_exact_label(self) -> None:
        backend = adapter.ResidentOperationBackend()
        discovery = self.subtitle_menu(
            ("external.subtitle.source-a.0", "First sidecar", False),
            ("external.subtitle.source-b.0", "Second sidecar", False),
            ("ffmpeg.subtitle.4", "Embedded", False),
            ("off", "Off", True),
        )
        arguments = {
            "host": "playerUI",
            "sourceKind": "local-sidecar",
            "deadlineSeconds": 30,
        }
        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                return_value=self.subtitle_playback_state(),
            ),
            mock.patch.object(
                backend, "_app_command", return_value=discovery
            ) as app_command,
        ):
            with self.assertRaisesRegex(adapter.OperationAdapterError, "ambiguous"):
                backend._playback_select_subtitle_1(arguments, self.device)
        app_command.assert_called_once()

        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                return_value=self.subtitle_playback_state(),
            ),
            mock.patch.object(
                backend, "_app_command", return_value=discovery
            ) as missing_command,
        ):
            missing = backend._playback_select_subtitle_1(
                {**arguments, "trackLabel": "Embedded"},
                self.device,
            )
        self.assertTrue(missing["succeeded"])
        self.assertEqual(missing["semanticOutcome"], "candidate-missing")
        self.assertFalse(missing["selectionSettled"])
        self.assertIsNone(missing["selectedTrack"])
        self.assertIsNone(missing["selectionResponse"])
        self.assertEqual(missing["postActionState"], missing["beforeState"])
        missing_command.assert_called_once()

    def test_subtitle_selection_rejects_malformed_menu_and_wrong_product_source(self) -> None:
        backend = adapter.ResidentOperationBackend()
        duplicate = self.subtitle_menu(
            ("external.subtitle.source.0", "Sidecar", False),
            ("external.subtitle.source.0", "Sidecar duplicate", False),
        )
        arguments = {
            "host": "playerUI",
            "sourceKind": "local-sidecar",
            "deadlineSeconds": 30,
        }
        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                return_value=self.subtitle_playback_state(),
            ),
            mock.patch.object(backend, "_app_command", return_value=duplicate),
        ):
            with self.assertRaisesRegex(adapter.OperationAdapterError, "unique"):
                backend._playback_select_subtitle_1(arguments, self.device)

        remote_state = self.subtitle_playback_state(
            collectionOrigin="sourceDirectory",
            playbackAddressKind="loopback",
        )
        with mock.patch.object(
            backend,
            "_diagnostics_playback_state_1",
            return_value=remote_state,
        ), mock.patch.object(backend, "_app_command") as app_command:
            with self.assertRaisesRegex(adapter.OperationAdapterError, "source kind"):
                backend._playback_select_subtitle_1(arguments, self.device)
        app_command.assert_not_called()

    def test_subtitle_selection_response_does_not_replace_settlement_or_identity_proof(self) -> None:
        backend = adapter.ResidentOperationBackend()
        target_id = "external.subtitle.source.0"
        discovery = self.subtitle_menu((target_id, "Only sidecar", False))
        selected = self.subtitle_menu((target_id, "Only sidecar", False))
        still_off = self.subtitle_playback_state()
        arguments = {
            "host": "playerUI",
            "sourceKind": "local-sidecar",
            "deadlineSeconds": 1,
        }
        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                side_effect=[self.subtitle_playback_state(), still_off],
            ),
            mock.patch.object(
                backend,
                "_app_command",
                side_effect=[discovery, selected, discovery],
            ),
            mock.patch.object(
                adapter.time, "monotonic", side_effect=[1.0, 1.1, 2.1]
            ),
            mock.patch.object(adapter.time, "sleep"),
        ):
            result = backend._playback_select_subtitle_1(arguments, self.device)
        self.assertTrue(result["succeeded"])
        self.assertEqual(result["semanticOutcome"], "selection-not-settled")
        self.assertFalse(result["selectionSettled"])
        self.assertEqual(result["reason"], "subtitle-selection-deadline-expired")
        self.assertEqual(result["selectionResponse"], selected)

        changed = self.subtitle_playback_state(
            session="session-b", subtitleTrack=target_id
        )
        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                side_effect=[self.subtitle_playback_state(), changed],
            ),
            mock.patch.object(
                backend,
                "_app_command",
                side_effect=[discovery, selected, self.subtitle_menu((target_id, "Only sidecar", True))],
            ),
            mock.patch.object(
                adapter.time, "monotonic", side_effect=[1.0, 1.1]
            ),
        ):
            with self.assertRaisesRegex(
                adapter.OperationAdapterError, "session changed"
            ):
                backend._playback_select_subtitle_1(arguments, self.device)

    def test_media_open_can_expect_codec_rejection_without_steady_playback(self) -> None:
        backend = adapter.ResidentOperationBackend()
        before_probe = {"cursorToken": "1:2", "lines": []}
        after_probe = {
            "cursorToken": "1:3",
            "lines": ["openRequestForwarded"],
        }
        action = self.action_response("Application")
        rejection = {
            "succeeded": True,
            "expectedCategory": "unsupportedVideoCodec",
            "terminal": {
                "error": "unsupportedVideoCodec",
                "session": "none",
                "technicalSession": "none",
                "videoSamples": "0",
                "rendererInputs": "0",
                "sampleMediaSubtype": "none",
            },
            "alertMessage": "This video uses MPEG-4 Part 2, which Enchron does not support.",
            "postActionState": {
                "schema": "enchron.regression.post-action-product-state@1"
            },
        }
        arguments = {
            "identifier": "MediaLibrary-grid-video-packed_bframes.avi",
            "expectedLanding": "window",
            "expectedIssueCategory": "unsupportedVideoCodec",
            "deadlineSeconds": 45,
        }
        with (
            mock.patch.object(
                backend,
                "_diagnostics_surface_probe_1",
                side_effect=[before_probe, after_probe],
            ) as surface_probe,
            mock.patch.object(
                backend, "_controller", return_value=action
            ) as controller,
            mock.patch.object(
                backend,
                "_wait_for_expected_issue",
                return_value=rejection,
            ) as wait_for_issue,
            mock.patch.object(backend, "_wait_for_window") as wait_for_window,
        ):
            result = backend._media_open_2(arguments, self.device)

        controller.assert_called_once_with(
            self.device,
            "tap",
            "--identifier",
            arguments["identifier"],
        )
        self.assertEqual(
            surface_probe.call_args_list,
            [
                mock.call({}, self.device),
                mock.call({"cursorToken": "1:2"}, self.device),
            ],
        )
        wait_for_issue.assert_called_once_with(
            self.device,
            category="unsupportedVideoCodec",
            deadline_seconds=45,
        )
        wait_for_window.assert_not_called()
        self.assertTrue(result["succeeded"])
        self.assertTrue(result["deliveryObserved"])
        self.assertIs(result["settlement"], rejection)

    def test_media_open_fails_when_the_expected_product_issue_never_appears(self) -> None:
        backend = adapter.ResidentOperationBackend()
        before_probe = {"cursorToken": "1:2", "lines": []}
        after_probe = {
            "cursorToken": "1:3",
            "lines": ["openRequestForwarded"],
        }
        missing_issue = {
            "succeeded": False,
            "reason": "expected-issue-deadline-expired",
            "expectedCategory": "unsupportedVideoCodec",
        }
        arguments = {
            "identifier": "MediaLibrary-grid-video-packed_bframes.avi",
            "expectedLanding": "either-main-window",
            "expectedIssueCategory": "unsupportedVideoCodec",
            "deadlineSeconds": 45,
        }
        with (
            mock.patch.object(
                backend,
                "_diagnostics_surface_probe_1",
                side_effect=[before_probe, after_probe],
            ),
            mock.patch.object(
                backend,
                "_controller",
                return_value=self.action_response("Application"),
            ),
            mock.patch.object(
                backend,
                "_wait_for_expected_issue",
                return_value=missing_issue,
            ),
        ):
            result = backend._media_open_2(arguments, self.device)

        self.assertFalse(result["succeeded"])
        self.assertTrue(result["deliveryObserved"])
        self.assertIs(result["settlement"], missing_issue)

    def test_expected_issue_poll_requires_product_state_and_codec_message(self) -> None:
        backend = adapter.ResidentOperationBackend()
        terminal = {
            "error": "unsupportedVideoCodec",
            "session": "none",
            "technicalSession": "none",
            "videoSamples": "0",
            "rendererInputs": "0",
            "sampleMediaSubtype": "none",
        }
        control_response = self.action_response(
            "Application, identifier: 'PlayerUI-application-state'",
            identifier="PlayerUI-application-state",
            value="error=unsupportedVideoCodec",
        )
        alert_response = self.action_response(
            "Application, identifier: 'Emby-Playback-Error'",
            identifier="Emby-Playback-Error",
            label="This video uses MPEG-4 Part 2, which Enchron does not support.",
        )
        with (
            mock.patch.object(
                backend,
                "_read_control_plane",
                return_value=(terminal, control_response),
            ) as read_control_plane,
            mock.patch.object(
                backend, "_controller", return_value=alert_response
            ) as controller,
            mock.patch.object(adapter.time, "monotonic", side_effect=[1.0, 1.1]),
        ):
            result = backend._wait_for_expected_issue(
                self.device,
                category="unsupportedVideoCodec",
                deadline_seconds=45,
            )

        read_control_plane.assert_called_once_with(
            self.device, "PlayerUI-application-state"
        )
        controller.assert_called_once_with(
            self.device,
            "snapshot",
            "--identifier",
            "Emby-Playback-Error",
            "--no-screenshot",
        )
        self.assertTrue(result["succeeded"])
        self.assertTrue(result["noActiveSession"])
        self.assertTrue(result["noDeliveredSample"])
        self.assertEqual(
            result["alertMessage"],
            "This video uses MPEG-4 Part 2, which Enchron does not support.",
        )
        self.assertEqual(
            result["postActionState"]["schema"],
            "enchron.regression.post-action-product-state@1",
        )

    def test_accessibility_activation_returns_same_transaction_post_state(self) -> None:
        backend = adapter.ResidentOperationBackend()
        response = self.action_response(
            "Application, identifier: 'FileBrowsing-SourceConnection-webDAV-address'"
        )
        with mock.patch.object(
            backend, "_controller", return_value=response
        ) as controller:
            result = backend._accessibility_activate_2(
                {
                    "context": "main-window-browser",
                    "identifiers": [
                        "FileBrowsing-SourcesSidebar-sourceMore",
                        "FileBrowsing-SourcesSidebar-add",
                        "FileBrowsing-SourcesSidebar-addWebDAV",
                    ],
                },
                self.device,
            )

        controller.assert_called_once_with(
            self.device,
            "tapSequence",
            "--identifiers",
            "FileBrowsing-SourcesSidebar-sourceMore",
            "FileBrowsing-SourcesSidebar-add",
            "FileBrowsing-SourcesSidebar-addWebDAV",
        )
        self.assertIs(result["interaction"], response)
        self.assertEqual(
            result["postActionState"]["hierarchy"], response["hierarchy"]
        )
        self.assertRegex(
            result["postActionState"]["hierarchyDigest"],
            r"^sha256:[0-9a-f]{64}$",
        )

    def test_secret_text_returns_redacted_post_state_without_secret_bytes(self) -> None:
        backend = adapter.ResidentOperationBackend()
        secret = "correct-horse-battery-staple"
        runtime = self.device.attempt_root / "credentials.json"
        runtime.write_text(json.dumps({"password": secret}), encoding="utf-8")
        runtime.chmod(0o600)
        response = self.action_response(
            f"SecureTextField value: '{secret}'",
            identifier="FileBrowsing-SourceConnection-webDAV-password",
            value=secret,
        )
        with mock.patch.object(
            backend, "_controller", return_value=response
        ) as controller:
            result = backend._accessibility_type_2(
                {
                    "context": "main-window-browser",
                    "identifier": "FileBrowsing-SourceConnection-webDAV-password",
                    "mode": "replace",
                    "textFile": str(runtime),
                    "textJSONKey": "password",
                    "secret": True,
                },
                self.device,
            )

        self.assertIn("--redact-response-text", controller.call_args.args)
        encoded = json.dumps(result, sort_keys=True)
        self.assertNotIn(secret, encoded)
        self.assertIn("<redacted>", encoded)
        self.assertEqual(result["postActionState"]["appState"], "runningForeground")

    def test_media_stage_device_transport_uses_lane_target(self) -> None:
        backend = adapter.ResidentOperationBackend()
        source = self.device.attempt_root / "fixture.bin"
        source.write_bytes(b"fixture")
        captured: dict[str, object] = {}

        def stage(*, registry, fixture_id, source_root, transport):
            del registry, fixture_id, source_root
            captured["transport"] = transport
            transport.copy_to_container(
                source, "Documents/TestMediaInbox/fixture.bin"
            )
            return {
                "schema": "fixture-stage-receipt@1",
                "lane": transport.lane,
                "target": transport.target,
            }

        completed = mock.Mock(returncode=0, stdout="", stderr="")
        with (
            mock.patch(
                "stage_registered_fixture.FixtureRegistry.load",
                return_value=mock.sentinel.registry,
            ),
            mock.patch(
                "stage_registered_fixture.stage_registered_fixture",
                side_effect=stage,
            ),
            mock.patch.object(backend, "_developer_dir", return_value="/Developer"),
            mock.patch.object(adapter.subprocess, "run", return_value=completed) as run,
        ):
            result = backend._media_stage_fixture_2(
                {"fixtureID": "fixture", "sourceRoot": str(self.device.attempt_root)},
                self.device,
            )

        self.assertEqual(result["receipt"]["target"], self.device.target)
        command = run.call_args.args[0]
        self.assertEqual(
            command[command.index("--device") + 1], self.device.target
        )
        self.assertEqual(captured["transport"].target, self.device.target)

    def test_seek_waits_for_target_and_preserves_session_and_media(self) -> None:
        backend = adapter.ResidentOperationBackend()
        before_fields = {
            "presentation": "window",
            "lifecycle": "Playing",
            "controls": "shown",
            "transition": "none",
            "session": "session-a",
            "mediaName": "fixture.mkv",
            "contentRevision": "sha256:" + "1" * 64,
            "position": "10.0",
            "duration": "100.0",
        }
        before = {
            "succeeded": True,
            "session": "session-a",
            "mediaName": "fixture.mkv",
            "fields": before_fields,
            "response": {"success": True},
        }
        settling = {**before_fields, "position": "35.0"}
        terminal = {**before_fields, "position": "50.2"}
        with (
            mock.patch.object(
                backend, "_diagnostics_playback_state_1", return_value=before
            ),
            mock.patch.object(
                backend,
                "_app_command",
                return_value={"success": True, "payload": ["true"]},
            ),
            mock.patch.object(
                backend,
                "_read_control_plane",
                side_effect=[
                    (settling, {"success": True}),
                    (terminal, {"success": True}),
                ],
            ),
            mock.patch.object(adapter.time, "sleep"),
        ):
            result = backend._playback_seek_2(
                {"positionMillionths": 500_000}, self.device
            )

        self.assertTrue(result["succeeded"])
        self.assertTrue(result["identityObservation"]["sessionPreserved"])
        self.assertTrue(result["identityObservation"]["mediaPreserved"])
        self.assertEqual(result["settlement"]["terminal"], terminal)
        self.assertEqual(result["settlement"]["targetPositionMillis"], 50_000)
        self.assertEqual(len(result["settlement"]["observations"]), 2)

    def test_seek_rejects_a_session_change_even_at_the_requested_position(self) -> None:
        backend = adapter.ResidentOperationBackend()
        before_fields = {
            "session": "session-a",
            "mediaName": "fixture.mkv",
            "position": "10",
            "duration": "100",
        }
        with (
            mock.patch.object(
                backend,
                "_diagnostics_playback_state_1",
                return_value={
                    "succeeded": True,
                    "session": "session-a",
                    "mediaName": "fixture.mkv",
                    "fields": before_fields,
                    "response": {"success": True},
                },
            ),
            mock.patch.object(
                backend,
                "_app_command",
                return_value={"success": True, "payload": ["true"]},
            ),
            mock.patch.object(
                backend,
                "_read_control_plane",
                return_value=(
                    {
                        **before_fields,
                        "session": "session-b",
                        "position": "50",
                        "lifecycle": "Playing",
                        "transition": "none",
                    },
                    {"success": True},
                ),
            ),
            self.assertRaisesRegex(
                adapter.OperationAdapterError, "session changed"
            ),
        ):
            backend._playback_seek_2(
                {"positionMillionths": 500_000}, self.device
            )

    def test_storage_clear_returns_closed_before_after_product_state(self) -> None:
        backend = adapter.ResidentOperationBackend()
        protected = {
            "schema": "enchron.regression.viewing-storage-protected-state@1",
            "digest": "sha256:" + "a" * 64,
        }
        before_snapshot = {
            "viewingState": {"viewingRecordCount": 2},
            "containerIndex": {"entryCount": 3, "totalBytes": 100},
            "artwork": {"entryCount": 4, "totalBytes": 200},
            "protectedState": protected,
        }
        after_snapshot = {
            **before_snapshot,
            "artwork": {"entryCount": 0, "totalBytes": 0},
        }
        before = {"snapshot": before_snapshot, "response": {"success": True}}
        after = {"snapshot": after_snapshot, "response": {"success": True}}
        interaction = self.action_response("Settings-StoragePrivacy-group")
        with (
            mock.patch.object(
                backend, "_viewing_storage_observation", return_value=before
            ),
            mock.patch.object(
                backend, "_await_viewing_storage_observation", return_value=after
            ) as await_state,
            mock.patch.object(
                backend, "_controller", return_value=interaction
            ),
        ):
            result = backend._storage_clear_1(
                {"target": "artwork-cache"}, self.device
            )

        await_state.assert_called_once_with(self.device, ("artwork",), 30)
        self.assertIs(result["interaction"], interaction)
        self.assertEqual(result["beforeState"], before_snapshot)
        self.assertEqual(result["postActionState"], after_snapshot)
        self.assertEqual(
            result["storageObservation"]["beforeCounts"]["artwork"],
            {"entries": 4, "bytes": 200},
        )
        self.assertEqual(
            result["storageObservation"]["afterCounts"]["artwork"],
            {"entries": 0, "bytes": 0},
        )
        self.assertTrue(result["storageObservation"]["protectedStatePreserved"])

    def test_presentation_operations_summon_controls_before_action(self) -> None:
        backend = adapter.ResidentOperationBackend()
        summon = {"success": True, "payload": ["true"]}
        settlement = {"succeeded": True, "settlement": {"verdict": "pass"}}
        trace = {
            "success": True,
            "transitionTraceSnapshot": {"generation": 7, "records": []},
        }
        control_plane = {
            "succeeded": True,
            "fields": {"presentation": "panorama"},
            "response": {"success": True},
        }
        with (
            mock.patch.object(
                backend, "_app_command", side_effect=[summon, summon, trace]
            ) as app_command,
            mock.patch.object(
                backend, "_enter_spatial", return_value=settlement
            ) as enter,
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                return_value=control_plane,
            ),
        ):
            docked = backend._presentation_enter_docked_skybox_1(
                {"deadlineSeconds": 30}, self.device
            )
            panorama = backend._presentation_enter_panorama_1(
                {"deadlineSeconds": 30}, self.device
            )

        self.assertEqual(
            app_command.call_args_list,
            [
                mock.call(self.device, "toggleControls", "visible=true"),
                mock.call(self.device, "toggleControls", "visible=true"),
                mock.call(self.device, "fetchTransitionTraceSnapshot"),
            ],
        )
        self.assertEqual(enter.call_count, 2)
        self.assertIs(docked["summon"], summon)
        self.assertIs(panorama["summon"], summon)

        with (
            mock.patch.object(
                backend, "_app_command", side_effect=[summon, trace]
            ) as app_command,
            mock.patch.object(
                backend, "_controller", return_value={"success": True}
            ) as controller,
            mock.patch.object(
                backend,
                "_wait_for_window",
                return_value={
                    "succeeded": True,
                    "terminal": {},
                    "fields": {"presentation": "portal"},
                    "response": {"success": True},
                },
            ),
        ):
            exited = backend._presentation_exit_spatial_1(
                {"from": "panorama", "deadlineSeconds": 30}, self.device
            )
        self.assertEqual(
            app_command.call_args_list,
            [
                mock.call(self.device, "toggleControls", "visible=true"),
                mock.call(self.device, "fetchTransitionTraceSnapshot"),
            ],
        )
        controller.assert_called_once_with(
            self.device,
            "tap",
            "--identifier",
            "PlayerPanel-button-exit-spatial",
        )
        self.assertIs(exited["summon"], summon)

    def test_custom_angle_selection_is_one_resident_tap_sequence(self) -> None:
        backend = adapter.ResidentOperationBackend()
        fields = {
            "presentation": "portal",
            "lifecycle": "Playing",
            "controls": "shown",
            "transition": "none",
            "projection": "customAngle",
            "horizontalFieldOfViewDegrees": "240",
            "stereoLayout": "sideBySide",
        }
        observation = {
            "succeeded": True,
            "fields": fields,
            "response": {"success": True},
        }
        with (
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                side_effect=[observation, observation],
            ),
            mock.patch.object(
                backend,
                "_app_command",
                return_value={"success": True, "payload": ["true"]},
            ),
            mock.patch.object(
                backend, "_controller", return_value={"success": True}
            ) as controller,
            mock.patch.object(
                backend,
                "_wait_for_window",
                return_value={"succeeded": True, "terminal": fields},
            ),
        ):
            result = backend._format_apply_2(
                {
                    "projection": "customAngle",
                    "horizontalCoverageDegrees": 240,
                    "stereoLayout": "sideBySide",
                    "deadlineSeconds": 30,
                },
                self.device,
            )

        self.assertTrue(result["succeeded"])
        controller.assert_called_once_with(
            self.device,
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-videoFormat",
            "PlayerUI-VideoFormat-CustomAngle",
            "PlayerUI-VideoFormat-CustomAngle-240",
            "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side",
            "PlayerUI-VideoFormat-apply",
        )

    def test_browse_hierarchy_drives_and_records_the_requested_path(self) -> None:
        backend = adapter.ResidentOperationBackend()
        hierarchy = "\n".join(
            (
                "identifier: 'FileBrowsing-FilesScreen-itemCount', label: '2 items'",
                "identifier: 'FileBrowsing-grid-folder-Media'",
                "identifier: 'FileBrowsing-grid-video-fixture.mkv'",
            )
        )
        response = self.action_response(hierarchy)
        with mock.patch.object(
            backend, "_controller", return_value=response
        ) as controller:
            result = backend._diagnostics_browse_hierarchy_1(
                {
                    "context": "main-window-browser",
                    "sourceLabel": "Enchron Regression SMB",
                    "pathComponents": ["Media"],
                },
                self.device,
            )

        self.assertEqual(
            controller.call_args_list,
            [
                mock.call(
                    self.device,
                    "tap",
                    "--label",
                    "Enchron Regression SMB",
                ),
                mock.call(self.device, "snapshot"),
                mock.call(
                    self.device,
                    "tap",
                    "--identifier",
                    "FileBrowsing-grid-folder-Media",
                ),
                mock.call(self.device, "snapshot"),
            ],
        )
        self.assertEqual(len(result["stages"]), 2)
        self.assertEqual(result["stages"][0]["facts"]["itemCount"], 2)
        self.assertEqual(result["observationMode"], "navigated-requested-hierarchy")

    def test_artwork_frame_capture_is_read_only(self) -> None:
        backend = adapter.ResidentOperationBackend()
        arguments = {
            "count": 4,
            "minimumIntervalMillis": 0,
            "context": "window",
            "artworkExpectation": "exit-replaces-current-frame",
        }
        probe = {
            "schema": "enchron.regression.artwork-probe@1",
            "artworkKey": "media-" + "1" * 64,
            "currentDigest": "sha256:" + "2" * 64,
            "storedDigest": "sha256:" + "3" * 64,
            "currentWidth": "1920",
            "currentHeight": "1080",
            "storedBytes": "8192",
            "byteStreamScope": "none",
            "byteStreamRequestCount": "none",
        }
        snapshot = self.action_response("WindowPlayback-root")
        with (
            mock.patch.object(
                backend, "_artwork_probe", side_effect=[probe, probe]
            ) as artwork_probe,
            mock.patch.object(
                backend, "_controller", return_value=snapshot
            ) as controller,
            mock.patch.object(
                backend,
                "_wait_for_window",
                return_value={"succeeded": True, "terminal": {}},
            ),
            mock.patch.object(adapter.time, "monotonic", return_value=1.0),
        ):
            result = backend._evidence_capture_frames_1(arguments, self.device)

        self.assertEqual(artwork_probe.call_count, 2)
        self.assertEqual(len(result["frames"]), 4)
        self.assertTrue(result["artworkObservation"]["readOnly"])
        self.assertEqual(
            {call.args[1] for call in controller.call_args_list}, {"snapshot"}
        )

    def test_certificate_change_surface_probe_does_not_close_product_issue(self) -> None:
        backend = adapter.ResidentOperationBackend()
        cursor = type("Cursor", (), {"sequence": 1, "line_count": 1})()
        matrix = mock.Mock()
        matrix.ProbeCursor.return_value = cursor
        matrix.probe_cursor.return_value = cursor
        matrix.probe_lines_since.return_value = ([], cursor, None)
        remote = {
            "traceLines": [],
            "priorCertificateFingerprint": "sha256:" + "a" * 64,
            "certificateFingerprint": "sha256:" + "b" * 64,
        }
        with (
            mock.patch.object(backend, "_matrix", return_value=matrix),
            mock.patch.object(backend, "_probe_lines", return_value=[]),
            mock.patch.object(
                backend,
                "_window_control_plane_observation",
                return_value={
                    "succeeded": True,
                    "fields": {"lifecycle": "Playing"},
                    "response": {"success": True},
                },
            ),
            mock.patch.object(
                backend, "_remote_observation", return_value=remote
            ),
        ):
            result = backend._diagnostics_surface_probe_1(
                {
                    "cursorToken": "1:1",
                    "remoteExpectation": "certificate-change",
                    "remoteReceiptID": "receipt:g-000001:certificate-rotation",
                    "restoredGenerationToken": "2",
                },
                self.device,
            )

        self.assertFalse(hasattr(backend, "_close_certificate_change_issue"))
        self.assertIsNone(result["certificateBoundary"])

    def test_transition_arm_clears_stale_fault_and_disarm_proves_inactive(self) -> None:
        backend = adapter.ResidentOperationBackend()
        stale_snapshot = {
            "success": True,
            "payload": ["generation=4"],
            "transitionTraceSnapshot": {"generation": 4, "isArmed": True},
        }
        stale_disarm = {"success": True, "payload": ["generation=4"]}
        armed = {
            "success": True,
            "payload": [
                "generation=5",
                "capacity=2048",
                "fault=settlement-timeout",
            ],
        }
        with mock.patch.object(
            backend,
            "_app_command",
            side_effect=[stale_snapshot, stale_disarm, armed],
        ) as app_command:
            result = backend._transition_trace_arm_1(
                {"fault": "settlement-timeout"}, self.device
            )

        self.assertEqual(result["generationToken"], "5")
        self.assertEqual(result["fault"], "settlement-timeout")
        self.assertTrue(result["priorCleanup"]["disarmed"])
        self.assertEqual(
            app_command.call_args_list,
            [
                mock.call(self.device, "fetchTransitionTraceSnapshot"),
                mock.call(self.device, "disarmTransitionTrace", "generation=4"),
                mock.call(
                    self.device,
                    "armTransitionTrace",
                    "fault=settlement-timeout",
                ),
            ],
        )

        disarm = {"success": True, "payload": ["generation=5"]}
        inactive = {
            "success": True,
            "payload": ["generation=5"],
            "transitionTraceSnapshot": {"generation": 5, "isArmed": False},
        }
        with mock.patch.object(
            backend, "_app_command", side_effect=[disarm, inactive]
        ):
            cleanup = backend._transition_trace_disarm_1(
                {"generationToken": "5"}, self.device
            )
        self.assertTrue(cleanup["disarmed"])
        self.assertFalse(cleanup["postActionState"]["isArmed"])

    def test_device_hub_input_binds_host_interaction_to_product_post_state(self) -> None:
        backend = adapter.ResidentOperationBackend()
        host_result = {
            "targetBinding": {"device": self.simulator.target},
            "canvas": {"width": 1400, "height": 800},
            "point": [700, 400],
        }
        product_state = self.action_response(
            "Application, identifier: 'PlayerPanel-controls'"
        )
        with (
            mock.patch.object(backend, "_run_json", return_value=host_result),
            mock.patch.object(
                backend, "_controller", return_value=product_state
            ) as controller,
        ):
            result = backend._input_device_hub_pinch_2(
                {
                    "targetDomain": "canvas",
                    "shotX": 100,
                    "shotY": 100,
                    "shotWidth": 1200,
                    "shotHeight": 900,
                },
                self.simulator,
            )

        controller.assert_called_once_with(
            self.simulator, "snapshot", "--no-screenshot"
        )
        self.assertEqual(result["interaction"], host_result)
        self.assertEqual(
            result["postActionState"]["appState"], "runningForeground"
        )


if __name__ == "__main__":
    unittest.main()
