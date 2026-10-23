#!/usr/bin/env python3

from __future__ import annotations

import argparse
import contextlib
import fcntl
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import run_verification as verification


@contextlib.contextmanager
def captured():
    """Keep the guards' expected complaints out of the enclosing gate log.

    These tests run as one of the gate's own structure checks, so anything
    they print lands in a passing run's log and reads like a real failure.
    """
    stream = io.StringIO()
    with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
        yield stream


class CheckTagTests(unittest.TestCase):
    def test_every_check_carries_three_known_tags(self) -> None:
        checks = verification.STRUCTURE_CHECKS + verification.discovered_test_checks()
        self.assertGreater(len(checks), 100)
        self.assertEqual(verification.untagged(checks), [])

    def test_a_new_registered_check_without_a_tag_is_reported(self) -> None:
        untagged = verification.StructureCheck("a-new-check", "verify_a_new_check.py")
        self.assertEqual(verification.untagged((untagged,)), ["a-new-check"])

    def test_a_discovered_check_carries_the_default_tags(self) -> None:
        check = verification.discovered_check("test-something", "tests/test_something.py")
        self.assertEqual(
            (check.environment, check.authority, check.attribution),
            verification.DISCOVERED_TAGS,
        )

    def test_a_discovered_check_can_override_its_environment(self) -> None:
        check = verification.discovered_check(
            "test-regression-environment-preflight",
            "../verification/tests/test_regression_environment_preflight.py",
        )
        self.assertEqual(check.environment, "services")
        self.assertEqual(check.authority, "precondition")

    def test_failures_name_the_attribution_and_the_environment(self) -> None:
        self.assertIn("product", verification.ATTRIBUTIONS)
        self.assertIn("services", verification.ENVIRONMENTS)


class StepSilenceGuardTests(unittest.TestCase):
    """The gate holds one lock for every worktree while a step runs.

    A step that stops emitting without exiting used to block the read loop
    forever, so the holder never released and every later run and every push
    queued behind it in silence.
    """

    def test_a_step_that_stops_emitting_is_terminated_with_its_subtree(self) -> None:
        original = verification.STEP_SILENCE_SECONDS
        verification.STEP_SILENCE_SECONDS = 2
        marker = f"verification-silence-probe-{os.getpid()}"
        try:
            with tempfile.TemporaryDirectory() as scratch, captured():
                started = time.monotonic()
                code, output = verification.run_logged(
                    "silence probe",
                    ["/bin/sh", "-c", f"echo alive; exec sleep 600 # {marker}"],
                    Path(scratch) / "step.log",
                    os.environ.copy(),
                )
        finally:
            verification.STEP_SILENCE_SECONDS = original

        self.assertEqual(code, 124)
        self.assertLess(time.monotonic() - started, 30)
        self.assertIn("alive", output)
        self.assertIn("no output for", output)
        survivors = subprocess.run(
            ["/usr/bin/pgrep", "-f", marker],
            capture_output=True,
            text=True,
        )
        self.assertEqual(survivors.stdout.strip(), "")

    def test_a_step_that_finishes_normally_is_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as scratch, captured():
            code, output = verification.run_logged(
                "fast probe",
                ["/bin/echo", "done"],
                Path(scratch) / "step.log",
                os.environ.copy(),
            )
        self.assertEqual(code, 0)
        self.assertEqual(output, "done\n")


