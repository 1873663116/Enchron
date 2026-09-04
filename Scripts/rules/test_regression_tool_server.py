#!/usr/bin/env python3

from __future__ import annotations

import base64
import io
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
if str(SCRIPTS / "rules") not in sys.path:
    sys.path.insert(0, str(SCRIPTS / "rules"))

from regression.core.contracts import BoundLane
from regression.core.expression import OracleResult
from regression.core.runview import NodeStatus
from regression.tools import op_tool, server, session_tool
from regression.tools.ledger_lock import LedgerLockError
from regression.tools.op_tool import OpToolError
from regression.tools.session_tool import SessionToolError

from test_regression_ledger_lock import _both_lane_plan, run_node
from test_regression_core_runtime import _single_node_plan, open_run
from test_regression_raster import flat, png


PENDING_TOOLS = ("receipt",)


class RegistryTests(unittest.TestCase):
    def test_the_registry_holds_the_five_designed_tools(self) -> None:
        self.assertEqual(set(server.TOOL_NAMES), set(server.registry()))
        self.assertEqual(
            {"session", "op", "bundle", "ledger", "receipt"},
            set(server.registry()),
        )

    def test_every_tool_publishes_an_object_schema(self) -> None:
        for name, definition in server.registry().items():
            with self.subTest(tool=name):
                descriptor = definition.descriptor()
                self.assertEqual(name, descriptor["name"])
                self.assertTrue(descriptor["description"])
                self.assertEqual("object", descriptor["inputSchema"]["type"])

    def test_an_unimplemented_tool_refuses_instead_of_raising(self) -> None:
        for name in PENDING_TOOLS:
            with self.subTest(tool=name):
                result = server.call_tool(name, {})
                self.assertFalse(result.json["implemented"])
                self.assertIn("unimplemented", result.json["refusal"])
                self.assertEqual((), result.images)

    def test_the_refusal_names_the_phase_that_fills_the_tool_in(self) -> None:
        self.assertIn("phase 17", server.call_tool("receipt", {}).json["refusal"])

    def test_an_unregistered_name_is_refused(self) -> None:
        with self.assertRaisesRegex(ValueError, "is not a registered tool"):
            server.call_tool("verdict", {})


class ContentBlockTests(unittest.TestCase):
    def test_an_image_block_encodes_as_base64_with_its_caption(self) -> None:
        image = server.ImageBlock("image/png", b"\x89PNG frame", "the poster wall")
        result = server.ToolResult({"verdict": "failed"}, (image,))
        blocks = result.content()

        self.assertEqual(3, len(blocks))
        self.assertEqual({"verdict": "failed"}, json.loads(blocks[0]["text"]))
        self.assertEqual("the poster wall", blocks[1]["text"])
        self.assertEqual("image", blocks[2]["type"])
        self.assertEqual("image/png", blocks[2]["mimeType"])
        self.assertEqual(b"\x89PNG frame", base64.b64decode(blocks[2]["data"]))

    def test_a_result_without_images_carries_one_text_block(self) -> None:
        blocks = server.ToolResult({"ready": True}).content()
        self.assertEqual(1, len(blocks))
        self.assertEqual("text", blocks[0]["type"])

    def test_a_malformed_image_block_is_refused(self) -> None:
        for arguments in (
            ("png", b"bytes", "caption"),
            ("image/png", b"", "caption"),
            ("image/png", b"bytes", ""),
        ):
            with self.subTest(arguments=arguments):
                with self.assertRaises(ValueError):
                    server.ImageBlock(*arguments)


