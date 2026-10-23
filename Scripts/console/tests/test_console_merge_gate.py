from __future__ import annotations

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import merge_gate


class ClassifyTests(unittest.TestCase):
    def test_no_failures_is_green(self) -> None:
        verdict = merge_gate.classify([], [], [], reference="2026-10-23")
        self.assertEqual(verdict.status, merge_gate.GREEN)

    def test_a_declared_unit_failure_is_yellow(self) -> None:
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [{"test": "PlaybackTests/testSeek", "reason": "known defect"}],
            [],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.YELLOW)
        self.assertEqual(len(verdict.yellow), 1)
        self.assertEqual(verdict.red, [])

    def test_a_declared_checker_failure_is_yellow_only_on_a_phrase_match(self) -> None:
        declaration = {"checker": "no-literal-rfc1918", "match": "private address"}
        matching = merge_gate.classify(
            [merge_gate.Failure("ci:no-literal-rfc1918", "found a private address")],
            [declaration],
            [],
            reference="2026-10-23",
        )
        self.assertEqual(matching.status, merge_gate.YELLOW)
        other = merge_gate.classify(
            [merge_gate.Failure("ci:no-literal-rfc1918", "different finding")],
            [declaration],
            [],
            reference="2026-10-23",
        )
        self.assertEqual(other.status, merge_gate.RED)

    def test_an_undeclared_failure_is_red(self) -> None:
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [],
            [],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.RED)
        self.assertEqual(len(verdict.red), 1)

    def test_an_expired_declaration_is_red(self) -> None:
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [
                {
                    "test": "PlaybackTests/testSeek",
                    "expires": "2026-10-01",
                }
            ],
            [],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.RED)

    def test_a_build_failure_is_never_yellow(self) -> None:
        verdict = merge_gate.classify(
            [merge_gate.Failure("build")],
            [{"checker": "build", "match": ""}],
            [],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.RED)

    def test_a_valid_override_allows_a_red_failure(self) -> None:
        record = {
            "schema": "enchron.console.merge-override",
            "schemaVersion": 1,
            "signature": "unit:PlaybackTests/testSeek",
            "reason": "operator approved the known break",
            "approvedBy": "operator",
            "approvedAt": "2026-10-23",
            "expires": "2026-11-01",
        }
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [],
            [record],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.OVERRIDE)
        self.assertEqual(len(verdict.overridden), 1)
        self.assertEqual(verdict.red, [])

    def test_an_expired_override_leaves_the_failure_red(self) -> None:
        record = {
            "schema": "enchron.console.merge-override",
            "schemaVersion": 1,
            "signature": "unit:PlaybackTests/testSeek",
            "reason": "approved",
            "approvedBy": "operator",
            "approvedAt": "2026-10-01",
            "expires": "2026-10-10",
        }
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [],
            [record],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.RED)

    def test_an_override_without_human_approval_is_inert(self) -> None:
        record = {
            "schema": "enchron.console.merge-override",
            "schemaVersion": 1,
            "signature": "unit:PlaybackTests/testSeek",
            "reason": "approved",
            "approvedAt": "2026-10-23",
        }
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [],
            [record],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.RED)

    def test_an_override_for_another_signature_is_inert(self) -> None:
        record = {
            "schema": "enchron.console.merge-override",
            "schemaVersion": 1,
            "signature": "unit:OtherTests/testOther",
            "reason": "approved",
            "approvedBy": "operator",
            "approvedAt": "2026-10-23",
        }
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [],
            [record],
            reference="2026-10-23",
        )
        self.assertEqual(verdict.status, merge_gate.RED)


