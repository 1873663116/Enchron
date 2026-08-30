#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/verification"))

import regression_operation_adapter as operations
import regression_preparation_adapter as preparations
import regression_remote_source as remote


EXPECTED_LANES = {
    "preparation:audio-only-fixtures": "device",
    "preparation:local-aggregate-device": "device",
    "preparation:local-aggregate-simulator": "simulator",
    "preparation:local-directory-subtitle-source": "device",
    "preparation:smb-test-source": "device",
    "preparation:window-input-fixture": "simulator",
    "preparation:system-import-fixtures": "simulator",
    "preparation:dynamic-range-corpus": "device",
    "preparation:emby-test-library": "device",
    "preparation:faultable-remote-source": "device",
    "preparation:format-corpus": "device",
    "preparation:issue-fixtures": "device",
    "preparation:presentation-fixtures-device": "device",
    "preparation:presentation-fixtures-simulator": "simulator",
    "preparation:projection-corpus": "device",
    "preparation:viewing-storage-fixtures-device": "device",
    "preparation:viewing-storage-fixtures-simulator": "simulator",
    "preparation:webdav-test-source": "device",
}

READY_IDS = {
    "preparation:audio-only-fixtures",
    "preparation:dynamic-range-corpus",
    "preparation:emby-test-library",
    "preparation:local-aggregate-device",
    "preparation:local-aggregate-simulator",
    "preparation:local-directory-subtitle-source",
    "preparation:projection-corpus",
    "preparation:smb-test-source",
    "preparation:faultable-remote-source",
    "preparation:issue-fixtures",
    "preparation:format-corpus",
    "preparation:presentation-fixtures-device",
    "preparation:presentation-fixtures-simulator",
    "preparation:viewing-storage-fixtures-device",
    "preparation:viewing-storage-fixtures-simulator",
    "preparation:webdav-test-source",
    "preparation:window-input-fixture",
    "preparation:system-import-fixtures",
}

BLOCKED_IDS: set[str] = set()

LOCAL_AGGREGATE_READY_IDS = {
    "preparation:local-aggregate-device",
    "preparation:local-aggregate-simulator",
}

EXPECTED_STATE_CONTRACTS = {
    "preparation:audio-only-fixtures": ("audio-only-fixtures-ready", "fixture-set.audio-only@2"),
    "preparation:local-aggregate-device": ("local-aggregate-staged", "fixture-set.local-aggregate-staged@2"),
    "preparation:local-aggregate-simulator": ("local-aggregate-staged", "fixture-set.local-aggregate-staged@2"),
    "preparation:local-directory-subtitle-source": (
        "local-directory-subtitle-source-ready",
        "media-source.local-directory-sidecars@1",
    ),
    "preparation:smb-test-source": ("smb-test-source-ready", "remote-source.smb-fixture@2"),
    "preparation:window-input-fixture": ("window-input-fixture-ready", "fixture-set.window-input@2"),
    "preparation:system-import-fixtures": ("system-import-fixtures-ready", "fixture-set.system-import@2"),
    "preparation:dynamic-range-corpus": ("dynamic-range-corpus-ready", "fixture-set.dynamic-range@2"),
    "preparation:emby-test-library": ("emby-test-library-ready", "remote-source.emby-library@2"),
    "preparation:faultable-remote-source": ("faultable-remote-source-ready", "remote-source.faultable@2"),
    "preparation:format-corpus": ("format-corpus-ready", "fixture-set.format-corpus@2"),
    "preparation:issue-fixtures": ("issue-fixtures-ready", "fixture-set.issue-surfaces@2"),
    "preparation:presentation-fixtures-device": ("presentation-fixtures-ready", "fixture-set.presentation-tour@2"),
    "preparation:presentation-fixtures-simulator": ("presentation-fixtures-ready", "fixture-set.presentation-tour@2"),
    "preparation:projection-corpus": ("projection-corpus-ready", "fixture-set.projection-stereo@2"),
    "preparation:viewing-storage-fixtures-device": ("viewing-storage-fixtures-ready", "fixture-set.viewing-storage@2"),
    "preparation:viewing-storage-fixtures-simulator": ("viewing-storage-fixtures-ready", "fixture-set.viewing-storage@2"),
    "preparation:webdav-test-source": ("webdav-test-source-ready", "remote-source.webdav-fixture@2"),
}


class FakeBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object, object]] = []

    def execute(self, operation_id, arguments, context):
        self.calls.append((operation_id, arguments, context))
        return {"succeeded": True}