class SessionParameterTests(unittest.TestCase):
    def test_the_mode_and_stage_are_closed_vocabularies(self) -> None:
        with self.assertRaisesRegex(SessionToolError, "agent or human mode"):
            session_tool.run("operator", "udid", session_tool.ENSURE_STAGE)
        with self.assertRaisesRegex(SessionToolError, "ensure or halt stage"):
            session_tool.run(session_tool.AGENT_MODE, "udid", "restart")

    def test_human_mode_refuses_and_names_its_phase(self) -> None:
        with self.assertRaisesRegex(SessionToolError, "phase 16"):
            session_tool.run(
                session_tool.HUMAN_MODE, "udid", session_tool.ENSURE_STAGE
            )

    def test_a_session_without_its_device_is_refused(self) -> None:
        with self.assertRaisesRegex(SessionToolError, "needs the device"):
            session_tool.run(session_tool.AGENT_MODE, "", session_tool.ENSURE_STAGE)

    def test_the_schema_matches_the_vocabularies_the_tool_enforces(self) -> None:
        properties = server.SESSION_SCHEMA["properties"]
        self.assertEqual(list(session_tool.SESSION_MODES), properties["mode"]["enum"])
        self.assertEqual(list(session_tool.SESSION_STAGES), properties["stage"]["enum"])
        self.assertEqual(
            ["mode", "device", "stage"], server.SESSION_SCHEMA["required"]
        )

    def test_the_forwarded_argv_parses_into_a_namespace_the_controller_reads(
        self,
    ) -> None:
        from interactive_visionpro_ui import parse_arguments

        ensure = parse_arguments(
            [
                "--device",
                "udid",
                "--output-directory",
                "/tmp/session",
                "--execution-input",
                "/tmp/execution-input.json",
                session_tool.ENSURE_SESSION_ACTION,
            ]
        )
        self.assertEqual("ensure-session", ensure.action)
        self.assertEqual("udid", ensure.device)
        self.assertEqual("/tmp/session", ensure.output_directory)
        self.assertEqual(
            Path("/tmp/execution-input.json"), ensure.execution_input
        )
        for attribute in (
            "runner_bundle_id",
            "destination_id",
            "developer_dir",
            "ready_timeout",
            "identifier",
            "identifiers",
            "no_screenshot",
            "timeout_seconds",
        ):
            with self.subTest(attribute=attribute):
                self.assertTrue(hasattr(ensure, attribute))

        halt = parse_arguments(
            ["--device", "udid", session_tool.HALT_ACTION]
        )
        self.assertEqual("halt", halt.action)
        self.assertEqual("udid", halt.device)

    def forwarded(self, **overrides):
        captured = {}

        def capture(arguments):
            captured["arguments"] = arguments
            return {"stage": "ready"}

        fields = {
            "mode": session_tool.AGENT_MODE,
            "device": "udid",
            "stage": session_tool.ENSURE_STAGE,
        }
        fields.update(overrides)
        target = (
            "ensure_session"
            if fields["stage"] == session_tool.ENSURE_STAGE
            else "halt_session"
        )
        original = getattr(session_tool, target)
        setattr(session_tool, target, capture)
        try:
            result = session_tool.run(**fields)
        finally:
            setattr(session_tool, target, original)
        return captured["arguments"], result

    def test_ensure_forwards_the_device_paths_and_action(self) -> None:
        arguments, result = self.forwarded(
            execution_input="/tmp/execution-input.json",
            output_directory="/tmp/session",
        )
        self.assertEqual("ensure-session", arguments.action)
        self.assertEqual("udid", arguments.device)
        self.assertEqual("/tmp/session", arguments.output_directory)
        self.assertEqual(
            Path("/tmp/execution-input.json"), arguments.execution_input
        )
        self.assertEqual({"stage": "ready"}, result)

    def test_halt_forwards_without_an_execution_input(self) -> None:
        arguments, _ = self.forwarded(stage=session_tool.HALT_STAGE)
        self.assertEqual("halt", arguments.action)
        self.assertIsNone(arguments.execution_input)

    def test_an_omitted_output_directory_keeps_the_controller_default(self) -> None:
        arguments, _ = self.forwarded()
        self.assertEqual("/tmp/enchron-interactive-ui", arguments.output_directory)

    def test_an_option_shaped_device_reaches_the_controller_intact(self) -> None:
        arguments, _ = self.forwarded(device="--not-a-device")
        self.assertEqual("--not-a-device", arguments.device)

    def test_a_controller_failure_becomes_a_document_not_an_exception(self) -> None:
        def explode(arguments):
            raise RuntimeError("the controller target is not paired")

        original = session_tool.ensure_session
        session_tool.ensure_session = explode
        try:
            result = session_tool.run(
                session_tool.AGENT_MODE, "udid", session_tool.ENSURE_STAGE
            )
        finally:
            session_tool.ensure_session = original

        self.assertFalse(result["success"])
        self.assertIn("not paired", result["error"])

    def test_the_controller_still_answers_every_stage_the_tool_forwards(self) -> None:
        source = (
            SCRIPTS / "verification" / "interactive_visionpro_ui.py"
        ).read_text(encoding="utf-8")
        for stage in session_tool.ENSURE_RESULT_STAGES:
            with self.subTest(stage=stage):
                self.assertIn(f'"stage": "{stage}"', source)


