#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import interactive_visionpro_ui as controller


class DeferredAppCommandTests(unittest.TestCase):
    def test_deferred_command_sends_once_without_copying_its_response(self) -> None:
        sent: dict[str, object] = {}
        arguments = argparse.Namespace(
            verb="toggleControls",
            timeout_seconds=30.0,
            app_arguments=["evidenceSession=session-10", "visible=true"],
            device="device",
            defer_response=True,
        )
        def capture_request(**kwargs) -> None:
            sent.update(json.loads(kwargs["local_path"].read_text(encoding="utf-8")))

        with patch.object(
            controller.uuid, "uuid4", return_value="command-10"
        ), patch.object(
            controller, "copy_to_device", side_effect=capture_request
        ) as copy_to, patch.object(
            controller, "copy_from_device"
        ) as copy_from, patch.object(controller.time, "sleep"):
            response = controller.app_command(arguments)

        copy_to.assert_called_once()
        self.assertEqual(
            copy_to.call_args.kwargs["remote_path"],
            "Documents/test-commands/command-10.json",
        )
        copy_from.assert_not_called()
        self.assertEqual(
            sent,
            {
                "id": "command-10",
                "verb": "toggleControls",
                "args": {
                    "evidenceSession": "session-10",
                    "visible": "true",
                },
            },
        )
        self.assertEqual(
            response,
            {
                "success": True,
                "deferred": True,
                "id": "command-10",
                "verb": "toggleControls",
            },
        )


class CommandTextTests(unittest.TestCase):
    def test_json_field_is_loaded_without_putting_secret_in_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            credentials = Path(directory) / "credentials.json"
            credentials.write_text(
                json.dumps({"username": "viewer", "password": "secret-value"}),
                encoding="utf-8",
            )
            arguments = argparse.Namespace(
                text=None,
                text_file=credentials,
                text_json_key="password",
            )

            self.assertEqual(controller.resolve_command_text(arguments), "secret-value")
            self.assertNotIn("secret-value", repr(arguments))

    def test_response_redaction_removes_the_input_from_nested_text(self) -> None:
        response = {
            "hierarchy": "Username: private-user",
            "matchedElement": {"value": "private-user"},
        }

        redacted = controller.redact_command_text(response, "private-user")

        self.assertNotIn("private-user", json.dumps(redacted))
        self.assertEqual(redacted["matchedElement"]["value"], "<redacted-input>")


if __name__ == "__main__":
    unittest.main()
