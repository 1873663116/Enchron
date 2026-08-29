#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from typing import Any, Callable, Mapping, Sequence

from regression.core.digest import canonical_bytes, canonical_digest
from regression.core.expression import OracleResult
from regression.core.plan import AgentEnvironment
from regression.core.runtime import (
    CriterionEvaluation,
    NegativeControlEvaluation,
    OracleDiagnostic,
)
from verification.regression_oracle_adapter import (
    OracleAdapterError,
    OracleDecision,
    OracleDecisionRequest,
)


PROTOCOL_VERSION = 1
PROMPT_PROTOCOL = """You are the Oracle judge for one Enchron regression obligation.
Judge only the supplied evidence against the ordered criteria and negative controls.
Read obligationId, caseKey, producer Operation and arguments, the complete ordered
operationTranscript through that producer, the complete operationOutput, and every
content-bound attachment. Inspect local image or audio attachments when required.
Transcript status, operationResult, and operationError fields describe completed
acquisition attempts and retry history; they are never product verdicts.
operationOutput.succeeded means that observation acquisition completed; it is never a product
verdict and must not be treated as satisfying a criterion.
Do not run the product, change files, infer absent facts, or ask a human.
Return one result for every input item, in the same order and with exactly the same text.
Use satisfied only when the evidence establishes the item, violated when it contradicts
the item, and indeterminate when the supplied evidence cannot decide it. A negative
control is satisfied only when the forbidden or misleading condition is absent.
Diagnostics must identify concrete evidence gaps or contradictions and must not add
criteria, waive a criterion, or reinterpret the requested behavior.
"""

DECISION_SCHEMA: Mapping[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": False,
    "required": ["criteria", "negativeControls", "diagnostics"],
    "properties": {
        "criteria": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["criterion", "result"],
                "properties": {
                    "criterion": {"type": "string", "minLength": 1},
                    "result": {
                        "type": "string",
                        "enum": ["satisfied", "violated", "indeterminate"],
                    },
                },
            },
        },
        "negativeControls": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["negativeControl", "result"],
                "properties": {
                    "negativeControl": {"type": "string", "minLength": 1},
                    "result": {
                        "type": "string",
                        "enum": ["satisfied", "violated", "indeterminate"],
                    },
                },
            },
        },
        "diagnostics": {
            "type": "array",
            "maxItems": 16,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["code", "detail"],
                "properties": {
                    "code": {"type": "string", "minLength": 1},
                    "detail": {"type": "string", "minLength": 1, "maxLength": 1024},
                },
            },
        },
    },
}

Runner = Callable[..., subprocess.CompletedProcess[bytes]]


def _command(executable: str, model: str) -> tuple[str, ...]:
    if not isinstance(executable, str) or not executable.strip():
        raise OracleAdapterError("Agent executable must be non-empty text")
    if not isinstance(model, str) or not model.strip():
        raise OracleAdapterError("Agent model must be non-empty text")
    return (
        executable,
        "exec",
        "--ephemeral",
        "--ignore-user-config",
        "--sandbox",
        "read-only",
        "--model",
        model,
        "--color",
        "never",
    )


def agent_environment(model: str, executable: str = "codex") -> AgentEnvironment:
    command = _command(executable, model)
    return AgentEnvironment(
        model,
        canonical_digest(
            {
                "protocolVersion": PROTOCOL_VERSION,
                "prompt": PROMPT_PROTOCOL,
            }
        ),
        canonical_digest(
            {
                "command": list(command),
                "outputSchema": DECISION_SCHEMA,
            }
        ),
    )


