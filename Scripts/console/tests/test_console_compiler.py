import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


CONSOLE_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = CONSOLE_ROOT.parents[1]
sys.path.insert(0, str(CONSOLE_ROOT))

import compile as compile_module
import loader
import machine


def run_console(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CONSOLE_ROOT / "cli.py"), *arguments],
        capture_output=True,
        text=True,
        cwd=str(REPOSITORY_ROOT),
    )


def write_unit(root: Path, name: str, metadata: dict) -> None:
    units = root / "Config" / "console" / "units"
    units.mkdir(parents=True, exist_ok=True)
    body = json.dumps(metadata, indent=1)
    (units / f"{name}.md").write_text(f"---\n{body}\n---\n", encoding="utf-8")


def write_feature(root: Path, name: str, units: list[str]) -> None:
    features = root / "Config" / "console" / "features"
    features.mkdir(parents=True, exist_ok=True)
    body = json.dumps({"id": f"feature:{name}", "units": units}, indent=1)
    (features / f"{name}.md").write_text(f"---\n{body}\n---\n", encoding="utf-8")


class ReferenceTests(unittest.TestCase):
    def compile(self, actions: list[dict]) -> list[str]:
        unit = loader.parse_unit(
            {
                "schema": "enchron.console.unit",
                "schemaVersion": 1,
                "id": "unit:reference@1",
                "layer": 3,
                "actions": actions,
                "requires": ["mac", "device", "daemon"],
                "terminal": {"kind": "artifact", "path": "app-command.json", "schema": "enchron.console.app-command@1"},
            },
            "test",
        )
        compiler = compile_module.Compiler(Path.cwd())
        _, errors = compiler.compile(unit, "e2e", machine.synthetic("mac-daemon"))
        return [code for code, _ in errors]

    def test_a_reference_after_its_capture_compiles(self) -> None:
        codes = self.compile(
            [
                {"verb": "device.stage-identity", "args": {"source": "x.json"}, "capture": {"digest": "sig"}},
                {"verb": "device.app-command", "args": {"verb": "embySignIn", "arguments": {"identityDigest": "$sig"}}},
            ]
        )
        self.assertEqual(codes, [])

    def test_a_reference_before_any_capture_is_refused(self) -> None:
        codes = self.compile(
            [
                {"verb": "device.app-command", "args": {"verb": "ping", "arguments": {"x": "$sig"}}},
                {"verb": "device.stage-identity", "args": {"source": "x.json"}, "capture": {"digest": "sig"}},
            ]
        )
        self.assertIn("C018", codes)

    def test_a_capture_written_twice_is_refused(self) -> None:
        codes = self.compile(
            [
                {"verb": "device.stage-identity", "args": {"source": "a.json"}, "capture": {"digest": "sig"}},
                {"verb": "device.stage-identity", "args": {"source": "b.json"}, "capture": {"digest": "sig"}},
            ]
        )
        self.assertIn("C018", codes)


