#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import sys
from types import MappingProxyType
from typing import Any, Mapping, Protocol

SCRIPTS_DIRECTORY = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIRECTORY))

from regression.core.contracts import OracleKind
from regression.core.digest import canonical_bytes, canonical_digest
from regression.core.expression import OracleResult
from regression.core.ids import Digest, OracleID
from regression.core.plan import AgentEnvironment
from regression.core.runtime import (
    CriterionEvaluation,
    EvidenceReference,
    NegativeControlEvaluation,
    OracleDiagnostic,
    OracleEvaluation,
    OracleEvaluationRequest,
    OracleEvaluatorIdentity,
    aggregate_oracle_evaluation,
)
from regression.core.store import ArtifactReceipt


ARTIFACT_SCHEMA = "enchron.regression.oracle-evidence"
ARTIFACT_SCHEMA_VERSION = 4
IMPLEMENTATION_LOCATOR = "Scripts/verification/regression_oracle_adapter.py"
_MAX_DIAGNOSTICS = 16
_MAX_DIAGNOSTIC_DETAIL = 1024
_MISSING_PROVIDER_ENVIRONMENT = object()


class OracleAdapterError(ValueError):
    pass


@dataclass(frozen=True)
class EvidenceProvenance:
    obligation_id: str
    case_key: str
    call_id: str
    operation_id: str
    contract_digest: str
    arguments: Mapping[str, Any]
    arguments_digest: str
    implementation_locator: str
    implementation_digest: str

    def payload(self) -> Mapping[str, Any]:
        return {
            "obligationId": self.obligation_id,
            "caseKey": self.case_key,
            "producer": {
                "callId": self.call_id,
                "operationId": self.operation_id,
                "contractDigest": self.contract_digest,
                "arguments": self.arguments,
                "argumentsDigest": self.arguments_digest,
                "implementationLocator": self.implementation_locator,
                "implementationDigest": self.implementation_digest,
            },
        }


@dataclass(frozen=True)
class EvidenceAttachment:
    role: str
    media_type: str
    path: str
    byte_length: int
    digest: str

    def payload(self) -> Mapping[str, Any]:
        return {
            "role": self.role,
            "mediaType": self.media_type,
            "path": self.path,
            "byteLength": self.byte_length,
            "digest": self.digest,
        }


@dataclass(frozen=True)
class OracleSpec:
    identifier: str
    kind: OracleKind
    evidence_type: str
    evidence_schema: str
    payload_field: str
    payload_kind: str
    source_field: str | None
    supplemental_fields: tuple[str, ...]


def _spec(
    identifier: str,
    kind: OracleKind,
    evidence_type: str,
    evidence_schema: str,
    payload_field: str,
    payload_kind: str = "object-array",
    source_field: str | None = None,
    supplemental_fields: tuple[str, ...] = (),
) -> OracleSpec:
    return OracleSpec(
        identifier,
        kind,
        evidence_type,
        evidence_schema,
        payload_field,
        payload_kind,
        source_field,
        supplemental_fields,
    )


_SPEC_VALUES = (
    _spec(
        "oracle:agent-audio@2",
        OracleKind.AGENT,
        "audio.measurement",
        "audio-measurement@2",
        "measurement",
        "object",
        "measurement",
        ("wavPath",),
    ),
    _spec(
        "oracle:agent-visual@2",
        OracleKind.AGENT,
        "visual.frames",
        "frame-sequence@2",
        "frames",
        source_field="frames",
    ),
    _spec(
        "oracle:agent-structured-accessibility-tree@1",
        OracleKind.AGENT,
        "accessibility.tree",
        "accessibility-tree@1",
        "nodes",
    ),
    _spec(
        "oracle:agent-structured-emby-evidence@1",
        OracleKind.AGENT,
        "emby.evidence",
        "emby-evidence@1",
        "observations",
    ),
    _spec(
        "oracle:agent-structured-interaction-trace@1",
        OracleKind.AGENT,
        "interaction.trace",
        "interaction-trace@1",
        "events",
        "string-array",
        "interactionTrace",
    ),
    _spec(
        "oracle:agent-structured-library-command@1",
        OracleKind.AGENT,
        "library.command",
        "library-command@1",
        "commands",
    ),
    _spec(
        "oracle:agent-structured-playback-probe@1",
        OracleKind.AGENT,
        "playback.probe",
        "playback-probe@1",
        "snapshots",
    ),
    _spec(
        "oracle:agent-structured-spatial-input@1",
        OracleKind.AGENT,
        "spatial.input",
        "spatial-input@1",
        "events",
        "string-array",
        "spatialInputTrace",
    ),
    _spec(
        "oracle:agent-structured-structural-test@2",
        OracleKind.AGENT,
        "structural.test",
        "structural-test@2",
        "tests",
    ),
    _spec(
        "oracle:agent-structured-transition@1",
        OracleKind.AGENT,
        "transition.trace",
        "transition-trace@1",
        "records",
    ),
    _spec(
        "oracle:agent-structured-window-control-plane@1",
        OracleKind.AGENT,
        "window.control-plane",
        "window-control-plane@1",
        "snapshots",
    ),
)
SPECS: Mapping[str, OracleSpec] = MappingProxyType(
    {spec.identifier: spec for spec in _SPEC_VALUES}
)
_SPECS_BY_PAIR: Mapping[tuple[str, str], OracleSpec] = MappingProxyType(
    {(spec.evidence_type, spec.evidence_schema): spec for spec in _SPEC_VALUES}
)
if len(_SPECS_BY_PAIR) != len(_SPEC_VALUES):
    raise RuntimeError("Oracle evidence pairs must be unique")


