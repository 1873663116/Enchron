#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import fields, replace
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(SCRIPTS / "verification"))

import regression_oracle_adapter as adapter
from regression.core.contracts import ArtifactClass, OracleKind
from regression.core.digest import canonical_bytes, canonical_digest
from regression.core.expression import OracleResult
from regression.core.ids import (
    CallID,
    CaseKey,
    Digest,
    EvidenceSchema,
    EvidenceType,
    LeaseID,
    ObligationID,
    OracleID,
    RubricID,
)
from regression.core.plan import (
    AgentEnvironment,
    EvaluationBinding,
    OracleEvaluationBinding,
    RubricEvaluationBinding,
)
from regression.core.runtime import (
    CriterionEvaluation,
    NegativeControlEvaluation,
    OracleDiagnostic,
    OracleEvaluationRequest,
)
from regression.core.store import ArtifactReceipt


SHA = "sha256:" + "1" * 64
PROVENANCE = adapter.EvidenceProvenance(
    obligation_id="obligation:test-evidence",
    case_key="test-case",
    call_id="call:test-producer",
    operation_id="operation:test-producer@1",
    contract_digest=SHA,
    arguments={},
    arguments_digest=canonical_digest({}),
    implementation_locator="Scripts/test-producer.py",
    implementation_digest=SHA,
)
CRITERIA = (
    "The first required fact is established.",
    "The second required fact is established.",
)


def _successful_transcript(operation_output: object):
    return (
        {
            **dict(PROVENANCE.payload()["producer"]),
            "grantId": "grant:test-producer:1",
            "invocationIndex": 1,
            "status": "succeeded",
            "operationResult": operation_output,
            "operationError": "",
        },
    )


def _typed_payload(
    evidence_type: str,
    evidence_schema: str,
    operation_output: object,
):
    return adapter.build_typed_evidence_payload(
        evidence_type,
        evidence_schema,
        operation_output,
        PROVENANCE,
        operation_transcript=_successful_transcript(operation_output),
    )
NEGATIVE_CONTROLS = (
    "The forbidden fallback is absent.",
    "Contradictory evidence is not accepted.",
)


def _raw_output(identifier: str) -> dict[str, object]:
    values: dict[str, dict[str, object]] = {
        "oracle:agent-audio@2": {
            "succeeded": True,
            "measurement": {
                "dominantFrequencyHz": 997.5,
                "rmsDbfs": -12.0,
                "silent": False,
            },
            "wavPath": "audio/fixture.wav",
        },
        "oracle:agent-visual@2": {
            "succeeded": True,
            "context": "window",
            "artifactRoot": "controller",
            "frames": [
                {
                    "index": 0,
                    "capturedAtMonotonicMillis": 10,
                    "record": {"success": True, "screenshot": "frame-0.png"},
                }
            ],
        },
        "oracle:agent-structured-accessibility-tree@1": {
            "succeeded": True,
            "context": "window",
            "response": {
                "success": True,
                "matchedElement": {"identifier": "PlayerUI-control", "value": "Playing"},
                "hierarchy": "Window/Button",
            },
        },
        "oracle:agent-structured-emby-range-log@1": {
            "succeeded": True,
            "itemID": "emby-item",
            "fileSize": 4096,
            "openCount": 2,
            "secondOpenRequests": 1,
            "indexWindowHits": [],
        },
        "oracle:agent-structured-interaction-trace@1": {
            "succeeded": True,
            "cursorToken": "7:20",
            "compacted": False,
            "lines": ["toggle source=window"],
            "interactionTrace": ["toggle source=window"],
            "spatialInputTrace": ["spatialTap entity=surface"],
        },
        "oracle:agent-structured-library-command@1": {
            "succeeded": True,
            "response": {"success": True, "payload": ["folder=Movies"]},
            "snapshot": {"folders": [], "references": [], "stagedFiles": []},
            "entries": [{"kind": "folder", "name": "Movies"}],
        },
        "oracle:agent-structured-playback-probe@1": {
            "succeeded": True,
            "fields": {"lifecycle": "playing", "positionMillis": "1200"},
            "response": {"success": True, "hierarchy": "Playback"},
        },
        "oracle:agent-structured-spatial-input@1": {
            "succeeded": True,
            "cursorToken": "7:20",
            "compacted": False,
            "lines": ["spatialTap entity=surface"],
            "interactionTrace": ["toggle source=window"],
            "spatialInputTrace": ["spatialTap entity=surface"],
        },
        "oracle:agent-structured-structural-test@2": {
            "succeeded": True,
            "check": "regression-core",
            "command": ["python3", "-m", "unittest"],
            "returnCode": 0,
            "artifactPath": "structural/regression-core.log",
            "artifactDigest": SHA,
            "toolchain": "/Applications/Xcode-beta.app/Contents/Developer",
        },
        "oracle:agent-structured-transition@1": {
            "succeeded": True,
            "response": {"success": True, "transitionTraceAnalysis": {"switchCount": 1}},
            "snapshot": {"generation": "7", "records": [{"sequence": 1}]},
            "analysis": {"switchCount": 1},
        },
        "oracle:agent-structured-window-control-plane@1": {
            "succeeded": True,
            "fields": {"presentation": "window", "lifecycle": "playing"},
            "response": {"success": True, "hierarchy": "Window"},
        },
    }
    return json.loads(json.dumps(values[identifier]))