class PreconditionTests(unittest.TestCase):
    def test_a_media_server_precondition_compiles(self) -> None:
        unit = loader.parse_unit(
            {
                "schema": "enchron.console.unit",
                "schemaVersion": 1,
                "id": "unit:precondition.ok@1",
                "layer": 3,
                "actions": [{"verb": "device.probe", "args": {"probe": "X"}}],
                "requires": ["mac", "device", "daemon"],
                "preconditions": [{"kind": "media-server", "provider": "emby"}],
                "terminal": {"kind": "artifact", "path": "probe.json", "schema": "enchron.console.probe@1"},
            },
            "test",
        )
        compiler = compile_module.Compiler(Path.cwd())
        plan, errors = compiler.compile(unit, "e2e", machine.synthetic("mac-daemon"))
        self.assertEqual(errors, [])
        self.assertIsNotNone(plan)
        self.assertEqual(plan.preconditions[0]["provider"], "emby")

    def test_an_unknown_provider_is_refused(self) -> None:
        unit = loader.parse_unit(
            {
                "schema": "enchron.console.unit",
                "schemaVersion": 1,
                "id": "unit:precondition.bad@1",
                "layer": 3,
                "actions": [{"verb": "device.probe", "args": {"probe": "X"}}],
                "requires": ["mac", "device", "daemon"],
                "preconditions": [{"kind": "media-server", "provider": "plex"}],
                "terminal": {"kind": "artifact", "path": "probe.json", "schema": "enchron.console.probe@1"},
            },
            "test",
        )
        compiler = compile_module.Compiler(Path.cwd())
        plan, errors = compiler.compile(unit, "e2e", machine.synthetic("mac-daemon"))
        self.assertIsNone(plan)
        self.assertIn("C016", [code for code, _ in errors])

    def test_an_unknown_kind_is_refused_at_load(self) -> None:
        with self.assertRaises(loader.LoadRefusal):
            loader.parse_unit(
                {
                    "schema": "enchron.console.unit",
                    "schemaVersion": 1,
                    "id": "unit:precondition.kind@1",
                    "layer": 3,
                    "actions": [{"verb": "device.probe", "args": {"probe": "X"}}],
                    "requires": ["mac"],
                    "preconditions": [{"kind": "moon-phase"}],
                    "terminal": {"kind": "artifact", "path": "probe.json", "schema": "enchron.console.probe@1"},
                },
                "test",
            )


class ConsoleCompilerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def test_a_unit_without_terminal_is_refused(self) -> None:
        write_unit(
            self.root,
            "no-terminal",
            {
                "id": "unit:no-terminal@1",
                "layer": 2,
                "actions": [
                    {"verb": "static.check", "args": {"checker": "verify_swiftlint.py"}}
                ],
            },
        )
        write_feature(self.root, "cover", ["unit:no-terminal@1"])
        result = run_console(
            "--root", str(self.root), "--json", "plan", "show", "unit:no-terminal@1",
            "--tier", "static",
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["findings"][0]["code"], "C001")

    def test_a_device_unit_compiles_on_a_linux_profile_shape(self) -> None:
        write_unit(
            self.root,
            "device-unit",
            {
                "id": "unit:device@1",
                "layer": 3,
                "requires": ["mac", "device", "daemon"],
                "actions": [{"verb": "device.snapshot", "args": {}}],
                "terminal": {"kind": "artifact", "path": "hierarchy.json"},
            },
        )
        write_feature(self.root, "cover", ["unit:device@1"])
        result = run_console(
            "--root", str(self.root), "--machine", "linux", "--json",
            "plan", "check",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_unit_needing_a_device_fails_a_linux_profile(self) -> None:
        write_unit(
            self.root,
            "device-unit",
            {
                "id": "unit:device@1",
                "layer": 3,
                "requires": ["mac", "device", "daemon"],
                "actions": [{"verb": "device.snapshot", "args": {}}],
                "terminal": {"kind": "artifact", "path": "hierarchy.json"},
            },
        )
        write_feature(self.root, "cover", ["unit:device@1"])
        result = run_console(
            "--root", str(self.root), "--machine", "linux", "--json",
            "plan", "show", "unit:device@1", "--tier", "static",
        )
        self.assertEqual(result.returncode, 4, result.stderr)
        codes = {finding["code"] for finding in json.loads(result.stdout)["findings"]}
        self.assertIn("C004", codes)

    def test_an_orphan_unit_is_reported(self) -> None:
        write_unit(
            self.root,
            "orphan",
            {
                "id": "unit:orphan@1",
                "layer": 2,
                "actions": [
                    {"verb": "static.check", "args": {"checker": "verify_swiftlint.py"}}
                ],
                "terminal": {"kind": "artifact", "path": "static-check.json"},
            },
        )
        result = run_console(
            "--root", str(self.root), "--json", "plan", "check", "--tier", "static"
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        codes = {finding["code"] for finding in json.loads(result.stdout)["findings"]}
        self.assertIn("C013", codes)

    def test_a_dangling_feature_reference_is_reported(self) -> None:
        write_feature(self.root, "cover", ["unit:absent@1"])
        result = run_console(
            "--root", str(self.root), "--json", "plan", "check", "--tier", "static"
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        codes = {finding["code"] for finding in json.loads(result.stdout)["findings"]}
        self.assertIn("C012", codes)

    def test_an_unknown_verb_points_at_a_recompile(self) -> None:
        write_unit(
            self.root,
            "bad-verb",
            {
                "id": "unit:bad-verb@1",
                "layer": 2,
                "actions": [{"verb": "no.such.verb", "args": {}}],
                "terminal": {"kind": "artifact", "path": "static-check.json"},
            },
        )
        write_feature(self.root, "cover", ["unit:bad-verb@1"])
        result = run_console(
            "--root", str(self.root), "--json", "plan", "show", "unit:bad-verb@1",
            "--tier", "static",
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["findings"][0]["code"], "C003")
        self.assertIn("recompile", payload["findings"][0]["message"])

    def test_a_well_formed_unit_compiles_on_its_machine(self) -> None:
        write_unit(
            self.root,
            "good",
            {
                "id": "unit:good@1",
                "layer": 3,
                "requires": ["mac", "device", "daemon"],
                "actions": [{"verb": "device.snapshot", "args": {}}],
                "terminal": {"kind": "artifact", "path": "hierarchy.json"},
            },
        )
        write_feature(self.root, "cover", ["unit:good@1"])
        result = run_console(
            "--root", str(self.root), "--machine", "mac-daemon", "--json",
            "plan", "show", "unit:good@1", "--tier", "e2e",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["transport"], "daemon")
        self.assertEqual(len(payload["steps"]), 1)

    def test_run_rejects_a_second_unit(self) -> None:
        result = run_console(
            "--root", str(self.root), "run", "unit:one@1", "unit:two@1"
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()


class ExpectationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def plan(self, actions: list[dict]) -> subprocess.CompletedProcess:
        write_unit(
            self.root,
            "guarded",
            {
                "id": "unit:guarded@1",
                "layer": 3,
                "requires": ["mac", "device", "daemon"],
                "actions": actions,
                "terminal": {
                    "kind": "artifact",
                    "path": "hierarchy.json",
                    "schema": "enchron.console.hierarchy@1",
                },
            },
        )
        write_feature(self.root, "cover", ["unit:guarded@1"])
        return run_console(
            "--root", str(self.root), "--json", "plan", "show", "unit:guarded@1",
            "--tier", "e2e",
        )

    def test_an_expectation_needs_a_comparison(self) -> None:
        result = self.plan(
            [
                {
                    "verb": "device.snapshot",
                    "args": {},
                    "expect": {"path": "hierarchy"},
                }
            ]
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(json.loads(result.stdout)["findings"][0]["code"], "C005")

    def test_a_containment_expectation_compiles(self) -> None:
        result = self.plan(
            [
                {
                    "verb": "device.snapshot",
                    "args": {},
                    "expect": {"path": "hierarchy", "contains": "Library"},
                }
            ]
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_terminal_schema_must_match_its_producer(self) -> None:
        write_unit(
            self.root,
            "wrong-schema",
            {
                "id": "unit:wrong-schema@1",
                "layer": 3,
                "requires": ["mac", "device", "daemon"],
                "actions": [{"verb": "device.snapshot", "args": {}}],
                "terminal": {
                    "kind": "artifact",
                    "path": "hierarchy.json",
                    "schema": "enchron.console.hierarch@1",
                },
            },
        )
        write_feature(self.root, "cover", ["unit:wrong-schema@1"])
        result = run_console(
            "--root", str(self.root), "--json", "plan", "show", "unit:wrong-schema@1",
            "--tier", "e2e",
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(json.loads(result.stdout)["findings"][0]["code"], "C014")

    def test_a_command_action_outside_the_table_is_refused(self) -> None:
        result = self.plan(
            [
                {
                    "verb": "device.command",
                    "args": {"action": "activate", "identifier": "Library-Root"},
                },
                {"verb": "device.snapshot", "args": {}},
            ]
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(json.loads(result.stdout)["findings"][0]["code"], "C005")