class PoisonedBuildDirectoryTests(unittest.TestCase):
    """A terminated `swift test` leaves the shared build directory wedged.

    Every later run inherited it and failed a different handful of
    timing-sensitive tests, which reads as a flaky product rather than as
    stale state carried over from a run that never finished.
    """

    @contextlib.contextmanager
    def scratch_at(self, directory: str, reported: tuple[int, str]):
        scratch = Path(directory) / "PlaybackCore"
        scratch.mkdir()
        (scratch / "wedged.o").write_text("stale", encoding="utf-8")
        original_scratch = verification.PLAYBACK_CORE_SCRATCH
        original_run_logged = verification.run_logged
        verification.PLAYBACK_CORE_SCRATCH = scratch
        verification.run_logged = lambda *arguments, **keywords: reported
        try:
            yield scratch
        finally:
            verification.PLAYBACK_CORE_SCRATCH = original_scratch
            verification.run_logged = original_run_logged

    def test_a_step_that_never_reports_discards_the_build_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.scratch_at(directory, (124, "")) as scratch:
                with captured():
                    result = verification.run_playback_core_tests(
                        Path(directory), {}, verification.load_baseline()
                    )
                self.assertEqual(result.state, "FAIL")
                self.assertIn("discarded the shared build directory", result.detail)
                self.assertFalse(scratch.exists())

    def test_a_step_that_reports_leaves_the_build_directory_alone(self) -> None:
        reported = (1, "Test run with 1 test in 1 suite failed after 0.1 seconds.")
        with tempfile.TemporaryDirectory() as directory:
            with self.scratch_at(directory, reported) as scratch:
                with captured():
                    result = verification.run_playback_core_tests(
                        Path(directory), {}, verification.load_baseline()
                    )
                self.assertEqual(result.state, "FAIL")
                self.assertNotIn("discarded", result.detail)
                self.assertTrue(scratch.exists())

    def test_playback_core_suite_is_forced_to_run_serially(self) -> None:
        recorded: list[str] = []

        def run_logged(*arguments, **keywords):
            recorded.extend(arguments[1])
            return (
                0,
                "Test run with 1 test in 1 suite passed after 0.1 seconds.\n",
            )

        with tempfile.TemporaryDirectory() as directory:
            original_scratch = verification.PLAYBACK_CORE_SCRATCH
            original_run_logged = verification.run_logged
            verification.PLAYBACK_CORE_SCRATCH = Path(directory) / "PlaybackCore"
            verification.run_logged = run_logged
            try:
                result = verification.run_playback_core_tests(
                    Path(directory), {}, verification.load_baseline()
                )
            finally:
                verification.PLAYBACK_CORE_SCRATCH = original_scratch
                verification.run_logged = original_run_logged

        self.assertEqual(result.state, "PASS")
        self.assertIn("--no-parallel", recorded)


class LockWaitGuardTests(unittest.TestCase):
    def test_a_held_lock_names_its_holder_and_gives_up(self) -> None:
        original = verification.LOCK_WAIT_SECONDS
        verification.LOCK_WAIT_SECONDS = 2
        try:
            with tempfile.TemporaryDirectory() as scratch:
                lock_path = Path(scratch) / ".verification.lock"
                holder = subprocess.Popen(
                    [
                        sys.executable,
                        "-c",
                        "import fcntl, sys, time;"
                        f" f = open({str(lock_path)!r}, 'a+');"
                        " fcntl.flock(f, fcntl.LOCK_EX);"
                        " sys.stderr.write('ready\\n'); sys.stderr.flush();"
                        " time.sleep(60)",
                    ],
                    stderr=subprocess.PIPE,
                    text=True,
                )
                try:
                    self.assertEqual(holder.stderr.readline().strip(), "ready")
                    with captured() as complaint:
                        with lock_path.open("a+", encoding="utf-8") as lock:
                            self.assertFalse(verification.acquire_lock(lock, lock_path))
                    self.assertIn(str(holder.pid), complaint.getvalue())
                finally:
                    holder.kill()
                    holder.wait()
                    holder.stderr.close()
        finally:
            verification.LOCK_WAIT_SECONDS = original

    def test_a_free_lock_is_taken_without_waiting(self) -> None:
        with tempfile.TemporaryDirectory() as scratch, captured():
            lock_path = Path(scratch) / ".verification.lock"
            with lock_path.open("a+", encoding="utf-8") as lock:
                started = time.monotonic()
                self.assertTrue(verification.acquire_lock(lock, lock_path))
                self.assertLess(time.monotonic() - started, 1)
                fcntl.flock(lock, fcntl.LOCK_UN)


class InterpreterFloorTests(unittest.TestCase):
    """The gate ran for months under whichever python3 the caller's PATH held.

    On the self-hosted runner that was Xcode's 3.9, and ten structure checks
    failed with unrelated-looking tracebacks: zip() rejecting a keyword, unions
    unparseable, credentials unreadable. One configuration fault presented as
    ten defects, so the gate names it instead.
    """

    def test_an_interpreter_below_the_floor_is_refused_by_version(self) -> None:
        refusal = verification.interpreter_refusal((3, 9, 6), "/usr/bin/python3")
        self.assertIsNotNone(refusal)
        self.assertIn("3.9.6", refusal)
        self.assertIn("/usr/bin/python3", refusal)
        self.assertIn("zip(strict=True)", refusal)

    def test_the_floor_itself_and_anything_above_it_is_accepted(self) -> None:
        self.assertIsNone(
            verification.interpreter_refusal(verification.MINIMUM_PYTHON, "python3")
        )
        self.assertIsNone(verification.interpreter_refusal((3, 14, 6), "python3"))

    def test_gate_configuration_refuses_before_it_reads_the_toolchain(self) -> None:
        original = verification.interpreter_refusal
        verification.interpreter_refusal = lambda version, executable: "stale python"
        try:
            with self.assertRaisesRegex(ValueError, "stale python"):
                verification.tool_environment()
        finally:
            verification.interpreter_refusal = original




