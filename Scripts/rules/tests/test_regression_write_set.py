#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "regression"))

from write_set import WritePlan, WriteScope, WriteSetError, report


TOOL = Path(__file__).resolve().parents[2] / "regression/writectl.py"


def plan(*tasks: dict[str, object]) -> WritePlan:
    return WritePlan.parse({"version": 1, "tasks": list(tasks)})


class WriteScopeTests(unittest.TestCase):
    def test_exact_and_subtree_overlap_has_precise_semantics(self) -> None:
        subtree = WriteScope.parse("Modules/Playback/Session/**")
        self.assertTrue(subtree.overlaps(WriteScope.parse("Modules/Playback/Session/A.swift")))
        self.assertFalse(subtree.overlaps(WriteScope.parse("Modules/Playback/Domain/**")))

    def test_broad_or_ambiguous_patterns_are_rejected(self) -> None:
        for value in (".", "/", "../Modules/**", "Modules/*/A.swift"):
            with self.subTest(value=value), self.assertRaises(WriteSetError):
                WriteScope.parse(value)


class WritePlanTests(unittest.TestCase):
    def test_disjoint_sibling_write_sets_can_run_concurrently(self) -> None:
        parsed = plan(
            {"id": "driver", "writes": ["Modules/Playback/Session/Driver.swift"]},
            {"id": "format", "writes": ["Modules/Playback/Domain/**"]},
        )
        self.assertEqual(parsed.conflicts(), ())
        self.assertTrue(report(parsed)["safe"])

    def test_concurrent_overlap_is_rejected(self) -> None:
        parsed = plan(
            {"id": "facade", "writes": ["Modules/Playback/**"]},
            {"id": "driver", "writes": ["Modules/Playback/Session/**"]},
        )
        self.assertEqual(len(parsed.conflicts()), 1)
        self.assertFalse(report(parsed)["safe"])

    def test_dependency_orders_an_overlapping_integrator(self) -> None:
        parsed = plan(
            {"id": "driver", "writes": ["Modules/Playback/Session/**"]},
            {
                "id": "integrator",
                "dependsOn": ["driver"],
                "writes": ["Modules/Playback/**"],
            },
        )
        self.assertEqual(parsed.conflicts(), ())

    def test_transitive_dependency_orders_shared_state(self) -> None:
        parsed = plan(
            {"id": "a", "writes": ["ARCHITECTURE.md"]},
            {"id": "b", "dependsOn": ["a"], "writes": ["Modules/A.swift"]},
            {"id": "c", "dependsOn": ["b"], "writes": ["ARCHITECTURE.md"]},
        )
        self.assertEqual(parsed.conflicts(), ())

    def test_unknown_dependency_and_cycle_fail_closed(self) -> None:
        with self.assertRaises(WriteSetError):
            plan({"id": "a", "dependsOn": ["missing"], "writes": ["A"]})
        with self.assertRaises(WriteSetError):
            plan(
                {"id": "a", "dependsOn": ["b"], "writes": ["A"]},
                {"id": "b", "dependsOn": ["a"], "writes": ["B"]},
            )

    def test_digest_is_independent_of_task_and_scope_input_order(self) -> None:
        first = plan(
            {"id": "b", "writes": ["B/Two", "B/One"]},
            {"id": "a", "writes": ["A"]},
        )
        second = plan(
            {"id": "a", "writes": ["A"]},
            {"id": "b", "writes": ["B/One", "B/Two"]},
        )
        self.assertEqual(first.digest(), second.digest())

    def test_cli_exit_code_expresses_safety(self) -> None:
        payload = {
            "version": 1,
            "tasks": [
                {"id": "one", "writes": ["Regression/**"]},
                {"id": "two", "writes": ["Regression/journeys/**"]},
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "plan.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(TOOL), str(path)],
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.returncode, 1)
        self.assertFalse(json.loads(completed.stdout)["safe"])


if __name__ == "__main__":
    unittest.main()
