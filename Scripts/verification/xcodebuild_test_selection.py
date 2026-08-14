#!/usr/bin/env python3

"""Resolves `-only-testing:` identifiers before a test run and reads how many
tests a finished run actually executed.

An `xcodebuild test` invocation whose `-only-testing:` filter matches nothing
exits zero and prints `** TEST EXECUTE SUCCEEDED **`. Nothing in the exit status,
and nothing in the terminal verdict line, separates that from a run where every
selected test passed. A Swift Testing function identifier carries its parentheses,
so `EnchronAppTests/someTest` selects nothing where `EnchronAppTests/someTest()`
selects one test, and the run that follows reports success having executed none.
An XCTest method is accepted with or without its parentheses, so the bare form is
not wrong everywhere, and an enumeration does not say which kind of test a name
belongs to. The enumerated form works for both, which is why it is demanded before
a run rather than inferred.

Reading the executed count is not sufficient either, because the count is split
across two reporters that do not know about each other. The XCTest reporter prints

    Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds

and Swift Testing prints its own

    Test run with 9 tests in 0 suites passed after 0.007 seconds.

A suite that is entirely Swift Testing therefore prints `Executed 0 tests` on a
completely successful run. The preserved pair in
`TestEvidence/dv76-verify-20260814` shows both logs carrying that line twice and
both ending in `** TEST EXECUTE SUCCEEDED **`; the nine tests that ran appear only
in the Swift Testing lines. Any rule that reads the XCTest counter alone condemns
the good run, and any rule that reads the exit status alone accepts the empty one.

Three entry points, ordered by how early they can stop a wrong conclusion:

  resolve   takes the identifiers a run is about to select and an enumeration of
            what exists, and fails when a filter matches nothing. This is the only
            one that fires before a run, so it is the only one that prevents the
            wrong conclusion rather than contradicting it afterwards.
  run       enumerates, resolves, refuses to launch xcodebuild when any filter
            matches nothing, and reads the verdict of the run it did launch,
            expecting the number of tests the filters resolved to.
  verdict   reads a finished log. Given an enumeration as well, it recovers the
            run's own `-only-testing:` arguments from its command line and holds
            the executed count against what those arguments select. Here the count
            is the authority: a run whose identifiers are not in the enumerated form
            but which executed tests is reported as having executed them.

Enumeration is read from `-enumerate-tests -test-enumeration-format json`. When
this script runs the enumeration itself it passes
`-test-enumeration-output-path`, because xcodebuild writes that JSON to stdout by
default and its own progress output interleaves into it mid-token: the preserved
`r5-test-enumeration.json` is cut in half through an identifier by a
`** TEST EXECUTE SUCCEEDED **` block. The parser here repairs that shape and says
that it did, since an identifier silently dropped by a damaged enumeration would
be reported as a filter matching nothing, which is the same wrong answer this
script exists to prevent, arriving from the opposite direction.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import difflib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).parent))

try:
    from enchron_artifact_paths import scratch_directory
except ModuleNotFoundError:
    # Only `run` needs somewhere to put a log. Resolving a selection and reading a
    # finished run are pure text, so a copy of this file carried on its own to
    # wherever a log is still does those two.
    scratch_directory = None  # type: ignore[assignment]

# How far past an unterminated identifier the salvage will look for the rest of
# it. The interleaved block in the preserved fixture is six lines; anything much
# longer is a different kind of damage and should be reported rather than guessed.
SALVAGE_LOOKAHEAD = 40

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

IDENTIFIER_COMPLETE = re.compile(r'^\s*"identifier"\s*:\s*"([^"]*)"\s*,?\s*$')
IDENTIFIER_OPEN = re.compile(r'^\s*"identifier"\s*:\s*"([^"]*)$')
IDENTIFIER_CLOSE = re.compile(r'^([^"]*)"\s*,?\s*$')
SECTION = re.compile(r'"(enabledTests|disabledTests)"\s*:')

ONLY_TESTING = re.compile(r"-only-testing:([^\s\"']+)")
SKIP_TESTING = re.compile(r"-skip-testing:([^\s\"']+)")

XCTEST_EXECUTED = re.compile(r"Executed (\d+) tests?, with (\d+) failures?")
SWIFT_TESTING_RUN = re.compile(
    r"Test run with (\d+) tests?(?: in (\d+) suites?)? (passed|failed)"
)
SWIFT_TESTING_CASE = re.compile(r'Test "(.*)" (passed|failed|skipped)\b')
TERMINAL_VERDICT = re.compile(r"\*\* TEST (?:EXECUTE )?(SUCCEEDED|FAILED) \*\*")

TEST_ACTIONS = ("test", "test-without-building", "build-for-testing")


# ---------------------------------------------------------------------------
# Enumeration


@dataclass(frozen=True)
class Enumeration:
    """What `-enumerate-tests` says exists, and how much of it survived reading."""

    identifiers: tuple[str, ...]
    disabled: tuple[str, ...]
    status: str
    repaired: tuple[str, ...] = ()
    damaged: tuple[str, ...] = ()
    source: Path | None = None

    @property
    def trustworthy(self) -> bool:
        """True when nothing was lost. A salvaged enumeration that needed no
        repair is still complete; only damage that could not be stitched back
        together leaves identifiers missing."""
        return not self.damaged

    def describe(self) -> str:
        parts = [f"{len(self.identifiers)} enumerated tests"]
        if self.disabled:
            parts.append(f"{len(self.disabled)} disabled")
        parts.append(self.status)
        if self.repaired:
            parts.append(f"{len(self.repaired)} identifier(s) repaired")
        if self.damaged:
            parts.append(f"{len(self.damaged)} identifier(s) LOST")
        return ", ".join(parts)


def parse_enumeration(text: str, source: Path | None = None) -> Enumeration:
    start = text.find("{")
    if start < 0:
        raise SystemExit(
            f"no JSON object in the enumeration output{f' at {source}' if source else ''}. "
            "It was probably written with -test-enumeration-format text; this script "
            "reads the json form."
        )
    try:
        payload, _ = json.JSONDecoder().raw_decode(text[start:])
    except json.JSONDecodeError:
        return salvage_enumeration(text, source)

    enabled: list[str] = []
    disabled: list[str] = []
    for value in payload.get("values", []):
        enabled.extend(entry["identifier"] for entry in value.get("enabledTests", []))
        disabled.extend(entry["identifier"] for entry in value.get("disabledTests", []))
    return Enumeration(
        identifiers=tuple(enabled),
        disabled=tuple(disabled),
        status="clean",
        source=source,
    )


def salvage_enumeration(text: str, source: Path | None) -> Enumeration:
    """Recovers identifiers from an enumeration that is not parseable as JSON.

    xcodebuild writes the enumeration to stdout by default and its own output goes
    to the same stream, so a capture can be interrupted in the middle of a token.
    An identifier line broken that way is stitched back to the line that closes it
    and counted as repaired; one that has no closing line is reported as lost, so a
    filter that then appears to match nothing can be told apart from a filter that
    really does."""
    lines = ANSI.sub("", text).splitlines()
    enabled: list[str] = []
    disabled: list[str] = []
    repaired: list[str] = []
    damaged: list[str] = []
    section = "enabledTests"
    index = 0
    while index < len(lines):
        line = lines[index]
        marker = SECTION.search(line)
        if marker is not None:
            section = marker.group(1)
        bucket = enabled if section == "enabledTests" else disabled

        complete = IDENTIFIER_COMPLETE.match(line)
        if complete is not None:
            bucket.append(complete.group(1))
            index += 1
            continue

        opened = IDENTIFIER_OPEN.match(line)
        if opened is not None:
            head = opened.group(1)
            stitched = None
            for offset in range(1, min(SALVAGE_LOOKAHEAD, len(lines) - index)):
                candidate = lines[index + offset]
                if '"identifier"' in candidate:
                    break
                closing = IDENTIFIER_CLOSE.match(candidate)
                if closing is not None and closing.group(1) != "":
                    stitched = head + closing.group(1)
                    index += offset
                    break
            if stitched is None:
                damaged.append(head)
            else:
                bucket.append(stitched)
                repaired.append(stitched)
        index += 1

    return Enumeration(
        identifiers=tuple(enabled),
        disabled=tuple(disabled),
        status="salvaged",
        repaired=tuple(repaired),
        damaged=tuple(damaged),
        source=source,
    )


def read_enumeration(path: Path) -> Enumeration:
    if not path.is_file():
        raise SystemExit(f"no enumeration to resolve against at {path}")
    return parse_enumeration(path.read_text(encoding="utf-8", errors="replace"), path)


def enumeration_arguments(passthrough: list[str], output: Path) -> list[str]:
    """The enumeration invocation for a set of xcodebuild arguments.

    Anything that already selects or skips tests is dropped, because the point is
    to learn what exists before deciding whether the selection names any of it,
    and `-test-enumeration-output-path` is passed so the JSON lands in its own
    file rather than interleaved into xcodebuild's progress output on stdout."""
    kept = [
        argument
        for argument in passthrough
        if not argument.startswith(("-only-testing", "-skip-testing"))
    ]
    return [
        *kept,
        "-enumerate-tests",
        "-test-enumeration-style",
        "flat",
        "-test-enumeration-format",
        "json",
        "-test-enumeration-output-path",
        str(output),
    ]