class PreparationRegistryTests(unittest.TestCase):
    def plans(self, target: str = "literal-lane-target"):
        return {
            identifier: preparations.build_plan(identifier, lane, target)
            for identifier, lane in EXPECTED_LANES.items()
        }

    def test_registry_is_the_exact_catalog_v2_preparation_set(self) -> None:
        self.assertEqual(set(preparations.PREPARATION_REGISTRY), set(EXPECTED_LANES))
        self.assertEqual(len(preparations.PREPARATION_REGISTRY), 18)

    def test_all_18_ids_materialize_as_ready(self) -> None:
        plans = self.plans()
        ready = {identifier for identifier, plan in plans.items() if plan.readiness == "ready"}
        blocked = {
            identifier
            for identifier, plan in plans.items()
            if plan.readiness == "implementation-blocked"
        }
        self.assertEqual(ready, READY_IDS)
        self.assertEqual(blocked, BLOCKED_IDS)
        self.assertEqual(len(ready), len(READY_IDS))
        self.assertEqual(len(blocked), len(EXPECTED_LANES) - len(READY_IDS))
        self.assertEqual(ready | blocked, set(EXPECTED_LANES))

    def test_all_18_state_contracts_have_exact_key_schema_and_tag_identity(self) -> None:
        plans = self.plans()
        self.assertEqual(set(EXPECTED_STATE_CONTRACTS), set(plans))
        for identifier, plan in plans.items():
            with self.subTest(preparation=identifier):
                self.assertEqual(
                    (plan.state.key, plan.state.schema),
                    EXPECTED_STATE_CONTRACTS[identifier],
                )
                self.assertIn("lane.instance", plan.state.tags)
                self.assertEqual(plan.state.tags, tuple(sorted(set(plan.state.tags))))

    def test_plan_and_implementation_digests_are_deterministic(self) -> None:
        first = self.plans()
        second = self.plans()
        self.assertEqual(
            {identifier: plan.plan_digest for identifier, plan in first.items()},
            {identifier: plan.plan_digest for identifier, plan in second.items()},
        )
        for plan in first.values():
            self.assertRegex(plan.plan_digest, r"^sha256:[0-9a-f]{64}$")
            self.assertEqual(
                plan.implementation_digest,
                preparations.IMPLEMENTATION_DIGESTS[plan.preparation_id],
            )
            preparations.validate_plan(plan)
        self.assertRegex(preparations.REGISTRY_DIGEST, r"^sha256:[0-9a-f]{64}$")
        self.assertEqual(len(preparations.IMPLEMENTATION_DIGESTS), 18)
        changed_target = preparations.build_plan(
            "preparation:local-aggregate-device", "device", "another-literal-target"
        )
        self.assertNotEqual(
            first["preparation:local-aggregate-device"].plan_digest,
            changed_target.plan_digest,
        )

    def test_operation_allowlist_is_closed_to_the_catalog_35(self) -> None:
        expected = set(operations.SPECS)
        self.assertEqual(preparations.OPERATION_ALLOWLIST, expected)
        self.assertEqual(len(preparations.OPERATION_ALLOWLIST), 35)
        self.assertEqual(
            preparations.OPERATION_IMPLEMENTATION_DIGEST,
            operations.implementation_digest(),
        )
        self.assertNotIn("operation:host.query@1", preparations.OPERATION_ALLOWLIST)
        for plan in self.plans().values():
            for call in plan.calls:
                self.assertIn(call.operation_id, expected)
                self.assertIn(call.operation_id, operations.SPECS)
                operations.SPECS[call.operation_id].validate(
                    plan.lane, dict(call.arguments)
                )

    def test_generated_catalog_is_not_a_preparation_authority_or_prerequisite(self) -> None:
        source = Path(preparations.__file__).read_text(encoding="utf-8")
        self.assertNotIn("Config/regression/catalog-v2.json", source)
        self.assertFalse(hasattr(preparations, "CATALOG_FILE_DIGEST"))
        for plan in self.plans().values():
            kinds = {item.kind for item in plan.prerequisites}
            self.assertNotIn("catalog", kinds)
            operation = next(
                item for item in plan.prerequisites if item.kind == "operation-adapter"
            )
            self.assertEqual(
                operation.identity,
                "Scripts/verification/regression_operation_adapter.py",
            )
            self.assertEqual(
                operation.digest,
                operations.implementation_digest(),
            )

    def test_fixture_registry_and_digest_closure_is_exact(self) -> None:
        registry_path = REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json"
        encoded = registry_path.read_bytes()
        registry = json.loads(encoded)
        expected = {
            item["id"]: item
            for item in registry["fixtures"]
            if "deviceImportPath" in item
        }
        self.assertTrue(expected)
        self.assertEqual(set(preparations.STAGEABLE_FIXTURES), set(expected))
        self.assertEqual(
            preparations.FIXTURE_REGISTRY_DIGEST,
            "sha256:" + hashlib.sha256(encoded).hexdigest(),
        )
        for identifier, binding in preparations.STAGEABLE_FIXTURES.items():
            self.assertEqual(binding.device_import_path, expected[identifier]["deviceImportPath"])
            self.assertEqual(binding.digest, "sha256:" + expected[identifier]["sha256"])
        self.assertEqual(
            preparations.FIXTURE_SOURCE_ROOT,
            str((REPOSITORY_ROOT.parent / "TestMedia").resolve()),
        )
        for plan in self.plans().values():
            fixture_calls = [
                call for call in plan.calls if call.operation_id == "operation:media.stage-fixture@2"
            ]
            for call in fixture_calls:
                identifier = call.arguments["fixtureID"]
                binding = preparations.STAGEABLE_FIXTURES[identifier]
                self.assertEqual(call.arguments["sourceRoot"], preparations.FIXTURE_SOURCE_ROOT)
                self.assertTrue(
                    any(
                        item.kind == "registered-fixture"
                        and item.identity == identifier
                        and item.digest == binding.digest
                        for item in plan.prerequisites
                    )
                )

    def test_semantic_authority_is_digest_bound_and_forbids_runtime_human_work(self) -> None:
        source_path = (
            REPOSITORY_ROOT
            / "Config/regression/catalog-root/semantic-authority.json"
        )
        encoded = source_path.read_bytes()
        authority = json.loads(encoded)
        self.assertFalse(authority["authority"]["runtimeHumanActorAllowed"])
        self.assertEqual(preparations.SEMANTIC_AUTHORITY_SOURCE_PATH, source_path)
        self.assertEqual(
            preparations.SEMANTIC_AUTHORITY_PATH,
            REPOSITORY_ROOT / "Regression/semantic-authority.json",
        )
        self.assertEqual(
            preparations.SEMANTIC_AUTHORITY_DIGEST,
            "sha256:" + hashlib.sha256(encoded).hexdigest(),
        )
        for plan in self.plans().values():
            self.assertTrue(
                any(
                    item.kind == "semantic-authority"
                    and item.identity == "Regression/semantic-authority.json"
                    and item.digest == preparations.SEMANTIC_AUTHORITY_DIGEST
                    for item in plan.prerequisites
                )
            )

    def test_fresh_import_does_not_read_the_generated_catalog_authority(self) -> None:
        script = """
from pathlib import Path
import sys

repository = Path(sys.argv[1]).resolve()
generated_authority = repository / "Regression/semantic-authority.json"
original_read_bytes = Path.read_bytes

def guarded_read_bytes(candidate):
    if candidate.resolve() == generated_authority:
        raise AssertionError("Preparation adapter read generated Catalog authority")
    return original_read_bytes(candidate)

Path.read_bytes = guarded_read_bytes
sys.path.insert(0, str(repository / "Scripts/verification"))
import regression_preparation_adapter as adapter
assert adapter.SEMANTIC_AUTHORITY_SOURCE_PATH == (
    repository / "Config/regression/catalog-root/semantic-authority.json"
)
assert adapter.SEMANTIC_AUTHORITY_PATH == generated_authority
"""
        subprocess.run(
            [sys.executable, "-c", script, str(REPOSITORY_ROOT)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

    def test_ready_local_aggregate_plans_stage_exact_fixtures_without_import(self) -> None:
        self.assertIn(
            "generated-sdr-avc-bframe-duplicate-label-audio-30s-v1",
            preparations.LOCAL_AGGREGATE_FIXTURES,
        )
        plans = self.plans()
        for identifier in sorted(LOCAL_AGGREGATE_READY_IDS):
            plan = plans[identifier]
            operations_in_order = [call.operation_id for call in plan.calls]
            self.assertEqual(
                operations_in_order[:4],
                [
                    "operation:harness.ensure-session@1",
                    "operation:app.relaunch@1",
                    "operation:harness.reset-product-state@2",
                    "operation:harness.assert-channels@2",
                ],
            )
            self.assertEqual(dict(plan.calls[0].arguments), {})
            self.assertEqual(plan.target, "literal-lane-target")
            self.assertEqual(
                [call.arguments["fixtureID"] for call in plan.calls[4:]],
                list(preparations.LOCAL_AGGREGATE_FIXTURES),
            )
            self.assertNotIn("operation:media.import-staged@2", operations_in_order)
            self.assertEqual(plan.state.key, "local-aggregate-staged")
            self.assertEqual(plan.state.schema, "fixture-set.local-aggregate-staged@2")
            self.assertEqual(
                plan.state.tags, ("app.session", "fixture.corpus", "lane.instance")
            )
            self.assertEqual(plan.state.produced_by_call, plan.calls[-1].call_id)

    def test_local_directory_subtitle_preparation_stages_and_imports_one_real_source(self) -> None:
        plan = self.plans()["preparation:local-directory-subtitle-source"]
        self.assertEqual(plan.readiness, "ready")
        self.assertIsNone(plan.blocker)
        self.assertEqual(
            [
                call.arguments["fixtureID"]
                for call in plan.calls
                if call.operation_id == "operation:media.stage-fixture@2"
            ],
            list(preparations.LOCAL_DIRECTORY_SUBTITLE_FIXTURES),
        )
        self.assertNotIn(
            "operation:media.import-staged@2",
            [call.operation_id for call in plan.calls],
        )
        source_call = plan.calls[-1]
        self.assertEqual(
            source_call.operation_id,
            "operation:preparation.local-directory-subtitle-source@1",
        )
        source = preparations.LOCAL_DIRECTORY_SUBTITLE_SOURCE
        self.assertEqual(
            dict(source_call.arguments),
            {
                "directoryName": source.directory_name,
                "mediaFileName": preparations.STAGEABLE_FIXTURES[
                    source.media_fixture_id
                ].file_name,
                "memberFileNames": [
                    preparations.STAGEABLE_FIXTURES[fixture_id].file_name
                    for fixture_id in source.member_fixture_ids
                ],
            },
        )
        self.assertEqual(
            plan.state.tags,
            (
                "app.session",
                "certificate.trust",
                "emby.account",
                "fixture.corpus",
                "lane.instance",
                "library.contents",
                "source.connection",
                "source.emby",
                "source.emby.fixture-revision",
                "source.session",
                "source.webdav",
            ),
        )
        self.assertEqual(plan.state.produced_by_call, source_call.call_id)

    def test_fixed_preflights_are_used_only_by_the_matching_preparations(self) -> None:
        plans = self.plans()
        expected = {
            "preparation:audio-only-fixtures": ["audio-fixtures"],
            "preparation:local-directory-subtitle-source": ["emby-aggregate", "webdav-regression", "emby-aggregate"],
            "preparation:smb-test-source": ["smb-aggregate", "smb-aggregate"],
            "preparation:emby-test-library": ["emby-aggregate", "emby-aggregate"],
            "preparation:system-import-fixtures": ["system-import-fixtures"],
            "preparation:faultable-remote-source": ["remote-faults", "webdav-regression"],
            "preparation:issue-fixtures": ["remote-faults", "webdav-regression"],
            "preparation:presentation-fixtures-device": ["webdav-regression", "webdav-regression"],
            "preparation:presentation-fixtures-simulator": ["webdav-regression", "webdav-regression"],
            "preparation:viewing-storage-fixtures-device": ["webdav-regression", "webdav-regression"],
            "preparation:viewing-storage-fixtures-simulator": ["webdav-regression", "webdav-regression"],
            "preparation:webdav-test-source": ["webdav-regression", "webdav-regression"],
        }
        observed: dict[str, list[str]] = {}
        for identifier, plan in plans.items():
            for call in plan.calls:
                if call.operation_id == "operation:host.preflight@1":
                    observed.setdefault(identifier, []).append(call.arguments["check"])
        self.assertEqual(observed, expected)

    def test_registered_fixture_sets_are_materialized_without_symbolic_aliases(self) -> None:
        plans = self.plans()
        expected = {
            "preparation:audio-only-fixtures": preparations.REGRESSION_FIXTURE_SETS["audio-only"],
            "preparation:dynamic-range-corpus": preparations.REGRESSION_FIXTURE_SETS["dynamic-range"],
            "preparation:format-corpus": preparations.FORMAT_CORPUS_FIXTURES,
            "preparation:presentation-fixtures-device": tuple(
                dict.fromkeys(
                    preparations.REGRESSION_FIXTURE_SETS["presentation-tour"]
                    + preparations.REGRESSION_FIXTURE_SETS["projection-stereo"]
                )
            ),
            "preparation:presentation-fixtures-simulator": preparations.REGRESSION_FIXTURE_SETS["presentation-tour"],
            "preparation:projection-corpus": preparations.REGRESSION_FIXTURE_SETS["projection-stereo"]
            + ("generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",),
            "preparation:viewing-storage-fixtures-device": preparations.REGRESSION_FIXTURE_SETS["viewing-storage"],
            "preparation:viewing-storage-fixtures-simulator": preparations.REGRESSION_FIXTURE_SETS["viewing-storage"],
        }
        for identifier, expected_ids in expected.items():
            with self.subTest(preparation=identifier):
                plan = plans[identifier]
                staged = [
                    call.arguments["fixtureID"]
                    for call in plan.calls
                    if call.operation_id == "operation:media.stage-fixture@2"
                ]
                self.assertEqual(
                    staged,
                    list(expected_ids),
                )
                imported = [
                    call.arguments["fileName"]
                    for call in plan.calls
                    if call.operation_id == "operation:media.import-staged@2"
                ]
                if "viewing-storage" in identifier:
                    self.assertEqual(imported, [])
                else:
                    self.assertEqual(
                        imported,
                        [
                            preparations.STAGEABLE_FIXTURES[item].file_name
                            for item in staged
                            if Path(preparations.STAGEABLE_FIXTURES[item].file_name).suffix.removeprefix(".").lower()
                            in preparations.PREPARATION_IMPORT_EXTENSIONS
                            and (
                                preparations.PREPARATION_REGISTRY[
                                    identifier
                                ].directory_source
                                is None
                                or item
                                != preparations.PREPARATION_REGISTRY[
                                    identifier
                                ].directory_source.media_fixture_id
                            )
                        ],
                    )

    def test_format_corpus_includes_the_registered_duplicate_label_audio_fixture(self) -> None:
        fixture_id = "generated-sdr-avc-bframe-duplicate-label-audio-30s-v1"
        self.assertIn(fixture_id, preparations.REGRESSION_FIXTURE_SETS["format-corpus"])
        binding = preparations.STAGEABLE_FIXTURES[fixture_id]
        plan = self.plans()["preparation:format-corpus"]
        self.assertTrue(
            any(
                call.operation_id == "operation:media.stage-fixture@2"
                and call.arguments["fixtureID"] == fixture_id
                and call.arguments["sourceRoot"] == preparations.FIXTURE_SOURCE_ROOT
                for call in plan.calls
            )
        )
        self.assertTrue(
            any(
                call.operation_id == "operation:media.import-staged@2"
                and call.arguments["fileName"] == binding.file_name
                for call in plan.calls
            )
        )
        self.assertTrue(
            any(
                item.kind == "registered-fixture"
                and item.identity == fixture_id
                and item.digest == binding.digest
                for item in plan.prerequisites
            )
        )

    def test_format_corpus_imports_external_subtitles_with_their_media_directory(self) -> None:
        plan = self.plans()["preparation:format-corpus"]
        source_calls = [
            call
            for call in plan.calls
            if call.operation_id
            == "operation:preparation.local-directory-subtitle-source@1"
        ]
        self.assertEqual(len(source_calls), 1)
        self.assertEqual(
            dict(source_calls[0].arguments),
            {
                "directoryName": "format-corpus-multiaudio-avsync-30s-sidecars",
                "mediaFileName": "sdr-bframe-multiaudio-avsync-30s.mp4",
                "memberFileNames": [
                    "sdr-bframe-multiaudio-avsync-30s.mp4",
                    "sdr-bframe-multiaudio-avsync-30s.zh-CN.srt",
                    "sdr-bframe-multiaudio-avsync-30s.styled.ass",
                ],
            },
        )
        imported = {
            call.arguments["fileName"]
            for call in plan.calls
            if call.operation_id == "operation:media.import-staged@2"
        }
        self.assertTrue(
            {
                "sdr-bframe-multiaudio-avsync-30s.mp4",
                "sdr-bframe-multiaudio-avsync-30s.zh-CN.srt",
                "sdr-bframe-multiaudio-avsync-30s.styled.ass",
            }.isdisjoint(imported)
        )

    def test_format_corpus_closes_the_reviewed_codec_and_container_manifest(self) -> None:
        self.assertTrue(
            preparations.FORMAT_CORPUS_REQUIRED_FIXTURES.issubset(
                preparations.REGRESSION_FIXTURE_SETS["format-corpus"]
            )
        )
        self.assertEqual(
            preparations.FORMAT_CORPUS_REQUIRED_FIXTURES,
            {
                "generated-sdr-avc-bframe-audio-codec-matrix-15s-v1",
                "internal-fate-dts-es-matroska-v1",
                "internal-fate-truehd-atmos-matroska-v1",
                "internal-fate-vorbis-v1",
                "internal-apple-apmp-180-v1",
                "internal-apple-mvhevc-short-v1",
                "internal-fate-mpeg4-part2-packed-bframes-v1",
            },
        )
        plan = self.plans()["preparation:format-corpus"]
        self.assertEqual(plan.readiness, "ready")
        self.assertIsNone(plan.blocker)
        self.assertFalse(
            any(
                call.operation_id == "operation:host.preflight@1"
                for call in plan.calls
            )
        )

    def test_window_input_declares_the_only_real_lane_and_is_executable(self) -> None:
        plan = self.plans()["preparation:window-input-fixture"]
        self.assertEqual(plan.lane, "simulator")
        self.assertEqual(
            [
                call.arguments["fixtureID"]
                for call in plan.calls
                if call.operation_id == "operation:media.stage-fixture@2"
            ],
            ["generated-sdr-avc-bframe-multiaudio-avsync-120s-v1"],
        )
        self.assertEqual(plan.readiness, "ready")
        self.assertIsNone(plan.blocker)
        self.assertIn(
            "operation:media.import-staged@2",
            [call.operation_id for call in plan.calls],
        )
        self.assertEqual(
            dict(plan.calls[0].arguments),
            {"controlsAutoHideSeconds": 8},
        )
        self.assertIn(
            "operation:input.device-hub-prepare@1",
            [call.operation_id for call in plan.calls],
        )
        self.assertNotIn("operation:input.device-hub-pinch@2", [call.operation_id for call in plan.calls])

    def test_system_import_is_one_simulator_preflight_with_bound_runtime_and_device_hub(self) -> None:
        plan = self.plans()["preparation:system-import-fixtures"]
        self.assertEqual(plan.lane, "simulator")
        self.assertEqual(plan.readiness, "ready")
        self.assertIsNone(plan.blocker)
        self.assertEqual(
            [call.canonical() for call in plan.calls],
            [
                {
                    "callId": "call:preparation:system-import-fixtures:01",
                    "operation": "operation:host.preflight@1",
                    "arguments": {"check": "system-import-fixtures"},
                }
            ],
        )
        self.assertEqual(
            plan.state.tags,
            (
                "fixture.corpus",
                "input.device-hub",
                "lane.instance",
                "system.permission",
            ),
        )
        expected_runtime = str(
            (
                preparations.SYSTEM_IMPORT_RUNTIME_ROOT
                / plan.target
                / "runtime.json"
            ).resolve()
        )
        self.assertTrue(
            any(
                item.kind == "runtime-identity"
                and item.identity == expected_runtime
                for item in plan.prerequisites
            )
        )
        for identity, binding in preparations.SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES.items():
            self.assertTrue(
                any(
                    item.kind == identity
                    and item.identity == binding["path"]
                    and item.digest == binding["digest"]
                    for item in plan.prerequisites
                )
            )

    def test_system_import_state_requires_exact_assets_and_enlarged_canvas(self) -> None:
        plan = self.plans()["preparation:system-import-fixtures"]
        context = type(
            "Context",
            (),
            {"lane": "simulator", "target": "literal-lane-target"},
        )()
        result = {
            "succeeded": True,
            "report": {"ready": True},
            "deviceHub": {"canvas": {"width": 1729, "height": 972}},
        }

        class Invoker:
            def invoke(self, operation_id, arguments, execution_context):
                return type("Invocation", (), {"result": result})()

        with mock.patch.object(
            preparations.system_import,
            "validate_preflight_report",
            return_value=True,
        ) as validate:
            execution = preparations.execute_plan(plan, Invoker(), context)
        self.assertEqual(execution.state, plan.state)
        validate.assert_called_once()

        result["deviceHub"] = {"canvas": {"width": 1199, "height": 675}}
        with (
            mock.patch.object(
                preparations.system_import,
                "validate_preflight_report",
                return_value=True,
            ),
            self.assertRaises(preparations.PreparationExecutionError),
        ):
            preparations.execute_plan(plan, Invoker(), context)

    def test_unknown_ids_aliases_wrong_lanes_and_symbolic_targets_are_rejected(self) -> None:
        cases = (
            ("preparation:unknown", "device", "target"),
            ("preparation:local-aggregate:device", "device", "target"),
            ("preparation:local-aggregate-device", "simulator", "target"),
            ("preparation:window-input-fixture", "device", "target"),
            ("preparation:system-import-fixtures", "device", "target"),
            ("preparation:local-aggregate-device", "device", "<device>"),
            ("preparation:local-aggregate-device", "device", "lease://target"),
        )
        for preparation_id, lane, target in cases:
            with self.subTest(preparation=preparation_id, lane=lane, target=target):
                with self.assertRaises(preparations.PreparationAdapterError):
                    preparations.build_plan(preparation_id, lane, target)

    def test_arbitrary_queries_symbolic_fixture_sets_raw_secrets_and_unregistered_fixtures_are_rejected(self) -> None:
        base = self.plans()["preparation:local-aggregate-device"]
        first = base.calls[0]
        mutations = (
            replace(first, operation_id="operation:host.query@1"),
            replace(first, arguments={"source": "fixture-set:local-aggregate"}),
            replace(first, arguments={"password": "not-a-real-password"}),
            replace(first, arguments={"authorization": "Bearer not-a-real-token"}),
            replace(
                base.calls[4],
                arguments={
                    "fixtureID": "semantic-flat-video",
                    "sourceRoot": preparations.FIXTURE_SOURCE_ROOT,
                },
            ),
        )
        for call in mutations:
            calls = (call,) + base.calls[1:]
            malicious = replace(base, calls=calls)
            with self.subTest(call=call.operation_id):
                with self.assertRaises(preparations.PreparationAdapterError):
                    preparations.validate_plan(malicious)

    def test_canonical_registry_and_plans_contain_no_credential_bytes(self) -> None:
        serialized = json.dumps(
            {
                "registry": {
                    key: dict(value) for key, value in preparations.CANONICAL_REGISTRY.items()
                },
                "plans": [plan.canonical() for plan in self.plans().values()],
            },
            sort_keys=True,
        )
        lowered = serialized.casefold()
        self.assertNotIn('"authorization"', lowered)
        self.assertIsNone(re.search(r"(?i)\b(?:basic|bearer)\s+\S+", serialized))
        self.assertIsNone(re.search(r"[a-z][a-z0-9+.-]*://[^/@:]+:[^/@]+@", serialized))
        environment_path = REPOSITORY_ROOT / ".env"
        if environment_path.is_file():
            secrets = []
            for line in environment_path.read_text().splitlines():
                if "=" not in line or line.lstrip().startswith("#"):
                    continue
                key, value = line.split("=", 1)
                if any(word in key.casefold() for word in ("password", "token", "secret")):
                    value = value.strip().strip('"').strip("'")
                    if value:
                        secrets.append(value)
            self.assertFalse(
                any(value in serialized for value in secrets),
                "canonical Preparation data contains a credential value",
            )

    def test_remote_implementation_identity_and_runtime_reference_are_bound(self) -> None:
        plans = self.plans()
        affected = {
            identifier
            for identifier, spec in preparations.PREPARATION_REGISTRY.items()
            if spec.connect_webdav
        }
        self.assertEqual(
            affected,
            {
                "preparation:faultable-remote-source",
                "preparation:issue-fixtures",
                "preparation:local-directory-subtitle-source",
                "preparation:presentation-fixtures-device",
                "preparation:presentation-fixtures-simulator",
                "preparation:viewing-storage-fixtures-device",
                "preparation:viewing-storage-fixtures-simulator",
                "preparation:webdav-test-source",
            },
        )
        for identifier, plan in plans.items():
            prerequisites = {
                (item.kind, item.identity): item.digest for item in plan.prerequisites
            }
            for kind, binding in operations.REMOTE_IMPLEMENTATION_IDENTITIES.items():
                key = (kind, binding["path"])
                if identifier in affected:
                    self.assertEqual(prerequisites.get(key), binding["digest"])
                else:
                    self.assertNotIn(key, prerequisites)
            runtime_key = ("runtime-identity", str(operations.REMOTE_RUNTIME_FILE))
            if identifier in affected:
                self.assertIn(runtime_key, prerequisites)
            else:
                self.assertNotIn(runtime_key, prerequisites)

    def test_emby_source_is_ready_after_typed_public_connection_calls(self) -> None:
        plan = self.plans()["preparation:emby-test-library"]
        self.assertEqual(plan.readiness, "ready")
        self.assertIsNone(plan.blocker)
        self.assertEqual(
            [call.operation_id for call in plan.calls],
            [
                "operation:host.preflight@1",
                "operation:harness.ensure-session@1",
                "operation:app.relaunch@1",
                "operation:harness.reset-product-state@2",
                "operation:harness.assert-channels@2",
                "operation:navigation.select-tab@1",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.inspect@2",
                "operation:host.preflight@1",
            ],
        )
        self.assertEqual(plan.calls[0].arguments, {"check": "emby-aggregate"})
        self.assertEqual(plan.calls[5].arguments, {"tab": "emby"})
        typed = plan.calls[6:9]
        self.assertEqual(
            [call.arguments["identifier"] for call in typed],
            [
                "Emby-Connection-Address",
                "Emby-Connection-Username",
                "Emby-Connection-Password",
            ],
        )
        self.assertEqual(
            [call.arguments["textJSONKey"] for call in typed],
            ["address", "username", "password"],
        )
        self.assertTrue(
            all(
                call.arguments["textFile"] == str(preparations.EMBY_RUNTIME_FILE)
                for call in typed
            )
        )
        self.assertEqual(
            [call.arguments["secret"] for call in typed],
            [False, False, True],
        )
        self.assertTrue(all("text" not in call.arguments for call in typed))
        self.assertEqual(
            dict(plan.calls[9].arguments),
            {
                "context": "main-window-browser",
                "identifiers": ["Emby-Connection-Connect"],
                "settleDelayMillis": 30_000,
            },
        )
        self.assertEqual(
            dict(plan.calls[-2].arguments),
            {
                "context": "main-window-browser",
                "identifier": "Emby-Home",
                "requireMatchedElement": True,
            },
        )
        self.assertEqual(plan.calls[-1].arguments, {"check": "emby-aggregate"})
        self.assertEqual(plan.state.produced_by_call, plan.calls[-1].call_id)
        prerequisites = {
            (item.kind, item.identity): item.digest for item in plan.prerequisites
        }
        self.assertEqual(
            set(preparations.EMBY_IMPLEMENTATION_IDENTITIES),
            {
                "preparation-adapter",
                "emby-source-adapter",
                "environment-preflight-adapter",
                "emby-command-channel",
                "emby-account-session",
                "interactive-command-controller",
            },
        )
        for kind, binding in preparations.EMBY_IMPLEMENTATION_IDENTITIES.items():
            self.assertEqual(prerequisites[(kind, binding["path"])], binding["digest"])
        self.assertIn(
            ("runtime-identity", str(preparations.EMBY_RUNTIME_FILE)),
            prerequisites,
        )

    def test_emby_preflight_cannot_produce_evidence(self) -> None:
        preflight = operations.SPECS["operation:host.preflight@1"]
        self.assertEqual(preflight.outputs, ())

    def test_emby_plan_executes_only_registered_operations(self) -> None:
        plan = self.plans()["preparation:emby-test-library"]
        self.assertTrue(plan.calls)
        self.assertTrue(
            all(call.operation_id in operations.SPECS for call in plan.calls)
        )
        self.assertEqual(len(operations.SPECS), 35)

    def test_emby_state_declaration_retains_only_semantic_tags(self) -> None:
        state = self.plans()["preparation:emby-test-library"].state
        self.assertEqual(
            state.tags,
            (
                "app.session",
                "emby.account",
                "lane.instance",
                "source.connection",
                "source.emby",
                "source.emby.fixture-revision",
                "source.session",
            ),
        )
        self.assertEqual(
            state.produced_by_call,
            self.plans()["preparation:emby-test-library"].calls[-1].call_id,
        )

    def test_every_ready_preparation_uses_its_final_call_as_producer(self) -> None:
        plans = self.plans()
        for identifier in sorted(READY_IDS):
            with self.subTest(preparation=identifier):
                plan = plans[identifier]
                self.assertEqual(
                    plan.state.produced_by_call,
                    plan.calls[-1].call_id,
                )

    def test_smb_preparation_exports_the_session_tag_it_establishes(self) -> None:
        plan = self.plans()["preparation:smb-test-source"]
        self.assertIn("source.connection", plan.state.tags)
        self.assertIn("source.session", plan.state.tags)
        self.assertNotIn("source.smb", plan.state.tags)

    def test_connection_preparations_snapshot_the_source_state_their_calls_invalidate(self) -> None:
        plans = self.plans()
        expected = {
            "preparation:emby-test-library": {"source.connection", "source.session"},
            "preparation:faultable-remote-source": {"source.connection", "source.session"},
            "preparation:issue-fixtures": {"source.connection", "source.session"},
            "preparation:presentation-fixtures-device": {"source.connection", "source.session"},
            "preparation:presentation-fixtures-simulator": {
                "source.connection",
                "source.session",
            },
            "preparation:smb-test-source": {"source.connection", "source.session"},
            "preparation:viewing-storage-fixtures-device": {"source.connection", "source.session"},
            "preparation:viewing-storage-fixtures-simulator": {
                "source.connection",
                "source.session",
            },
        }
        for identifier, tags in expected.items():
            with self.subTest(preparation=identifier):
                self.assertLessEqual(tags, set(plans[identifier].state.tags))

    def test_webdav_source_is_ready_only_after_exact_typed_connection_calls(self) -> None:
        plan = self.plans()["preparation:webdav-test-source"]
        self.assertEqual(plan.readiness, "ready")
        self.assertIsNone(plan.blocker)
        self.assertEqual(
            [call.operation_id for call in plan.calls],
            [
                "operation:host.preflight@1",
                "operation:harness.ensure-session@1",
                "operation:app.relaunch@1",
                "operation:harness.reset-product-state@2",
                "operation:harness.assert-channels@2",
                "operation:navigation.select-tab@1",
                "operation:accessibility.activate@2",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.inspect@2",
                "operation:host.preflight@1",
            ],
        )
        self.assertEqual(plan.calls[0].arguments["check"], "webdav-regression")
        self.assertEqual(
            plan.calls[6].arguments["identifiers"],
            [
                "FileBrowsing-SourcesSidebar-sourceMore",
                "FileBrowsing-SourcesSidebar-add",
                "FileBrowsing-SourcesSidebar-addWebDAV",
            ],
        )
        self.assertEqual(
            dict(plan.calls[13].arguments),
            {"context": "main-window-browser", "labels": ["以后"]},
        )
        self.assertEqual(
            [dict(call.arguments) for call in plan.calls[11:14]],
            [
                {
                    "context": "main-window-browser",
                    "identifiers": [
                        "FileBrowsing-SourceConnection-webDAV-connect"
                    ],
                },
                {
                    "context": "main-window-browser",
                    "identifiers": ["FileBrowsing-CertificateTrust-trust"],
                },
                {"context": "main-window-browser", "labels": ["以后"]},
            ],
        )
        typed = [
            call for call in plan.calls
            if call.operation_id == "operation:accessibility.type@2"
        ]
        self.assertEqual(typed[0].arguments["text"], "Enchron Regression WebDAV")
        self.assertEqual(
            [call.arguments.get("textJSONKey") for call in typed[1:]],
            ["address", "user", "password"],
        )
        self.assertTrue(
            all(call.arguments["textFile"] == str(operations.REMOTE_RUNTIME_FILE) for call in typed[1:])
        )
        self.assertEqual([call.arguments["secret"] for call in typed], [False, False, False, True])
        self.assertNotIn("text", typed[-1].arguments)
        self.assertEqual(
            plan.calls[-2].arguments["identifier"],
            "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        )
        self.assertTrue(plan.calls[-2].arguments["requireMatchedElement"])
        self.assertEqual(plan.calls[-1].arguments["check"], "webdav-regression")
        self.assertEqual(plan.state.produced_by_call, plan.calls[-1].call_id)

    def test_smb_source_is_ready_only_after_exact_typed_product_connection(self) -> None:
        plan = self.plans()["preparation:smb-test-source"]
        self.assertEqual(plan.readiness, "ready")
        self.assertIsNone(plan.blocker)
        self.assertEqual(
            [call.operation_id for call in plan.calls],
            [
                "operation:host.preflight@1",
                "operation:harness.ensure-session@1",
                "operation:app.relaunch@1",
                "operation:harness.reset-product-state@2",
                "operation:harness.assert-channels@2",
                "operation:navigation.select-tab@1",
                "operation:accessibility.activate@2",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.type@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.activate@2",
                "operation:accessibility.inspect@2",
                "operation:host.preflight@1",
            ],
        )
        typed = [
            call
            for call in plan.calls
            if call.operation_id == "operation:accessibility.type@2"
        ]
        self.assertEqual(typed[0].arguments["text"], "Enchron Regression SMB")
        self.assertEqual(
            [call.arguments.get("textJSONKey") for call in typed[1:]],
            ["address", "user", "password"],
        )
        self.assertTrue(
            all(
                call.arguments["textFile"] == str(operations.SMB_RUNTIME_FILE)
                for call in typed[1:]
            )
        )
        self.assertEqual(
            [call.arguments["identifier"] for call in typed],
            [
                "FileBrowsing-SourceConnection-smb-name",
                "FileBrowsing-SourceConnection-smb-address",
                "FileBrowsing-SourceConnection-smb-username",
                "FileBrowsing-SourceConnection-smb-password",
            ],
        )
        self.assertEqual(
            [call.arguments["secret"] for call in typed],
            [False, False, False, True],
        )
        self.assertEqual(
            plan.calls[6].arguments["identifiers"],
            [
                "FileBrowsing-SourcesSidebar-sourceMore",
                "FileBrowsing-SourcesSidebar-add",
                "FileBrowsing-SourcesSidebar-addSMB",
            ],
        )
        self.assertEqual(
            dict(plan.calls[12].arguments),
            {"context": "main-window-browser", "labels": ["以后"]},
        )
        self.assertEqual(
            [dict(call.arguments) for call in plan.calls[11:13]],
            [
                {
                    "context": "main-window-browser",
                    "identifiers": ["FileBrowsing-SourceConnection-smb-connect"],
                },
                {"context": "main-window-browser", "labels": ["以后"]},
            ],
        )
        self.assertEqual(
            plan.calls[-6].arguments["identifiers"],
            ["FileBrowsing-grid-folder-TestMedia"],
        )
        self.assertEqual(
            [call.arguments["identifiers"] for call in plan.calls[-5:-2]],
            [
                ["FileBrowsing-grid-folder-TestVectors"],
                ["FileBrowsing-grid-folder-Enchron"],
                ["FileBrowsing-grid-folder-PlaybackBehavior"],
            ],
        )
        self.assertEqual(
            plan.calls[-2].arguments["identifier"],
            "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        )
        self.assertTrue(plan.calls[-2].arguments["requireMatchedElement"])
        self.assertEqual(plan.calls[-1].arguments["check"], "smb-aggregate")
        self.assertEqual(plan.state.produced_by_call, plan.calls[-1].call_id)

        prerequisites = {
            (item.kind, item.identity): item.digest for item in plan.prerequisites
        }
        for kind, binding in operations.SMB_IMPLEMENTATION_IDENTITIES.items():
            self.assertEqual(
                prerequisites[(kind, binding["path"])], binding["digest"]
            )
        self.assertIn(
            ("runtime-identity", str(operations.SMB_RUNTIME_FILE)), prerequisites
        )

    def test_webdav_connection_tail_is_identical_on_device_and_simulator(self) -> None:
        plans = self.plans()

        def connection_tail(identifier: str):
            calls = plans[identifier].calls
            start = next(
                index
                for index, call in enumerate(calls)
                if call.operation_id == "operation:navigation.select-tab@1"
            )
            return [
                (call.operation_id, dict(call.arguments))
                for call in calls[start:]
            ]

        for device_id, simulator_id in (
            (
                "preparation:presentation-fixtures-device",
                "preparation:presentation-fixtures-simulator",
            ),
            (
                "preparation:viewing-storage-fixtures-device",
                "preparation:viewing-storage-fixtures-simulator",
            ),
        ):
            with self.subTest(device=device_id, simulator=simulator_id):
                self.assertEqual(
                    connection_tail(device_id),
                    connection_tail(simulator_id),
                )

        for identifier, spec in preparations.PREPARATION_REGISTRY.items():
            if not spec.connect_webdav:
                continue
            with self.subTest(preparation=identifier):
                calls = plans[identifier].calls
                menu_calls = [
                    call
                    for call in calls
                    if call.operation_id == "operation:accessibility.activate@2"
                    and call.arguments.get("identifiers")
                    == [
                        "FileBrowsing-SourcesSidebar-sourceMore",
                        "FileBrowsing-SourcesSidebar-add",
                        "FileBrowsing-SourcesSidebar-addWebDAV",
                    ]
                ]
                dismiss_calls = [
                    call
                    for call in calls
                    if call.operation_id == "operation:accessibility.activate@2"
                    and call.arguments.get("labels") == ["以后"]
                ]
                self.assertEqual(len(menu_calls), 1)
                self.assertEqual(len(dismiss_calls), 1)
                connect_index = next(
                    index
                    for index, call in enumerate(calls)
                    if call.arguments.get("identifiers")
                    == ["FileBrowsing-SourceConnection-webDAV-connect"]
                )
                dismiss_index = calls.index(dismiss_calls[0])
                self.assertGreater(dismiss_index, connect_index)

    def test_remote_fault_and_issue_preparations_are_webdav_only_and_ready(self) -> None:
        plans = self.plans()
        for identifier in (
            "preparation:faultable-remote-source",
            "preparation:issue-fixtures",
        ):
            with self.subTest(preparation=identifier):
                spec = preparations.PREPARATION_REGISTRY[identifier]
                plan = plans[identifier]
                self.assertEqual(plan.readiness, "ready")
                self.assertIsNone(plan.blocker)
                self.assertNotIn("source.smb", spec.tags)
                self.assertIn("source.webdav", spec.tags)
                self.assertTrue(spec.connect_webdav)
                canonical = json.dumps(plan.canonical(), sort_keys=True)
                self.assertNotIn(str(operations.SMB_RUNTIME_FILE), canonical)
                self.assertNotIn("smb-source-preflight", canonical)
                self.assertEqual(
                    [
                        call.arguments["check"]
                        for call in plan.calls
                        if call.operation_id == "operation:host.preflight@1"
                    ],
                    ["remote-faults", "webdav-regression"],
                )
                self.assertTrue(
                    any(
                        call.operation_id == "operation:accessibility.type@2"
                        and call.arguments.get("textJSONKey") == "password"
                        and call.arguments.get("secret") is True
                        for call in plan.calls
                    )
                )
        remote_wording = json.dumps(
            {
                identifier: plan.blocker.canonical()
                for identifier, plan in plans.items()
                if plan.blocker is not None
            },
            sort_keys=True,
        )
        for closed_phrase in (
            "owned HTTPS WebDAV preflight",
            "neutral reversible fault controller",
            "owned reversible four-case source-failure configurator",
            "remote presentation source with request-log identity",
            "logged remote source",
            "SMB fault",
            "connected SMB",
        ):
            self.assertNotIn(closed_phrase, remote_wording)

    def test_presentation_and_viewing_preparations_are_concrete_and_ready(self) -> None:
        plans = self.plans()
        expected_presentation_names = {
            "preparation:presentation-fixtures-device": {
                preparations.STAGEABLE_FIXTURES[fixture_id].file_name
                for fixture_id in tuple(
                    dict.fromkeys(
                        preparations.REGRESSION_FIXTURE_SETS["presentation-tour"]
                        + preparations.REGRESSION_FIXTURE_SETS["projection-stereo"]
                    )
                )
            },
            "preparation:presentation-fixtures-simulator": {
                preparations.STAGEABLE_FIXTURES[fixture_id].file_name
                for fixture_id in preparations.REGRESSION_FIXTURE_SETS["presentation-tour"]
            },
        }
        for identifier, expected_names in expected_presentation_names.items():
            plan = plans[identifier]
            self.assertEqual(plan.readiness, "ready")
            self.assertIsNone(plan.blocker)
            names = {
                preparations.STAGEABLE_FIXTURES[call.arguments["fixtureID"]].file_name
                for call in plan.calls
                if call.operation_id == "operation:media.stage-fixture@2"
            }
            self.assertEqual(names, expected_names)

        for identifier in (
            "preparation:viewing-storage-fixtures-device",
            "preparation:viewing-storage-fixtures-simulator",
        ):
            plan = plans[identifier]
            self.assertEqual(plan.readiness, "ready")
            self.assertIsNone(plan.blocker)
            names = {
                preparations.STAGEABLE_FIXTURES[call.arguments["fixtureID"]].file_name
                for call in plan.calls
                if call.operation_id == "operation:media.stage-fixture@2"
            }
            self.assertEqual(
                names,
                {
                    "sdr-bframe-aggregate-30s.mkv",
                    "viewing-storage-16m01s.mp4",
                    "viewing-storage-16m01s-b.mp4",
                    "sdr-bframe-multiaudio-avsync-30s.mp4",
                    "sdr-bframe-multiaudio-avsync-120s.mp4",
                },
            )
            self.assertEqual(
                [
                    call.arguments["target"]
                    for call in plan.calls
                    if call.operation_id == "operation:storage.clear@1"
                ],
                ["container-index-cache", "playback-progress"],
            )
            self.assertFalse(
                any(
                    call.operation_id == "operation:media.import-staged@2"
                    for call in plan.calls
                )
            )

    def test_remote_fault_preflight_authority_covers_all_recipes_and_restore(self) -> None:
        self.assertEqual(
            remote.RECIPE_NAMES,
            (
                "healthy",
                "credentials-rejected",
                "missing-object",
                "access-denied",
                "corrupt-media",
                "recoverable-read-interruption",
                "finite-reconnect",
                "buffer-absorbed-interruption",
                "certificate-rotation",
                "transport-interrupted",
            ),
        )
        source = (REPOSITORY_ROOT / "Scripts/verification/regression_environment_preflight.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("controller.restore", source)
        self.assertIn('final["recipe"] == "healthy"', source)
        for identifier in (
            "preparation:faultable-remote-source",
            "preparation:issue-fixtures",
        ):
            checks = [
                call.arguments["check"]
                for call in self.plans()[identifier].calls
                if call.operation_id == "operation:host.preflight@1"
            ]
            self.assertEqual(
                checks,
                ["remote-faults", "webdav-regression"]
                if preparations.PREPARATION_REGISTRY[identifier].connect_webdav
                else ["remote-faults"],
            )

    def test_ready_plan_executes_in_order(self) -> None:
        plans = self.plans()
        backend = FakeBackend()
        invoker = operations.RegressionOperationAdapter(backend)
        with tempfile.TemporaryDirectory(prefix="preparation-plan-test-") as directory:
            root = Path(directory).resolve()
            context = operations.OperationContext(
                "device", "literal-lane-target", root, root / "controller"
            )
            execution = preparations.execute_plan(
                plans["preparation:local-aggregate-device"], invoker, context
            )
        self.assertEqual(execution.plan_digest, plans["preparation:local-aggregate-device"].plan_digest)
        self.assertEqual(
            [operation_id for operation_id, _, _ in backend.calls],
            [call.operation_id for call in plans["preparation:local-aggregate-device"].calls],
        )

    def test_local_directory_preparation_execution_requires_its_typed_receipt(self) -> None:
        plan = self.plans()["preparation:local-directory-subtitle-source"]
        source_call = plan.calls[-1]
        directory_name = str(source_call.arguments["directoryName"])
        media_name = str(source_call.arguments["mediaFileName"])
        root_path = f"/private/app/Documents/TestMediaInbox/{directory_name}"
        receipt = {
            "schema": "enchron.regression.directory-media-import@1",
            "directoryName": directory_name,
            "mediaFileName": media_name,
            "memberFileNames": sorted(source_call.arguments["memberFileNames"]),
            "referenceID": "22222222-2222-4222-8222-222222222222",
            "bookmarkRootPath": root_path,
            "bookmarkRootIsDirectory": True,
            "mediaRelativePath": media_name,
            "mediaSourcePath": f"{root_path}/{media_name}",
        }
        context = type(
            "Context", (), {"lane": "device", "target": "literal-lane-target"}
        )()

        class ReceiptInvoker:
            def __init__(self, include_receipt: bool):
                self.include_receipt = include_receipt

            def invoke(self, operation_id, arguments, execution_context):
                result = {"succeeded": True}
                if (
                    self.include_receipt
                    and operation_id
                    == "operation:preparation.local-directory-subtitle-source@1"
                ):
                    result["directoryMediaImportReceipt"] = receipt
                return type("Invocation", (), {"result": result})()

        execution = preparations.execute_plan(plan, ReceiptInvoker(True), context)
        self.assertEqual(execution.state, plan.state)
        with self.assertRaises(preparations.PreparationExecutionError):
            preparations.execute_plan(plan, ReceiptInvoker(False), context)

    def test_runtime_failure_is_an_error_not_a_non_applicable_verdict(self) -> None:
        plan = self.plans()["preparation:local-aggregate-device"]

        class FailedInvoker:
            def invoke(self, operation_id, arguments, context):
                return type("Invocation", (), {"result": {"succeeded": False}})()

        context = type(
            "Context", (), {"lane": "device", "target": "literal-lane-target"}
        )()
        with self.assertRaises(preparations.PreparationExecutionError):
            preparations.execute_plan(plan, FailedInvoker(), context)
        vocabulary = json.dumps(plan.canonical()).casefold()
        self.assertNotIn("skipped", vocabulary)
        self.assertNotIn("voided", vocabulary)
        self.assertNotIn("notapplicable", vocabulary.replace("-", ""))


if __name__ == "__main__":
    unittest.main()