class AgentOracleProvider:
    def __init__(
        self,
        repository_root: Path,
        runtime_root: Path,
        *,
        model: str,
        executable: str = "codex",
        timeout_seconds: int = 300,
        runner: Runner = subprocess.run,
    ) -> None:
        repository = Path(repository_root).resolve()
        if not repository.is_dir():
            raise OracleAdapterError("Agent repository root must be a directory")
        if type(timeout_seconds) is not int or timeout_seconds < 1:
            raise OracleAdapterError("Agent timeout must be a positive integer")
        if not callable(runner):
            raise OracleAdapterError("Agent runner must be callable")
        self.repository_root = repository
        self.runtime_root = Path(runtime_root).resolve()
        self.runtime_root.mkdir(parents=True, exist_ok=True)
        if self.runtime_root.is_symlink() or not self.runtime_root.is_dir():
            raise OracleAdapterError("Agent runtime root must be a real directory")
        self.model = model
        self.executable = executable
        self.timeout_seconds = timeout_seconds
        self.agent_environment = agent_environment(model, executable)
        self._runner = runner

    def decide(self, request: OracleDecisionRequest) -> OracleDecision:
        if not isinstance(request, OracleDecisionRequest):
            raise OracleAdapterError("Agent provider needs an OracleDecisionRequest")
        payload = {
            "schema": "enchron.regression.oracle-agent-request",
            "schemaVersion": PROTOCOL_VERSION,
            "oracleKind": request.oracle_kind.value,
            "criteria": list(request.criteria),
            "negativeControls": list(request.negative_controls),
            "artifactPath": str(request.artifact_path.resolve()),
            "artifactReceiptDigest": str(request.receipt_digest),
            "artifact": request.artifact_payload,
        }
        prompt = PROMPT_PROTOCOL.encode("utf-8") + b"\nREQUEST\n" + canonical_bytes(payload)

        with TemporaryDirectory(dir=self.runtime_root) as temporary:
            directory = Path(temporary)
            schema_path = directory / "decision.schema.json"
            output_path = directory / "decision.json"
            schema_path.write_bytes(canonical_bytes(DECISION_SCHEMA) + b"\n")
            command = (
                *_command(self.executable, self.model),
                "--output-schema",
                str(schema_path),
                "--output-last-message",
                str(output_path),
                "-C",
                str(self.repository_root),
                "-",
            )
            completed = self._runner(
                command,
                input=prompt,
                cwd=self.repository_root,
                timeout=self.timeout_seconds,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if completed.returncode != 0:
                raise OracleAdapterError(
                    f"Oracle agent process failed with exit code {completed.returncode}"
                )
            if not output_path.is_file() or output_path.is_symlink():
                raise OracleAdapterError("Oracle agent did not produce a decision file")
            source = output_path.read_bytes()

        value = _decode_json(source)
        return _decision(value, request.criteria, request.negative_controls)


def _decode_json(source: bytes) -> Mapping[str, Any]:
    def reject_duplicate(pairs: Sequence[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise OracleAdapterError(f"Oracle decision repeats field {key!r}")
            result[key] = value
        return result

    def reject_constant(value: str) -> None:
        raise OracleAdapterError(f"Oracle decision rejects JSON constant {value}")

    try:
        value = json.loads(
            source.decode("utf-8"),
            object_pairs_hook=reject_duplicate,
            parse_constant=reject_constant,
        )
    except UnicodeDecodeError as error:
        raise OracleAdapterError("Oracle decision must be UTF-8 JSON") from error
    except json.JSONDecodeError as error:
        raise OracleAdapterError("Oracle decision must be valid JSON") from error
    if not isinstance(value, dict):
        raise OracleAdapterError("Oracle decision must be a JSON object")
    return value


def _exact_object(
    value: object, expected: frozenset[str], location: str
) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise OracleAdapterError(f"{location} must be a JSON object")
    if set(value) != expected:
        raise OracleAdapterError(
            f"{location} must contain exactly {', '.join(sorted(expected))}"
        )
    return value


def _result(value: object, location: str) -> OracleResult:
    if not isinstance(value, str):
        raise OracleAdapterError(f"{location} must be a result string")
    try:
        return OracleResult(value)
    except ValueError as error:
        raise OracleAdapterError(f"{location} has an unknown result {value!r}") from error


def _decision(
    value: Mapping[str, Any],
    criteria: tuple[str, ...],
    negative_controls: tuple[str, ...],
) -> OracleDecision:
    root = _exact_object(
        value,
        frozenset(("criteria", "negativeControls", "diagnostics")),
        "Oracle decision",
    )
    criterion_values = root["criteria"]
    control_values = root["negativeControls"]
    diagnostic_values = root["diagnostics"]
    if not isinstance(criterion_values, list):
        raise OracleAdapterError("Oracle decision criteria must be an array")
    if not isinstance(control_values, list):
        raise OracleAdapterError("Oracle decision negativeControls must be an array")
    if not isinstance(diagnostic_values, list):
        raise OracleAdapterError("Oracle decision diagnostics must be an array")
    if len(criterion_values) != len(criteria):
        raise OracleAdapterError("Oracle decision must cover every criterion exactly once")
    if len(control_values) != len(negative_controls):
        raise OracleAdapterError(
            "Oracle decision must cover every negative control exactly once"
        )

    criterion_results = []
    for index, (item, expected) in enumerate(zip(criterion_values, criteria)):
        parsed = _exact_object(
            item, frozenset(("criterion", "result")), f"criteria[{index}]"
        )
        if parsed["criterion"] != expected:
            raise OracleAdapterError(
                f"criteria[{index}] does not preserve the requested criterion"
            )
        criterion_results.append(
            CriterionEvaluation(expected, _result(parsed["result"], f"criteria[{index}].result"))
        )

    control_results = []
    for index, (item, expected) in enumerate(zip(control_values, negative_controls)):
        parsed = _exact_object(
            item,
            frozenset(("negativeControl", "result")),
            f"negativeControls[{index}]",
        )
        if parsed["negativeControl"] != expected:
            raise OracleAdapterError(
                f"negativeControls[{index}] does not preserve the requested control"
            )
        control_results.append(
            NegativeControlEvaluation(
                expected,
                _result(parsed["result"], f"negativeControls[{index}].result"),
            )
        )

    diagnostics = []
    for index, item in enumerate(diagnostic_values):
        parsed = _exact_object(
            item, frozenset(("code", "detail")), f"diagnostics[{index}]"
        )
        diagnostics.append(OracleDiagnostic(parsed["code"], parsed["detail"]))
    return OracleDecision(
        tuple(criterion_results), tuple(control_results), tuple(diagnostics)
    )


__all__ = (
    "AgentOracleProvider",
    "DECISION_SCHEMA",
    "PROMPT_PROTOCOL",
    "PROTOCOL_VERSION",
    "agent_environment",
)
