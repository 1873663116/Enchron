from __future__ import annotations

import datetime
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))

from harness.budgets import Budget, BudgetProvider
from harness.controller import CompletedInvocation, ControllerClient
from harness.evidence import EvidenceScope
from harness.failures import InstrumentFault, ProductFailure
from harness.recovery import FaultRecord, Halt, RecoveryPolicy, Retry
from harness.waits import wait_for

SHIPPED_PROVISIONAL_PATH = (
    Path(__file__).parents[2]
    / "Scripts"
    / "verification"
    / "harness"
    / "provisional_budgets.json"
)


def write_timings(
    directory: Path, lane: str, verb: str, samples: list[dict[str, object]]
) -> None:
    document = {
        "verbs": {verb: {"samples": samples}},
        "updatedAt": "2026-08-01T00:00:00+00:00",
    }
    (directory / f"controller_timings.{lane}.json").write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def measured(seconds: float, censored: bool = False) -> dict[str, object]:
    return {"seconds": seconds, "censored": censored, "at": "2026-08-01T00:00:00+00:00"}


def provider(
    directory: Path,
    provisional: dict[str, object] | None = None,
    today: datetime.date = datetime.date(2026, 9, 1),
) -> BudgetProvider:
    provisional_path = directory / "provisional_budgets.json"
    if provisional is not None:
        provisional_path.write_text(
            json.dumps(provisional, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    return BudgetProvider(
        timings_directory=directory,
        provisional_path=provisional_path,
        today=lambda: today,
        now=lambda: datetime.datetime(2026, 9, 1, tzinfo=datetime.timezone.utc),
    )


class BudgetDerivationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())

    def test_p95_times_multiplier(self) -> None:
        samples = [measured(float(value)) for value in range(1, 21)]
        write_timings(self.directory, "device", "press", samples)
        budget = provider(self.directory).budget("device", "press")
        self.assertAlmostEqual(budget.seconds, 19.0 * 1.5)
        self.assertEqual(budget.provenance, "p95 19.00s × 1.5, lane=device, n=20, censored=0")

    def test_censored_samples_merge_into_p95(self) -> None:
        samples = [measured(2.0) for _ in range(8)] + [
            measured(30.0, censored=True),
            measured(30.0, censored=True),
        ]
        write_timings(self.directory, "device", "press", samples)
        budget = provider(self.directory).budget("device", "press")
        self.assertAlmostEqual(budget.seconds, 30.0 * 1.5)
        self.assertIn("censored=2", budget.provenance)
        self.assertIn("n=10", budget.provenance)

    def test_floor_clamp(self) -> None:
        samples = [measured(0.5) for _ in range(6)]
        write_timings(self.directory, "simulator", "press", samples)
        budget = provider(self.directory).budget("simulator", "press")
        self.assertEqual(budget.seconds, 5.0)

    def test_ceiling_clamp(self) -> None:
        samples = [measured(500.0) for _ in range(6)]
        write_timings(self.directory, "device", "probe-copy", samples)
        budget = provider(self.directory).budget("device", "probe-copy")
        self.assertEqual(budget.seconds, 600.0)

    def test_lanes_are_isolated(self) -> None:
        write_timings(self.directory, "device", "press", [measured(10.0)] * 6)
        with self.assertRaises(InstrumentFault) as caught:
            provider(self.directory).budget("simulator", "press")
        self.assertEqual(caught.exception.kind, "provisional-budget-expired")

    def test_provisional_used_below_five_samples(self) -> None:
        write_timings(self.directory, "device", "halt", [measured(3.0)] * 4)
        budgets = provider(
            self.directory,
            provisional={"halt": {"seconds": 60, "expires": "2026-10-01"}},
        )
        budget = budgets.budget("device", "halt")
        self.assertEqual(budget.seconds, 60.0)
        self.assertIn("provisional 60s", budget.provenance)
        self.assertIn("expires 2026-10-01", budget.provenance)

    def test_provisional_expired_raises(self) -> None:
        budgets = provider(
            self.directory,
            provisional={"halt": {"seconds": 60, "expires": "2026-10-01"}},
            today=datetime.date(2026, 10, 1),
        )
        with self.assertRaises(InstrumentFault) as caught:
            budgets.budget("device", "halt")
        self.assertEqual(caught.exception.kind, "provisional-budget-expired")
        self.assertEqual(caught.exception.evidence["expires"], "2026-10-01")

    def test_missing_provisional_entry_raises(self) -> None:
        budgets = provider(self.directory, provisional={})
        with self.assertRaises(InstrumentFault) as caught:
            budgets.budget("device", "unknown-verb")
        self.assertEqual(caught.exception.kind, "provisional-budget-expired")

    def test_record_sample_keeps_last_forty(self) -> None:
        budgets = provider(self.directory)
        for index in range(41):
            budgets.record_sample("device", "press", float(index), censored=False)
        samples = budgets.samples("device", "press")
        self.assertEqual(len(samples), 40)
        self.assertEqual(samples[0]["seconds"], 1.0)
        self.assertEqual(samples[-1]["seconds"], 40.0)

    def test_unknown_lane_rejected(self) -> None:
        with self.assertRaises(AssertionError):
            provider(self.directory).budget("watch", "press")

    def test_shipped_provisional_table(self) -> None:
        table = json.loads(SHIPPED_PROVISIONAL_PATH.read_text(encoding="utf-8"))
        self.assertEqual(table["halt"], {"seconds": 60, "expires": "2026-10-01"})
        self.assertEqual(
            table["ensure-session"], {"seconds": 300, "expires": "2026-10-01"}
        )
        self.assertEqual(
            table["probe-copy"], {"seconds": 120, "expires": "2026-10-01"}
        )


class FakeRun:
    def __init__(
        self,
        returncode: int = 0,
        stdout: str = "",
        stderr: str = "",
        times_out: bool = False,
    ) -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr
        self.times_out = times_out
        self.commands: list[list[str]] = []
        self.timeouts: list[float] = []

    def __call__(self, command, timeout_seconds) -> CompletedInvocation:
        self.commands.append(list(command))
        self.timeouts.append(timeout_seconds)
        if self.times_out:
            raise TimeoutError(f"exceeded {timeout_seconds}s")
        return CompletedInvocation(self.returncode, self.stdout, self.stderr)


class ControllerReconciliationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        write_timings(self.directory, "device", "press", [measured(4.0)] * 10)
        self.budgets = provider(self.directory)

    def client(self, run: FakeRun) -> ControllerClient:
        return ControllerClient(
            "device",
            command_prefix=["runner"],
            budgets=self.budgets,
            run=run,
            clock=iter(range(1000)).__next__,
        )

    def test_success_returns_response_and_records_sample(self) -> None:
        run = FakeRun(returncode=0, stdout=json.dumps({"success": True, "value": 7}))
        response = self.client(run).invoke("press", ["--identifier", "Play"])
        self.assertIsNone(response.failure)
        self.assertEqual(response.document["value"], 7)
        self.assertEqual(run.commands, [["runner", "press", "--identifier", "Play"]])
        self.assertEqual(run.timeouts, [6.0])
        samples = self.budgets.samples("device", "press")
        self.assertEqual(len(samples), 11)
        self.assertFalse(samples[-1]["censored"])

    def test_subprocess_timeout_records_censored_and_raises_transport_timeout(
        self,
    ) -> None:
        run = FakeRun(times_out=True)
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "transport-timeout")
        self.assertIn("p95 4.00s", caught.exception.budget.provenance)
        newest = self.budgets.samples("device", "press")[-1]
        self.assertTrue(newest["censored"])
        self.assertEqual(newest["seconds"], 6.0)

    def test_nonzero_exit_without_json_is_runner_crashed(self) -> None:
        run = FakeRun(returncode=1, stdout="Traceback ...", stderr="boom")
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "runner-crashed")

    def test_zero_exit_without_json_is_response_undecodable(self) -> None:
        run = FakeRun(returncode=0, stdout="not json")
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "response-undecodable")

    def test_exit_zero_with_success_false_is_contract_mismatch(self) -> None:
        run = FakeRun(returncode=0, stdout=json.dumps({"success": False}))
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "contract-mismatch")

    def test_exit_two_with_success_true_is_contract_mismatch(self) -> None:
        run = FakeRun(returncode=2, stdout=json.dumps({"success": True}))
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "contract-mismatch")

    def test_exit_two_without_failure_block_is_contract_mismatch(self) -> None:
        run = FakeRun(returncode=2, stdout=json.dumps({"success": False}))
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "contract-mismatch")

    def test_exit_one_with_json_is_runner_crashed(self) -> None:
        run = FakeRun(returncode=1, stdout=json.dumps({"success": False}))
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "runner-crashed")

    def test_instrument_failure_is_rethrown_with_evidence(self) -> None:
        document = {
            "success": False,
            "failure": {
                "class": "instrument",
                "kind": "session-lost",
                "evidence": {"diagnosis": "runner session vanished"},
            },
        }
        run = FakeRun(returncode=2, stdout=json.dumps(document))
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "session-lost")
        self.assertEqual(
            caught.exception.evidence["diagnosis"], "runner session vanished"
        )

    def test_product_failure_is_returned_not_raised(self) -> None:
        document = {
            "success": False,
            "failure": {
                "class": "product",
                "kind": "assertion-mismatch",
                "evidence": {"diagnosis": "label differed", "observations": []},
            },
        }
        run = FakeRun(returncode=2, stdout=json.dumps(document))
        response = self.client(run).invoke("press")
        self.assertEqual(
            response.failure,
            ProductFailure(
                kind="assertion-mismatch",
                evidence={"diagnosis": "label differed", "observations": []},
            ),
        )

    def test_unknown_failure_class_is_contract_mismatch(self) -> None:
        document = {
            "success": False,
            "failure": {"class": "cosmic", "kind": "assertion-mismatch"},
        }
        run = FakeRun(returncode=2, stdout=json.dumps(document))
        with self.assertRaises(InstrumentFault) as caught:
            self.client(run).invoke("press")
        self.assertEqual(caught.exception.kind, "contract-mismatch")

    def test_invoke_accepts_no_caller_timeout(self) -> None:
        with self.assertRaises(TypeError):
            self.client(FakeRun()).invoke("press", timeout=5)


