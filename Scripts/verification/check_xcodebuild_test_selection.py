#!/usr/bin/env python3

"""Asserts that `xcodebuild_test_selection.py` tells a run that executed six tests
from a run that executed none, and that it refuses the second one before it is
launched.

An `xcodebuild test` invocation whose `-only-testing:` filter matches nothing
exits zero and prints `** TEST EXECUTE SUCCEEDED **`. A Swift Testing identifier
written without its parentheses does exactly that: `EnchronAppTests/someTest`
selects nothing where `EnchronAppTests/someTest()` selects one test. It has
happened four times in this repository, and the instruction written down after the
first three, read `Executed N` rather than the exit status, does not work, because
`Executed N` comes from the XCTest reporter and reads zero on a fully successful
Swift Testing run as well.

The pair in `Tests/Fixtures/xcodebuild-test-selection` is what makes that provable
rather than asserted. `swift-testing-bare-selection.log` selected six tests without
parentheses and ran none. `swift-testing-enumerated-selection.log` selected the same
six with parentheses and ran all six. Both print `Executed 0 tests, with 0 failures`
twice, and both end in `** TEST EXECUTE SUCCEEDED **`.

The Swift Testing pair alone leaves the XCTest reporter reading zero on both sides,
so three XCTest runs are read as well: one that passed, one that failed, and one
whose count carries a skipped clause. The passing one settles a question the pair
cannot: an XCTest method is accepted with or without its parentheses, and that run
selected its test in the bare form and executed it. So the bare form is not wrong
everywhere, and a guard that called that run a failure would be switched off within
a week. The enumerated form is demanded before a run, where there is no count yet
and no way to tell the two kinds of test apart; afterwards the count decides.

Where they came from. Each log is an `xcodebuild test-without-building` run of the
`Enchron` scheme against the visionOS simulator, cut down to the reporter, verdict
and `Command line invocation:` lines that any reading of it depends on. The failing
one selected a throwaway `XCTestCase` that called `XCTFail`, because no test in this
repository is meant to fail. `test-enumeration-salvaged.json` is the enumeration of
that same scheme with a block of xcodebuild's own progress output inserted through
one identifier, which is what a capture written to stdout instead of
`-test-enumeration-output-path` looks like.

Eight checks, because the parts fail independently:

  fixtures     the logs and the enumeration are present, since a pair that has been
               deleted leaves every check below passing vacuously.
  trap         the two obvious rules, the XCTest counter and the terminal verdict
               line, still read identically on both logs, so separating them is a
               decision this script makes and not something any reading would get
               right.
  enumeration  the enumeration is still interleaved mid-identifier by xcodebuild's
               own output, and every identifier survives reading it, including the
               one that was cut in half.
  identifiers  the six selections taken from each log's own command line resolve to
               nothing and to six respectively, and the parenthesised form is
               offered as the repair for each of the six that fail.
  verdict      the zero-test log fails and the real one passes, as exit codes,
               through the command line rather than through imported functions,
               including with no enumeration to resolve against, which is the only
               reading where the executed count alone has to carry the judgement.
  xctest       the nested `Executed 1 test` lines of an XCTest run aggregate to one
               rather than three, a run that selected its test in the bare form and
               executed it reads as a pass, and a run that failed still fails.
  preflight    driven end to end against a stand-in xcodebuild, the run wrapper
               refuses the parenthesis-less selection without launching a test run
               at all, and completes the correct one. This is the leg that matters:
               a check that only reads a finished log lets a wrong conclusion be
               written down first.
  truncation   a run cut off before its reporters finished does not read as a pass,
               so the guard cannot be satisfied by killing xcodebuild early.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import types

sys.path.insert(0, str(Path(__file__).parent))

from enchron_artifact_paths import scratch_directory

TOOL = Path(__file__).parent / "xcodebuild_test_selection.py"
FIXTURES = Path(__file__).resolve().parents[2] / "Tests/Fixtures/xcodebuild-test-selection"
ZERO_TEST_LOG = FIXTURES / "swift-testing-bare-selection.log"
REAL_LOG = FIXTURES / "swift-testing-enumerated-selection.log"
ENUMERATION = FIXTURES / "test-enumeration-salvaged.json"

# The Swift Testing pair leaves the XCTest reporter reading zero on both sides and so
# measures nothing about how it is read. These two do. One passed and one failed, and
# both print their count three times over nested suites.
XCTEST_LOG = FIXTURES / "xctest-passing.log"
FAILED_LOG = FIXTURES / "xctest-failing.log"
XCTEST_NESTED_LINES = 3
# The bare identifier the passing run selected and executed, and the enumerated form
# that has to be demanded before a run even though this one worked without it.
XCTEST_BARE_IDENTIFIER = (
    "EnchronAppTests/PlaybackSwitchStateRingTests/"
    "testCapacityRetainsEveryRecordThroughItsBoundary"
)

# A suite with an absent prerequisite prints its count as `Executed 6 tests, with 1
# test skipped and 0 failures`. That clause sits between the count and the failures,
# so a pattern written against the two-part form reads the whole run as zero and the
# guard stops a passing suite.
SKIPPED_LOG = FIXTURES / "xctest-skipped.log"
SKIPPED_EXECUTED = 6

ENUMERATED_TOTAL = 138
SELECTED = 6
# The identifier the interleaved block cuts in half in the salvaged enumeration.
REPAIRED_IDENTIFIER = (
    "EnchronAppUITests/SpatialHandoffUITests/"
    "testDockedTemporarilyUsesDefaultEnvironmentAndRestoresActiveEnvironmentOnReturn()"
)

STUB_SOURCE = '''#!/usr/bin/env python3
"""Stands in for xcodebuild so a selection can be resolved and a run driven with
no build and no device.