# ---------------------------------------------------------------------------
# Selection


def selects(test_filter: str, identifier: str) -> bool:
    """Whether one `-only-testing:` value selects one enumerated test.

    The value is a path of components, and it selects every identifier it is a
    prefix of at a component boundary: a target, a suite within it, or one test.
    `EnchronAppTests/someTest` and `EnchronAppTests/someTest()` differ in their
    last component and so select different things, which is the whole hazard."""
    wanted = test_filter.split("/")
    available = identifier.split("/")
    return len(wanted) <= len(available) and available[: len(wanted)] == wanted


@dataclass
class Resolution:
    test_filter: str
    matched: tuple[str, ...]
    disabled: tuple[str, ...] = ()
    repair: str | None = None
    near: tuple[str, ...] = ()

    @property
    def ok(self) -> bool:
        return bool(self.matched)


def component_prefixes(identifiers: tuple[str, ...]) -> list[str]:
    prefixes: set[str] = set()
    for identifier in identifiers:
        components = identifier.split("/")
        for depth in range(1, len(components) + 1):
            prefixes.add("/".join(components[:depth]))
    return sorted(prefixes)


def resolve(filters: list[str], enumeration: Enumeration) -> list[Resolution]:
    prefixes = component_prefixes(enumeration.identifiers)
    resolutions: list[Resolution] = []
    for test_filter in filters:
        matched = tuple(
            identifier
            for identifier in enumeration.identifiers
            if selects(test_filter, identifier)
        )
        disabled = tuple(
            identifier
            for identifier in enumeration.disabled
            if selects(test_filter, identifier)
        )
        repair = None
        near: tuple[str, ...] = ()
        if not matched:
            # The parentheses are the common case by a wide margin, so they are
            # offered as a repair rather than as one guess among several.
            candidate = f"{test_filter}()"
            if any(selects(candidate, name) for name in enumeration.identifiers):
                repair = candidate
            else:
                near = tuple(difflib.get_close_matches(test_filter, prefixes, n=3, cutoff=0.6))
        resolutions.append(
            Resolution(
                test_filter=test_filter,
                matched=matched,
                disabled=disabled,
                repair=repair,
                near=near,
            )
        )
    return resolutions