class FakeClock:
    def __init__(self) -> None:
        self.time = 0.0

    def __call__(self) -> float:
        return self.time

    def sleep(self, seconds: float) -> None:
        self.time += seconds


class WaitForTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.budget = Budget(seconds=10.0, provenance="p95 6.67s × 1.5, lane=device, n=9, censored=0")
        self.recorded: list[tuple[str, float, bool]] = []

    def record(self, label: str, seconds: float, censored: bool) -> None:
        self.recorded.append((label, seconds, censored))

    def test_returns_probe_evidence_when_it_appears(self) -> None:
        answers = iter([None, None, {"state": "ready"}])
        result = wait_for(
            "player-ready",
            lambda: next(answers),
            self.budget,
            observe=lambda: self.fail("observe must not run when the probe succeeds"),
            record=self.record,
            clock=self.clock,
            sleep=self.clock.sleep,
        )
        self.assertEqual(result, {"state": "ready"})
        self.assertEqual(self.recorded, [("player-ready", 2.0, False)])

    def test_expiry_observes_the_scene_and_raises(self) -> None:
        observed: list[int] = []

        def observe() -> list[object]:
            observed.append(1)
            return [{"hierarchy": "frozen spinner"}]

        with self.assertRaises(InstrumentFault) as caught:
            wait_for(
                "player-ready",
                lambda: None,
                self.budget,
                observe=observe,
                record=self.record,
                clock=self.clock,
                sleep=self.clock.sleep,
            )
        fault = caught.exception
        self.assertEqual(fault.kind, "wait-expired")
        self.assertEqual(fault.evidence["label"], "player-ready")
        self.assertEqual(
            fault.evidence["observations"], [{"hierarchy": "frozen spinner"}]
        )
        self.assertEqual(fault.evidence["budget"], self.budget.provenance)
        self.assertEqual(observed, [1])
        self.assertEqual(self.recorded, [("player-ready", 10.0, True)])

    def test_expiry_never_returns_a_stale_snapshot(self) -> None:
        earlier = wait_for(
            "player-ready",
            lambda: {"state": "ready", "at": self.clock()},
            self.budget,
            observe=lambda: [],
            clock=self.clock,
            sleep=self.clock.sleep,
        )
        self.assertEqual(earlier["state"], "ready")
        outcome: list[object] = []
        try:
            outcome.append(
                wait_for(
                    "player-ready",
                    lambda: None,
                    self.budget,
                    observe=lambda: [],
                    clock=self.clock,
                    sleep=self.clock.sleep,
                )
            )
        except InstrumentFault as fault:
            outcome.append(fault.kind)
        self.assertEqual(outcome, ["wait-expired"])


