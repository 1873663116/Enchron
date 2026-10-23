from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import compile as compiler
import loader
import model


CAPABILITIES = frozenset(
    {"python", "mac", "xcode", "simulator", "device", "daemon"}
)
PROFILE = model.MachineProfile(capabilities=CAPABILITIES, target="TARGET")


def write_unit(root: Path, metadata: dict) -> None:
    units = root / "Config/console/units"
    units.mkdir(parents=True, exist_ok=True)
    body = json.dumps(metadata, indent=1)
    (units / "multi.md").write_text(f"---\n{body}\n---\n", encoding="utf-8")


def unit_definition(cases: list[dict] | None = None) -> dict:
    metadata = {
        "schema": "enchron.console.unit",
        "schemaVersion": 1,
        "id": "unit:multi@1",
        "layer": 3,
        "role": "verification",
        "requires": ["mac", "device", "daemon"],
        "isolation": "clean-library",
        "actions": [
            {"verb": "device.session.ensure", "args": {"lane": "simulator"}},
            {"verb": "device.snapshot", "args": {}},
            {
                "verb": "device.app-command",
                "args": {"verb": "resetState", "arguments": {"keepSession": "true"}},
            },
            {"verb": "device.snapshot", "args": {}},
        ],
        "terminal": {"kind": "artifact", "path": "hierarchy.json"},
        "teardown": [
            {
                "verb": "device.app-command",
                "args": {"verb": "leavePlayback", "arguments": {}},
            }
        ],
    }
    if cases is not None:
        metadata["cases"] = cases
    return metadata


class CaseMetadataTests(unittest.TestCase):
    def test_the_loader_reads_case_boundaries(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            write_unit(
                root,
                unit_definition(
                    [
                        {"key": "first", "start": 1},
                        {"key": "second", "start": 3},
                    ]
                ),
            )
            unit = loader.load_units(root)["unit:multi@1"]
        self.assertEqual([case["key"] for case in unit.cases], ["first", "second"])

    def test_a_unit_without_cases_has_none(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            write_unit(root, unit_definition())
            unit = loader.load_units(root)["unit:multi@1"]
        self.assertEqual(unit.cases, ())

    def test_a_duplicate_case_start_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            write_unit(
                root,
                unit_definition(
                    [
                        {"key": "first", "start": 1},
                        {"key": "second", "start": 1},
                    ]
                ),
            )
            with self.assertRaises(loader.LoadRefusal) as caught:
                loader.load_units(root)
        self.assertEqual(caught.exception.code, "C019")

    def test_a_malformed_case_entry_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            write_unit(root, unit_definition([{"key": "", "start": 1}]))
            with self.assertRaises(loader.LoadRefusal) as caught:
                loader.load_units(root)
        self.assertEqual(caught.exception.code, "C019")


class CasePlanTests(unittest.TestCase):
    def setUp(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            self.root = Path(scratch)
            write_unit(
                self.root,
                unit_definition(
                    [
                        {"key": "first", "start": 1},
                        {"key": "second", "start": 3},
                    ]
                ),
            )
            self.unit = loader.load_units(self.root)["unit:multi@1"]
            self.plan, errors = compiler.Compiler(self.root).compile(
                self.unit, "e2e", PROFILE
            )
            self.assertEqual(errors, [])

    def test_a_case_keeps_the_setup_and_its_own_steps(self) -> None:
        subset, refusal = compiler.case_plan(self.plan, self.unit, "second")
        self.assertEqual(refusal, "")
        verbs = [step.verb for step in subset.steps]
        self.assertEqual(verbs[0], "device.session.ensure")
        self.assertEqual(verbs[-1], "device.snapshot")
        self.assertNotIn(
            ("device.app-command", "resetState", "first"),
            [
                (step.verb, step.args.get("verb"), step.args.get("arguments", {}).get("case"))
                for step in subset.steps
            ],
        )
        self.assertLess(len(subset.steps), len(self.plan.steps))

    def test_a_case_gets_its_own_digest_and_evidence_name(self) -> None:
        first, _ = compiler.case_plan(self.plan, self.unit, "first")
        second, _ = compiler.case_plan(self.plan, self.unit, "second")
        self.assertNotEqual(first.digest, second.digest)
        self.assertNotEqual(first.unit, second.unit)
        self.assertIn("#first", first.unit)

    def test_an_unknown_case_is_refused(self) -> None:
        subset, refusal = compiler.case_plan(self.plan, self.unit, "third")
        self.assertIsNone(subset)
        self.assertIn("no case 'third'", refusal)

    def test_a_unit_without_cases_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            write_unit(root, unit_definition())
            unit = loader.load_units(root)["unit:multi@1"]
            plan, _ = compiler.Compiler(root).compile(unit, "e2e", PROFILE)
            subset, refusal = compiler.case_plan(plan, unit, "first")
        self.assertIsNone(subset)
        self.assertIn("records no case boundaries", refusal)


class GeneratedCaseTests(unittest.TestCase):
    def test_generated_units_carry_the_declared_cases(self) -> None:
        root = Path(__file__).resolve().parents[3]
        units = loader.load_units(root)
        matrix = units["unit:catalog.scenario-dynamic-range-interpretation-dolby-vision-profile-matrix@1"]
        self.assertEqual(
            [case["key"] for case in matrix.cases],
            ["dv-profile-5", "dv-profile-7-dual", "dv-profile-8-hdr10", "dv-profile-8-hlg"],
        )
        plan, _ = compiler.Compiler(root).compile(matrix, "e2e", PROFILE)
        subset, refusal = compiler.case_plan(plan, matrix, "dv-profile-5")
        self.assertEqual(refusal, "")
        self.assertTrue(any(step.verb == "device.capture-frames" for step in subset.steps))


if __name__ == "__main__":
    unittest.main()