@dataclass(frozen=True)
class ImplementationIdentity:
    locator: str
    digest: str


def _source_digest() -> str:
    return "sha256:" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


IMPLEMENTATION_DIGEST = _source_digest()
IMPLEMENTATION_IDENTITIES: Mapping[str, ImplementationIdentity] = MappingProxyType(
    {
        identifier: ImplementationIdentity(
            IMPLEMENTATION_LOCATOR, IMPLEMENTATION_DIGEST
        )
        for identifier in SPECS
    }
)


def implementation_identity(oracle_id: str) -> ImplementationIdentity:
    try:
        return IMPLEMENTATION_IDENTITIES[oracle_id]
    except (KeyError, TypeError) as error:
        raise OracleAdapterError(f"unknown Oracle ID: {oracle_id!r}") from error


def build_typed_evidence_payload(
    evidence_type: str,
    evidence_schema: str,
    operation_output: Mapping[str, Any],
    provenance: EvidenceProvenance,
    operation_transcript: tuple[Mapping[str, Any], ...],
    attachments: tuple[EvidenceAttachment, ...] = (),
) -> Mapping[str, Any]:
    if not isinstance(evidence_type, str) or not isinstance(evidence_schema, str):
        raise OracleAdapterError("evidence type and schema must be strings")
    spec = _SPECS_BY_PAIR.get((evidence_type, evidence_schema))
    if spec is None:
        raise OracleAdapterError(
            f"unknown registered evidence pair: {evidence_type}/{evidence_schema}"
        )
    output = _canonical_json_object(operation_output, "operation output")
    if not isinstance(provenance, EvidenceProvenance):
        raise OracleAdapterError("typed evidence requires EvidenceProvenance")
    provenance_payload = _validate_provenance(provenance.payload())
    if any(not isinstance(item, EvidenceAttachment) for item in attachments):
        raise OracleAdapterError(
            "typed evidence attachments must contain EvidenceAttachment values"
        )
    attachment_payload = _validate_attachments(
        [item.payload() for item in attachments]
    )
    if output.get("succeeded") is not True:
        raise OracleAdapterError(
            "typed evidence requires a successful raw Operation output"
        )
    _reject_embedded_judgment(output, "operation output")
    _validate_operation_output(spec, output)
    transcript = _validate_operation_transcript(
        list(operation_transcript),
        provenance_payload["producer"],
        output,
    )

    payload: dict[str, Any] = {
        "schema": ARTIFACT_SCHEMA,
        "schemaVersion": ARTIFACT_SCHEMA_VERSION,
        "evidenceType": spec.evidence_type,
        "evidenceSchema": spec.evidence_schema,
        **provenance_payload,
        "operationOutput": output,
        "operationTranscript": transcript,
        "attachments": attachment_payload,
    }
    if spec.source_field is None:
        payload[spec.payload_field] = [output]
    else:
        if spec.source_field not in output:
            raise OracleAdapterError(
                f"operation output requires {spec.source_field} for "
                f"{spec.evidence_type}/{spec.evidence_schema}"
            )
        payload[spec.payload_field] = output[spec.source_field]
    for field in spec.supplemental_fields:
        if field not in output:
            raise OracleAdapterError(
                f"operation output requires {field} for "
                f"{spec.evidence_type}/{spec.evidence_schema}"
            )
        payload[field] = output[field]

    _validate_typed_payload(payload, spec)
    return payload