class SatisfyingProvider:
    def __init__(self) -> None:
        self.agent_environment = None
        self.requests: list[adapter.OracleDecisionRequest] = []

    def decide(self, request: adapter.OracleDecisionRequest) -> adapter.OracleDecision:
        self.requests.append(request)
        return adapter.OracleDecision(
            criteria=tuple(
                CriterionEvaluation(statement, OracleResult.SATISFIED)
                for statement in request.criteria
            ),
            negative_controls=tuple(
                NegativeControlEvaluation(statement, OracleResult.SATISFIED)
                for statement in request.negative_controls
            ),
            diagnostics=(
                OracleDiagnostic(
                    "oracle.reviewed", "The provider inspected the typed artifact."
                ),
            ),
        )


class OracleAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="oracle-adapter-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_registry_is_the_exact_catalog_v2_set_with_one_pair_each(self) -> None:
        expected = {
            "oracle:agent-audio@2": ("agent", "audio.measurement", "audio-measurement@2"),
            "oracle:agent-visual@2": ("agent", "visual.frames", "frame-sequence@2"),
            "oracle:agent-structured-accessibility-tree@1": ("agent", "accessibility.tree", "accessibility-tree@1"),
            "oracle:agent-structured-emby-range-log@1": ("agent", "emby.range-log", "emby-range-log@1"),
            "oracle:agent-structured-interaction-trace@1": ("agent", "interaction.trace", "interaction-trace@1"),
            "oracle:agent-structured-library-command@1": ("agent", "library.command", "library-command@1"),
            "oracle:agent-structured-playback-probe@1": ("agent", "playback.probe", "playback-probe@1"),
            "oracle:agent-structured-spatial-input@1": ("agent", "spatial.input", "spatial-input@1"),
            "oracle:agent-structured-structural-test@2": ("agent", "structural.test", "structural-test@2"),
            "oracle:agent-structured-transition@1": ("agent", "transition.trace", "transition-trace@1"),
            "oracle:agent-structured-window-control-plane@1": ("agent", "window.control-plane", "window-control-plane@1"),
        }
        actual = {
            identifier: (spec.kind.value, spec.evidence_type, spec.evidence_schema)
            for identifier, spec in adapter.SPECS.items()
        }
        self.assertEqual(actual, expected)
        self.assertEqual(
            len({(spec.evidence_type, spec.evidence_schema) for spec in adapter.SPECS.values()}),
            11,
        )

    def test_builder_maps_all_eleven_operation_outputs_to_exact_typed_payloads(self) -> None:
        direct_sources = {
            "oracle:agent-visual@2": "frames",
            "oracle:agent-structured-interaction-trace@1": "interactionTrace",
            "oracle:agent-structured-spatial-input@1": "spatialInputTrace",
        }
        for identifier, spec in adapter.SPECS.items():
            with self.subTest(oracle=identifier):
                raw = _raw_output(identifier)
                payload = _typed_payload(
                    spec.evidence_type, spec.evidence_schema, raw
                )
                expected_keys = {
                    "schema",
                    "schemaVersion",
                    "evidenceType",
                    "evidenceSchema",
                    "obligationId",
                    "caseKey",
                    "producer",
                    "operationOutput",
                    "operationTranscript",
                    "attachments",
                    spec.payload_field,
                }
                if identifier == "oracle:agent-audio@2":
                    expected_keys.add("wavPath")
                    self.assertEqual(payload["measurement"], raw["measurement"])
                    self.assertEqual(payload["wavPath"], raw["wavPath"])
                elif identifier in direct_sources:
                    self.assertEqual(
                        payload[spec.payload_field], raw[direct_sources[identifier]]
                    )
                else:
                    self.assertEqual(payload[spec.payload_field], [raw])
                self.assertEqual(set(payload), expected_keys)
                self.assertEqual(payload["schema"], adapter.ARTIFACT_SCHEMA)
                self.assertEqual(payload["schemaVersion"], 4)
                self.assertEqual(payload["evidenceType"], spec.evidence_type)
                self.assertEqual(payload["evidenceSchema"], spec.evidence_schema)
                self.assertEqual(payload["obligationId"], PROVENANCE.obligation_id)
                self.assertEqual(payload["caseKey"], PROVENANCE.case_key)
                self.assertEqual(payload["operationOutput"], raw)
                self.assertEqual(
                    payload["operationTranscript"][-1]["operationResult"],
                    raw,
                )
                self.assertEqual(payload["attachments"], [])
                self.assertEqual(
                    payload["producer"]["argumentsDigest"],
                    canonical_digest(payload["producer"]["arguments"]),
                )
                self.assertEqual(
                    canonical_bytes(payload), canonical_bytes(json.loads(canonical_bytes(payload)))
                )

    def test_builder_rejects_wrong_pairs_failed_results_and_malformed_shapes(self) -> None:
        with self.assertRaisesRegex(adapter.OracleAdapterError, "registered evidence pair"):
            _typed_payload(
                "visual.frames",
                "audio-measurement@2",
                _raw_output("oracle:agent-visual@2"),
            )
        with self.assertRaisesRegex(adapter.OracleAdapterError, "successful"):
            _typed_payload(
                "visual.frames",
                "frame-sequence@2",
                {"succeeded": False, "frames": [{}]},
            )
        for malformed in (
            None,
            {},
            {"succeeded": True},
            {"succeeded": True, "frames": []},
        ):
            with self.subTest(malformed=malformed):
                with self.assertRaises(adapter.OracleAdapterError):
                    _typed_payload(
                        "visual.frames", "frame-sequence@2", malformed
                    )
        for spec in adapter.SPECS.values():
            with self.subTest(pair=(spec.evidence_type, spec.evidence_schema)):
                with self.assertRaises(adapter.OracleAdapterError):
                    _typed_payload(
                        spec.evidence_type,
                        spec.evidence_schema,
                        {"succeeded": True},
                    )

    def test_operation_transcript_requires_a_successful_final_producer_attempt(self) -> None:
        spec = adapter.SPECS["oracle:agent-structured-playback-probe@1"]
        output = _raw_output("oracle:agent-structured-playback-probe@1")
        failed_result = {**output, "succeeded": False, "reason": "retryable"}
        failed_transcript = (
            {
                **dict(PROVENANCE.payload()["producer"]),
                "grantId": "grant:test-producer:1",
                "invocationIndex": 1,
                "status": "failed",
                "operationResult": failed_result,
                "operationError": "retryable",
            },
        )

        with self.assertRaisesRegex(
            adapter.OracleAdapterError, "final producer attempt must be successful"
        ):
            adapter.build_typed_evidence_payload(
                spec.evidence_type,
                spec.evidence_schema,
                output,
                PROVENANCE,
                operation_transcript=failed_transcript,
            )

    def test_library_command_accepts_the_structured_snapshot_as_its_observation(self) -> None:
        spec = adapter.SPECS["oracle:agent-structured-library-command@1"]
        raw = {
            "succeeded": True,
            "snapshot": {"folders": [], "references": [], "stagedFiles": []},
        }
        payload = _typed_payload(
            spec.evidence_type,
            spec.evidence_schema,
            raw,
        )
        self.assertEqual(payload[spec.payload_field], [raw])

    def test_builder_and_reader_reject_producer_judgments(self) -> None:
        spec = adapter.SPECS["oracle:agent-structured-window-control-plane@1"]
        for injection in (
            {"assertions": [{"criterion": CRITERIA[0], "observations": ["satisfied"]}]},
            {"nested": {"verdict": "violated"}},
            {"nested": {"result": "satisfied"}},
        ):
            with self.subTest(injection=injection):
                raw = _raw_output(spec.identifier)
                raw.update(injection)
                with self.assertRaisesRegex(adapter.OracleAdapterError, "judgment"):
                    _typed_payload(
                        spec.evidence_type, spec.evidence_schema, raw
                    )

        payload = self._payload(spec.identifier)
        payload["assertions"] = {"criteria": []}
        with self.assertRaisesRegex(adapter.OracleAdapterError, "unknown fields"):
            adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(
                self._request(spec.identifier, payload)
            )

    def test_nested_product_facts_are_open_while_typed_envelope_is_closed(self) -> None:
        identifier = "oracle:agent-structured-playback-probe@1"
        raw = _raw_output(identifier)
        raw["futureProductFact"] = {"newField": 3}
        spec = adapter.SPECS[identifier]
        payload = _typed_payload(
            spec.evidence_type, spec.evidence_schema, raw
        )
        result = adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(
            self._request(identifier, payload)
        )
        self.assertIs(result.overall, OracleResult.SATISFIED)

        payload["futureEnvelopeField"] = 3
        with self.assertRaisesRegex(adapter.OracleAdapterError, "unknown fields"):
            adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(
                self._request(identifier, payload)
            )

    def test_content_addressed_attachment_must_still_match_at_oracle_time(self) -> None:
        identifier = "oracle:agent-visual@2"
        spec = adapter.SPECS[identifier]
        path = self.root / "frame.png"
        data = b"stable-image-bytes"
        path.write_bytes(data)
        attachment = adapter.EvidenceAttachment(
            role="visual.frame[0]",
            media_type="image/png",
            path=str(path.resolve()),
            byte_length=len(data),
            digest="sha256:" + hashlib.sha256(data).hexdigest(),
        )
        payload = adapter.build_typed_evidence_payload(
            spec.evidence_type,
            spec.evidence_schema,
            _raw_output(identifier),
            PROVENANCE,
            attachments=(attachment,),
            operation_transcript=_successful_transcript(_raw_output(identifier)),
        )
        result = adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(
            self._request(identifier, payload)
        )
        self.assertIs(result.overall, OracleResult.SATISFIED)

        path.write_bytes(b"mutated")
        with self.assertRaisesRegex(adapter.OracleAdapterError, "drifted"):
            adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(
                self._request(identifier, payload)
            )

    def test_every_oracle_kind_uses_the_decision_provider(self) -> None:
        provider = SatisfyingProvider()
        evaluator = adapter.RegressionOracleAdapter(provider)
        for identifier, spec in adapter.SPECS.items():
            with self.subTest(oracle=identifier):
                request = self._request(identifier, self._payload(identifier))
                result = evaluator.evaluate(request)
                self.assertIs(result.overall, OracleResult.SATISFIED)
                provider_request = provider.requests[-1]
                self.assertIs(provider_request.oracle_kind, spec.kind)
                self.assertEqual(provider_request.criteria, CRITERIA)
                self.assertEqual(provider_request.negative_controls, NEGATIVE_CONTROLS)
                self.assertEqual(
                    provider_request.receipt_digest, request.artifact.receipt_digest
                )
                self.assertEqual(
                    provider_request.artifact_path, request.artifact.object_path
                )

        self.assertEqual(len(provider.requests), 11)

    def test_provider_request_contains_only_the_approved_judgment_inputs(self) -> None:
        provider = SatisfyingProvider()
        identifier = "oracle:agent-structured-structural-test@2"
        request = self._request(identifier, self._payload(identifier))
        adapter.RegressionOracleAdapter(provider).evaluate(request)
        self.assertEqual(
            {field.name for field in fields(provider.requests[0])},
            {
                "oracle_kind",
                "criteria",
                "negative_controls",
                "artifact_path",
                "artifact_payload",
                "receipt_digest",
            },
        )
        self.assertNotIn("assertions", provider.requests[0].artifact_payload)

    def test_missing_provider_is_per_rule_indeterminate_for_both_kinds(self) -> None:
        for identifier in (
            "oracle:agent-visual@2",
            "oracle:agent-structured-structural-test@2",
        ):
            with self.subTest(oracle=identifier):
                result = adapter.RegressionOracleAdapter().evaluate(
                    self._request(identifier, self._payload(identifier))
                )
                self.assertIs(result.overall, OracleResult.INDETERMINATE)
                self.assertTrue(
                    all(item.result is OracleResult.INDETERMINATE for item in result.criteria)
                )
                self.assertTrue(
                    all(
                        item.result is OracleResult.INDETERMINATE
                        for item in result.negative_controls
                    )
                )
                self.assertIn(
                    "oracle.provider-unavailable", {item.code for item in result.detail}
                )

    def test_command_success_and_return_code_never_decide_a_rubric(self) -> None:
        identifier = "oracle:agent-structured-structural-test@2"
        payload = self._payload(identifier)
        self.assertTrue(payload["tests"][0]["succeeded"])
        self.assertEqual(payload["tests"][0]["returnCode"], 0)
        result = adapter.RegressionOracleAdapter().evaluate(
            self._request(identifier, payload)
        )
        self.assertIs(result.overall, OracleResult.INDETERMINATE)

    def test_nonzero_structural_result_reaches_the_oracle_as_typed_evidence(self) -> None:
        identifier = "oracle:agent-structured-structural-test@2"
        raw = _raw_output(identifier)
        raw["returnCode"] = 1
        spec = adapter.SPECS[identifier]
        payload = _typed_payload(
            spec.evidence_type,
            spec.evidence_schema,
            raw,
        )
        provider = SatisfyingProvider()
        result = adapter.RegressionOracleAdapter(provider).evaluate(
            self._request(identifier, payload)
        )

        self.assertIs(result.overall, OracleResult.SATISFIED)
        self.assertEqual(provider.requests[0].artifact_payload["tests"][0]["returnCode"], 1)

    def test_provider_must_return_exact_typed_rule_coverage(self) -> None:
        class BadProvider:
            def decide(self, request):
                return adapter.OracleDecision(
                    criteria=(
                        CriterionEvaluation("undeclared", OracleResult.SATISFIED),
                    ),
                    negative_controls=(),
                )

        with self.assertRaisesRegex(adapter.OracleAdapterError, "rubric order"):
            adapter.RegressionOracleAdapter(BadProvider()).evaluate(
                self._request(
                    "oracle:agent-structured-transition@1",
                    self._payload("oracle:agent-structured-transition@1"),
                )
            )

    def test_untyped_provider_result_and_unbounded_diagnostics_are_rejected(self) -> None:
        class UntypedProvider:
            def decide(self, request):
                return {"overall": "skipped"}

        with self.assertRaisesRegex(adapter.OracleAdapterError, "OracleDecision"):
            adapter.RegressionOracleAdapter(UntypedProvider()).evaluate(
                self._request(
                    "oracle:agent-audio@2", self._payload("oracle:agent-audio@2")
                )
            )

        with self.assertRaises(adapter.OracleAdapterError):
            adapter.OracleDecision(
                criteria=(),
                negative_controls=(),
                diagnostics=tuple(
                    OracleDiagnostic("oracle.detail", "x") for _ in range(17)
                ),
            )

    def test_unknown_oracle_and_wrong_bound_pair_fail_before_a_verdict(self) -> None:
        request = self._request(
            "oracle:deterministic-unknown@1",
            {"not": "read"},
            evidence_type="playback.probe",
            evidence_schema="playback-probe@1",
        )
        request.artifact.object_path.unlink()
        with self.assertRaisesRegex(adapter.OracleAdapterError, "unknown Oracle"):
            adapter.RegressionOracleAdapter().evaluate(request)

        identifier = "oracle:agent-structured-playback-probe@1"
        request = self._request(identifier, self._payload(identifier))
        for field, value in (
            ("evidence_type", EvidenceType("visual.frames")),
            ("evidence_schema", EvidenceSchema("frame-sequence@2")),
        ):
            with self.subTest(field=field):
                changed = replace(request.binding, **{field: value})
                with self.assertRaisesRegex(adapter.OracleAdapterError, "evidence pair"):
                    adapter.RegressionOracleAdapter().evaluate(
                        replace(request, binding=changed)
                    )

    def test_empty_malformed_and_wrong_typed_payloads_fail(self) -> None:
        cases = (
            b"",
            b"{",
            canonical_bytes({}),
            canonical_bytes(
                {
                    "schema": adapter.ARTIFACT_SCHEMA,
                    "schemaVersion": 1,
                    "evidenceType": "playback.probe",
                    "evidenceSchema": "playback-probe@1",
                    "snapshots": [],
                }
            ),
        )
        for index, data in enumerate(cases):
            with self.subTest(case=index):
                request = self._request_bytes(
                    "oracle:agent-structured-playback-probe@1", data
                )
                with self.assertRaises(adapter.OracleAdapterError):
                    adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(request)

    def test_receipt_must_be_current_and_evaluation_cites_it_exactly(self) -> None:
        identifier = "oracle:agent-structured-library-command@1"
        request = self._request(identifier, self._payload(identifier))
        result = adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(request)
        self.assertEqual(
            result.evidence_refs[0].receipt_digest, request.artifact.receipt_digest
        )

        receipt = json.loads(request.artifact.receipt_path.read_text(encoding="utf-8"))
        receipt["digest"] = SHA
        request.artifact.receipt_path.write_bytes(canonical_bytes(receipt) + b"\n")
        with self.assertRaisesRegex(adapter.OracleAdapterError, "receipt"):
            adapter.RegressionOracleAdapter(SatisfyingProvider()).evaluate(request)

    def test_implementation_identity_exports_locator_and_actual_source_digest(self) -> None:
        expected = "sha256:" + hashlib.sha256(Path(adapter.__file__).read_bytes()).hexdigest()
        self.assertEqual(
            adapter.IMPLEMENTATION_LOCATOR,
            "Scripts/verification/regression_oracle_adapter.py",
        )
        self.assertEqual(adapter.IMPLEMENTATION_DIGEST, expected)
        for identifier in adapter.SPECS:
            identity = adapter.implementation_identity(identifier)
            self.assertEqual(identity.locator, adapter.IMPLEMENTATION_LOCATOR)
            self.assertEqual(identity.digest, expected)

    def test_runtime_identity_exposes_provider_environment_and_rejects_omission(self) -> None:
        identifier = OracleID("oracle:agent-structured-playback-probe@1")
        environment = AgentEnvironment(
            "test-agent",
            canonical_digest({"prompt": "test"}),
            canonical_digest({"configuration": "test"}),
        )
        provider = SatisfyingProvider()
        provider.agent_environment = environment
        identity = adapter.RegressionOracleAdapter(provider).identity_for(identifier)
        compiled = adapter.implementation_identity(str(identifier))

        self.assertEqual(identity.oracle_id, identifier)
        self.assertEqual(identity.implementation_locator, compiled.locator)
        self.assertEqual(str(identity.implementation_digest), compiled.digest)
        self.assertEqual(identity.agent_environment, environment)

        class EnvironmentlessProvider:
            def decide(self, request):
                raise AssertionError("identity validation must precede decision")

        with self.assertRaisesRegex(
            adapter.OracleAdapterError, "agent_environment"
        ):
            adapter.RegressionOracleAdapter(EnvironmentlessProvider()).identity_for(
                identifier
            )

    def _payload(self, identifier: str) -> dict[str, object]:
        spec = adapter.SPECS[identifier]
        return dict(
            _typed_payload(
                spec.evidence_type,
                spec.evidence_schema,
                _raw_output(identifier),
            )
        )

    def _request(
        self,
        identifier: str,
        payload: object,
        *,
        evidence_type: str | None = None,
        evidence_schema: str | None = None,
    ) -> OracleEvaluationRequest:
        spec = adapter.SPECS.get(identifier)
        return self._request_bytes(
            identifier,
            canonical_bytes(payload),
            evidence_type=evidence_type
            or (spec.evidence_type if spec else "playback.probe"),
            evidence_schema=evidence_schema
            or (spec.evidence_schema if spec else "playback-probe@1"),
        )

    def _request_bytes(
        self,
        identifier: str,
        data: bytes,
        *,
        evidence_type: str = "playback.probe",
        evidence_schema: str = "playback-probe@1",
    ) -> OracleEvaluationRequest:
        ordinal = len(list(self.root.glob("object-*")))
        object_path = self.root / f"object-{ordinal}.json"
        object_path.write_bytes(data)
        digest = Digest("sha256:" + hashlib.sha256(data).hexdigest())
        receipt_value = {
            "leaseId": "lease:oracle-test",
            "evidenceSchema": evidence_schema,
            "relativePath": f"evidence/{ordinal}.json",
            "byteLength": len(data),
            "digest": str(digest),
            "objectPath": f"objects/sha256/{str(digest)[7:]}",
        }
        receipt_digest = canonical_digest(receipt_value)
        receipt_path = self.root / f"{str(receipt_digest)[7:]}.json"
        receipt_path.write_bytes(canonical_bytes(receipt_value) + b"\n")
        receipt = ArtifactReceipt(
            LeaseID("lease:oracle-test"),
            EvidenceSchema(evidence_schema),
            f"evidence/{ordinal}.json",
            len(data),
            digest,
            object_path,
            receipt_digest,
            receipt_path,
        )
        spec = adapter.SPECS.get(identifier)
        kind = spec.kind if spec else OracleKind.DETERMINISTIC
        oracle = OracleEvaluationBinding(
            OracleID(identifier),
            kind,
            Digest(SHA),
            "test://oracle",
            Digest(SHA),
            "body",
        )
        rubric = RubricEvaluationBinding(
            RubricID("rubric:test.oracle@1"),
            Digest(SHA),
            CRITERIA,
            NEGATIVE_CONTROLS,
            "body",
        )
        binding = EvaluationBinding(
            ObligationID("obligation:test:oracle"),
            ArtifactClass.COVERAGE,
            EvidenceType(evidence_type),
            EvidenceSchema(evidence_schema),
            CaseKey("default"),
            CallID("call:test:evidence"),
            Digest(SHA),
            oracle,
            rubric,
        )
        return OracleEvaluationRequest(binding, receipt)


if __name__ == "__main__":
    unittest.main()
