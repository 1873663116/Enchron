#!/usr/bin/env python3
from __future__ import annotations

import datetime
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

from harness.budgets import BudgetProvider

import reachability_matrix as matrix

SHIPPED_PROVISIONAL_PATH = (
    Path(__file__).resolve().parents[2]
    / "verification"
    / "harness"
    / "provisional_budgets.json"
)

RAISED_WAIT_VERBS = (
    "identifier-appearance",
    "any-identifier-appearance",
    "identifier-absence",
    "identifier-value",
    "probe-needle",
    "presentation-settle",
)

STEADY_WAIT_VERBS = (
    "presentation",
    "immersive-settlement",
    "wedge",
    "clean-open",
    "panorama-settle",
    "result-bundle",
)

FROZEN_ENVIRONMENT = {"ENCHRON_EXECUTION_INPUT": "/tmp/execution-input.json"}

FIXED_NOW = datetime.datetime(2026, 9, 1, tzinfo=datetime.timezone.utc)


def provider(
    directory: Path,
    provisional: dict[str, object] | None = None,
    output_directory: Path | None = None,
    today: datetime.date = datetime.date(2026, 9, 1),
) -> BudgetProvider:
    provisional_path = directory / "provisional_budgets.json"
    if provisional is not None:
        provisional_path.write_text(
            json.dumps(provisional, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    keyword_arguments: dict[str, object] = {
        "timings_directory": directory,
        "provisional_path": provisional_path,
        "today": lambda: today,
        "now": lambda: FIXED_NOW,
    }
    if output_directory is not None:
        keyword_arguments["output_directory"] = output_directory
    return BudgetProvider(**keyword_arguments)


def timings_document(samples: list[dict[str, object]]) -> dict[str, object]:
    return {
        "verbs": {"identifier-appearance": {"samples": samples}},
        "updatedAt": "2026-08-01T00:00:00+00:00",
    }


def sample(seconds: float, at: str, censored: bool = False) -> dict[str, object]:
    return {"seconds": seconds, "censored": censored, "at": at}


def sample_line(
    verb: str, lane: str, seconds: float, at: str, censored: bool = False
) -> str:
    return json.dumps(
        {
            "verb": verb,
            "lane": lane,
            "seconds": seconds,
            "censored": censored,
            "at": at,
        },
        sort_keys=True,
    )


class ShippedCeilingTests(unittest.TestCase):
    def test_wait_verbs_carry_the_sixty_second_ceiling(self) -> None:
        table = json.loads(SHIPPED_PROVISIONAL_PATH.read_text(encoding="utf-8"))
        for verb in RAISED_WAIT_VERBS + STEADY_WAIT_VERBS:
            with self.subTest(verb=verb):
                self.assertEqual(table[verb]["seconds"], 60)
                self.assertEqual(table[verb]["expires"], "2026-10-01")

    def test_synthetic_input_provisional_values_are_untouched(self) -> None:
        table = json.loads(SHIPPED_PROVISIONAL_PATH.read_text(encoding="utf-8"))
        self.assertEqual(
            table["tap"],
            {"seconds": 60, "expires": "2026-10-01", "floorSeconds": 75},
        )
        self.assertEqual(table["press"]["seconds"], 20)
        self.assertEqual(table["press"]["floorSeconds"], 75)
        self.assertEqual(table["activate"]["seconds"], 20)
        self.assertEqual(table["typeText"]["seconds"], 20)

    def test_wait_provenance_names_the_ceiling(self) -> None:
        directory = Path(tempfile.mkdtemp())
        budgets = provider(
            directory,
            provisional={
                "identifier-appearance": {"seconds": 60, "expires": "2026-10-01"}
            },
        )
        budget = budgets.budget("device", "identifier-appearance")
        self.assertEqual(budget.seconds, 60.0)
        self.assertIn("provisional ceiling 60s", budget.provenance)
        self.assertIn("expires 2026-10-01", budget.provenance)
        self.assertIn("n=0", budget.provenance)

    def test_plain_provenance_survives_for_non_wait_verbs(self) -> None:
        directory = Path(tempfile.mkdtemp())
        budgets = provider(
            directory,
            provisional={"halt": {"seconds": 60, "expires": "2026-10-01"}},
        )
        budget = budgets.budget("device", "halt")
        self.assertIn("provisional 60s", budget.provenance)
        self.assertNotIn("ceiling", budget.provenance)


class FrozenSampleTests(unittest.TestCase):
    def test_frozen_sample_lands_in_the_output_directory(self) -> None:
        timings = Path(tempfile.mkdtemp())
        output = Path(tempfile.mkdtemp())
        budgets = provider(timings, output_directory=output)
        with mock.patch.dict(os.environ, FROZEN_ENVIRONMENT):
            budgets.record_sample(
                "device", "identifier-appearance", 12.5, censored=False
            )
            budgets.record_sample(
                "device", "identifier-appearance", 60.0, censored=True
            )
        lines = (
            (output / "timing-samples.jsonl").read_text(encoding="utf-8").splitlines()
        )
        self.assertEqual(len(lines), 2)
        self.assertEqual(
            json.loads(lines[0]),
            {
                "verb": "identifier-appearance",
                "lane": "device",
                "seconds": 12.5,
                "censored": False,
                "at": "2026-09-01T00:00:00+00:00",
            },
        )
        second = json.loads(lines[1])
        self.assertEqual(second["seconds"], 60.0)
        self.assertTrue(second["censored"])
        self.assertFalse((timings / "controller_timings.device.json").exists())

    def test_live_sample_still_goes_to_controller_timings(self) -> None:
        timings = Path(tempfile.mkdtemp())
        output = Path(tempfile.mkdtemp())
        budgets = provider(timings, output_directory=output)
        with mock.patch.dict(os.environ):
            os.environ.pop("ENCHRON_EXECUTION_INPUT", None)
            budgets.record_sample("device", "press", 4.25, censored=False)
        stored = json.loads(
            (timings / "controller_timings.device.json").read_text(encoding="utf-8")
        )
        self.assertEqual(len(stored["verbs"]["press"]["samples"]), 1)
        self.assertFalse((output / "timing-samples.jsonl").exists())

    def test_frozen_sample_without_an_output_directory_is_dropped(self) -> None:
        timings = Path(tempfile.mkdtemp())
        budgets = provider(timings)
        with mock.patch.dict(os.environ, FROZEN_ENVIRONMENT):
            budgets.record_sample("device", "press", 4.25, censored=False)
        self.assertFalse((timings / "controller_timings.device.json").exists())


class TimingSamplesSummaryTests(unittest.TestCase):
    def test_summary_counts_sample_lines(self) -> None:
        output = Path(tempfile.mkdtemp())
        (output / "timing-samples.jsonl").write_text(
            sample_line("identifier-appearance", "device", 3.0, "2026-09-01T00:00:01+00:00")
            + "\n"
            + sample_line("tap", "device", 4.0, "2026-09-01T00:00:02+00:00")
            + "\n",
            encoding="utf-8",
        )
        self.assertEqual(
            matrix.timing_samples_summary(output),
            {"path": "timing-samples.jsonl", "count": 2},
        )

    def test_summary_reports_zero_without_a_samples_file(self) -> None:
        output = Path(tempfile.mkdtemp())
        self.assertEqual(
            matrix.timing_samples_summary(output),
            {"path": "timing-samples.jsonl", "count": 0},
        )


class FoldTimingSamplesTests(unittest.TestCase):
    def setUp(self) -> None:
        import importlib

        self.fold = importlib.import_module("fold_timing_samples")

    def test_fold_merges_jsonl_per_lane_and_dedupes(self) -> None:
        timings = Path(tempfile.mkdtemp())
        (timings / "controller_timings.device.json").write_text(
            json.dumps(
                timings_document([
                    sample(2.0, "2026-09-01T00:00:01+00:00"),
                    sample(3.0, "2026-09-01T00:00:02+00:00"),
                ]),
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        results = Path(tempfile.mkdtemp())
        (results / "timing-samples.jsonl").write_text(
            "\n".join([
                sample_line(
                    "identifier-appearance",
                    "device",
                    4.0,
                    "2026-09-01T00:00:03+00:00",
                ),
                sample_line(
                    "identifier-appearance",
                    "device",
                    2.0,
                    "2026-09-01T00:00:01+00:00",
                ),
                sample_line("tap", "simulator", 5.0, "2026-09-01T00:00:04+00:00"),
            ])
            + "\n",
            encoding="utf-8",
        )
        summary = self.fold.fold_samples([results], timings, lambda: FIXED_NOW)
        self.assertEqual(summary["device"]["added"], 1)
        self.assertEqual(summary["simulator"]["added"], 1)
        device = json.loads(
            (timings / "controller_timings.device.json").read_text(encoding="utf-8")
        )
        kept = device["verbs"]["identifier-appearance"]["samples"]
        self.assertEqual([entry["at"] for entry in kept], [
            "2026-09-01T00:00:01+00:00",
            "2026-09-01T00:00:02+00:00",
            "2026-09-01T00:00:03+00:00",
        ])
        simulator = json.loads(
            (timings / "controller_timings.simulator.json").read_text(encoding="utf-8")
        )
        self.assertEqual(len(simulator["verbs"]["tap"]["samples"]), 1)

    def test_fold_respects_the_sample_limit(self) -> None:
        timings = Path(tempfile.mkdtemp())
        existing = [
            sample(float(index), f"2026-09-01T00:{index:02d}:00+00:00")
            for index in range(40)
        ]
        (timings / "controller_timings.device.json").write_text(
            json.dumps(timings_document(existing), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        results = Path(tempfile.mkdtemp())
        (results / "timing-samples.jsonl").write_text(
            "\n".join(
                sample_line(
                    "identifier-appearance",
                    "device",
                    9.0,
                    f"2026-09-01T01:{index:02d}:00+00:00",
                )
                for index in range(5)
            )
            + "\n",
            encoding="utf-8",
        )
        self.fold.fold_samples([results], timings, lambda: FIXED_NOW)
        kept = json.loads(
            (timings / "controller_timings.device.json").read_text(encoding="utf-8")
        )["verbs"]["identifier-appearance"]["samples"]
        self.assertEqual(len(kept), 40)
        self.assertEqual(kept[0]["at"], "2026-09-01T00:05:00+00:00")
        self.assertEqual(kept[-1]["at"], "2026-09-01T01:04:00+00:00")

    def test_fold_is_idempotent(self) -> None:
        timings = Path(tempfile.mkdtemp())
        results = Path(tempfile.mkdtemp())
        (results / "timing-samples.jsonl").write_text(
            sample_line("identifier-appearance", "device", 4.0, "2026-09-01T00:00:03+00:00")
            + "\n",
            encoding="utf-8",
        )
        first = self.fold.fold_samples([results], timings, lambda: FIXED_NOW)
        self.assertEqual(first["device"]["added"], 1)
        before = (timings / "controller_timings.device.json").read_bytes()
        second = self.fold.fold_samples([results], timings, lambda: FIXED_NOW)
        self.assertEqual(second["device"]["added"], 0)
        self.assertEqual(
            (timings / "controller_timings.device.json").read_bytes(), before
        )

    def test_folded_samples_drive_measured_budgets(self) -> None:
        timings = Path(tempfile.mkdtemp())
        results = Path(tempfile.mkdtemp())
        (results / "timing-samples.jsonl").write_text(
            "\n".join(
                sample_line(
                    "identifier-appearance",
                    "device",
                    float(value),
                    f"2026-09-01T00:00:{value:02d}+00:00",
                )
                for value in (1, 2, 3, 4, 5, 6)
            )
            + "\n",
            encoding="utf-8",
        )
        self.fold.fold_samples([results], timings, lambda: FIXED_NOW)
        budgets = provider(timings)
        budget = budgets.budget("device", "identifier-appearance")
        self.assertAlmostEqual(budget.seconds, 6.0 * 1.5)
        self.assertTrue(budget.provenance.startswith("p95 6.00s"))

    def test_fold_rejects_an_unknown_lane(self) -> None:
        timings = Path(tempfile.mkdtemp())
        results = Path(tempfile.mkdtemp())
        (results / "timing-samples.jsonl").write_text(
            sample_line("tap", "watch", 1.0, "2026-09-01T00:00:01+00:00") + "\n",
            encoding="utf-8",
        )
        with self.assertRaises(ValueError):
            self.fold.fold_samples([results], timings, lambda: FIXED_NOW)


if __name__ == "__main__":
    unittest.main()