class EvidenceScopeTests(unittest.TestCase):
    def setUp(self) -> None:
        root = Path(tempfile.mkdtemp())
        self.probe_log = root / "probe-log"
        self.responses = root / "responses"
        self.archive = root / "archive"
        self.probe_log.mkdir()
        self.responses.mkdir()

    def scope(self, label: str = "segment-3") -> EvidenceScope:
        return EvidenceScope(
            label,
            sources=[self.probe_log, self.responses],
            archive_root=self.archive,
            now=lambda: datetime.datetime(2026, 9, 1, tzinfo=datetime.timezone.utc),
        )

    def test_enter_archives_and_clears_sources(self) -> None:
        (self.probe_log / "old.txt").write_text("stale", encoding="utf-8")
        with self.scope():
            self.assertEqual(list(self.probe_log.iterdir()), [])
            archived = self.archive / "segment-3" / "prior" / "probe-log" / "old.txt"
            self.assertEqual(archived.read_text(encoding="utf-8"), "stale")

    def test_destruction_inside_scope_taints_and_raises(self) -> None:
        scope = self.scope()
        with self.assertRaises(InstrumentFault) as caught:
            with scope:
                scope.register_destruction("relaunched the app")
        self.assertEqual(caught.exception.kind, "evidence-destroyed")
        self.assertEqual(caught.exception.evidence["scope"], "segment-3")
        self.assertTrue(scope.tainted)
        manifest = json.loads(
            (self.archive / "segment-3" / "manifest.json").read_text(encoding="utf-8")
        )
        self.assertFalse(manifest["valid"])
        self.assertEqual(manifest["destructions"], ["relaunched the app"])

    def test_clean_exit_seals_valid_evidence(self) -> None:
        scope = self.scope()
        with scope:
            (self.responses / "001-press.json").write_text("{}", encoding="utf-8")
        self.assertTrue(scope.sealed)
        self.assertFalse(scope.tainted)
        sealed = self.archive / "segment-3" / "sealed" / "responses" / "001-press.json"
        self.assertTrue(sealed.is_file())
        manifest = json.loads(
            (self.archive / "segment-3" / "manifest.json").read_text(encoding="utf-8")
        )
        self.assertTrue(manifest["valid"])

    def test_destruction_outside_scope_is_rejected(self) -> None:
        with self.assertRaises(AssertionError):
            self.scope().register_destruction("halted the session")


class RecoveryPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = RecoveryPolicy()
        for _ in range(10):
            self.policy.record_action()

    def fault(self, kind: str = "wait-expired") -> InstrumentFault:
        return InstrumentFault(kind, {})

    def test_first_occurrence_retries(self) -> None:
        decision = self.policy.on_fault(
            self.fault(), [FaultRecord("open-media", "wait-expired")]
        )
        self.assertIsInstance(decision, Retry)

    def test_second_consecutive_strike_halts_with_fault_rate(self) -> None:
        history = [
            FaultRecord("open-media", "wait-expired"),
            FaultRecord("open-media", "wait-expired"),
        ]
        self.policy.on_fault(self.fault(), history[:1])
        decision = self.policy.on_fault(self.fault(), history)
        self.assertIsInstance(decision, Halt)
        self.assertEqual(decision.report["instrumentFaults"], 2)
        self.assertEqual(decision.report["actions"], 10)
        self.assertEqual(decision.report["faultRate"], 0.2)

    def test_same_kind_at_different_locations_retries(self) -> None:
        history = [
            FaultRecord("open-media", "wait-expired"),
            FaultRecord("close-media", "wait-expired"),
        ]
        decision = self.policy.on_fault(self.fault(), history)
        self.assertIsInstance(decision, Retry)

    def test_non_consecutive_repeat_retries(self) -> None:
        history = [
            FaultRecord("open-media", "wait-expired"),
            FaultRecord("open-media", "session-lost"),
            FaultRecord("open-media", "wait-expired"),
        ]
        decision = self.policy.on_fault(self.fault(), history)
        self.assertIsInstance(decision, Retry)

    def test_censored_fault_is_treated_as_transient(self) -> None:
        history = [
            FaultRecord("open-media", "transport-timeout", censored=True),
        ]
        decision = self.policy.on_fault(self.fault("transport-timeout"), history)
        self.assertIsInstance(decision, Retry)
        self.assertIn("transient", decision.reason)

    def test_history_tail_must_match_fault(self) -> None:
        with self.assertRaises(AssertionError):
            self.policy.on_fault(
                self.fault("session-lost"),
                [FaultRecord("open-media", "wait-expired")],
            )


if __name__ == "__main__":
    unittest.main()
