#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import unittest
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


if __name__ == "__main__":
    unittest.main()
