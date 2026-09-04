#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
import json
from pathlib import Path
import sys
from typing import Any, Callable, Dict, Mapping, Optional, Tuple


TOOLS_ROOT = Path(__file__).resolve().parents[2]
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from regression.core.contracts import BoundLane
from regression.runctl import compile_execution_plan
from regression.core.errors import RegressionError
from regression.core.ids import CallID, NodeID, SidekickID
from regression.core.runview import NodeStatus
from regression.tools import (
    bundle_tool,
    ledger_tool,
    op_tool,
    receipt_tool,
    session_tool,
)
from regression.tools.bundle_tool import BundleError
from regression.tools.human_receipt import HumanReceiptError
from regression.tools.ledger_lock import LedgerLockError
from regression.tools.op_tool import OpToolError
from regression.tools.receipt_tool import ReceiptToolError
from regression.tools.session_tool import SessionToolError
from regression.tools.verdict import Attribution, Verdict, VerdictError


PROTOCOL_VERSION = "2025-06-18"
SERVER_NAME = "enchron-regression"
SERVER_VERSION = "1"

JSONRPC_VERSION = "2.0"
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INVALID_REQUEST = -32600
PARSE_ERROR = -32700

TOOL_REFUSALS = (
    BundleError,
    HumanReceiptError,
    LedgerLockError,
    OpToolError,
    ReceiptToolError,
    RegressionError,
    SessionToolError,
    VerdictError,
)
TOOL_FAILURES = (Exception,)
UNEXPECTED_FAILURE = (
    "the tool did not refuse this call, it failed part way through serving it"
)


@dataclass(frozen=True)
class ImageBlock:
    media_type: str
    data: bytes
    caption: str

    def __post_init__(self) -> None:
        if not isinstance(self.media_type, str) or "/" not in self.media_type:
            raise ValueError("an image block carries an IANA media type")
        if not isinstance(self.data, bytes) or not self.data:
            raise ValueError("an image block carries its bytes")
        if not isinstance(self.caption, str) or not self.caption:
            raise ValueError("an image block says what it shows")

    def content(self) -> Dict[str, Any]:
        return {
            "type": "image",
            "mimeType": self.media_type,
            "data": base64.b64encode(self.data).decode("ascii"),
        }


@dataclass(frozen=True)
class ToolResult:
    json: Mapping[str, Any]
    images: Tuple[ImageBlock, ...] = ()

    def content(self) -> Tuple[Dict[str, Any], ...]:
        blocks = [{"type": "text", "text": _encode(self.json)}]
        for image in self.images:
            blocks.append({"type": "text", "text": image.caption})
            blocks.append(image.content())
        return tuple(blocks)


@dataclass(frozen=True)
class ToolDefinition:
    name: str
    description: str
    input_schema: Mapping[str, Any]
    handler: Callable[[Mapping[str, Any]], ToolResult]
    arguments: Tuple[Tuple[str, Dict[str, Any]], ...] = ()

    def descriptor(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "description": self.description,
            "inputSchema": dict(self.input_schema),
        }