class FailureParsingTests(unittest.TestCase):
    def test_failed_tests_are_unique_and_in_order(self) -> None:
        text = (
            '✘ Test "PlaybackTests/testSeek" failed after 3.0 s\n'
            '✘ Test "PlaybackTests/testSeek" failed after 3.0 s\n'
            '✘ Test "StorageTests/testClear" failed after 1.0 s\n'
        )
        self.assertEqual(
            merge_gate.failed_tests(text),
            ["PlaybackTests/testSeek", "StorageTests/testClear"],
        )

    def test_a_passing_unit_payload_has_no_failures(self) -> None:
        self.assertEqual(
            merge_gate.unit_failures({"exitCode": 0, "passed": True}), []
        )

    def test_a_unit_failure_names_each_failed_test(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            log = Path(scratch) / "unit.log"
            log.write_text(
                '✘ Test "PlaybackTests/testSeek" failed after 3.0 s\n',
                encoding="utf-8",
            )
            failures = merge_gate.unit_failures(
                {"exitCode": 1, "passed": False, "log": str(log)}
            )
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0].signature, "unit:PlaybackTests/testSeek")

    def test_a_unit_failure_without_a_test_line_is_infrastructure(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            log = Path(scratch) / "unit.log"
            log.write_text("The project cannot be built.\n", encoding="utf-8")
            failures = merge_gate.unit_failures(
                {"exitCode": 1, "passed": False, "log": str(log)}
            )
        self.assertEqual(failures[0].signature, "unit:infrastructure")

    def test_a_missing_unit_payload_is_infrastructure(self) -> None:
        self.assertEqual(
            merge_gate.unit_failures(None)[0].signature, "unit:infrastructure"
        )

    def test_a_missing_build_payload_is_a_build_failure(self) -> None:
        self.assertEqual(merge_gate.build_failures(None)[0].signature, "build")

    def test_a_passing_build_has_no_failures(self) -> None:
        self.assertEqual(merge_gate.build_failures({"exitCode": 0}), [])

    def test_ci_known_and_failing_checks_become_failures(self) -> None:
        payload = {
            "exitCode": 1,
            "checks": [
                {"checker": "no-literal-rfc1918", "state": "known", "detail": "x"},
                {"checker": "verify_product_source_comments", "state": "FAIL", "detail": "y"},
                {"checker": "harness-primitives-gate", "state": "PASS"},
            ],
        }
        signatures = [item.signature for item in merge_gate.ci_failures(payload)]
        self.assertEqual(
            signatures,
            ["ci:no-literal-rfc1918", "ci:verify_product_source_comments"],
        )

    def test_a_ci_failure_without_a_check_is_infrastructure(self) -> None:
        failures = merge_gate.ci_failures({"exitCode": 1, "checks": [], "stderr": "boom"})
        self.assertEqual(failures[0].signature, "ci:infrastructure")


class MainRecordTests(unittest.TestCase):
    def repository(self) -> Path:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        self.git(root, "init", "-q", "-b", "main")
        self.git(root, "config", "user.email", "tests@example.com")
        self.git(root, "config", "user.name", "tests")
        return root

    def git(self, root: Path, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", str(root), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_declarations_are_read_from_main_not_from_the_branch(self) -> None:
        root = self.repository()
        path = root / "Config/console/known-failures.md"
        path.parent.mkdir(parents=True)
        path.write_text(
            "---\n"
            '{"schema": "enchron.console.known-failures", "schemaVersion": 1,'
            ' "failures": [{"test": "MainTests/testMain"}]}\n'
            "---\n",
            encoding="utf-8",
        )
        self.git(root, "add", ".")
        self.git(root, "commit", "-q", "-m", "main declaration")
        path.write_text(
            "---\n"
            '{"schema": "enchron.console.known-failures", "schemaVersion": 1,'
            ' "failures": [{"test": "BranchTests/testBranch"}]}\n'
            "---\n",
            encoding="utf-8",
        )
        declarations = merge_gate.main_declarations(root)
        self.assertEqual([item["test"] for item in declarations], ["MainTests/testMain"])

    def test_overrides_are_read_from_main(self) -> None:
        root = self.repository()
        directory = root / "Config/console/merge-overrides"
        directory.mkdir(parents=True)
        record = {
            "schema": "enchron.console.merge-override",
            "schemaVersion": 1,
            "signature": "unit:MainTests/testMain",
            "reason": "approved",
            "approvedBy": "operator",
            "approvedAt": "2026-10-23",
        }
        (directory / "main.json").write_text(json.dumps(record), encoding="utf-8")
        self.git(root, "add", ".")
        self.git(root, "commit", "-q", "-m", "main override")
        (directory / "branch.json").write_text(json.dumps(record), encoding="utf-8")
        records = merge_gate.main_overrides(root)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["signature"], "unit:MainTests/testMain")

    def test_no_override_directory_means_no_records(self) -> None:
        root = self.repository()
        self.assertEqual(merge_gate.main_overrides(root), [])


class KnownEnvironmentTests(unittest.TestCase):
    def test_the_environment_names_the_declaration_file_to_read(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "known.md"
            path.write_text(
                "---\n"
                '{"schema": "enchron.console.known-failures", "schemaVersion": 1,'
                ' "failures": [{"checker": "x", "match": "y"}]}\n'
                "---\n",
                encoding="utf-8",
            )
            with unittest.mock.patch.dict(
                "os.environ", {"ENCHRON_KNOWN_FAILURES": str(path)}
            ):
                declarations = merge_gate.known.declarations(Path(scratch))
        self.assertEqual([item["checker"] for item in declarations], ["x"])


class RenderingTests(unittest.TestCase):
    def test_a_green_verdict_renders_the_word_green(self) -> None:
        verdict = merge_gate.classify([], [], [])
        self.assertIn("merge gate green", merge_gate.render(verdict, 10))

    def test_a_yellow_verdict_names_the_known_failure(self) -> None:
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")],
            [{"test": "PlaybackTests/testSeek"}],
            [],
        )
        rendered = merge_gate.render(verdict, 10)
        self.assertIn("yellow (1 known)", rendered)
        self.assertIn("known    unit:PlaybackTests/testSeek", rendered)

    def test_a_red_verdict_names_the_undeclared_failure(self) -> None:
        verdict = merge_gate.classify(
            [merge_gate.Failure("unit:PlaybackTests/testSeek")], [], []
        )
        rendered = merge_gate.render(verdict, 10)
        self.assertIn("red (1 undeclared)", rendered)
        self.assertIn("red      unit:PlaybackTests/testSeek", rendered)


class GateIntegrationTests(unittest.TestCase):
    def git(self, root: Path, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", str(root), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )

    def repository(self, unit_failure: bool = False) -> Path:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        self.git(root, "init", "-q", "-b", "main")
        self.git(root, "config", "user.email", "tests@example.com")
        self.git(root, "config", "user.name", "tests")
        declaration = root / "Config/console/known-failures.md"
        declaration.parent.mkdir(parents=True)
        declaration.write_text(
            "---\n"
            '{"schema": "enchron.console.known-failures", "schemaVersion": 1,'
            ' "failures": [{"checker": "no-literal-rfc1918", "match": ""}]}\n'
            "---\n",
            encoding="utf-8",
        )
        self.git(root, "add", ".")
        self.git(root, "commit", "-q", "-m", "declarations")
        failure_line = '✘ Test "PlaybackTests/testSeek" failed after 1.0 s\n'
        console = root / "Scripts" / "console"
        console.mkdir(parents=True)
        log = root / "TestEvidence" / "console" / "tiers" / "unit.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        if unit_failure:
            log.write_text(failure_line, encoding="utf-8")
        script = console / "cli.py"
        static_payload = (
            "{'exitCode': 0, 'checks': [{'checker': 'no-literal-rfc1918', "
            "'state': 'known', 'detail': 'declared'}]}"
        )
        if unit_failure:
            unit_payload = (
                "{'exitCode': 1, 'passed': False, 'log': " + repr(str(log)) + "}"
            )
        else:
            unit_payload = "{'exitCode': 0, 'passed': True, 'log': None}"
        script.write_text(
            "import json\n"
            "import sys\n"
            "from pathlib import Path\n"
            "root = Path(__file__).resolve().parents[2]\n"
            "evidence = root / 'TestEvidence' / 'console'\n"
            "args = sys.argv[1:]\n"
            f"static = {static_payload}\n"
            f"unit = {unit_payload}\n"
            "build = {'exitCode': 0, 'durationMs': 1}\n"
            "if 'static' in args:\n"
            "    target = evidence / 'static' / 'last-run.json'\n"
            "    target.parent.mkdir(parents=True, exist_ok=True)\n"
            "    target.write_text(json.dumps(static))\n"
            "elif 'build' in args:\n"
            "    target = evidence / 'tiers' / 'build.json'\n"
            "    target.parent.mkdir(parents=True, exist_ok=True)\n"
            "    target.write_text(json.dumps(build))\n"
            "elif 'unit' in args:\n"
            "    target = evidence / 'tiers' / 'unit.json'\n"
            "    target.parent.mkdir(parents=True, exist_ok=True)\n"
            "    target.write_text(json.dumps(unit))\n",
            encoding="utf-8",
        )
        return root

    def run_gate(self, root: Path) -> tuple[int, dict]:
        evidence = root / "TestEvidence" / "console"
        with contextlib.redirect_stdout(io.StringIO()):
            return merge_gate.run_gate(root, None, evidence)

    def test_a_declared_failure_produces_yellow_and_evidence(self) -> None:
        root = self.repository()
        exit_code, summary = self.run_gate(root)
        self.assertEqual(exit_code, 0)
        self.assertEqual(summary["status"], merge_gate.YELLOW)
        self.assertTrue(
            list((root / "TestEvidence" / "console" / "merges").glob("*/summary.json"))
        )
        status = (root / ".scratch" / "console" / "merge-gate" / "status.txt").read_text()
        self.assertEqual(status, "yellow (1 known)")
        saved = json.loads(
            next((root / "TestEvidence" / "console" / "merges").glob("*/summary.json")).read_text()
        )
        self.assertEqual(saved["status"], merge_gate.YELLOW)
        self.assertEqual(len(saved["yellow"]), 1)

    def test_an_undeclared_unit_failure_is_red(self) -> None:
        root = self.repository(unit_failure=True)
        exit_code, summary = self.run_gate(root)
        self.assertEqual(exit_code, 1)
        self.assertEqual(summary["status"], merge_gate.RED)
        self.assertEqual(summary["red"][0]["signature"], "unit:PlaybackTests/testSeek")


    def test_a_declaration_added_on_the_branch_does_not_protect_a_failure(self) -> None:
        root = self.repository(unit_failure=True)
        declaration = root / "Config/console/known-failures.md"
        declaration.write_text(
            "---\n"
            '{"schema": "enchron.console.known-failures", "schemaVersion": 1,'
            ' "failures": [{"checker": "no-literal-rfc1918", "match": ""},'
            ' {"test": "PlaybackTests/testSeek"}]}\n'
            "---\n",
            encoding="utf-8",
        )
        exit_code, summary = self.run_gate(root)
        self.assertEqual(exit_code, 1)
        self.assertEqual(summary["status"], merge_gate.RED)

    def test_an_approved_override_on_main_allows_the_red_failure(self) -> None:
        root = self.repository(unit_failure=True)
        directory = root / "Config/console/merge-overrides"
        directory.mkdir(parents=True)
        (directory / "approved.json").write_text(
            json.dumps(
                {
                    "schema": "enchron.console.merge-override",
                    "schemaVersion": 1,
                    "signature": "unit:PlaybackTests/testSeek",
                    "reason": "operator approved the known break",
                    "approvedBy": "operator",
                    "approvedAt": "2026-10-23",
                }
            ),
            encoding="utf-8",
        )
        self.git(root, "add", ".")
        self.git(root, "commit", "-q", "-m", "approved override")
        exit_code, summary = self.run_gate(root)
        self.assertEqual(exit_code, 0)
        self.assertEqual(summary["status"], merge_gate.OVERRIDE)
        self.assertEqual(len(summary["overridden"]), 1)
        self.assertEqual(summary["overridden"][0]["signature"], "unit:PlaybackTests/testSeek")


if __name__ == "__main__":
    unittest.main()