def report_resolutions(resolutions: list[Resolution], enumeration: Enumeration) -> list[str]:
    problems: list[str] = []
    for resolution in resolutions:
        if resolution.ok:
            print(f"  ok   {resolution.test_filter} -> {len(resolution.matched)} test(s)")
            if resolution.disabled:
                print(f"       {len(resolution.disabled)} of them are disabled and will not run")
            continue
        print(f"  FAIL {resolution.test_filter} -> nothing")
        if resolution.repair is not None:
            # An XCTest method is accepted with or without its parentheses, so this
            # form is not always fatal. A Swift Testing function is not, and nothing
            # in an enumeration says which kind a name is. The enumerated form is
            # accepted by both, so it is demanded rather than guessed at.
            detail = [
                f"-only-testing:{resolution.test_filter} is not an enumerated identifier. "
                f"A Swift Testing function selects nothing without its parentheses and the "
                f"run reports success having executed none; an XCTest method is accepted "
                f"either way. Which this is cannot be read off an enumeration."
            ]
        else:
            detail = [
                f"-only-testing:{resolution.test_filter} selects no enumerated test, so a "
                "run carrying it reports success having executed nothing for it."
            ]
        if resolution.disabled:
            detail.append(
                f"       it does select {len(resolution.disabled)} disabled test(s), which "
                "will not run: " + ", ".join(resolution.disabled[:3])
            )
            print(f"       selects only disabled tests: {resolution.disabled[0]}")
        if resolution.repair is not None:
            detail.append(f"       write {resolution.repair} instead; both accept that form")
            print(f"       write {resolution.repair} instead")
        elif resolution.near:
            detail.append("       nearest enumerated names: " + ", ".join(resolution.near))
            print("       nearest: " + ", ".join(resolution.near))
        if not enumeration.trustworthy:
            detail.append(
                "       the enumeration this was resolved against lost "
                f"{len(enumeration.damaged)} identifier(s) to a damaged capture, so this "
                "filter may in fact be fine. Re-enumerate with "
                "-test-enumeration-output-path before believing this."
            )
        problems.append("\n".join(detail))
    return problems


