#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.contracts import OracleKind  # noqa: E402
from regression.core.digest import canonical_digest  # noqa: E402
from regression.core.expression import OracleResult  # noqa: E402
from regression.core.runtime import OracleDiagnostic  # noqa: E402
from regression.oracle_agent import (  # noqa: E402
    AgentOracleProvider,
    agent_environment,
)
from verification.regression_oracle_adapter import OracleDecisionRequest  # noqa: E402


class FakeRunner:
    def __init__(self, payload: object, return_code: int = 0) -> None:
        self.payload = payload
        self.return_code = return_code
        self.calls = []

    def __call__(self, command, *, input, cwd, timeout, check, stdout, stderr):
        self.calls.append((tuple(command), input, cwd, timeout, check, stdout, stderr))
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(self.payload, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        return subprocess.CompletedProcess(command, self.return_code, b"", b"failure")


def _request() -> OracleDecisionRequest:
    return OracleDecisionRequest(
        oracle_kind=OracleKind.AGENT,
        criteria=("The current frame is non-empty.", "The title is visible."),
        negative_controls=("A blank frame is not accepted.",),
        artifact_path=Path("/tmp/evidence.json"),
        artifact_payload={
            "schema": "enchron.regression.oracle-evidence",
            "schemaVersion": 1,
            "evidenceType": "visual.frames",
            "evidenceSchema": "frame-sequence@2",
            "frames": [{"record": {"screenshot": "/tmp/frame.png"}}],
        },
        receipt_digest=canonical_digest({"receipt": "fixture"}),
    )


class AgentOracleProviderTests(unittest.TestCase):
    def test_provider_invokes_pinned_read_only_agent_and_returns_exact_decision(self) -> None:
        response = {
            "criteria": [
                {
                    "criterion": "The current frame is non-empty.",
                    "result": "satisfied",
                },
                {
                    "criterion": "The title is visible.",
                    "result": "violated",
                },
            ],
            "negativeControls": [
                {
                    "negativeControl": "A blank frame is not accepted.",
                    "result": "satisfied",
                }
            ],
            "diagnostics": [
                {"code": "oracle.title-missing", "detail": "No title node is visible."}
            ],
        }
        runner = FakeRunner(response)
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            provider = AgentOracleProvider(
                root,
                root / "runtime",
                model="gpt-5.6-sol",
                executable="/usr/local/bin/codex",
                runner=runner,
            )
            decision = provider.decide(_request())

        self.assertEqual(
            (OracleResult.SATISFIED, OracleResult.VIOLATED),
            tuple(item.result for item in decision.criteria),
        )
        self.assertEqual(
            (OracleResult.SATISFIED,),
            tuple(item.result for item in decision.negative_controls),
        )
        self.assertEqual(
            (OracleDiagnostic("oracle.title-missing", "No title node is visible."),),
            decision.diagnostics,
        )
        command, prompt, cwd, timeout, check, stdout, stderr = runner.calls[0]
        self.assertEqual(root.resolve(), cwd)
        self.assertIn("--ephemeral", command)
        self.assertIn("--ignore-user-config", command)
        self.assertEqual("read-only", command[command.index("--sandbox") + 1])
        self.assertEqual("gpt-5.6-sol", command[command.index("--model") + 1])
        self.assertEqual("-", command[-1])
        self.assertNotIn("/tmp/frame.png", " ".join(command))
        self.assertIn(
            f'"artifactPath":"{Path("/tmp/evidence.json").resolve()}"'.encode(),
            prompt,
        )
        self.assertEqual(300, timeout)
        self.assertFalse(check)
        self.assertIs(subprocess.PIPE, stdout)
        self.assertIs(subprocess.PIPE, stderr)

    def test_provider_rejects_missing_reordered_or_extra_judgments(self) -> None:
        invalid_values = (
            {
                "criteria": [],
                "negativeControls": [
                    {
                        "negativeControl": "A blank frame is not accepted.",
                        "result": "satisfied",
                    }
                ],
                "diagnostics": [],
            },
            {
                "criteria": [
                    {"criterion": "The title is visible.", "result": "satisfied"},
                    {
                        "criterion": "The current frame is non-empty.",
                        "result": "satisfied",
                    },
                ],
                "negativeControls": [
                    {
                        "negativeControl": "A blank frame is not accepted.",
                        "result": "satisfied",
                    }
                ],
                "diagnostics": [],
            },
            {
                "criteria": [
                    {
                        "criterion": "The current frame is non-empty.",
                        "result": "satisfied",
                        "reason": "extra",
                    },
                    {"criterion": "The title is visible.", "result": "satisfied"},
                ],
                "negativeControls": [
                    {
                        "negativeControl": "A blank frame is not accepted.",
                        "result": "satisfied",
                    }
                ],
                "diagnostics": [],
            },
        )
        for index, payload in enumerate(invalid_values):
            with self.subTest(index=index), TemporaryDirectory() as temporary:
                root = Path(temporary)
                provider = AgentOracleProvider(
                    root,
                    root / "runtime",
                    model="gpt-5.6-sol",
                    runner=FakeRunner(payload),
                )
                with self.assertRaises(ValueError):
                    provider.decide(_request())

    def test_provider_rejects_agent_failure_and_malformed_output(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            failed = AgentOracleProvider(
                root,
                root / "failed",
                model="gpt-5.6-sol",
                runner=FakeRunner({}, return_code=1),
            )
            with self.assertRaisesRegex(ValueError, "agent process failed"):
                failed.decide(_request())

            malformed = FakeRunner({})
            provider = AgentOracleProvider(
                root,
                root / "malformed",
                model="gpt-5.6-sol",
                runner=malformed,
            )
            original = malformed.__call__

            def write_malformed(*args, **kwargs):
                result = original(*args, **kwargs)
                command = args[0]
                output_index = command.index("--output-last-message") + 1
                Path(command[output_index]).write_text(
                    '{"criteria":', encoding="utf-8"
                )
                return result

            provider._runner = write_malformed
            with self.assertRaisesRegex(ValueError, "valid JSON"):
                provider.decide(_request())

    def test_agent_environment_binds_prompt_schema_model_and_command(self) -> None:
        first = agent_environment("gpt-5.6-sol", "codex")
        repeated = agent_environment("gpt-5.6-sol", "codex")
        other_model = agent_environment("gpt-5.6-terra", "codex")
        other_command = agent_environment("gpt-5.6-sol", "/opt/codex")

        self.assertEqual(first, repeated)
        self.assertNotEqual(first.configuration_digest, other_model.configuration_digest)
        self.assertNotEqual(first.configuration_digest, other_command.configuration_digest)
        self.assertEqual(first.prompt_digest, other_model.prompt_digest)


if __name__ == "__main__":
    unittest.main()