def _encode(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def _pending(name: str, phase: str, builds: str) -> ToolDefinition:
    refusal = f"{name} is registered but unimplemented; {phase} builds {builds}"

    def handler(arguments: Mapping[str, Any]) -> ToolResult:
        return ToolResult({"tool": name, "implemented": False, "refusal": refusal})

    return ToolDefinition(
        name,
        refusal,
        {"type": "object", "properties": {}, "additionalProperties": True},
        handler,
    )


def _session(arguments: Mapping[str, Any]) -> ToolResult:
    return ToolResult(
        session_tool.run(
            arguments.get("mode"),
            arguments.get("device"),
            arguments.get("stage"),
            arguments.get("executionInput"),
            arguments.get("outputDirectory"),
        )
    )


def _op(arguments: Mapping[str, Any]) -> ToolResult:
    missing = [
        name
        for name in OP_COMPILE_INPUTS + OP_INVOCATION_INPUTS
        if not arguments.get(name)
    ]
    if missing:
        raise OpToolError(
            "op compiles the plan it runs against and needs " + ", ".join(missing)
        )

    plan, _ = compile_execution_plan(
        Path(arguments["repositoryRoot"]),
        Path(arguments["executionInput"]),
        Path(arguments["catalogRoot"]),
        Path(arguments["policy"]),
        Path(arguments["reviewsRoot"]),
        Path(arguments["blueprint"]),
    )
    outcome = op_tool.run(
        plan,
        Path(arguments["runDirectory"]),
        NodeID(arguments["node"]),
        CallID(arguments["call"]),
        BoundLane(arguments["lane"]),
        arguments["target"],
        SidekickID(arguments["sidekick"]),
    )
    images = ()
    if outcome.screenshot is not None:
        images = (
            ImageBlock(
                op_tool.SCREENSHOT_MEDIA_TYPE,
                outcome.screenshot,
                f"{outcome.call} on {outcome.node}",
            ),
        )
    return ToolResult(outcome.payload(), images)


def _bundle(arguments: Mapping[str, Any]) -> ToolResult:
    directory = arguments.get("runDirectory")
    if not isinstance(directory, str) or not directory:
        raise bundle_tool.BundleError("bundle reads one run directory")
    outcome = bundle_tool.run(
        Path(directory),
        NodeID(arguments.get("node")),
        arguments.get("attempt"),
    )
    images = tuple(
        ImageBlock(op_tool.SCREENSHOT_MEDIA_TYPE, item.png, item.caption)
        for item in outcome.images()
    )
    return ToolResult(outcome.payload(), images)


def _receipt(arguments: Mapping[str, Any]) -> ToolResult:
    directory = arguments.get("runDirectory")
    if not isinstance(directory, str) or not directory:
        raise receipt_tool.ReceiptToolError("receipt reads one run directory")
    human = arguments.get("humanReceipt")
    return ToolResult(
        receipt_tool.run(
            Path(directory), None if human is None else Path(human)
        )
    )


def _ledger(arguments: Mapping[str, Any]) -> ToolResult:
    action = arguments.get("action")
    directory = arguments.get("runDirectory")
    if not isinstance(directory, str) or not directory:
        raise LedgerLockError("ledger reads one run directory")
    if action == "view":
        raw_lane = arguments.get("lane")
        lane = None if raw_lane is None else BoundLane(raw_lane)
        return ToolResult(ledger_tool.view(Path(directory), lane))
    if action == "resume":
        return ToolResult(ledger_tool.resume(Path(directory)))
    if action == "reopen":
        node = arguments.get("node")
        if not isinstance(node, str) or not node:
            raise LedgerLockError("a reopen names the node it sends back")
        return ToolResult(ledger_tool.reopen(Path(directory), NodeID(node)))
    if action != "write":
        raise LedgerLockError(
            f"ledger takes the write, view, resume or reopen action, not {action!r}"
        )
    raw_verdict = arguments.get("verdict")
    if not isinstance(raw_verdict, Mapping):
        raise LedgerLockError("a ledger write carries its verdict")
    verdict = Verdict(
        raw_verdict.get("node"),
        raw_verdict.get("firstDeviantFrame"),
        raw_verdict.get("regionObservation", ""),
        Attribution(raw_verdict.get("attribution")),
        raw_verdict.get("signature"),
    )
    return ToolResult(
        ledger_tool.write(
            Path(directory),
            verdict,
            NodeStatus(arguments.get("status")),
        )
    )


OP_INVOCATION_INPUTS = (
    "runDirectory",
    "node",
    "call",
    "lane",
    "target",
    "sidekick",
)

OP_COMPILE_INPUTS = (
    "repositoryRoot",
    "executionInput",
    "catalogRoot",
    "policy",
    "reviewsRoot",
    "blueprint",
)

OP_SCHEMA = {
    "type": "object",
    "properties": {
        **{name: {"type": "string"} for name in OP_COMPILE_INPUTS},
        "runDirectory": {"type": "string"},
        "node": {"type": "string"},
        "call": {"type": "string"},
        "lane": {"type": "string", "enum": [item.value for item in BoundLane]},
        "target": {"type": "string"},
        "sidekick": {"type": "string"},
    },
    "required": [
        *OP_COMPILE_INPUTS,
        "runDirectory",
        "node",
        "call",
        "lane",
        "target",
        "sidekick",
    ],
    "additionalProperties": False,
}

RECEIPT_SCHEMA = {
    "type": "object",
    "properties": {
        "runDirectory": {"type": "string"},
        "humanReceipt": {"type": ["string", "null"]},
    },
    "required": ["runDirectory"],
    "additionalProperties": False,
}

BUNDLE_SCHEMA = {
    "type": "object",
    "properties": {
        "runDirectory": {"type": "string"},
        "node": {"type": "string"},
        "attempt": {"type": "integer", "minimum": 1},
    },
    "required": ["runDirectory", "node", "attempt"],
    "additionalProperties": False,
}

SESSION_SCHEMA = {
    "type": "object",
    "properties": {
        "mode": {"type": "string", "enum": list(session_tool.SESSION_MODES)},
        "device": {"type": "string"},
        "stage": {"type": "string", "enum": list(session_tool.SESSION_STAGES)},
        "executionInput": {"type": "string"},
        "outputDirectory": {"type": "string"},
    },
    "required": ["mode", "device", "stage"],
    "additionalProperties": False,
}

LEDGER_SCHEMA = {
    "type": "object",
    "properties": {
        "action": {
            "type": "string",
            "enum": ["write", "view", "resume", "reopen"],
        },
        "runDirectory": {"type": "string"},
        "node": {"type": "string"},
        "lane": {"type": "string", "enum": [item.value for item in BoundLane]},
        "status": {
            "type": "string",
            "enum": [
                item.value
                for item in NodeStatus
                if item not in ledger_tool.DERIVED_ONLY_STATUSES
            ],
        },
        "verdict": {
            "type": "object",
            "properties": {
                "node": {"type": "string"},
                "firstDeviantFrame": {"type": ["integer", "null"], "minimum": 0},
                "regionObservation": {"type": "string"},
                "attribution": {
                    "type": "string",
                    "enum": [item.value for item in Attribution],
                },
                "signature": {"type": ["string", "null"]},
            },
            "required": ["node", "regionObservation", "attribution"],
            "additionalProperties": False,
        },
    },
    "required": ["action", "runDirectory"],
    "additionalProperties": False,
}


def registry() -> Dict[str, ToolDefinition]:
    return {
        item.name: item
        for item in (
            ToolDefinition(
                "session",
                "Bring one device session up or take it down.",
                SESSION_SCHEMA,
                _session,
                (
                    ("--mode", {"default": session_tool.AGENT_MODE}),
                    ("--device", {}),
                    ("--stage", {}),
                    ("--execution-input", {"dest": "executionInput"}),
                    ("--output-directory", {"dest": "outputDirectory"}),
                ),
            ),
            ToolDefinition(
                "op",
                "Run one Operation call and read its pixel heuristics.",
                OP_SCHEMA,
                _op,
                (
                    ("--repository-root", {"dest": "repositoryRoot"}),
                    ("--execution-input", {"dest": "executionInput"}),
                    ("--catalog-root", {"dest": "catalogRoot"}),
                    ("--policy", {"dest": "policy"}),
                    ("--reviews-root", {"dest": "reviewsRoot"}),
                    ("--blueprint", {"dest": "blueprint"}),
                    ("--run-directory", {"dest": "runDirectory"}),
                    ("--node", {"dest": "node"}),
                    ("--call", {"dest": "call"}),
                    ("--lane", {"dest": "lane"}),
                    ("--target", {"dest": "target"}),
                    ("--sidekick", {"dest": "sidekick"}),
                ),
            ),
            ToolDefinition(
                "bundle",
                "Assemble the anomaly bundle one attribution reads.",
                BUNDLE_SCHEMA,
                _bundle,
                (
                    ("--run-directory", {"dest": "runDirectory"}),
                    ("--node", {"dest": "node"}),
                    ("--attempt", {"dest": "attempt", "type": int}),
                ),
            ),
            ToolDefinition(
                "ledger",
                "Write a verdict, read the run view, or read the resume points.",
                LEDGER_SCHEMA,
                _ledger,
                (
                    ("--action", {}),
                    ("--run-directory", {"dest": "runDirectory"}),
                    ("--node", {}),
                    ("--lane", {}),
                    ("--status", {}),
                    ("--verdict-json", {"dest": "verdict", "type": json.loads}),
                ),
            ),
            ToolDefinition(
                "receipt",
                "Close the run into a merge receipt, or name what is still open.",
                RECEIPT_SCHEMA,
                _receipt,
                (
                    ("--run-directory", {"dest": "runDirectory"}),
                    ("--human-receipt", {"dest": "humanReceipt"}),
                ),
            ),
        )
    }


TOOL_NAMES = ("session", "op", "bundle", "ledger", "receipt")


def call_tool(name: str, arguments: Mapping[str, Any]) -> ToolResult:
    tools = registry()
    if name not in tools:
        joined = ", ".join(sorted(tools))
        raise ValueError(f"{name!r} is not a registered tool; the registry holds {joined}")
    return tools[name].handler(arguments)


def _serve(stream_in, stream_out) -> int:
    for line in stream_in:
        text = line.strip()
        if not text:
            continue
        try:
            request = json.loads(text)
        except json.JSONDecodeError as error:
            _write(stream_out, _error(None, PARSE_ERROR, str(error)))
            continue
        response = _dispatch(request)
        if response is not None:
            _write(stream_out, response)
    return 0


def _dispatch(request: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(request, Mapping):
        return _error(None, INVALID_REQUEST, "a JSON-RPC frame must be an object")
    identifier = request.get("id")
    notification = "id" not in request
    method = request.get("method")
    if notification:
        return None
    if method == "ping":
        return _reply(identifier, {})
    if method == "initialize":
        return _reply(
            identifier,
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        )
    if method == "tools/list":
        return _reply(
            identifier,
            {"tools": [item.descriptor() for item in registry().values()]},
        )
    if method != "tools/call":
        return _error(identifier, METHOD_NOT_FOUND, f"unknown method {method!r}")
    parameters = request.get("params") or {}
    if not isinstance(parameters, Mapping):
        return _error(identifier, INVALID_PARAMS, "params must be an object")
    supplied = parameters.get("arguments") or {}
    if not isinstance(supplied, Mapping):
        return _error(identifier, INVALID_PARAMS, "tool arguments must be an object")
    try:
        result = call_tool(parameters.get("name"), supplied)
    except TOOL_REFUSALS as error:
        return _reply(
            identifier,
            {
                "content": [{"type": "text", "text": str(error)}],
                "isError": True,
            },
        )
    except TOOL_FAILURES as error:
        return _reply(
            identifier,
            {
                "content": [
                    {
                        "type": "text",
                        "text": (
                            f"{UNEXPECTED_FAILURE}: "
                            f"{type(error).__name__}: {error}"
                        ),
                    }
                ],
                "isError": True,
            },
        )
    return _reply(identifier, {"content": list(result.content()), "isError": False})


def _reply(identifier: Any, result: Mapping[str, Any]) -> Dict[str, Any]:
    return {"jsonrpc": JSONRPC_VERSION, "id": identifier, "result": dict(result)}


def _error(identifier: Any, code: int, message: str) -> Dict[str, Any]:
    return {
        "jsonrpc": JSONRPC_VERSION,
        "id": identifier,
        "error": {"code": code, "message": message},
    }


def _write(stream_out, payload: Mapping[str, Any]) -> None:
    stream_out.write(_encode(payload) + "\n")
    stream_out.flush()


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Expose the regression harness tools over MCP."
    )
    parser.add_argument("--once", choices=TOOL_NAMES)
    known, remainder = parser.parse_known_args(argv)
    if known.once is None:
        return _serve(sys.stdin, sys.stdout)

    definition = registry()[known.once]
    once = argparse.ArgumentParser(prog=f"server.py --once {known.once}")
    for flag, options in definition.arguments:
        once.add_argument(flag, **options)
    arguments = {
        key: value
        for key, value in vars(once.parse_args(remainder)).items()
        if value is not None
    }
    try:
        result = call_tool(known.once, arguments)
    except TOOL_FAILURES as error:
        sys.stdout.write(_encode({"error": str(error)}) + "\n")
        return 1
    sys.stdout.write(_encode({"content": list(result.content())}) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