def selected_identifiers(resolutions: list[Resolution]) -> tuple[str, ...]:
    union: list[str] = []
    for resolution in resolutions:
        for identifier in resolution.matched:
            if identifier not in union:
                union.append(identifier)
    return tuple(union)


# ---------------------------------------------------------------------------
# Reading a finished run


@dataclass
class RunVerdict:
    """What a finished log says ran, counted from both reporters separately."""

    xctest_executed: int = 0
    xctest_failures: int = 0
    swift_testing_executed: int = 0
    swift_testing_failed: int = 0
    swift_testing_runs: int = 0
    swift_testing_started: bool = False
    cases_passed: int = 0
    cases_failed: int = 0
    cases_skipped: int = 0
    marker: str | None = None
    only_testing: tuple[str, ...] = ()
    skip_testing: tuple[str, ...] = ()

    @property
    def executed(self) -> int:
        return self.xctest_executed + self.swift_testing_executed

    @property
    def failures(self) -> int:
        return self.xctest_failures + self.swift_testing_failed


def command_line_block(lines: list[str]) -> list[str]:
    """The `Command line invocation:` block, which is where a log records the
    arguments it was given. Falling back to the whole log would pick up
    `-only-testing:` strings quoted inside unrelated output."""
    for index, line in enumerate(lines):
        if line.startswith("Command line invocation:"):
            block = []
            for candidate in lines[index + 1 :]:
                if candidate.strip() == "":
                    break
                block.append(candidate)
            return block
    return lines


