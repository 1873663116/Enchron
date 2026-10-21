import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


CONSOLE_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = CONSOLE_ROOT.parents[1]


def run_console(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CONSOLE_ROOT / "cli.py"), *arguments],
        capture_output=True,
        text=True,
        cwd=str(REPOSITORY_ROOT),
    )


def write_unit(root: Path, name: str, metadata: dict) -> None:
    units = root / "Regression" / "units"
    units.mkdir(parents=True, exist_ok=True)
    body = json.dumps(metadata, indent=1)
    (units / f"{name}.md").write_text(f"---\n{body}\n---\n", encoding="utf-8")


def write_feature(root: Path, name: str, units: list[str]) -> None:
    features = root / "Regression" / "features"
    features.mkdir(parents=True, exist_ok=True)
    body = json.dumps({"id": f"feature:{name}", "units": units}, indent=1)
    (features / f"{name}.md").write_text(f"---\n{body}\n---\n", encoding="utf-8")


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
            "plan", "check", "--tier", "static",
        )
        self.assertEqual(result.returncode, 3, result.stderr)
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
