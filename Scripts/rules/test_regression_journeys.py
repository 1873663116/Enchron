from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
from io import StringIO
import json
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import regression_journeys as journeys


class RegistryTests(unittest.TestCase):
    def test_checked_transcription_matches_the_authoritative_draft(self) -> None:
        self.assertEqual(
            journeys.DRAFT_PATH.read_text(encoding="utf-8"),
            journeys._DRAFT_TEXT,
        )

    def test_registry_passes_structure_and_regenerated_documents(self) -> None:
        self.assertEqual([], journeys.registry_failures())
        with TemporaryDirectory() as temporary:
            reference_directory = Path(temporary) / "journeys"
            journeys.write_reference(reference_directory)
            self.assertEqual(
                [], journeys.reference_failures(reference_directory)
            )

    def test_every_step_primitive_reference_exists(self) -> None:
        known = {primitive.id for primitive in journeys.PRIMITIVES}
        for journey in journeys.JOURNEYS:
            for step in journey.steps:
                self.assertLessEqual(set(step.primitive_refs), known)

    def test_on_demand_set_is_pinned(self) -> None:
        self.assertEqual(
            {"J00", "J05", "J06"},
            {
                journey.id
                for journey in journeys.JOURNEYS
                if journey.trigger == journeys.ON_DEMAND
            },
        )


class RunLedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.previous_root = os.environ.get("ENCHRON_ARTIFACT_ROOT")
        os.environ["ENCHRON_ARTIFACT_ROOT"] = self.temporary.name
        self.addCleanup(self._restore_root)
        self.path = journeys.ledger_path()
        self.clock = lambda: datetime(2026, 8, 21, 12, 0, tzinfo=timezone.utc)

    def _restore_root(self) -> None:
        if self.previous_root is None:
            os.environ.pop("ENCHRON_ARTIFACT_ROOT", None)
        else:
            os.environ["ENCHRON_ARTIFACT_ROOT"] = self.previous_root

    def _document(self) -> dict[str, object]:
        return json.loads(self.path.read_text(encoding="utf-8"))

    def _time(self, value: str) -> datetime:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))

    def _assert_valid_atomic_document(self) -> None:
        document = self._document()
        journeys.ledger_from_document(document)
        self.assertEqual([], list(self.path.parent.glob(".current.json.*.tmp")))

    def test_default_open_uses_all_standing_journeys(self) -> None:
        ledger = journeys.open_run(path=self.path, now=self.clock)
        self.assertEqual(
            [item.id for item in ledger.journeys],
            [
                journey.id
                for journey in journeys.JOURNEYS
                if journey.trigger == journeys.STANDING
            ],
        )
        self._assert_valid_atomic_document()

    def test_open_refuses_an_existing_in_progress_run_with_exit_two(self) -> None:
        stdout = StringIO()
        stderr = StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            self.assertEqual(
                0,
                journeys.main(
                    ["run", "open", "--journeys", "J01", "--session", "test"]
                ),
            )
            before = self.path.read_bytes()
            self.assertEqual(2, journeys.main(["run", "open"]))
        self.assertEqual(before, self.path.read_bytes())
        self.assertIn("in-progress", stderr.getvalue())

    def test_verdict_reason_rules_and_statuses_land_in_file(self) -> None:
        journeys.open_run(("J01", "J02", "J03", "J04"), path=self.path, now=self.clock)
        opened = self._document()["updatedAt"]
        for identifier, verdict in zip(
            ("J01", "J02", "J03", "J04"),
            ("passed", "failed", "voided", "blocked"),
        ):
            reason = None if verdict == "passed" else f"reason for {verdict}"
            journeys.record_verdict(
                identifier, verdict, reason, path=self.path, now=self.clock
            )
            self._assert_valid_atomic_document()
        document = self._document()
        self.assertEqual(
            ["passed", "failed", "voided", "blocked"],
            [item["status"] for item in document["journeys"]],
        )
        self.assertGreater(
            self._time(document["updatedAt"]), self._time(opened)
        )

    def test_failed_voided_and_blocked_require_reason(self) -> None:
        for verdict in ("failed", "voided", "blocked"):
            with self.subTest(verdict=verdict):
                if self.path.exists():
                    self.path.unlink()
                journeys.open_run(("J01",), path=self.path, now=self.clock)
                before = self.path.read_bytes()
                with self.assertRaisesRegex(journeys.LedgerError, "requires --reason"):
                    journeys.record_verdict(
                        "J01", verdict, path=self.path, now=self.clock
                    )
                self.assertEqual(before, self.path.read_bytes())

    def test_verdict_refuses_no_open_ledger_and_unknown_id(self) -> None:
        with self.assertRaisesRegex(journeys.LedgerError, "no regression run"):
            journeys.record_verdict(
                "J01", "passed", path=self.path, now=self.clock
            )
        journeys.open_run(("J01",), path=self.path, now=self.clock)
        before = self.path.read_bytes()
        with self.assertRaisesRegex(journeys.LedgerError, "not in the open run"):
            journeys.record_verdict(
                "J02", "passed", path=self.path, now=self.clock
            )
        self.assertEqual(before, self.path.read_bytes())

    def test_close_refuses_pending_then_succeeds_after_all_terminal(self) -> None:
        journeys.open_run(("J01", "J02"), path=self.path, now=self.clock)
        journeys.record_verdict("J01", "passed", path=self.path, now=self.clock)
        before = self.path.read_bytes()
        with self.assertRaisesRegex(journeys.LedgerError, "pending journeys: J02"):
            journeys.close_run(path=self.path, now=self.clock)
        self.assertEqual(before, self.path.read_bytes())
        journeys.record_verdict(
            "J02", "voided", "fixture unavailable", path=self.path, now=self.clock
        )
        ledger = journeys.close_run(path=self.path, now=self.clock)
        self.assertEqual("complete", ledger.status)
        self._assert_valid_atomic_document()

    def test_abort_requires_reason_and_records_abort(self) -> None:
        journeys.open_run(("J01",), path=self.path, now=self.clock)
        before = self.path.read_bytes()
        with self.assertRaisesRegex(journeys.LedgerError, "abort requires"):
            journeys.abort_run("  ", path=self.path, now=self.clock)
        self.assertEqual(before, self.path.read_bytes())
        ledger = journeys.abort_run(
            "device channel unavailable", path=self.path, now=self.clock
        )
        self.assertEqual("aborted", ledger.status)
        self.assertEqual("device channel unavailable", ledger.abort_reason)
        self._assert_valid_atomic_document()

    def test_updated_at_advances_for_each_mutation(self) -> None:
        opened = journeys.open_run(("J01",), path=self.path, now=self.clock)
        verdict = journeys.record_verdict(
            "J01", "passed", path=self.path, now=self.clock
        )
        corrected = journeys.record_verdict(
            "J01", "failed", "corrected verdict", path=self.path, now=self.clock
        )
        closed = journeys.close_run(path=self.path, now=self.clock)
        self.assertLess(self._time(opened.updated_at), self._time(verdict.updated_at))
        self.assertLess(self._time(verdict.updated_at), self._time(corrected.updated_at))
        self.assertLess(self._time(corrected.updated_at), self._time(closed.updated_at))

    def test_wire_contract_has_exact_fields_after_each_mutation(self) -> None:
        expected_root = {
            "schemaVersion",
            "openedAt",
            "updatedAt",
            "sessionId",
            "status",
            "abortReason",
            "journeys",
        }
        expected_item = {"id", "status", "reason", "at"}
        journeys.open_run(("J01",), "session", path=self.path, now=self.clock)
        for mutation in (
            lambda: journeys.record_verdict(
                "J01", "passed", path=self.path, now=self.clock
            ),
            lambda: journeys.close_run(path=self.path, now=self.clock),
        ):
            document = self._document()
            self.assertEqual(expected_root, set(document))
            self.assertTrue(all(set(item) == expected_item for item in document["journeys"]))
            mutation()
            self._assert_valid_atomic_document()

    def test_status_json_is_the_current_ledger_document(self) -> None:
        journeys.open_run(("J01",), "session", path=self.path, now=self.clock)
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(
                0, journeys.show_status(as_json=True, path=self.path)
            )
        self.assertEqual(self._document(), json.loads(output.getvalue()))


if __name__ == "__main__":
    unittest.main()
