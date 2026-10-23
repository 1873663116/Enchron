from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import explain
import model
import report


def failing_plan() -> model.Plan:
    return model.Plan(
        unit="unit:app-probe-status@1",
        tier="e2e",
        transport="daemon",
        target="TARGET",
        layer=3,
        requires=frozenset({"mac", "device", "daemon"}),
        steps=(
            model.Step(
                index=1,
                verb="device.command",
                args={"action": "tap", "identifier": "Playback-Play"},
                expect=model.Expectation(path="matchedElement.label", contains="Play"),
                evidence="command.json",
            ),
            model.Step(
                index=2,
                verb="device.snapshot",
                args={},
                expect=None,
                evidence="hierarchy.json",
            ),
        ),
        terminal=model.Terminal(kind="artifact", path="hierarchy.json", equals=None, schema=None),
        guardrails=(),
        evidence=(),
        digest="sha256:abc",
    )


def failing_report(verdict: str = "failed") -> model.Report:
    return model.Report(
        unit="unit:app-probe-status@1",
        digest="sha256:abc",
        product_digest="sha256:def",
        verdict=verdict,
        tier="e2e",
        duration_ms=4200,
        steps=(
            model.StepOutcome(
                index=1,
                verb="device.command",
                ok=False,
                duration_ms=2100,
                detail="matchedElement.label does not contain 'Play'",
                guardrails=(),
            ),
            model.StepOutcome(
                index=2,
                verb="device.snapshot",
                ok=True,
                duration_ms=1200,
                detail="37 elements",
                guardrails=(),
            ),
        ),
        terminal=model.TerminalOutcome(kind="artifact", ok=False, detail="never written"),
        evidence_dir="/tmp/evidence/unit-app-probe-status",
        exit_code=1,
    )


class FailureSummaryTests(unittest.TestCase):
    def test_a_failed_run_reports_step_expectation_and_rerun(self) -> None:
        text = report.failure_summary(failing_report(), failing_plan())
        self.assertIn("failure  unit:app-probe-status@1", text)
        self.assertIn("step      01 device.command", text)
        self.assertIn("expected  matchedElement.label contains 'Play'", text)
        self.assertIn("actual    matchedElement.label does not contain 'Play'", text)
        self.assertIn("evidence  /tmp/evidence/unit-app-probe-status", text)
        self.assertIn("rerun     python3 Scripts/console/cli.py run unit:app-probe-status@1 --tier e2e", text)
        self.assertIn("inspect   python3 Scripts/console/cli.py inspect unit:app-probe-status@1", text)

    def test_a_known_verdict_still_gets_the_summary(self) -> None:
        text = report.failure_summary(failing_report("known"), failing_plan())
        self.assertIn("verdict=known", text)

    def test_a_passing_run_has_no_summary(self) -> None:
        self.assertIsNone(report.failure_summary(failing_report("passed"), failing_plan()))

    def test_the_plan_payload_carries_the_expectation(self) -> None:
        payload = report.plan_payload(failing_plan())
        self.assertEqual(
            payload["steps"][0]["expect"],
            {"path": "matchedElement.label", "equals": None, "contains": "Play"},
        )


class ExplainTests(unittest.TestCase):
    def test_the_explanation_names_the_expectation_and_the_rerun(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            run = root / "TestEvidence/console/unit-app-probe-status@1/20260101T000000Z"
            steps = run / "steps"
            steps.mkdir(parents=True)
            (steps / "01-device-command.json").write_text(
                json.dumps({"hierarchy": "identifier: 'Library-Grid'"}), encoding="utf-8"
            )
            report_payload = {
                "unit": "unit:app-probe-status@1",
                "verdict": "failed",
                "steps": [
                    {
                        "index": 1,
                        "verb": "device.command",
                        "ok": False,
                        "durationMs": 2100,
                        "detail": "matchedElement.label does not contain 'Play'",
                    },
                    {
                        "index": 2,
                        "verb": "device.snapshot",
                        "ok": True,
                        "durationMs": 1200,
                        "detail": "37 elements",
                    },
                ],
                "terminal": {"kind": "artifact", "ok": True, "detail": "present"},
                "evidenceDir": str(run),
            }
            (run / "report.json").write_text(json.dumps(report_payload), encoding="utf-8")
            plan_payload = {
                "unit": "unit:app-probe-status@1",
                "steps": [
                    {
                        "index": 1,
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": "Playback-Play"},
                        "expect": {
                            "path": "matchedElement.label",
                            "equals": None,
                            "contains": "Play",
                        },
                    },
                    {
                        "index": 2,
                        "verb": "device.snapshot",
                        "args": {},
                        "expect": None,
                    },
                ],
            }
            (run / "plan.json").write_text(json.dumps(plan_payload), encoding="utf-8")
            payload = explain.report(root, "unit:app-probe-status@1")
        self.assertIn("contains 'Play'", payload["expected"])
        self.assertIn("run unit:app-probe-status@1", payload["rerun"])
        self.assertEqual(payload["slowest"][0]["index"], 1)
        rendered = explain.render(payload)
        self.assertIn("expected  matchedElement.label contains 'Play'", rendered)
        self.assertIn("slowest  01 device.command", rendered)


if __name__ == "__main__":
    unittest.main()