class PrePushHookTests(unittest.TestCase):
    def run_hook(self, stdin: str) -> tuple[subprocess.CompletedProcess, Path, Path]:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        subprocess.run(
            ["git", "init", "-q"],
            cwd=root,
            check=True,
            capture_output=True,
        )
        console = root / "Scripts" / "console"
        console.mkdir(parents=True)
        marker = root / "verification-ran"
        arguments = root / "verification-arguments"
        script = console / "cli.py"
        script.write_text(
            "import sys\n"
            "from pathlib import Path\n"
            f"Path({str(marker)!r}).touch()\n"
            f"Path({str(arguments)!r}).open('a').write(' '.join(sys.argv[1:]) + '\\n')\n",
            encoding="utf-8",
        )
        binaries = root / "bin"
        binaries.mkdir()
        lfs = binaries / "git-lfs"
        lfs.write_text(f'#!/bin/sh\ncat > "{root / "lfs-input"}"\nprintf "%s\\n" "$*" > "{root / "lfs-args"}"\n', encoding="utf-8")
        lfs.chmod(0o755)
        environment = dict(os.environ, PATH=f"{binaries}{os.pathsep}{os.environ['PATH']}")
        hook = Path(__file__).resolve().parents[3] / ".githooks" / "pre-push"
        result = subprocess.run(
            ["/bin/zsh", str(hook), "origin", "git@example.com:repo.git"],
            cwd=root,
            input=stdin,
            capture_output=True,
            text=True,
            env=environment,
        )
        return result, marker, arguments

    def test_a_push_of_only_deletions_still_runs_the_ci(self) -> None:
        zero = "0" * 40
        oid = "a" * 40
        stdin = (
            f"(delete) {zero} refs/heads/old-branch {oid}\n"
            f"(delete) {zero} refs/tags/old-tag {oid}\n"
        )
        result, marker, arguments = self.run_hook(stdin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(marker.exists())
        self.assertIn("--changed-list", arguments.read_text())

    def test_a_branch_update_runs_verification(self) -> None:
        zero = "0" * 40
        oid = "b" * 40
        stdin = f"refs/heads/main {oid} refs/heads/main {zero}\n"
        result, marker, arguments = self.run_hook(stdin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(marker.exists())
        calls = arguments.read_text().splitlines()
        self.assertEqual(calls[0], "plan check")
        self.assertIn("--event push", calls[1])
        self.assertIn(f"--remote-oid {zero}", calls[1])
        self.assertIn(f"--local-oid {oid}", calls[1])

    def test_a_mixed_push_still_runs_verification(self) -> None:
        zero = "0" * 40
        oid = "c" * 40
        stdin = (
            f"(delete) {zero} refs/heads/old-branch {oid}\n"
            f"refs/heads/main {oid} refs/heads/main {zero}\n"
        )
        result, marker, arguments = self.run_hook(stdin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(marker.exists())
        self.assertEqual((marker.parent / "lfs-input").read_text(), stdin)
        self.assertEqual(
            (marker.parent / "lfs-args").read_text().strip(),
            "pre-push origin git@example.com:repo.git",
        )

    def test_an_empty_push_runs_neither_verification_nor_lfs(self) -> None:
        result, marker, arguments = self.run_hook("")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertFalse(arguments.exists())
        self.assertFalse((marker.parent / "lfs-input").exists())


class PreCommitHookTests(unittest.TestCase):
    def run_hook(self) -> tuple[subprocess.CompletedProcess, Path]:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        subprocess.run(
            ["git", "init", "-q"],
            cwd=root,
            check=True,
            capture_output=True,
        )
        console = root / "Scripts" / "console"
        console.mkdir(parents=True)
        marker = root / "verification-ran"
        script = console / "cli.py"
        script.write_text(
            "import sys\n"
            "from pathlib import Path\n"
            f"Path({str(marker)!r}).open('a').write(' '.join(sys.argv[1:]) + '\\n')\n",
            encoding="utf-8",
        )
        hook = Path(__file__).resolve().parents[3] / ".githooks" / "pre-commit"
        result = subprocess.run(
            ["/bin/zsh", str(hook)],
            cwd=root,
            capture_output=True,
            text=True,
        )
        return result, marker

    def test_the_commit_hook_checks_the_plan_and_the_staged_diff(self) -> None:
        result, marker = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = marker.read_text().splitlines()
        self.assertEqual(len(calls), 2, calls)
        self.assertEqual(calls[0], "plan check")
        self.assertIn("tier static", calls[1])
        self.assertIn("--event commit", calls[1])


class ChangeScopeTests(unittest.TestCase):
    def test_infrastructure_paths_force_the_tooling_self_tests(self) -> None:
        for path in (
            "Scripts/rules/run_verification.py",
            "Scripts/console/cli.py",
            ".github/workflows/verification.yml",
            ".githooks/pre-push",
            "Config/console/units/static-comment-rule.md",
            "Regression/journeys/presentation-tour/scenarios/format-application-route.md",
            ".swiftlint.yml",
        ):
            self.assertTrue(
                verification.infrastructure_changed(frozenset({path})), path
            )

    def test_product_and_document_paths_leave_the_tooling_self_tests_skipped(self) -> None:
        for path in (
            "Apps/Enchron/PlayerView.swift",
            "Tests/EnchronDomainTests/PlaybackTests.swift",
            "docs/CONTEXT.md",
            "Samples/DynamicRange/HLG/example.ts",
        ):
            self.assertFalse(
                verification.infrastructure_changed(frozenset({path})), path
            )

    def test_a_self_test_is_recognized_by_its_target(self) -> None:
        self_test = verification.discovered_check("test-something", "tests/test_something.py")
        checker = verification.StructureCheck("verify-something", "verify_something.py")
        self.assertTrue(verification.is_self_test(self_test))
        self.assertFalse(verification.is_self_test(checker))

    def test_unchanged_tooling_skips_every_self_test(self) -> None:
        self_test = verification.discovered_check("test-something", "tests/test_something.py")
        checker = verification.StructureCheck("verify-something", "verify_something.py")
        checks = (self_test, checker)
        skipped = verification.skipped_tooling_self_tests(
            checks, frozenset({"Apps/Enchron/PlayerView.swift"})
        )
        self.assertEqual(skipped, frozenset({"test-something"}))

    def test_changed_tooling_runs_every_self_test(self) -> None:
        self_test = verification.discovered_check("test-something", "tests/test_something.py")
        checker = verification.StructureCheck("verify-something", "verify_something.py")
        self.assertEqual(
            verification.skipped_tooling_self_tests(
                (self_test, checker), frozenset({"Scripts/rules/verify_something.py"})
            ),
            frozenset(),
        )

    def test_an_unknown_diff_runs_every_self_test(self) -> None:
        self_test = verification.discovered_check("test-something", "tests/test_something.py")
        self.assertEqual(
            verification.skipped_tooling_self_tests((self_test,), None), frozenset()
        )

    def test_a_changed_list_file_names_each_path(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "changed.txt"
            path.write_text("Scripts/a.py\n\n Apps/b.swift \n", encoding="utf-8")
            self.assertEqual(
                verification.listed_changed_paths(str(path)),
                frozenset({"Scripts/a.py", "Apps/b.swift"}),
            )

    def test_an_explicit_changed_list_wins_over_the_event_scope(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "changed.txt"
            path.write_text("Scripts/a.py\n", encoding="utf-8")
            arguments = argparse.Namespace(
                event="commit",
                changed_list=str(path),
                changed_staged=False,
                changed_since="",
                remote_oid="",
                base_ref="main",
                local_oid="HEAD",
            )
            self.assertEqual(
                verification.requested_changes(arguments, {}),
                frozenset({"Scripts/a.py"}),
            )

    def test_console_tests_are_discovered_as_self_tests(self) -> None:
        checks = tuple(
            check
            for check in verification.discovered_test_checks()
            if check.filename.startswith("../console/tests/")
        )
        self.assertGreaterEqual(len(checks), 7)
        self.assertTrue(all(verification.is_self_test(check) for check in checks))

    def test_an_unreadable_changed_list_is_unknown(self) -> None:
        self.assertIsNone(verification.listed_changed_paths("/nonexistent/changed.txt"))

    def test_an_empty_changed_list_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "changed.txt"
            path.write_text("\n", encoding="utf-8")
            self.assertEqual(verification.listed_changed_paths(str(path)), frozenset())


class EventScopeTests(unittest.TestCase):
    def repository(self) -> Path:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        self.git(root, "init", "-q", "-b", "main")
        self.git(root, "config", "user.email", "tests@example.com")
        self.git(root, "config", "user.name", "tests")
        return root

    def git(self, root: Path, *arguments: str) -> subprocess.CompletedProcess:
        environment = dict(os.environ)
        for name in (
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_INDEX_FILE",
            "GIT_COMMON_DIR",
            "GIT_PREFIX",
        ):
            environment.pop(name, None)
        environment["GIT_EDITOR"] = "true"
        return subprocess.run(
            ["git", *arguments],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )

    def write_and_commit(self, root: Path, name: str, content: str) -> str:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        self.git(root, "add", name)
        self.git(root, "commit", "-q", "-m", name)
        return self.git(root, "rev-parse", "HEAD").stdout.strip()

    def changed(self, root: Path, event: str, **arguments: str) -> frozenset[str] | None:
        return verification.event_changed_paths(
            event,
            dict(os.environ),
            repository=root,
            **arguments,
        )

    def test_a_commit_compares_the_index_with_head(self) -> None:
        root = self.repository()
        self.write_and_commit(root, "tracked.txt", "one\n")
        (root / "staged.txt").write_text("two\n", encoding="utf-8")
        (root / "unstaged.txt").write_text("three\n", encoding="utf-8")
        self.git(root, "add", "staged.txt")
        self.assertEqual(
            self.changed(root, "commit"), frozenset({"staged.txt"})
        )

    def test_a_push_compares_the_remote_tip_with_the_pushed_revision(self) -> None:
        root = self.repository()
        first = self.write_and_commit(root, "first.txt", "one\n")
        second = self.write_and_commit(root, "second.txt", "two\n")
        self.assertEqual(
            self.changed(root, "push", remote_oid=first, local_oid=second),
            frozenset({"second.txt"}),
        )

    def test_a_new_branch_compares_the_merge_base_with_main(self) -> None:
        root = self.repository()
        first = self.write_and_commit(root, "first.txt", "one\n")
        second = self.write_and_commit(root, "second.txt", "two\n")
        self.git(root, "update-ref", "refs/remotes/origin/main", first)
        self.assertEqual(
            self.changed(
                root,
                "push",
                remote_oid="0" * 40,
                local_oid=second,
            ),
            frozenset({"second.txt"}),
        )

    def test_a_pull_request_compares_the_base_branch_merge_base_with_head(self) -> None:
        root = self.repository()
        first = self.write_and_commit(root, "first.txt", "one\n")
        second = self.write_and_commit(root, "second.txt", "two\n")
        self.git(root, "update-ref", "refs/remotes/origin/main", first)
        self.assertEqual(
            self.changed(root, "pr", base_ref="main", local_oid=second),
            frozenset({"second.txt"}),
        )

    def test_a_merge_compares_head_with_merge_head(self) -> None:
        root = self.repository()
        self.write_and_commit(root, "first.txt", "one\n")
        self.git(root, "checkout", "-q", "-b", "topic")
        self.write_and_commit(root, "topic.txt", "two\n")
        self.git(root, "checkout", "-q", "main")
        self.git(root, "merge", "--no-commit", "--no-ff", "topic")
        self.assertEqual(
            self.changed(root, "merge"), frozenset({"topic.txt"})
        )

    def test_an_unknown_event_has_no_scope(self) -> None:
        root = self.repository()
        self.assertIsNone(self.changed(root, "unknown"))


class StructureGroupTests(unittest.TestCase):
    def test_every_check_lands_in_exactly_one_group(self) -> None:
        checks = tuple(
            verification.discovered_check(f"check-{index}", f"verify_check_{index}.py")
            for index in range(10)
        ) + (
            verification.StructureCheck(
                "media-discovery-admission", "verify_media_discovery_admission.py"
            ),
            verification.StructureCheck(
                "playback-issue-ownership", "verify_playback_issue_ownership.py"
            ),
        )
        groups = verification.structure_groups(checks, 2)
        flat = [check.identifier for group in groups for check in group]
        self.assertEqual(len(flat), len(set(flat)))
        self.assertEqual(set(flat), {check.identifier for check in checks})

    def test_shared_lexer_partners_land_in_one_group(self) -> None:
        checks = tuple(
            verification.discovered_check(f"check-{index}", f"verify_check_{index}.py")
            for index in range(6)
        ) + (
            verification.StructureCheck(
                "media-discovery-admission", "verify_media_discovery_admission.py"
            ),
            verification.StructureCheck(
                "playback-issue-ownership", "verify_playback_issue_ownership.py"
            ),
        )
        groups = verification.structure_groups(checks, 2)
        holders = [
            group
            for group in groups
            if any(
                check.identifier in ("media-discovery-admission", "playback-issue-ownership")
                for check in group
            )
        ]
        self.assertEqual(len(holders), 1)
        identifiers = {check.identifier for check in holders[0]}
        self.assertIn("media-discovery-admission", identifiers)
        self.assertIn("playback-issue-ownership", identifiers)

    def test_unbatched_checks_are_left_to_the_worker_path(self) -> None:
        unbatched = verification.StructureCheck(
            "vision-test-suite-coverage", "verify_vision_test_suite_coverage.py"
        )
        bundled = verification.StructureCheck("verify-something", "verify_something.py")
        groups = verification.structure_groups((unbatched, bundled), 2)
        flat = [check.identifier for group in groups for check in group]
        self.assertEqual(flat, ["verify-something"])


class PreMergeCommitHookTests(unittest.TestCase):
    def run_hook(
        self, branch: str = "main", exit_code: int = 0
    ) -> tuple[subprocess.CompletedProcess, Path, Path]:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        subprocess.run(
            ["git", "init", "-q", "-b", branch],
            cwd=root,
            check=True,
            capture_output=True,
        )
        console = root / "Scripts" / "console"
        console.mkdir(parents=True)
        marker = root / "verification-ran"
        status_directory = root / ".scratch" / "console" / "merge-gate"
        status_directory.mkdir(parents=True)
        script = console / "cli.py"
        script.write_text(
            "import sys\n"
            "from pathlib import Path\n"
            f"Path({str(marker)!r}).open('a').write(' '.join(sys.argv[1:]) + '\\n')\n"
            f"Path({str(status_directory / 'status.txt')!r}).write_text('yellow (1 known)')\n"
            f"sys.exit({exit_code})\n",
            encoding="utf-8",
        )
        merge_msg = root / ".git" / "MERGE_MSG"
        merge_msg.write_text("Merge branch 'topic'\n", encoding="utf-8")
        hook = Path(__file__).resolve().parents[3] / ".githooks" / "pre-merge-commit"
        result = subprocess.run(
            ["/bin/zsh", str(hook)],
            cwd=root,
            capture_output=True,
            text=True,
        )
        return result, marker, merge_msg

    def test_the_merge_hook_runs_the_gate_and_records_the_status(self) -> None:
        result, marker, merge_msg = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(marker.read_text().strip(), "merge check")
        self.assertIn("Merge-gate: yellow (1 known)", merge_msg.read_text())

    def test_a_merge_off_main_does_not_run_the_gate(self) -> None:
        result, marker, merge_msg = self.run_hook(branch="feature")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertNotIn("Merge-gate:", merge_msg.read_text())

    def test_a_red_gate_aborts_the_merge_before_the_message_is_recorded(self) -> None:
        result, marker, merge_msg = self.run_hook(exit_code=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(marker.exists())
        self.assertNotIn("Merge-gate:", merge_msg.read_text())


class TreeHygieneTests(unittest.TestCase):
    def test_an_unchanged_worktree_passes(self) -> None:
        before = {"Scripts/verification/controller_timings.device.json": "abc"}
        result = verification.tree_hygiene(before, dict(before))
        self.assertEqual(result.state, "PASS")

    def test_a_file_the_run_rewrote_fails_by_name(self) -> None:
        before = {"Scripts/verification/controller_timings.device.json": "abc"}
        after = {"Scripts/verification/controller_timings.device.json": "def", "Scripts/x.py": "new"}
        result = verification.tree_hygiene(before, after)
        self.assertEqual(result.state, "FAIL")
        self.assertIn("controller_timings.device.json", result.detail)
        self.assertIn("Scripts/x.py", result.detail)

if __name__ == "__main__":
    unittest.main()
