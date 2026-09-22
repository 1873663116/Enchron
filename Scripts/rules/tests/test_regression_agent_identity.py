#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import unittest


SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.agent_identity import agent_environment


class AgentIdentityTests(unittest.TestCase):
    def test_agent_identity_binds_prompt_schema_model_and_command(self) -> None:
        first = agent_environment("gpt-5.6-sol", "codex")
        repeated = agent_environment("gpt-5.6-sol", "codex")
        other_model = agent_environment("gpt-5.6-terra", "codex")
        other_command = agent_environment("gpt-5.6-sol", "/opt/codex")

        self.assertEqual(first, repeated)
        self.assertNotEqual(first.configuration_digest, other_model.configuration_digest)
        self.assertNotEqual(first.configuration_digest, other_command.configuration_digest)
        self.assertEqual(first.prompt_digest, other_model.prompt_digest)
        self.assertEqual("gpt-5.6-sol", first.model)

    def test_agent_identity_rejects_empty_model_or_executable(self) -> None:
        with self.assertRaisesRegex(ValueError, "executable"):
            agent_environment("gpt-5.6-sol", "")
        with self.assertRaisesRegex(ValueError, "model"):
            agent_environment("", "codex")


if __name__ == "__main__":
    unittest.main()
