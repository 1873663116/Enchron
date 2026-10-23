from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import loader
import ops
from model import MachineProfile


PROFILE = MachineProfile(capabilities=frozenset({"python", "mac", "xcode", "simulator", "device", "daemon"}), target="TARGET")


def passing_executor(root, verb, args, target, steps_directory, timeout_scale):
    return {
        "ok": True,
        "detail": f"ran {verb.name}",
        "durationMs": 5,
        "guardrails": [],
        "payload": {"fields": {"screen": "library"}, "count": 1},
        "target": target,
        "sessionEnsureMs": 0,
    }


class ValidationTests(unittest.TestCase):
    def test_an_unknown_verb_is_refused(self) -> None:
        with self.assertRaises(ops.OperationRefusal):
            ops.validate_operation("device.nope", {})

    def test_an_unknown_argument_is_refused(self) -> None:
        with self.assertRaises(ops.OperationRefusal):
            ops.validate_operation("device.snapshot", {"depth": 3})

    def test_a_choice_outside_the_vocabulary_is_refused(self) -> None:
        with self.assertRaises(ops.OperationRefusal):
            ops.validate_operation("device.command", {"action": "wiggle"})

    def test_a_known_operation_is_accepted(self) -> None:
        verb = ops.validate_operation(
            "device.command", {"action": "tap", "identifier": "Library-Grid"}
        )
        self.assertEqual(verb.name, "device.command")

    def test_bad_args_json_is_refused(self) -> None:
        with self.assertRaises(ops.OperationRefusal):
            ops.parse_arguments("{not json")

    def test_non_object_args_are_refused(self) -> None:
        with self.assertRaises(ops.OperationRefusal):
            ops.parse_arguments("[]")

    def test_an_unsafe_session_name_is_refused(self) -> None:
        with self.assertRaises(ops.OperationRefusal):
            ops.validate_session_name("../escape")


class TransportTests(unittest.TestCase):
    def test_device_commands_use_the_daemon(self) -> None:
        verb = ops.validate_operation("device.command", {"action": "tap"})
        self.assertEqual(ops.operation_transport(verb), "daemon")

    def test_staging_media_runs_directly(self) -> None:
        verb = ops.validate_operation(
            "device.stage-media", {"source": "a.mp4", "target": "/tmp"}
        )
        self.assertEqual(ops.operation_transport(verb), "direct")

    def test_a_static_check_has_no_lane(self) -> None:
        verb = ops.validate_operation(
            "static.check", {"checker": "verify_swiftlint.py"}
        )
        self.assertEqual(ops.operation_transport(verb), "direct")


class StateSummaryTests(unittest.TestCase):
    def test_fields_and_scalars_are_reported(self) -> None:
        summary = ops.state_summary(
            {"fields": {"screen": "library"}, "count": 3, "hierarchy": "<xml/>"}
        )
        self.assertEqual(summary, {"screen": "library", "count": 3})

    def test_a_non_object_payload_has_no_summary(self) -> None:
        self.assertEqual(ops.state_summary(None), {})


class SessionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)

    def record(self, verb: str, args: dict, execute=passing_executor) -> dict:
        return ops.run_operation(
            self.root, PROFILE, verb, args, session="probe", execute=execute
        )

    def test_a_recorded_operation_lands_in_the_debug_tree_only(self) -> None:
        result = self.record("device.command", {"action": "tap", "identifier": "x"})
        self.assertTrue(result["ok"])
        session = self.root / ".scratch/console/debug/probe"
        self.assertTrue((session / "session.json").is_file())
        entries = ops.read_session(self.root, "probe")
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["verb"], "device.command")
        self.assertEqual(entries[0]["state"], {"screen": "library", "count": 1})
        self.assertFalse((self.root / "TestEvidence").exists())

    def test_a_second_operation_gets_the_next_index(self) -> None:
        self.record("device.snapshot", {})
        self.record("device.command", {"action": "tap"})
        entries = ops.read_session(self.root, "probe")
        self.assertEqual([entry["index"] for entry in entries], [1, 2])

    def test_a_failed_operation_is_recorded_and_reported(self) -> None:
        def failing(root, verb, args, target, steps_directory, timeout_scale):
            return {
                "ok": False,
                "detail": "no element matched",
                "durationMs": 7,
                "guardrails": [],
                "payload": {"detail": "no element matched"},
                "target": target,
                "sessionEnsureMs": 0,
            }

        result = self.record("device.command", {"action": "tap"}, execute=failing)
        self.assertFalse(result["ok"])
        entries = ops.read_session(self.root, "probe")
        self.assertFalse(entries[0]["ok"])


class ReplayTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)

    def record(self) -> None:
        for verb, args in (
            ("device.snapshot", {}),
            ("device.command", {"action": "tap", "identifier": "x"}),
        ):
            ops.run_operation(
                self.root, PROFILE, verb, args, session="probe", execute=passing_executor
            )

    def test_a_replayed_session_matches_every_result(self) -> None:
        self.record()
        summary = ops.replay_session(
            self.root, PROFILE, "probe", execute=passing_executor
        )
        self.assertEqual(summary["matched"], 2)
        self.assertEqual(summary["mismatched"], [])
        self.assertTrue(
            list((self.root / ".scratch/console/debug/probe/replays").glob("*/summary.json"))
        )

    def test_a_changed_result_is_reported_as_mismatched(self) -> None:
        self.record()
        calls = {"count": 0}

        def flaky(root, verb, args, target, steps_directory, timeout_scale):
            calls["count"] += 1
            if calls["count"] == 2:
                return {
                    "ok": False,
                    "detail": "different result",
                    "durationMs": 1,
                    "guardrails": [],
                    "payload": None,
                    "target": target,
                    "sessionEnsureMs": 0,
                }
            return passing_executor(
                root, verb, args, target, steps_directory, timeout_scale
            )

        summary = ops.replay_session(self.root, PROFILE, "probe", execute=flaky)
        self.assertEqual(summary["matched"], 1)
        self.assertEqual(len(summary["mismatched"]), 1)


class ScaffoldTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        for verb, args in (
            ("device.session.ensure", {"lane": "simulator"}),
            ("device.command", {"action": "tap", "identifier": "x"}),
        ):
            ops.run_operation(
                self.root, PROFILE, verb, args, session="probe", execute=passing_executor
            )

    def test_the_draft_parses_as_a_unit(self) -> None:
        summary = ops.scaffold_unit(self.root, "probe")
        draft = Path(summary["path"]).read_text(encoding="utf-8")
        self.assertTrue(draft.startswith("---\n"))
        units = self.root / "Config/console/units"
        units.mkdir(parents=True)
        (units / "draft.md").write_text(draft, encoding="utf-8")
        loaded = loader.load_units(self.root)
        self.assertIn("unit:debug.probe@1", loaded)
        unit = loaded["unit:debug.probe@1"]
        self.assertEqual(unit.layer, 3)
        self.assertIn("daemon", unit.requires)
        self.assertEqual(len(unit.actions), 2)

    def test_the_draft_names_the_session_and_asks_for_an_assertion(self) -> None:
        summary = ops.scaffold_unit(self.root, "probe")
        draft = Path(summary["path"]).read_text(encoding="utf-8")
        self.assertIn("debug session probe", draft)
        self.assertIn("Complete the terminal assertion", draft)

    def test_scaffolding_an_unknown_session_is_refused(self) -> None:
        with self.assertRaises(ops.OperationRefusal):
            ops.scaffold_unit(self.root, "missing")


class RenderTests(unittest.TestCase):
    def test_an_operation_line_names_the_verb_and_time(self) -> None:
        text = ops.render_operation(
            {
                "ok": True,
                "verb": "device.snapshot",
                "durationMs": 412,
                "detail": "37 elements",
                "state": {"screen": "library"},
                "sessionEnsureMs": 0,
            }
        )
        self.assertIn("ok   device.snapshot  412 ms", text)
        self.assertIn("screen=library", text)

    def test_a_replay_line_counts_matches(self) -> None:
        text = ops.render_replay(
            {
                "session": "probe",
                "operations": 1,
                "matched": 1,
                "mismatched": [],
                "results": [
                    {
                        "index": 1,
                        "verb": "device.snapshot",
                        "matched": True,
                        "durationMs": 10,
                        "recordedDurationMs": 11,
                    }
                ],
            }
        )
        self.assertIn("1 op(s), 1 matched, 0 mismatched", text)


if __name__ == "__main__":
    unittest.main()