Models the two behaviours this guard exists for: an enumeration is written to the
path it is given, and a test action exits zero whether or not its selection
matched anything, replaying the captured log for whichever case it was asked for.
"""

import json
import os
from pathlib import Path
import shutil
import sys

state = Path(os.environ["ENCHRON_XCODEBUILD_STUB_STATE"])
enumeration = Path(os.environ["ENCHRON_XCODEBUILD_STUB_ENUMERATION"])
zero_log = Path(os.environ["ENCHRON_XCODEBUILD_STUB_ZERO_LOG"])
real_log = Path(os.environ["ENCHRON_XCODEBUILD_STUB_REAL_LOG"])

argv = sys.argv[1:]
selections = [a.split(":", 1)[1] for a in argv if a.startswith("-only-testing:")]
enumerating = "-enumerate-tests" in argv

with (state / "calls.jsonl").open("a") as sink:
    sink.write(json.dumps({"argv": argv, "enumerating": enumerating}) + "\\n")

if enumerating:
    if "-test-enumeration-output-path" in argv:
        destination = argv[argv.index("-test-enumeration-output-path") + 1]
        shutil.copyfile(enumeration, destination)
    else:
        sys.stdout.write(enumeration.read_text(encoding="utf-8", errors="replace"))
    sys.exit(0)

# The hazard itself: a selection that matches nothing is not an error here.
matched = selections and all(name.endswith("()") for name in selections)
sys.stdout.write((real_log if matched else zero_log).read_text(encoding="utf-8", errors="replace"))
sys.exit(0)
'''


def load_tool(path: Path) -> types.ModuleType:
    name = f"selection_{id(path)}"
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    # Registered before execution because dataclasses resolves a class's module
    # through sys.modules while the decorator runs.
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def executed_by_the_xctest_counter_alone(text: str) -> int:
    """The rule the note written after the first three occurrences prescribes: read
    `Executed N` rather than the exit status. Restated here so the pair can be shown
    to defeat it."""
    counts = [int(value) for value in re.findall(r"Executed (\d+) tests?, with \d+ failure", text)]
    return max(counts) if counts else 0


def succeeded_by_the_terminal_verdict_alone(text: str) -> bool:
    """The rule anyone reads first: what xcodebuild printed at the end."""
    return "** TEST EXECUTE SUCCEEDED **" in text or "** TEST SUCCEEDED **" in text


def stub_environment(scratch: Path) -> tuple[Path, Path, dict[str, str]]:
    """A wiped working directory for one run of this check. The leg below asserts
    that no run log exists for a refused selection, which a log left behind by the
    previous run would answer for."""
    state = scratch / "stub-state"
    state.mkdir(parents=True)
    stub = scratch / "xcodebuild-stub.py"
    stub.write_text(STUB_SOURCE, encoding="utf-8")
    stub.chmod(0o755)
    environment = dict(os.environ)
    environment.update(
        ENCHRON_XCODEBUILD_STUB_STATE=str(state),
        ENCHRON_XCODEBUILD_STUB_ENUMERATION=str(ENUMERATION),
        ENCHRON_XCODEBUILD_STUB_ZERO_LOG=str(ZERO_TEST_LOG),
        ENCHRON_XCODEBUILD_STUB_REAL_LOG=str(REAL_LOG),
    )
    return stub, state, environment


def stub_calls(state: Path) -> list[dict]:
    path = state / "calls.jsonl"
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--tool",
        type=Path,
        default=TOOL,
        help="The selection guard to check. Point this at an older copy to confirm "
        "this check still fails on the state it was written for.",
    )
    arguments = parser.parse_args()
    tool = arguments.tool.resolve()
    if not tool.is_file():
        raise SystemExit(f"no selection guard to check at {tool}")
    print(f"checking {tool}")

    failures: list[str] = []

    def require(leg: str, held: bool, ok: str, bad: str) -> bool:
        if held:
            print(f"  ok   {ok}")
            return True
        print(f"  FAIL {bad}")
        failures.append(f"{leg}: {bad}")
        return False

    print("\nfixtures")
    for label, path in (
        ("zero-test log", ZERO_TEST_LOG),
        ("real run log", REAL_LOG),
        ("enumeration", ENUMERATION),
        ("passing XCTest log", XCTEST_LOG),
        ("failing XCTest log", FAILED_LOG),
        ("skipping XCTest log", SKIPPED_LOG),
    ):
        require(
            "fixtures",
            path.is_file(),
            f"the {label} fixture is present",
            f"the {label} fixture is gone, so this check proves nothing: {path}",
        )
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        raise SystemExit(1)

    module = load_tool(tool)
    zero_text = ZERO_TEST_LOG.read_text(encoding="utf-8", errors="replace")
    real_text = REAL_LOG.read_text(encoding="utf-8", errors="replace")

    print("\ntrap")
    zero_counter = executed_by_the_xctest_counter_alone(zero_text)
    real_counter = executed_by_the_xctest_counter_alone(real_text)
    require(
        "trap",
        zero_counter == real_counter == 0,
        f"the XCTest counter reads {real_counter} on both logs, so it cannot separate them",
        f"the XCTest counter now reads {zero_counter} and {real_counter}, so the pair no "
        "longer demonstrates the reporting split and this check is crediting the guard "
        "for a distinction the obvious rule would also make. Find a pair that does "
        "reproduce it before trusting this check again.",
    )
    require(
        "trap",
        succeeded_by_the_terminal_verdict_alone(zero_text)
        and succeeded_by_the_terminal_verdict_alone(real_text),
        "both logs end in ** TEST EXECUTE SUCCEEDED **, so the terminal verdict cannot "
        "separate them either",
        "the two logs no longer end in the same terminal verdict, so the pair no longer "
        "demonstrates that the exit status is uninformative.",
    )

    print("\nenumeration")
    enumeration = module.read_enumeration(ENUMERATION)
    require(
        "enumeration",
        enumeration.status == "salvaged",
        "the enumeration fixture is still interleaved and still exercises the repair",
        f"the enumeration fixture now reads as {enumeration.status}, so the repair path "
        "for a capture interrupted mid-identifier is no longer exercised by any fixture.",
    )
    require(
        "enumeration",
        len(enumeration.identifiers) == ENUMERATED_TOTAL,
        f"all {ENUMERATED_TOTAL} identifiers survived reading a damaged capture",
        f"reading the enumeration produced {len(enumeration.identifiers)} identifiers "
        f"rather than {ENUMERATED_TOTAL}. An identifier dropped here is reported as a "
        "filter matching nothing, which is a false alarm of exactly the kind that "
        "teaches a driver to ignore this guard.",
    )
    require(
        "enumeration",
        REPAIRED_IDENTIFIER in enumeration.repaired
        and REPAIRED_IDENTIFIER in enumeration.identifiers,
        "the identifier cut in half by the interleaved block was stitched back together",
        f"the identifier the interleaved block splits was not recovered: "
        f"repaired {enumeration.repaired}",
    )
    require(
        "enumeration",
        not enumeration.damaged,
        "nothing was lost, so an unmatched filter can be believed",
        f"{len(enumeration.damaged)} identifier(s) were lost: {enumeration.damaged}",
    )

    print("\nidentifiers")
    without_parentheses = module.read_verdict(zero_text).only_testing
    with_parentheses = module.read_verdict(real_text).only_testing
    require(
        "identifiers",
        len(without_parentheses) == len(with_parentheses) == SELECTED,
        f"each log records the {SELECTED} selections it was given",
        f"recovered {len(without_parentheses)} and {len(with_parentheses)} selections from "
        f"the two logs rather than {SELECTED} each.",
    )
    require(
        "identifiers",
        all(not name.endswith("()") for name in without_parentheses)
        and all(name.endswith("()") for name in with_parentheses),
        "the two selections differ only in the trailing parentheses",
        "the two logs no longer differ only in the parentheses, so they are no longer a "
        "controlled pair for this hazard.",
    )

    bad = module.resolve(list(without_parentheses), enumeration)
    good = module.resolve(list(with_parentheses), enumeration)
    require(
        "identifiers",
        all(not resolution.ok for resolution in bad),
        f"all {SELECTED} parenthesis-less selections resolve to nothing",
        "a parenthesis-less selection resolved to something, so this guard would have let "
        f"the zero-test run launch: {[r.test_filter for r in bad if r.ok]}",
    )
    require(
        "identifiers",
        all(resolution.repair in enumeration.identifiers for resolution in bad),
        "each failure is reported with the parenthesised identifier that fixes it",
        "a failure was reported without the repair that fixes it, which leaves the driver "
        "to guess at the same thing that produced the mistake.",
    )
    require(
        "identifiers",
        all(len(resolution.matched) == 1 for resolution in good)
        and len(module.selected_identifiers(good)) == SELECTED,
        f"the {SELECTED} parenthesised selections resolve to exactly one test each",
        f"the parenthesised selections resolved to "
        f"{[len(r.matched) for r in good]}, so the guard would refuse a run that is "
        "correct, which is the failure that gets a guard switched off.",
    )

    print("\nverdict")
    for label, log, expected_code in (
        ("the zero-test log", ZERO_TEST_LOG, 1),
        ("the real run log", REAL_LOG, 0),
    ):
        completed = subprocess.run(
            [sys.executable, str(tool), "verdict", str(log), "--enumeration", str(ENUMERATION)],
            check=False,
            text=True,
            capture_output=True,
        )
        require(
            "verdict",
            completed.returncode == expected_code,
            f"{label} exits {completed.returncode}",
            f"{label} exits {completed.returncode} where {expected_code} was required. "
            f"stderr: {completed.stderr.strip()[:400]}",
        )

    # Without an enumeration there is no resolution failure to fall back on, so this
    # is the only leg where the count alone has to carry the judgement. With one, the
    # zero-test log fails for two independent reasons and a broken count is invisible.
    completed = subprocess.run(
        [sys.executable, str(tool), "verdict", str(ZERO_TEST_LOG)],
        check=False,
        text=True,
        capture_output=True,
    )
    require(
        "verdict",
        completed.returncode == 1 and "executed no tests" in completed.stderr,
        "the zero-test log fails on its count alone, with no enumeration to resolve against",
        "the zero-test log passed when read without an enumeration, so the executed count "
        "is not being judged at all and the guard only works when it happens to also have "
        f"an enumeration. exit {completed.returncode}: {completed.stderr.strip()[:300]}",
    )

    # No captured log selects six tests and executes some of them, so the one shape
    # that puts the shortfall rule under load is constructed from the real run, the
    # way check_dolby_vision_premises.py muxes a container no sample tree contains.
    scratch = scratch_directory("xcodebuild-test-selection-check") / "work"
    if scratch.exists():
        shutil.rmtree(scratch)
    scratch.mkdir(parents=True)
    shortfall_executed = SELECTED - 2
    shortfall = scratch / "shortfall.log"
    shortfall.write_text(
        real_text.replace(
            f"Test run with {SELECTED} tests",
            f"Test run with {shortfall_executed} tests",
        ),
        encoding="utf-8",
    )
    completed = subprocess.run(
        [sys.executable, str(tool), "verdict", str(shortfall), "--enumeration", str(ENUMERATION)],
        check=False,
        text=True,
        capture_output=True,
    )
    require(
        "verdict",
        completed.returncode == 1 and f"executed {shortfall_executed}" in completed.stderr,
        f"a run that selected {SELECTED} tests and executed {shortfall_executed} is a failure",
        f"a run that executed {shortfall_executed} of the {SELECTED} tests it selected read "
        "as a pass. Only a run that executed none is caught, so a run that dies part way "
        f"through still reports green. exit {completed.returncode}: "
        f"{completed.stderr.strip()[:300]}",
    )

    real_verdict = module.read_verdict(real_text)
    require(
        "verdict",
        real_verdict.executed == SELECTED,
        f"the real run is counted as {real_verdict.executed} executed tests",
        f"the real run was counted as {real_verdict.executed} executed tests rather than "
        f"{SELECTED}, so the count the guard holds a run against is wrong.",
    )
    zero_verdict = module.read_verdict(zero_text)
    require(
        "verdict",
        zero_verdict.executed == 0 and zero_verdict.marker == "SUCCEEDED",
        "the zero-test run is counted as 0 executed tests despite its SUCCEEDED verdict",
        f"the zero-test run was counted as {zero_verdict.executed} executed tests with "
        f"verdict {zero_verdict.marker}.",
    )

    print("\nxctest")
    xctest_text = XCTEST_LOG.read_text(encoding="utf-8", errors="replace")
    failed_text = FAILED_LOG.read_text(encoding="utf-8", errors="replace")
    nested = len(re.findall(r"Executed 1 test, with 0 failures", xctest_text))
    require(
        "xctest",
        nested == XCTEST_NESTED_LINES,
        f"the passing XCTest log still prints its count {nested} times over nested suites",
        f"the passing XCTest log now prints its count {nested} times rather than "
        f"{XCTEST_NESTED_LINES}, so it no longer shows that the counts nest and the rule "
        "for aggregating them is measured by nothing.",
    )
    xctest_verdict = module.read_verdict(xctest_text)
    require(
        "xctest",
        xctest_verdict.executed == 1,
        f"it is read as {xctest_verdict.executed} executed test, not {nested}",
        f"the passing XCTest log was read as {xctest_verdict.executed} executed tests. "
        f"Summing the nested lines gives {nested} for a run of one test, which overstates "
        "every XCTest run and would let a shortfall pass as a match.",
    )
    skipped_verdict = module.read_verdict(
        SKIPPED_LOG.read_text(encoding="utf-8", errors="replace")
    )
    require(
        "xctest",
        skipped_verdict.executed == SKIPPED_EXECUTED,
        f"a suite reporting skips is read as {skipped_verdict.executed} executed tests",
        f"a run whose count carries a skipped clause was read as "
        f"{skipped_verdict.executed} executed rather than {SKIPPED_EXECUTED}. That clause "
        "splits the count from the failures, and reading zero there stops a passing suite "
        "mid-regression.",
    )

    completed = subprocess.run(
        [sys.executable, str(tool), "verdict", str(XCTEST_LOG), "--enumeration", str(ENUMERATION)],
        check=False,
        text=True,
        capture_output=True,
    )
    require(
        "xctest",
        completed.returncode == 0,
        "a real XCTest run that selected a test without parentheses and ran it reads as a pass",
        "a real XCTest run that executed its test was reported as a failure because its "
        "identifier was not written in the enumerated form. An XCTest method is accepted "
        "either way, and calling a run that worked a failure is what gets a guard switched "
        f"off. exit {completed.returncode}: {completed.stderr.strip()[:300]}",
    )
    completed = subprocess.run(
        [sys.executable, str(tool), "resolve", "--log", str(XCTEST_LOG),
         "--enumeration", str(ENUMERATION)],
        check=False,
        text=True,
        capture_output=True,
    )
    require(
        "xctest",
        completed.returncode == 1 and f"{XCTEST_BARE_IDENTIFIER}()" in completed.stdout,
        "but before a run the enumerated form is still demanded, with the repair named",
        "the same identifier was accepted before a run. Before a run there is no count to "
        "fall back on and no way to tell an XCTest method from a Swift Testing function, "
        f"so the enumerated form has to be demanded. exit {completed.returncode}",
    )
    failed_verdict = module.read_verdict(failed_text)
    require(
        "xctest",
        failed_verdict.executed == 1 and failed_verdict.failures == 1
        and failed_verdict.marker == "FAILED",
        "the failing XCTest log is read as 1 executed, 1 failed, verdict FAILED",
        f"the failing XCTest log was read as {failed_verdict.executed} executed, "
        f"{failed_verdict.failures} failed, verdict {failed_verdict.marker}.",
    )
    completed = subprocess.run(
        [sys.executable, str(tool), "verdict", str(FAILED_LOG)],
        check=False,
        text=True,
        capture_output=True,
    )
    require(
        "xctest",
        completed.returncode == 1 and "TEST FAILED" in completed.stderr,
        "and a run that executed its tests and failed them is still a failure",
        "a run that executed one test and failed it did not read as a failure, so counting "
        f"what ran has displaced noticing that it failed. exit {completed.returncode}",
    )

    print("\npreflight")
    stub, state, environment = stub_environment(scratch)
    passthrough = [
        "--",
        "test-without-building",
        "-project",
        "Enchron.xcodeproj",
        "-scheme",
        "Enchron",
        "-destination",
        "platform=visionOS Simulator,id=65A9A16C-CB84-4737-93DB-C93A01FDDB9C",
    ]

    def drive(selections: tuple[str, ...], log_name: str) -> subprocess.CompletedProcess:
        command = [
            sys.executable,
            str(tool),
            "--xcodebuild",
            str(stub),
            "run",
            "--quiet",
            "--log",
            str(scratch / log_name),
            "--keep-enumeration",
            str(scratch / f"{log_name}.enumeration.json"),
        ]
        for name in selections:
            command.extend(["--test", name])
        command.extend(passthrough)
        return subprocess.run(
            command, check=False, text=True, capture_output=True, env=environment
        )

    refused = drive(without_parentheses, "refused.log")
    calls = stub_calls(state)
    launched = [call for call in calls if not call["enumerating"]]
    require(
        "preflight",
        refused.returncode == 2,
        f"the parenthesis-less selection is refused, exit {refused.returncode}",
        f"the parenthesis-less selection exited {refused.returncode} where a refusal was "
        f"required. stderr: {refused.stderr.strip()[:400]}",
    )
    require(
        "preflight",
        launched == [],
        "no test run was launched at all, so no log existed to be misread",
        f"{len(launched)} test run(s) were launched despite a selection that matches "
        "nothing. A guard that only reads the log afterwards still lets the wrong "
        "conclusion be written down first, which is the whole reason this leg exists.",
    )
    require(
        "preflight",
        not (scratch / "refused.log").exists(),
        "no run log was written for the refused selection",
        "a run log was written for a selection that was supposed to be refused.",
    )

    accepted = drive(with_parentheses, "accepted.log")
    launched_after = [call for call in stub_calls(state) if not call["enumerating"]]
    require(
        "preflight",
        accepted.returncode == 0,
        f"the parenthesised selection runs and passes, exit {accepted.returncode}",
        f"the parenthesised selection exited {accepted.returncode}. A guard that refuses a "
        f"correct run is a guard that gets switched off. stderr: "
        f"{accepted.stderr.strip()[:400]}",
    )
    require(
        "preflight",
        len(launched_after) == 1,
        "exactly one test run was launched, for the selection that resolves",
        f"{len(launched_after)} test run(s) were launched across both drives.",
    )
    if launched_after:
        require(
            "preflight",
            sorted(
                argument.split(":", 1)[1]
                for argument in launched_after[0]["argv"]
                if argument.startswith("-only-testing:")
            )
            == sorted(with_parentheses),
            "the launched run carried exactly the selections that were resolved",
            "the launched run carried a different selection from the one that was "
            "resolved, so resolving it proved nothing about what ran.",
        )

    print("\ntruncation")
    cut = real_text[: real_text.index("Test run with")]
    truncated = scratch / "truncated.log"
    truncated.write_text(cut, encoding="utf-8")
    completed = subprocess.run(
        [sys.executable, str(tool), "verdict", str(truncated)],
        check=False,
        text=True,
        capture_output=True,
    )
    require(
        "truncation",
        completed.returncode != 0,
        "a run cut off before its reporters finished does not read as a pass",
        "a run cut off before its reporters finished read as a pass, so the guard can be "
        "satisfied by killing xcodebuild early.",
    )
    require(
        "truncation",
        "cut off" in completed.stderr,
        "and it is reported as a run that was cut off, not merely as an empty one",
        f"the truncated run was not reported as cut off: {completed.stderr.strip()[:300]}",
    )

    # A halt that kills xcodebuild after the tests have reported leaves a log whose
    # every test passed and whose terminal verdict never arrived. It is the only
    # shape where the missing verdict line is the sole defect, so it is the only one
    # that holds that judgement to anything.
    unfinished = scratch / "unfinished.log"
    unfinished.write_text(
        real_text.replace("** TEST EXECUTE SUCCEEDED **", ""), encoding="utf-8"
    )
    completed = subprocess.run(
        [sys.executable, str(tool), "verdict", str(unfinished)],
        check=False,
        text=True,
        capture_output=True,
    )
    require(
        "truncation",
        completed.returncode != 0 and "did not finish" in completed.stderr,
        "a run whose tests all reported but whose terminal verdict never arrived is not a pass",
        f"a log with {SELECTED} passing tests and no terminal verdict read as a pass, so a "
        "run killed before xcodebuild finished counts as a green one. exit "
        f"{completed.returncode}: {completed.stderr.strip()[:300]}",
    )

    print()
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    if failures:
        raise SystemExit(1)
    print(f"the guard separates a run that executed {SELECTED} tests from one that executed "
          "none, and refuses the second before it is launched")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