def _validate_operation_transcript(
    value: Any,
    producer: Mapping[str, Any],
    operation_output: Mapping[str, Any],
) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not value:
        raise OracleAdapterError("operation transcript must be a non-empty array")
    entries: list[dict[str, Any]] = []
    seen_grants: set[str] = set()
    attempt_counts: dict[str, int] = {}
    producer_fields = {
        "callId",
        "operationId",
        "contractDigest",
        "arguments",
        "argumentsDigest",
        "implementationLocator",
        "implementationDigest",
    }
    for index, raw in enumerate(value):
        entry = _canonical_json_object(raw, f"operation transcript[{index}]")
        if set(entry) != producer_fields | {
            "grantId",
            "invocationIndex",
            "status",
            "operationResult",
            "operationError",
        }:
            raise OracleAdapterError(
                f"operation transcript[{index}] has the wrong closed shape"
            )
        transcript_producer = {
            field: entry[field] for field in producer_fields
        }
        _validate_provenance(
            {
                "obligationId": "transcript",
                "caseKey": str(index),
                "producer": transcript_producer,
            }
        )
        call_id = str(entry["callId"])
        grant_id = entry.get("grantId")
        if not isinstance(grant_id, str) or not grant_id.strip():
            raise OracleAdapterError(
                f"operation transcript[{index}] grantId must be non-empty text"
            )
        if grant_id in seen_grants:
            raise OracleAdapterError(
                f"operation transcript repeats grantId {grant_id!r}"
            )
        seen_grants.add(grant_id)
        invocation_index = entry.get("invocationIndex")
        expected_index = attempt_counts.get(call_id, 0) + 1
        if type(invocation_index) is not int or invocation_index != expected_index:
            raise OracleAdapterError(
                f"operation transcript[{index}] invocationIndex must be {expected_index}"
            )
        attempt_counts[call_id] = expected_index
        status = entry.get("status")
        if status not in ("succeeded", "failed"):
            raise OracleAdapterError(
                f"operation transcript[{index}] status is invalid"
            )
        transcript_result = _canonical_json_object(
            entry.get("operationResult"),
            f"operation transcript[{index}].operationResult",
        )
        expected_success = status == "succeeded"
        if transcript_result.get("succeeded") is not expected_success:
            raise OracleAdapterError(
                f"operation transcript[{index}] result contradicts its status"
            )
        operation_error = entry.get("operationError")
        if not isinstance(operation_error, str) or (
            expected_success and operation_error
        ) or (not expected_success and not operation_error.strip()):
            raise OracleAdapterError(
                f"operation transcript[{index}] error contradicts its status"
            )
        _reject_embedded_judgment(
            transcript_result,
            f"operation transcript[{index}].operationResult",
        )
        entries.append(entry)
    final = entries[-1]
    if final["status"] != "succeeded":
        raise OracleAdapterError(
            "operation transcript final producer attempt must be successful"
        )
    if any(final[field] != producer[field] for field in producer_fields):
        raise OracleAdapterError(
            "operation transcript final entry differs from evidence producer"
        )
    if final["operationResult"] != operation_output:
        raise OracleAdapterError(
            "operation transcript final output differs from operationOutput"
        )
    return entries


def _validate_provenance(value: Mapping[str, Any]) -> dict[str, Any]:
    envelope = _canonical_json_object(value, "evidence provenance")
    if set(envelope) != {"obligationId", "caseKey", "producer"}:
        raise OracleAdapterError(
            "evidence provenance must contain obligationId, caseKey, and producer"
        )
    for field in ("obligationId", "caseKey"):
        _require_nonempty_text(envelope, field)
    producer = envelope.get("producer")
    expected_fields = {
        "callId",
        "operationId",
        "contractDigest",
        "arguments",
        "argumentsDigest",
        "implementationLocator",
        "implementationDigest",
    }
    if not isinstance(producer, dict) or set(producer) != expected_fields:
        raise OracleAdapterError(
            "evidence provenance producer has the wrong closed shape"
        )
    for field in ("callId", "operationId", "implementationLocator"):
        _require_nonempty_text(producer, field)
    for field in (
        "contractDigest",
        "argumentsDigest",
        "implementationDigest",
    ):
        digest = producer.get(field)
        if not isinstance(digest, str) or not _is_sha256(digest):
            raise OracleAdapterError(
                f"evidence provenance producer.{field} must be a SHA-256 digest"
            )
    arguments = producer.get("arguments")
    if not isinstance(arguments, dict):
        raise OracleAdapterError(
            "evidence provenance producer.arguments must be an object"
        )
    if canonical_digest(arguments) != producer["argumentsDigest"]:
        raise OracleAdapterError(
            "evidence provenance producer.argumentsDigest does not bind arguments"
        )
    return envelope