class LedgerToolRoutingTests(unittest.TestCase):
    def run_directory(self, temporary: str):
        directory = Path(temporary)
        main = open_run(_both_lane_plan(), directory)
        run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
        main.close()
        return directory

    def test_the_view_action_reaches_the_lane_lock(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = self.run_directory(temporary)
            result = server.call_tool(
                "ledger", {"action": "view", "runDirectory": str(directory)}
            )
            self.assertTrue(any(item["locked"] for item in result.json["locks"]))

    def test_the_resume_action_names_what_the_run_owes(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = self.run_directory(temporary)
            result = server.call_tool(
                "ledger", {"action": "resume", "runDirectory": str(directory)}
            )
            self.assertEqual(["node:gate"], result.json["awaitingVerdict"])

    def test_the_write_action_carries_the_verdict_through(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = self.run_directory(temporary)
            result = server.call_tool(
                "ledger",
                {
                    "action": "write",
                    "runDirectory": str(directory),
                    "status": "failed",
                    "bundleFrameCount": 12,
                    "verdict": {
                        "node": "node:gate",
                        "firstDeviantFrame": 4,
                        "regionObservation": "the gate never appeared",
                        "attribution": "product",
                        "signature": None,
                    },
                },
            )
            adjudicated = next(
                item for item in result.json["nodes"] if item["node"] == "node:gate"
            )
            self.assertEqual("failed", adjudicated["status"])
            self.assertEqual(4, adjudicated["adjudication"]["firstDeviantFrame"])

    def test_an_unknown_action_and_a_missing_directory_are_refused(self) -> None:
        with self.assertRaisesRegex(LedgerLockError, "reads one run directory"):
            server.call_tool("ledger", {"action": "view"})
        with self.assertRaisesRegex(LedgerLockError, "write, view or resume"):
            server.call_tool("ledger", {"action": "close", "runDirectory": "/tmp"})


class OpRoutingTests(unittest.TestCase):
    def arguments(self, directory: Path) -> dict:
        return {
            "repositoryRoot": ".",
            "executionInput": "execution-input.json",
            "catalogRoot": "Regression",
            "policy": "policy.json",
            "reviewsRoot": "Regression/reviews",
            "blueprint": "blueprint.json",
            "runDirectory": str(directory),
            "node": "node:gate",
            "call": "call:gate-evidence",
            "lane": "simulator",
            "target": "SIM-UDID",
            "sidekick": "sidekick:op",
        }

    def test_the_compiler_the_server_imports_is_the_real_one(self) -> None:
        from regression.runctl import compile_execution_plan

        self.assertIs(compile_execution_plan, server.compile_execution_plan)
        self.assertTrue(callable(server.compile_execution_plan))

    def test_op_reaches_the_compiler_with_every_input_it_was_given(self) -> None:
        captured = {}

        def compile_execution_plan(*arguments):
            captured["arguments"] = arguments
            raise RuntimeError("the catalog is not part of this test")

        original = server.compile_execution_plan
        server.compile_execution_plan = compile_execution_plan
        try:
            with TemporaryDirectory() as temporary:
                with self.assertRaisesRegex(RuntimeError, "not part of this test"):
                    server.call_tool("op", self.arguments(Path(temporary)))
        finally:
            server.compile_execution_plan = original

        self.assertEqual(6, len(captured["arguments"]))
        self.assertEqual(Path("Regression"), captured["arguments"][2])

    def test_op_names_every_compile_input_it_is_missing(self) -> None:
        with self.assertRaisesRegex(OpToolError, "repositoryRoot"):
            server.call_tool("op", {"runDirectory": "/tmp", "node": "node:gate"})

    def test_the_op_schema_requires_what_the_handler_requires(self) -> None:
        required = set(server.OP_SCHEMA["required"])
        self.assertTrue(set(server.OP_COMPILE_INPUTS) <= required)
        for name in ("runDirectory", "node", "call", "lane", "target", "sidekick"):
            with self.subTest(field=name):
                self.assertIn(name, required)

    def test_a_screenshot_returns_as_an_image_content_block(self) -> None:
        captured = {}

        def compile_execution_plan(*arguments):
            return _single_node_plan(), None

        def run(plan, run_directory, node, call, lane, target, sidekick, **rest):
            captured["lane"] = lane
            return op_tool.OpOutcome(
                node=node,
                call=call,
                succeeded=True,
                screenshot=png(4, 4, flat(4, 4, 90)),
            )

        original = (server.compile_execution_plan, op_tool.run)
        server.compile_execution_plan = compile_execution_plan
        op_tool.run = run
        try:
            with TemporaryDirectory() as temporary:
                result = server.call_tool("op", self.arguments(Path(temporary)))
        finally:
            server.compile_execution_plan, op_tool.run = original

        blocks = result.content()
        self.assertEqual(BoundLane.SIMULATOR, captured["lane"])
        self.assertEqual("image", blocks[-1]["type"])
        self.assertEqual(op_tool.SCREENSHOT_MEDIA_TYPE, blocks[-1]["mimeType"])
        self.assertEqual(1, len(result.images))


class ProtocolTests(unittest.TestCase):
    def test_initialize_announces_the_tool_capability(self) -> None:
        reply = server._dispatch({"id": 1, "method": "initialize"})
        self.assertEqual(server.PROTOCOL_VERSION, reply["result"]["protocolVersion"])
        self.assertIn("tools", reply["result"]["capabilities"])

    def test_tools_list_publishes_every_registered_tool(self) -> None:
        reply = server._dispatch({"id": 2, "method": "tools/list"})
        self.assertEqual(
            set(server.TOOL_NAMES),
            {item["name"] for item in reply["result"]["tools"]},
        )

    def test_a_frame_without_an_id_is_a_notification_and_draws_no_reply(
        self,
    ) -> None:
        for method in ("notifications/initialized", "notifications/cancelled"):
            with self.subTest(method=method):
                self.assertIsNone(server._dispatch({"method": method}))

    def test_ping_is_answered(self) -> None:
        self.assertEqual({}, server._dispatch({"id": 7, "method": "ping"})["result"])

    def test_a_frame_that_is_not_an_object_is_an_invalid_request(self) -> None:
        for frame in ([1, 2], "initialize", 7):
            with self.subTest(frame=frame):
                self.assertEqual(
                    server.INVALID_REQUEST,
                    server._dispatch(frame)["error"]["code"],
                )

    def test_non_object_params_and_arguments_are_invalid_params(self) -> None:
        for parameters in ("session", [1], {"name": "session", "arguments": [1]}):
            with self.subTest(parameters=parameters):
                reply = server._dispatch(
                    {"id": 8, "method": "tools/call", "params": parameters}
                )
                self.assertEqual(server.INVALID_PARAMS, reply["error"]["code"])

    def test_a_tool_raising_outside_the_valueerror_family_still_answers(self) -> None:
        def explode(arguments):
            raise RuntimeError("the device went away")

        original = server.registry
        server.registry = lambda: {
            "session": server.ToolDefinition(
                "session", "d", {"type": "object"}, explode
            )
        }
        try:
            reply = server._dispatch(
                {
                    "id": 9,
                    "method": "tools/call",
                    "params": {"name": "session", "arguments": {}},
                }
            )
        finally:
            server.registry = original

        self.assertTrue(reply["result"]["isError"])
        self.assertIn("device went away", reply["result"]["content"][0]["text"])

    def test_the_stdio_loop_survives_a_tool_that_raises(self) -> None:
        def explode(arguments):
            raise OSError("too many open files")

        original = server.registry
        server.registry = lambda: {
            "session": server.ToolDefinition(
                "session", "d", {"type": "object"}, explode
            )
        }
        stream_in = io.StringIO(
            json.dumps(
                {
                    "id": 1,
                    "method": "tools/call",
                    "params": {"name": "session", "arguments": {}},
                }
            )
            + "\n"
            + json.dumps({"id": 2, "method": "ping"})
            + "\n"
        )
        stream_out = io.StringIO()
        try:
            server._serve(stream_in, stream_out)
        finally:
            server.registry = original

        replies = [json.loads(line) for line in stream_out.getvalue().splitlines()]
        self.assertEqual([1, 2], [item["id"] for item in replies])

    def test_an_unknown_method_returns_a_jsonrpc_error(self) -> None:
        reply = server._dispatch({"id": 3, "method": "tools/describe"})
        self.assertEqual(server.METHOD_NOT_FOUND, reply["error"]["code"])

    def test_a_failing_tool_call_returns_an_error_result_not_a_transport_error(
        self,
    ) -> None:
        reply = server._dispatch(
            {
                "id": 4,
                "method": "tools/call",
                "params": {"name": "session", "arguments": {"mode": "operator"}},
            }
        )
        self.assertTrue(reply["result"]["isError"])
        self.assertIn("agent or human mode", reply["result"]["content"][0]["text"])

    def test_the_stdio_loop_answers_one_request_per_line(self) -> None:
        stream_in = io.StringIO(
            json.dumps({"id": 1, "method": "initialize"})
            + "\n"
            + json.dumps({"id": 2, "method": "tools/list"})
            + "\n"
        )
        stream_out = io.StringIO()
        self.assertEqual(0, server._serve(stream_in, stream_out))
        replies = [json.loads(line) for line in stream_out.getvalue().splitlines()]
        self.assertEqual([1, 2], [item["id"] for item in replies])

    def test_a_malformed_line_answers_with_a_parse_error(self) -> None:
        stream_out = io.StringIO()
        server._serve(io.StringIO("{not json\n"), stream_out)
        self.assertEqual(
            server.PARSE_ERROR,
            json.loads(stream_out.getvalue())["error"]["code"],
        )


class OnceModeTests(unittest.TestCase):
    def test_once_runs_one_tool_and_prints_its_content(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = open_run(_both_lane_plan(), directory)
            run_node(main, BoundLane.SIMULATOR, OracleResult.VIOLATED, "red")
            main.close()

            captured = io.StringIO()
            original = sys.stdout
            sys.stdout = captured
            try:
                code = server.main(
                    [
                        "--once",
                        "ledger",
                        "--action",
                        "resume",
                        "--run-directory",
                        str(directory),
                    ]
                )
            finally:
                sys.stdout = original

            self.assertEqual(0, code)
            payload = json.loads(captured.getvalue())
            self.assertEqual(
                ["node:gate"],
                json.loads(payload["content"][0]["text"])["awaitingVerdict"],
            )

    def test_once_reports_a_refusal_on_the_exit_code(self) -> None:
        captured = io.StringIO()
        original = sys.stdout
        sys.stdout = captured
        try:
            code = server.main(
                ["--once", "ledger", "--action", "view", "--run-directory", ""]
            )
        finally:
            sys.stdout = original

        self.assertEqual(1, code)
        self.assertIn("run directory", json.loads(captured.getvalue())["error"])

    def test_once_on_a_pending_tool_reports_the_refusal_as_content(self) -> None:
        captured = io.StringIO()
        original = sys.stdout
        sys.stdout = captured
        try:
            code = server.main(["--once", "receipt"])
        finally:
            sys.stdout = original

        self.assertEqual(0, code)
        payload = json.loads(captured.getvalue())
        self.assertFalse(
            json.loads(payload["content"][0]["text"])["implemented"]
        )


class BundleRegistrationTests(unittest.TestCase):
    """The anomaly bundle reaches an Agent as image content blocks. A payload
    that counts images the reply does not carry would describe evidence nobody
    can look at."""

    def test_the_bundle_schema_requires_the_run_the_node_and_the_attempt(self) -> None:
        schema = server.registry()["bundle"].descriptor()["inputSchema"]

        self.assertEqual(
            {"runDirectory", "node", "attempt"}, set(schema["required"])
        )
        self.assertEqual("integer", schema["properties"]["attempt"]["type"])
        self.assertFalse(schema["additionalProperties"])

    def test_a_bundle_call_without_a_run_directory_is_refused(self) -> None:
        with self.assertRaisesRegex(ValueError, "one run directory"):
            server.call_tool("bundle", {"node": "node:gate", "attempt": 1})

    def test_every_image_the_payload_counts_rides_with_the_reply(self) -> None:
        class Image:
            caption = "after call:step-0"
            png = b"\x89PNG\r\n\x1a\n"

        class Outcome:
            def images(self):
                return (Image(), Image())

            def payload(self):
                return {"frameCount": 2}

        original = server.bundle_tool.run
        server.bundle_tool.run = lambda directory, node, attempt: Outcome()
        try:
            result = server.call_tool(
                "bundle",
                {"runDirectory": "/tmp/run", "node": "node:gate", "attempt": 1},
            )
        finally:
            server.bundle_tool.run = original

        self.assertEqual(2, len(result.images))
        self.assertEqual("after call:step-0", result.images[0].caption)


if __name__ == "__main__":
    unittest.main()