def read_verdict(text: str) -> RunVerdict:
    lines = ANSI.sub("", text).splitlines()
    verdict = RunVerdict()

    block = "\n".join(command_line_block(lines))
    verdict.only_testing = tuple(dict.fromkeys(ONLY_TESTING.findall(block)))
    verdict.skip_testing = tuple(dict.fromkeys(SKIP_TESTING.findall(block)))

    executed_counts: list[tuple[int, int]] = []
    for line in lines:
        executed = XCTEST_EXECUTED.search(line)
        if executed is not None:
            executed_counts.append((int(executed.group(1)), int(executed.group(2))))

        run = SWIFT_TESTING_RUN.search(line)
        if run is not None:
            verdict.swift_testing_executed += int(run.group(1))
            verdict.swift_testing_runs += 1
            if run.group(3) == "failed":
                verdict.swift_testing_failed += 1
            continue

        if "Test run started" in line:
            verdict.swift_testing_started = True

        case = SWIFT_TESTING_CASE.search(line)
        if case is not None:
            outcome = case.group(2)
            if outcome == "passed":
                verdict.cases_passed += 1
            elif outcome == "failed":
                verdict.cases_failed += 1
            else:
                verdict.cases_skipped += 1

        terminal = TERMINAL_VERDICT.search(line)
        if terminal is not None:
            verdict.marker = terminal.group(1)

    # The XCTest reporter nests: each bundle prints its own total and the
    # enclosing 'Selected tests' or 'All tests' suite prints the aggregate. The
    # largest is that aggregate; summing would count the inner suites twice.
    if executed_counts:
        verdict.xctest_executed = max(count for count, _ in executed_counts)
        verdict.xctest_failures = max(failures for _, failures in executed_counts)
    return verdict


def judge(verdict: RunVerdict, expected: int | None) -> tuple[list[str], list[str]]:
    """Problems that make the run's result unusable, and notes that do not."""
    problems: list[str] = []
    notes: list[str] = []

    if verdict.marker is None:
        problems.append(
            "the log has no ** TEST SUCCEEDED ** or ** TEST FAILED ** line, so the run "
            "did not finish and whatever it printed is a partial result."
        )
    elif verdict.marker == "FAILED":
        problems.append("xcodebuild reported ** TEST FAILED **.")

    # Independent of the count below: a run cut off before Swift Testing reported
    # its total also reads as zero executed, and the two say different things about
    # what to do next, so both are stated when both are true.
    if verdict.swift_testing_started and verdict.swift_testing_runs == 0:
        problems.append(
            "Swift Testing announced a run and never reported its total, so it was cut "
            "off part way and its tests are not accounted for."
        )

    if verdict.executed == 0:
        problems.append(
            "the run executed no tests at all: the XCTest reporter counted "
            f"{verdict.xctest_executed} and Swift Testing counted "
            f"{verdict.swift_testing_executed}. "
            + (
                "Its -only-testing arguments matched nothing. "
                if verdict.only_testing
                else ""
            )
            + "A terminal verdict of SUCCEEDED here means only that nothing failed, "
            "because nothing ran."
        )

    if verdict.failures:
        # xcodebuild's own terminal verdict decides whether a run passed, and it is
        # checked above. A count of failures alongside a SUCCEEDED verdict is what
        # -retry-tests-on-failure produces when a test failed once and then passed,
        # so it is surfaced rather than treated as a contradiction.
        notes.append(
            f"{verdict.failures} failure(s) appear in the log: {verdict.xctest_failures} "
            f"counted by XCTest, {verdict.swift_testing_failed} Swift Testing run(s) "
            f"reported as failed. The terminal verdict is {verdict.marker or 'absent'}."
        )

    if expected is not None:
        if verdict.executed < expected:
            problems.append(
                f"the selection resolves to {expected} test(s) and the run executed "
                f"{verdict.executed}."
            )
        elif verdict.executed > expected:
            # A parameterized Swift Testing function enumerates once and runs once
            # per argument, so more is normal and only less is a problem.
            notes.append(
                f"the run executed {verdict.executed} test(s) against {expected} selected "
                "identifier(s), which is what a parameterized test does."
            )
    return problems, notes