def _is_sha256(value: str) -> bool:
    return (
        len(value) == 71
        and value.startswith("sha256:")
        and all(character in "0123456789abcdef" for character in value[7:])
    )


def _validate_attachments(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise OracleAdapterError("evidence attachments must be an array")
    attachments: list[dict[str, Any]] = []
    roles: set[str] = set()
    for index, raw in enumerate(value):
        attachment = _canonical_json_object(
            raw, f"evidence attachments[{index}]"
        )
        if set(attachment) != {
            "role",
            "mediaType",
            "path",
            "byteLength",
            "digest",
        }:
            raise OracleAdapterError(
                f"evidence attachments[{index}] has the wrong closed shape"
            )
        for field in ("role", "mediaType", "path"):
            _require_nonempty_text(attachment, field)
        role = str(attachment["role"])
        if role in roles:
            raise OracleAdapterError(f"evidence attachment repeats role {role!r}")
        roles.add(role)
        media_type = attachment["mediaType"]
        if media_type not in {"image/png", "audio/wav", "text/plain"}:
            raise OracleAdapterError(
                f"evidence attachments[{index}].mediaType is unsupported"
            )
        byte_length = attachment.get("byteLength")
        if type(byte_length) is not int or byte_length < 0:
            raise OracleAdapterError(
                f"evidence attachments[{index}].byteLength must be non-negative"
            )
        if media_type != "text/plain" and byte_length == 0:
            raise OracleAdapterError(
                f"evidence attachments[{index}] must not be empty"
            )
        digest = attachment.get("digest")
        if not isinstance(digest, str) or not _is_sha256(digest):
            raise OracleAdapterError(
                f"evidence attachments[{index}].digest must be SHA-256"
            )
        path = Path(str(attachment["path"]))
        if not path.is_absolute() or path.is_symlink() or not path.is_file():
            raise OracleAdapterError(
                f"evidence attachments[{index}].path must be an absolute regular file"
            )
        data = path.read_bytes()
        if len(data) != byte_length:
            raise OracleAdapterError(
                f"evidence attachments[{index}] byte length drifted"
            )
        actual = "sha256:" + hashlib.sha256(data).hexdigest()
        if actual != digest:
            raise OracleAdapterError(
                f"evidence attachments[{index}] digest drifted"
            )
        attachments.append(attachment)
    return attachments


def _canonical_json_object(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise OracleAdapterError(f"{location} must be a JSON object")
    try:
        encoded = canonical_bytes(value)
        decoded = json.loads(
            encoded.decode("utf-8"),
            object_pairs_hook=_unique_object,
            parse_constant=_reject_json_constant,
        )
    except (TypeError, ValueError, OverflowError, OracleAdapterError) as error:
        if isinstance(error, OracleAdapterError):
            raise
        raise OracleAdapterError(f"{location} must contain only finite JSON values") from error
    if not isinstance(decoded, dict) or not decoded:
        raise OracleAdapterError(f"{location} must be a non-empty JSON object")
    return decoded


def _reject_embedded_judgment(value: Any, location: str) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = key.casefold().replace("_", "").replace("-", "")
            if normalized in {
                "assertion",
                "assertions",
                "criterion",
                "criteria",
                "negativecontrol",
                "negativecontrols",
                "verdict",
                "verdicts",
            }:
                raise OracleAdapterError(
                    f"{location}.{key} contains a producer judgment"
                )
            _reject_embedded_judgment(item, f"{location}.{key}")
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            _reject_embedded_judgment(item, f"{location}[{index}]")
        return
    if isinstance(value, str) and value.casefold() in {
        item.value.casefold() for item in OracleResult
    }:
        raise OracleAdapterError(f"{location} contains a producer judgment token")


def _validate_operation_output(spec: OracleSpec, output: Mapping[str, Any]) -> None:
    evidence_type = spec.evidence_type
    if evidence_type == "audio.measurement":
        _require_nonempty_object(output, "measurement")
        _require_nonempty_text(output, "wavPath")
    elif evidence_type == "visual.frames":
        _require_object_array(output, "frames")
    elif evidence_type == "accessibility.tree":
        _require_nonempty_object(output, "response")
    elif evidence_type == "emby.evidence":
        matched_element = _require_nonempty_object(output, "matchedElement")
        value = matched_element.get("value")
        if not isinstance(value, str) or not value.strip():
            raise OracleAdapterError(
                "operation output matchedElement.value must be non-empty text"
            )
        try:
            evidence = json.loads(
                value,
                object_pairs_hook=_unique_object,
                parse_constant=_reject_json_constant,
            )
        except (TypeError, ValueError, OracleAdapterError) as error:
            raise OracleAdapterError(
                "operation output matchedElement.value must be a JSON object"
            ) from error
        if not isinstance(evidence, dict) or not isinstance(
            evidence.get("artworkLoads"), list
        ):
            raise OracleAdapterError(
                "operation output matchedElement.value must carry artworkLoads"
            )
    elif evidence_type == "interaction.trace":
        _require_text_array(output, "interactionTrace")
    elif evidence_type == "library.command":
        if not any(
            isinstance(output.get(field), (dict, list))
            for field in ("response", "snapshot", "entries", "import", "library")
        ):
            raise OracleAdapterError(
                "operation output must contain a structured library observation"
            )
    elif evidence_type == "playback.probe":
        _require_nonempty_object(output, "fields")
        _require_nonempty_object(output, "response")
    elif evidence_type == "spatial.input":
        _require_text_array(output, "spatialInputTrace")
    elif evidence_type == "structural.test":
        _require_nonempty_text(output, "check")
        _require_text_array(output, "command")
        if type(output.get("returnCode")) is not int:
            raise OracleAdapterError(
                "operation output returnCode must be an integer"
            )
        for field in ("artifactPath", "artifactDigest", "toolchain"):
            _require_nonempty_text(output, field)
    elif evidence_type == "transition.trace":
        _require_nonempty_object(output, "snapshot")
        _require_nonempty_object(output, "response")
    elif evidence_type == "window.control-plane":
        _require_nonempty_object(output, "fields")
        _require_nonempty_object(output, "response")
    else:
        raise RuntimeError(f"unknown Oracle evidence type: {evidence_type}")


def _require_nonempty_object(
    value: Mapping[str, Any], field: str
) -> Mapping[str, Any]:
    if not isinstance(value.get(field), dict) or not value[field]:
        raise OracleAdapterError(
            f"operation output {field} must be a non-empty object"
        )
    return value[field]


def _require_nonempty_text(value: Mapping[str, Any], field: str) -> None:
    if not isinstance(value.get(field), str) or not value[field].strip():
        raise OracleAdapterError(f"operation output {field} must be non-empty text")


def _require_object_array(value: Mapping[str, Any], field: str) -> None:
    items = value.get(field)
    if (
        not isinstance(items, list)
        or not items
        or any(not isinstance(item, dict) or not item for item in items)
    ):
        raise OracleAdapterError(
            f"operation output {field} must contain non-empty objects"
        )


def _require_text_array(value: Mapping[str, Any], field: str) -> None:
    items = value.get(field)
    if (
        not isinstance(items, list)
        or not items
        or any(not isinstance(item, str) or not item.strip() for item in items)
    ):
        raise OracleAdapterError(
            f"operation output {field} must contain non-empty text"
        )


@dataclass(frozen=True)
class OracleDecisionRequest:
    oracle_kind: OracleKind
    criteria: tuple[str, ...]
    negative_controls: tuple[str, ...]
    artifact_path: Path
    artifact_payload: Mapping[str, Any]
    receipt_digest: Digest


@dataclass(frozen=True)
class OracleDecision:
    criteria: tuple[CriterionEvaluation, ...]
    negative_controls: tuple[NegativeControlEvaluation, ...]
    diagnostics: tuple[OracleDiagnostic, ...] = ()

    def __post_init__(self) -> None:
        criteria = tuple(self.criteria)
        negative_controls = tuple(self.negative_controls)
        diagnostics = tuple(self.diagnostics)
        if any(not isinstance(item, CriterionEvaluation) for item in criteria):
            raise OracleAdapterError(
                "OracleDecision.criteria must contain CriterionEvaluation values"
            )
        if any(
            not isinstance(item, NegativeControlEvaluation)
            for item in negative_controls
        ):
            raise OracleAdapterError(
                "OracleDecision.negative_controls must contain NegativeControlEvaluation values"
            )
        _validate_diagnostics(diagnostics, "OracleDecision.diagnostics")
        object.__setattr__(self, "criteria", criteria)
        object.__setattr__(self, "negative_controls", negative_controls)
        object.__setattr__(self, "diagnostics", diagnostics)


AgentDecisionRequest = OracleDecisionRequest
AgentDecision = OracleDecision


class DecisionProvider(Protocol):
    agent_environment: AgentEnvironment | None

    def decide(self, request: OracleDecisionRequest) -> OracleDecision: ...


class RegressionOracleAdapter:
    def __init__(self, decision_provider: DecisionProvider | None = None) -> None:
        self._decision_provider = decision_provider

    def identity_for(self, oracle_id: OracleID) -> OracleEvaluatorIdentity:
        identifier = str(oracle_id)
        implementation = implementation_identity(identifier)
        provider = self._decision_provider
        environment = None
        if provider is not None:
            environment = getattr(
                provider,
                "agent_environment",
                _MISSING_PROVIDER_ENVIRONMENT,
            )
            if environment is _MISSING_PROVIDER_ENVIRONMENT:
                raise OracleAdapterError(
                    "DecisionProvider must expose a typed agent_environment"
                )
            if environment is not None and not isinstance(
                environment, AgentEnvironment
            ):
                raise OracleAdapterError(
                    "DecisionProvider must expose a typed agent_environment"
                )
        return OracleEvaluatorIdentity(
            OracleID(identifier),
            implementation.locator,
            Digest(implementation.digest),
            environment,
        )

    def evaluate(self, request: OracleEvaluationRequest) -> OracleEvaluation:
        if not isinstance(request, OracleEvaluationRequest):
            raise OracleAdapterError("Oracle evaluation needs an OracleEvaluationRequest")
        binding = request.binding
        identifier = str(binding.oracle.id)
        spec = SPECS.get(identifier)
        if spec is None:
            raise OracleAdapterError(f"unknown Oracle ID: {identifier}")
        if binding.oracle.kind is not spec.kind:
            raise OracleAdapterError(
                f"{identifier} kind must be {spec.kind.value}"
            )
        actual_pair = (str(binding.evidence_type), str(binding.evidence_schema))
        expected_pair = (spec.evidence_type, spec.evidence_schema)
        if actual_pair != expected_pair:
            raise OracleAdapterError(
                f"{identifier} evidence pair must be {expected_pair[0]}/{expected_pair[1]}"
            )

        artifact_bytes = _validate_receipt(request.artifact, spec.evidence_schema)
        payload = _parse_payload(artifact_bytes, spec)
        criteria = tuple(binding.rubric.criteria)
        negative_controls = tuple(binding.rubric.negative_controls)

        decisions, controls, diagnostics = self._decision(
            request,
            spec,
            payload,
            criteria,
            negative_controls,
        )

        overall = aggregate_oracle_evaluation(decisions, controls)
        return OracleEvaluation(
            overall=overall,
            criteria=decisions,
            negative_controls=controls,
            evidence_refs=(EvidenceReference(request.artifact.receipt_digest),),
            detail=diagnostics,
        )

    def __call__(self, request: OracleEvaluationRequest) -> OracleEvaluation:
        return self.evaluate(request)

    def _decision(
        self,
        request: OracleEvaluationRequest,
        spec: OracleSpec,
        payload: Mapping[str, Any],
        criteria: tuple[str, ...],
        negative_controls: tuple[str, ...],
    ) -> tuple[
        tuple[CriterionEvaluation, ...],
        tuple[NegativeControlEvaluation, ...],
        tuple[OracleDiagnostic, ...],
    ]:
        provider = self._decision_provider
        if provider is None:
            return (
                tuple(
                    CriterionEvaluation(item, OracleResult.INDETERMINATE)
                    for item in criteria
                ),
                tuple(
                    NegativeControlEvaluation(item, OracleResult.INDETERMINATE)
                    for item in negative_controls
                ),
                (
                    OracleDiagnostic(
                        "oracle.provider-unavailable",
                        "No DecisionProvider was supplied for this Oracle.",
                    ),
                ),
            )
        decide = getattr(provider, "decide", None)
        if not callable(decide):
            raise OracleAdapterError("DecisionProvider must define decide(request)")
        provider_request = OracleDecisionRequest(
            oracle_kind=spec.kind,
            criteria=criteria,
            negative_controls=negative_controls,
            artifact_path=request.artifact.object_path,
            artifact_payload=MappingProxyType(dict(payload)),
            receipt_digest=request.artifact.receipt_digest,
        )
        try:
            decision = decide(provider_request)
        except OracleAdapterError:
            raise
        except Exception as error:
            raise OracleAdapterError(
                f"DecisionProvider failed for {spec.identifier}: {error}"
            ) from error
        if not isinstance(decision, OracleDecision):
            raise OracleAdapterError("DecisionProvider must return an OracleDecision")
        _validate_exact_decision(decision, criteria, negative_controls)
        return decision.criteria, decision.negative_controls, decision.diagnostics


def _validate_receipt(receipt: ArtifactReceipt, expected_schema: str) -> bytes:
    if not isinstance(receipt, ArtifactReceipt):
        raise OracleAdapterError("artifact must be an accepted ArtifactReceipt")
    if str(receipt.evidence_schema) != expected_schema:
        raise OracleAdapterError(
            f"artifact receipt evidence schema must be {expected_schema}"
        )
    if type(receipt.byte_length) is not int or receipt.byte_length <= 0:
        raise OracleAdapterError("artifact receipt byte length must be positive")
    if not isinstance(receipt.relative_path, str) or not receipt.relative_path:
        raise OracleAdapterError("artifact receipt relative path must not be empty")
    for label, path in (
        ("artifact object", receipt.object_path),
        ("artifact receipt", receipt.receipt_path),
    ):
        if not isinstance(path, Path) or path.is_symlink() or not path.is_file():
            raise OracleAdapterError(f"{label} must be a current regular file")

    data = receipt.object_path.read_bytes()
    if not data:
        raise OracleAdapterError("artifact object must not be empty")
    if len(data) != receipt.byte_length:
        raise OracleAdapterError("artifact object byte length differs from its receipt")
    actual_digest = "sha256:" + hashlib.sha256(data).hexdigest()
    if actual_digest != str(receipt.digest):
        raise OracleAdapterError("artifact object digest differs from its receipt")

    receipt_value = {
        "leaseId": str(receipt.lease_id),
        "evidenceSchema": str(receipt.evidence_schema),
        "relativePath": receipt.relative_path,
        "byteLength": receipt.byte_length,
        "digest": str(receipt.digest),
        "objectPath": f"objects/sha256/{str(receipt.digest)[7:]}",
    }
    expected_receipt_digest = canonical_digest(receipt_value)
    if expected_receipt_digest != receipt.receipt_digest:
        raise OracleAdapterError("artifact receipt reference is stale")
    if receipt.receipt_path.name != f"{str(receipt.receipt_digest)[7:]}.json":
        raise OracleAdapterError("artifact receipt path does not match its reference")
    if receipt.receipt_path.read_bytes() != canonical_bytes(receipt_value) + b"\n":
        raise OracleAdapterError("artifact receipt file is stale or malformed")
    return data


def _parse_payload(data: bytes, spec: OracleSpec) -> Mapping[str, Any]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise OracleAdapterError("artifact payload must be UTF-8 JSON") from error
    try:
        payload = json.loads(
            text,
            object_pairs_hook=_unique_object,
            parse_constant=_reject_json_constant,
        )
    except (json.JSONDecodeError, OracleAdapterError) as error:
        if isinstance(error, OracleAdapterError):
            raise
        raise OracleAdapterError("artifact payload must be valid JSON") from error
    if not isinstance(payload, dict):
        raise OracleAdapterError("artifact payload must be a JSON object")

    _validate_typed_payload(payload, spec)
    return payload


def _validate_typed_payload(payload: Mapping[str, Any], spec: OracleSpec) -> None:
    allowed = {
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
        *spec.supplemental_fields,
    }
    unknown = sorted(set(payload) - allowed)
    if unknown:
        raise OracleAdapterError(
            "artifact payload rejects unknown fields: " + ", ".join(unknown)
        )
    expected = {
        "schema": ARTIFACT_SCHEMA,
        "schemaVersion": ARTIFACT_SCHEMA_VERSION,
        "evidenceType": spec.evidence_type,
        "evidenceSchema": spec.evidence_schema,
    }
    for field, value in expected.items():
        if payload.get(field) != value or type(payload.get(field)) is not type(value):
            raise OracleAdapterError(
                f"artifact payload {field} must be {value!r}"
            )
    _validate_provenance(
        {
            "obligationId": payload.get("obligationId"),
            "caseKey": payload.get("caseKey"),
            "producer": payload.get("producer"),
        }
    )
    operation_output = _canonical_json_object(
        payload.get("operationOutput"), "artifact payload operationOutput"
    )
    if operation_output.get("succeeded") is not True:
        raise OracleAdapterError(
            "artifact payload operationOutput requires a successful Operation output"
        )
    _reject_embedded_judgment(
        operation_output, "artifact payload operationOutput"
    )
    _validate_operation_output(spec, operation_output)
    producer = _validate_provenance(
        {
            "obligationId": payload.get("obligationId"),
            "caseKey": payload.get("caseKey"),
            "producer": payload.get("producer"),
        }
    )["producer"]
    _validate_operation_transcript(
        payload.get("operationTranscript"),
        producer,
        operation_output,
    )
    _validate_attachments(payload.get("attachments"))
    if spec.payload_field not in payload:
        raise OracleAdapterError(
            f"artifact payload requires {spec.payload_field}"
        )
    evidence = payload[spec.payload_field]
    if spec.payload_kind == "object":
        if not isinstance(evidence, dict) or not evidence:
            raise OracleAdapterError(
                f"artifact payload {spec.payload_field} must be a non-empty object"
            )
    elif not isinstance(evidence, list) or not evidence:
        raise OracleAdapterError(
            f"artifact payload {spec.payload_field} must be a non-empty array"
        )
    elif spec.payload_kind == "object-array" and any(
        not isinstance(item, dict) or not item for item in evidence
    ):
        raise OracleAdapterError(
            f"artifact payload {spec.payload_field} must contain non-empty objects"
        )
    elif spec.payload_kind == "string-array" and any(
        not isinstance(item, str) or not item.strip() for item in evidence
    ):
        raise OracleAdapterError(
            f"artifact payload {spec.payload_field} must contain non-empty text"
        )
    elif spec.payload_kind not in {"object", "object-array", "string-array"}:
        raise RuntimeError(f"unknown Oracle payload kind: {spec.payload_kind}")

    for field in spec.supplemental_fields:
        value = payload.get(field)
        if not isinstance(value, str) or not value.strip():
            raise OracleAdapterError(
                f"artifact payload {field} must be non-empty text"
            )
        if value != operation_output.get(field):
            raise OracleAdapterError(
                f"artifact payload {field} differs from operationOutput"
            )
    _reject_embedded_judgment(evidence, f"artifact payload {spec.payload_field}")
    if spec.source_field is None:
        if len(evidence) != 1:
            raise OracleAdapterError(
                f"artifact payload {spec.payload_field} must contain one Operation output"
            )
        if evidence[0].get("succeeded") is not True:
            raise OracleAdapterError(
                f"artifact payload {spec.payload_field} requires a successful Operation output"
            )
        if evidence[0] != operation_output:
            raise OracleAdapterError(
                f"artifact payload {spec.payload_field} differs from operationOutput"
            )
    elif evidence != operation_output.get(spec.source_field):
        raise OracleAdapterError(
            f"artifact payload {spec.payload_field} differs from operationOutput.{spec.source_field}"
        )


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise OracleAdapterError(f"artifact payload repeats JSON field {key!r}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise OracleAdapterError(f"artifact payload rejects non-finite number {value}")


def _validate_exact_decision(
    decision: OracleDecision,
    criteria: tuple[str, ...],
    negative_controls: tuple[str, ...],
) -> None:
    if tuple(item.criterion for item in decision.criteria) != criteria:
        raise OracleAdapterError(
            "OracleDecision criteria must exactly match the declared rubric order"
        )
    if (
        tuple(item.negative_control for item in decision.negative_controls)
        != negative_controls
    ):
        raise OracleAdapterError(
            "OracleDecision negative controls must exactly match the declared rubric order"
        )
    _validate_diagnostics(decision.diagnostics, "OracleDecision.diagnostics")


def _validate_diagnostics(values: tuple[OracleDiagnostic, ...], location: str) -> None:
    if len(values) > _MAX_DIAGNOSTICS:
        raise OracleAdapterError(
            f"{location} may contain at most {_MAX_DIAGNOSTICS} diagnostics"
        )
    if any(not isinstance(item, OracleDiagnostic) for item in values):
        raise OracleAdapterError(f"{location} must contain OracleDiagnostic values")
    if any(len(item.detail) > _MAX_DIAGNOSTIC_DETAIL for item in values):
        raise OracleAdapterError(
            f"{location} detail exceeds {_MAX_DIAGNOSTIC_DETAIL} characters"
        )


__all__ = (
    "ARTIFACT_SCHEMA",
    "ARTIFACT_SCHEMA_VERSION",
    "AgentDecision",
    "AgentDecisionRequest",
    "DecisionProvider",
    "EvidenceAttachment",
    "EvidenceProvenance",
    "IMPLEMENTATION_DIGEST",
    "IMPLEMENTATION_IDENTITIES",
    "IMPLEMENTATION_LOCATOR",
    "ImplementationIdentity",
    "OracleDecision",
    "OracleDecisionRequest",
    "OracleAdapterError",
    "OracleSpec",
    "RegressionOracleAdapter",
    "SPECS",
    "build_typed_evidence_payload",
    "implementation_identity",
)
