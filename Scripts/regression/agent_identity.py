#!/usr/bin/env python3

from __future__ import annotations

from regression.core.digest import canonical_digest
from regression.core.plan import AgentEnvironment


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

DECISION_SCHEMA = {
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


DEFAULT_AGENT_EXECUTABLE = "codex"
READ_ONLY_EXEC_FLAGS = (
    "exec",
    "--ephemeral",
    "--ignore-user-config",
    "--sandbox",
    "read-only",
)
DETERMINISTIC_OUTPUT_FLAGS = ("--color", "never")


def _command(executable: str, model: str) -> tuple[str, ...]:
    if not isinstance(executable, str) or not executable.strip():
        raise ValueError("Agent executable must be non-empty text")
    if not isinstance(model, str) or not model.strip():
        raise ValueError("Agent model must be non-empty text")
    return (
        executable,
        *READ_ONLY_EXEC_FLAGS,
        "--model",
        model,
        *DETERMINISTIC_OUTPUT_FLAGS,
    )


def agent_environment(
    model: str, executable: str = DEFAULT_AGENT_EXECUTABLE
) -> AgentEnvironment:
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


__all__ = (
    "DECISION_SCHEMA",
    "DEFAULT_AGENT_EXECUTABLE",
    "PROMPT_PROTOCOL",
    "PROTOCOL_VERSION",
    "agent_environment",
)