def report_verdict(verdict: RunVerdict) -> None:
    print(f"  XCTest reporter        {verdict.xctest_executed} executed, {verdict.xctest_failures} failed")
    print(
        f"  Swift Testing reporter {verdict.swift_testing_executed} executed across "
        f"{verdict.swift_testing_runs} run(s), {verdict.swift_testing_failed} run(s) failed"
    )
    if verdict.cases_passed or verdict.cases_failed or verdict.cases_skipped:
        print(
            f"  Swift Testing cases    {verdict.cases_passed} passed, "
            f"{verdict.cases_failed} failed, {verdict.cases_skipped} skipped"
        )
    print(f"  terminal verdict       {verdict.marker or 'absent'}")
    print(f"  executed, both         {verdict.executed}")


# ---------------------------------------------------------------------------
# Commands


def finish(problems: list[str], notes: list[str]) -> None:
    for note in notes:
        print(f"note {note}")
    print()
    for problem in problems:
        print(f"FAIL {problem}", file=sys.stderr)
    raise SystemExit(1 if problems else 0)


def command_resolve(arguments: argparse.Namespace) -> None:
    enumeration = read_enumeration(arguments.enumeration)
    filters = list(arguments.test)
    if arguments.log is not None:
        filters.extend(read_verdict(arguments.log.read_text(encoding="utf-8", errors="replace")).only_testing)
    if not filters:
        raise SystemExit(
            "nothing to resolve: pass --test, or --log to take the selection from a "
            "run's own command line."
        )
    print(f"resolving {len(filters)} selection(s) against {enumeration.describe()}")
    if enumeration.damaged:
        print(f"  note enumeration lost: {', '.join(enumeration.damaged)}")
    problems = report_resolutions(resolve(filters, enumeration), enumeration)
    finish(problems, [])


def command_verdict(arguments: argparse.Namespace) -> None:
    if not arguments.log.is_file():
        raise SystemExit(f"no run log to read at {arguments.log}")
    verdict = read_verdict(arguments.log.read_text(encoding="utf-8", errors="replace"))
    print(f"reading {arguments.log}")
    report_verdict(verdict)

    expected = arguments.expect
    problems: list[str] = []
    notes: list[str] = []
    if arguments.enumeration is not None:
        enumeration = read_enumeration(arguments.enumeration)
        if verdict.only_testing:
            print(f"\nselection recovered from the log, against {enumeration.describe()}")
            resolutions = resolve(list(verdict.only_testing), enumeration)
            unresolved = report_resolutions(resolutions, enumeration)
            if unresolved and verdict.executed > 0:
                # The run happened. Whatever the identifiers look like, tests ran, and
                # the count is the authority on that. Demanding the enumerated form is
                # worth doing before a run, where there is no count yet; afterwards it
                # would be reporting a run that worked as a failure.
                notes.append(
                    f"{len(unresolved)} of the log's selections are not written in the "
                    f"enumerated form, but {verdict.executed} test(s) ran, so this is a "
                    "note about how they were written and not about what happened."
                )
            else:
                problems.extend(unresolved)
            # Only a fully resolved selection gives a number worth holding the run to;
            # a partial one would understate what should have run and hide a shortfall.
            if expected is None and not unresolved:
                expected = len(selected_identifiers(resolutions))
        else:
            print("\nthe log carries no -only-testing arguments; it ran the whole plan")
            if expected is None and enumeration.trustworthy and not verdict.skip_testing:
                expected = len(enumeration.identifiers)

    print()
    verdict_problems, verdict_notes = judge(verdict, expected)
    finish(problems + verdict_problems, notes + verdict_notes)


def command_run(arguments: argparse.Namespace) -> None:
    if not arguments.passthrough:
        raise SystemExit(
            "pass the xcodebuild arguments after --, without any -only-testing."
        )
    xcodebuild = shutil.which(arguments.xcodebuild) or arguments.xcodebuild
    if arguments.keep_enumeration is None or arguments.log is None:
        if scratch_directory is None:
            raise SystemExit(
                "this copy of the script cannot find enchron_artifact_paths.py beside it, "
                "so it has nowhere of its own to put the enumeration and the run log. Pass "
                "--keep-enumeration and --log, or run the copy in Scripts/verification."
            )
        scratch = scratch_directory("xcodebuild-test-selection")
    enumeration_path = arguments.keep_enumeration or (scratch / "enumeration.json")
    log_path = arguments.log or (scratch / "test-run.log")

    print(f"enumerating into {enumeration_path}")
    command = [xcodebuild, *enumeration_arguments(list(arguments.passthrough), enumeration_path)]
    completed = subprocess.run(command, check=False, text=True, capture_output=True)
    if not enumeration_path.is_file():
        raise SystemExit(
            "the enumeration did not produce a file, so there is nothing to resolve the "
            f"selection against:\n{completed.stderr or completed.stdout}"
        )
    enumeration = read_enumeration(enumeration_path)
    print(f"  {enumeration.describe()}")

    print(f"\nresolving {len(arguments.test)} selection(s)")
    resolutions = resolve(list(arguments.test), enumeration)
    problems = report_resolutions(resolutions, enumeration)
    if problems:
        print(
            "\nrefusing to launch xcodebuild: a filter that selects nothing produces a "
            "run that reports success having executed nothing.",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"FAIL {problem}", file=sys.stderr)
        raise SystemExit(2)

    expected = len(selected_identifiers(resolutions))
    launch = [
        xcodebuild,
        *arguments.passthrough,
        *[f"-only-testing:{name}" for name in arguments.test],
    ]
    print(f"\nlaunching, expecting {expected} test(s), log at {log_path}")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as sink:
        process = subprocess.Popen(
            launch, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
        )
        assert process.stdout is not None
        for line in process.stdout:
            sink.write(line)
            if not arguments.quiet:
                sys.stdout.write(line)
        process.wait()

    print(f"\nreading {log_path}")
    verdict = read_verdict(log_path.read_text(encoding="utf-8", errors="replace"))
    report_verdict(verdict)
    print()
    verdict_problems, notes = judge(verdict, expected)
    if process.returncode != 0 and not verdict_problems:
        verdict_problems.append(f"xcodebuild exited {process.returncode}.")
    finish(verdict_problems, notes)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--xcodebuild",
        default="xcodebuild",
        help="The xcodebuild to invoke. Point this at a stand-in to exercise this "
        "script without a real build.",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    resolver = commands.add_parser(
        "resolve", help="Fail when a -only-testing identifier selects no enumerated test."
    )
    resolver.add_argument("--enumeration", type=Path, required=True)
    resolver.add_argument("--test", action="append", default=[])
    resolver.add_argument(
        "--log", type=Path, default=None, help="Take the selection from this run log."
    )
    resolver.set_defaults(handler=command_resolve)

    reader = commands.add_parser(
        "verdict", help="Fail when a finished run executed no tests, or fewer than it selected."
    )
    reader.add_argument("log", type=Path)
    reader.add_argument("--enumeration", type=Path, default=None)
    reader.add_argument("--expect", type=int, default=None)
    reader.set_defaults(handler=command_verdict)

    runner = commands.add_parser(
        "run", help="Enumerate, resolve, refuse or launch, then read the verdict."
    )
    runner.add_argument("--test", action="append", default=[], required=True)
    runner.add_argument("--log", type=Path, default=None)
    runner.add_argument("--keep-enumeration", type=Path, default=None)
    runner.add_argument("--quiet", action="store_true")
    runner.add_argument("passthrough", nargs=argparse.REMAINDER)
    runner.set_defaults(handler=command_run)

    arguments = parser.parse_args()
    if arguments.command == "run" and arguments.passthrough[:1] == ["--"]:
        arguments.passthrough = arguments.passthrough[1:]
    arguments.handler(arguments)


if __name__ == "__main__":
    main()
