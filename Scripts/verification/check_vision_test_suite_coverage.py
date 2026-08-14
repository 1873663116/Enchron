#!/usr/bin/env python3

"""Checks that the vision test verifier partitions an enumerated target exactly once.

The preserved enumeration contains the state that the old verifier misses: 31
target-level Swift Testing functions and six suites outside its hardcoded array. The
check first proves that the old selection still covers 185 of 257 tests, then drives the
verifier against a stand-in xcodebuild. Plan-only mode must enumerate into a dedicated
file, replace a stale file, write an auditable invocation plan, and launch no test action.

The plan is then damaged in three independent ways. Removing an invocation must report
unassigned tests, duplicating one must report overlapping ownership, and adding an empty
filter must report that it selects nothing. These controls matter because a checker that
only approves the generated plan could share the same omission as the planner.

Use --verifier or --tool to point this check at an older copy. The pre-repair verifier
exits zero after ten fake test actions, but this check fails because it never enumerates
and never writes a complete plan.
"""

from __future__ import annotations

import argparse
from dataclasses import replace
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import types

sys.path.insert(0, str(Path(__file__).parent))

from enchron_artifact_paths import scratch_directory

REPOSITORY = Path(__file__).resolve().parents[2]
VERIFIER = Path(__file__).parent / "verify_vision_test_suites.sh"
TOOL = Path(__file__).parent / "xcodebuild_test_selection.py"
ENUMERATION = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/"
    "dv76-verify-20260814/r5-test-enumeration.json"
)
TARGET = "EnchronAppTests"
ENUMERATED_TOTAL = 257
NESTED_TOTAL = 226
FREE_FUNCTION_TOTAL = 31
LEGACY_COVERED = 185
LEGACY_MISSING = 72
LEGACY_SUITES = (
    "EnvironmentSceneMappingTests",
    "WindowPlaybackPageGeometryTests",
    "PlaybackPresentationStateTests",
    "PlaybackSourceAccessTests",
    "PlaybackSourceAndAudioSessionTests",
    "MediaLibraryTests",
    "LocalDataSourceAdapterTests",
    "FakeFileDataSourceTests",
    "SMBDataSourceAdapterTests",
    "WebDAVDataSourceAdapterTests",
)

STUB_SOURCE = '''#!/usr/bin/env python3
"""Records xcodebuild calls and writes the preserved enumeration when requested."""

import json
import os
from pathlib import Path
import shutil
import sys

state = Path(os.environ["ENCHRON_XCODEBUILD_STUB_STATE"])
fixture = Path(os.environ["ENCHRON_XCODEBUILD_STUB_ENUMERATION"])
evidence = Path(os.environ["ENCHRON_EVIDENCE_ROOT"])
argv = sys.argv[1:]

with (state / "calls.jsonl").open("a") as sink:
    sink.write(json.dumps(argv) + "\\n")

if "-enumerate-tests" in argv:
    if "-test-enumeration-output-path" not in argv:
        print("enumeration was sent to stdout", file=sys.stderr)
        sys.exit(73)
    output = Path(argv[argv.index("-test-enumeration-output-path") + 1])
    if output.exists():
        print(f"enumeration output already exists: {output}", file=sys.stderr)
        sys.exit(74)
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fixture, output)
    print("enumerated")
    sys.exit(0)

# This is the xcodebuild hazard: an empty or incomplete selection still exits zero.
selections = [argument.split(":", 1)[1] for argument in argv if argument.startswith("-only-testing:")]
count = 0
plan_path = evidence / "test-invocation-plan.json"
if plan_path.is_file():
    plan = json.loads(plan_path.read_text())
    for invocation in plan["invocations"]:
        if selections == invocation["filters"]:
            count = len(invocation["identifiers"])
            break
if "-resultBundlePath" in argv:
    result = Path(argv[argv.index("-resultBundlePath") + 1])
    result.mkdir(parents=True, exist_ok=True)
print("Test run started")
print(f"Test run with {count} tests in 0 suites passed after 0.001 seconds.")
print("** TEST EXECUTE SUCCEEDED **")
sys.exit(0)
'''


def load_tool(path: Path) -> types.ModuleType:
    name = f"suite_coverage_{id(path)}"
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise SystemExit(f"cannot load selection tool at {path}")
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def recorded_calls(state: Path) -> list[list[str]]:
    path = state / "calls.jsonl"
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verifier",
        type=Path,
        default=VERIFIER,
        help="Verifier to check. Point this at an older copy to reproduce the drift.",
    )
    parser.add_argument(
        "--tool",
        type=Path,
        default=TOOL,
        help="Selection and planning tool used by the verifier.",
    )
    arguments = parser.parse_args()
    verifier = arguments.verifier.resolve()
    tool_path = arguments.tool.resolve()
    for label, path in (
        ("verifier", verifier),
        ("selection tool", tool_path),
        ("enumeration fixture", ENUMERATION),
    ):
        if not path.is_file():
            raise SystemExit(f"the {label} is missing, so this check proves nothing: {path}")

    tool = load_tool(tool_path)
    enumeration = tool.read_enumeration(ENUMERATION)
    target_identifiers = tuple(
        identifier
        for identifier in enumeration.identifiers
        if tool.selects(TARGET, identifier)
    )
    nested = tuple(name for name in target_identifiers if len(name.split("/")) >= 3)
    free_functions = tuple(name for name in target_identifiers if len(name.split("/")) == 2)
    failures: list[str] = []

    def require(leg: str, held: bool, ok: str, bad: str) -> bool:
        if held:
            print(f"  ok   {ok}")
            return True
        print(f"  FAIL {bad}")
        failures.append(f"{leg}: {bad}")
        return False

    print("\nfixture")
    require(
        "fixture",
        enumeration.trustworthy,
        "the damaged capture was repaired without losing an identifier",
        f"the enumeration lost identifiers: {enumeration.damaged}",
    )
    require(
        "fixture",
        (len(target_identifiers), len(nested), len(free_functions))
        == (ENUMERATED_TOTAL, NESTED_TOTAL, FREE_FUNCTION_TOTAL),
        f"the target still has {ENUMERATED_TOTAL} tests: {NESTED_TOTAL} in suites and "
        f"{FREE_FUNCTION_TOTAL} free functions",
        f"the fixture now has {len(target_identifiers)} target tests: {len(nested)} in "
        f"suites and {len(free_functions)} free functions",
    )
    disabled = tuple(name for name in enumeration.disabled if tool.selects(TARGET, name))
    require(
        "fixture",
        not disabled,
        "the target has no disabled enumerated tests",
        f"the fixture has disabled target tests that cannot be covered: {disabled}",
    )

    print("\ntrap")
    legacy_filters = [f"{TARGET}/{suite}" for suite in LEGACY_SUITES]
    legacy_resolutions = tool.resolve(legacy_filters, enumeration)
    legacy_covered = set(tool.selected_identifiers(legacy_resolutions))
    missing = sorted(set(target_identifiers) - legacy_covered)
    require(
        "trap",
        len(legacy_covered) == LEGACY_COVERED and len(missing) == LEGACY_MISSING,
        f"the old hardcoded selection still covers {LEGACY_COVERED} and misses "
        f"{LEGACY_MISSING}",
        f"the old selection now covers {len(legacy_covered)} and misses {len(missing)}, "
        "so this fixture no longer reproduces the defect",
    )

    print("\nverifier planning")
    scratch = scratch_directory("vision-test-suite-coverage-check") / "work"
    if scratch.exists():
        shutil.rmtree(scratch)
    binaries = scratch / "bin"
    state = scratch / "state"
    evidence = scratch / "evidence"
    for path in (binaries, state, evidence):
        path.mkdir(parents=True)
    stub = binaries / "xcodebuild"
    stub.write_text(STUB_SOURCE, encoding="utf-8")
    stub.chmod(0o755)
    enumeration_output = evidence / "test-enumeration.json"
    enumeration_output.write_text("stale", encoding="utf-8")

    environment = dict(os.environ)
    environment.update(
        PATH=f"{binaries}:{environment.get('PATH', '')}",
        ENCHRON_XCODEBUILD=str(stub),
        ENCHRON_XCODEBUILD_STUB_STATE=str(state),
        ENCHRON_XCODEBUILD_STUB_ENUMERATION=str(ENUMERATION),
        ENCHRON_VISION_TEST_DESTINATION="platform=visionOS,id=CHECK-NOT-A-DEVICE",
        ENCHRON_DERIVED_DATA=str(scratch / "DerivedData"),
        ENCHRON_SOURCE_PACKAGES=str(scratch / "SourcePackages"),
        ENCHRON_EVIDENCE_ROOT=str(evidence),
        ENCHRON_VISION_TEST_PLAN_ONLY="1",
    )
    completed = subprocess.run(
        [str(verifier)],
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    calls = recorded_calls(state)
    enumeration_calls = [call for call in calls if "-enumerate-tests" in call]
    test_calls = [call for call in calls if "-enumerate-tests" not in call]
    require(
        "verifier",
        completed.returncode == 0,
        f"plan-only verifier exited {completed.returncode}",
        f"plan-only verifier exited {completed.returncode}: "
        f"{(completed.stderr or completed.stdout).strip()[:500]}",
    )
    require(
        "verifier",
        len(enumeration_calls) == 1,
        "the verifier enumerated exactly once",
        f"the verifier made {len(enumeration_calls)} enumeration calls",
    )
    require(
        "verifier",
        not test_calls,
        "plan-only mode launched no test action",
        f"plan-only mode launched {len(test_calls)} test action(s)",
    )
    require(
        "verifier",
        enumeration_output.is_file()
        and enumeration_output.read_text(encoding="utf-8", errors="replace") != "stale",
        "the verifier removed and replaced the stale enumeration file",
        "the verifier did not replace the stale enumeration file",
    )

    plan_path = evidence / "test-invocation-plan.json"
    plan = None
    if require(
        "verifier",
        plan_path.is_file(),
        "the verifier wrote its invocation plan beside the future result bundles",
        f"the verifier wrote no invocation plan at {plan_path}",
    ):
        try:
            plan = tool.read_target_invocation_plan(plan_path)
            tool.audit_target_invocations(plan, enumeration)
        except (AttributeError, ValueError, SystemExit) as error:
            failures.append(f"verifier: the written plan was rejected: {error}")
            print(f"  FAIL the written plan was rejected: {error}")
        else:
            planned = sum(len(invocation.identifiers) for invocation in plan.invocations)
            require(
                "verifier",
                planned == ENUMERATED_TOTAL,
                f"the written plan assigns all {planned} target tests exactly once",
                f"the written plan assigns {planned} tests rather than {ENUMERATED_TOTAL}",
            )
            suite_invocations = tuple(
                invocation
                for invocation in plan.invocations
                if invocation.name != "TargetLevelFreeFunctions"
            )
            free_invocations = tuple(
                invocation
                for invocation in plan.invocations
                if invocation.name == "TargetLevelFreeFunctions"
            )
            require(
                "verifier",
                len(suite_invocations) == 16
                and all(len(invocation.filters) == 1 for invocation in suite_invocations),
                "all 16 suites retain one isolated invocation each",
                f"the plan has {len(suite_invocations)} suite invocation(s), and their "
                "filter counts are "
                f"{[len(invocation.filters) for invocation in suite_invocations]}",
            )
            require(
                "verifier",
                len(free_invocations) == 1
                and len(free_invocations[0].filters) == FREE_FUNCTION_TOTAL
                and set(free_invocations[0].filters) == set(free_functions),
                f"all {FREE_FUNCTION_TOTAL} free functions share one exact-filter invocation",
                "the target-level free functions are missing, split into extra calls, or "
                "selected by something other than their exact enumerated identifiers",
            )

    print("\nexecution wiring")
    if plan is None:
        print("  FAIL no complete plan exists, so invocation wiring cannot be checked")
        failures.append("execution: no complete plan exists")
    else:
        calls_path = state / "calls.jsonl"
        calls_path.unlink(missing_ok=True)
        environment["ENCHRON_VISION_TEST_PLAN_ONLY"] = "0"
        executed = subprocess.run(
            [str(verifier)],
            cwd=REPOSITORY,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        run_calls = recorded_calls(state)
        run_enumerations = [call for call in run_calls if "-enumerate-tests" in call]
        invocations = [call for call in run_calls if "-enumerate-tests" not in call]
        require(
            "execution",
            executed.returncode == 0,
            f"the complete stand-in run exited {executed.returncode}",
            f"the complete stand-in run exited {executed.returncode}: "
            f"{(executed.stderr or executed.stdout).strip()[-500:]}",
        )
        require(
            "execution",
            len(run_enumerations) == 1 and len(invocations) == len(plan.invocations),
            f"one enumeration was followed by all {len(invocations)} planned invocations",
            f"the run made {len(run_enumerations)} enumeration call(s) and "
            f"{len(invocations)} test call(s), expected 1 and {len(plan.invocations)}",
        )

        owners: dict[str, list[int]] = {identifier: [] for identifier in target_identifiers}
        result_paths: list[str] = []
        for index, call in enumerate(invocations):
            filters = [
                argument.split(":", 1)[1]
                for argument in call
                if argument.startswith("-only-testing:")
            ]
            resolutions = tool.resolve(filters, enumeration)
            for identifier in tool.selected_identifiers(resolutions):
                if identifier in owners:
                    owners[identifier].append(index)
            if "-resultBundlePath" in call:
                result_paths.append(call[call.index("-resultBundlePath") + 1])
        missing_from_calls = [name for name, indices in owners.items() if not indices]
        repeated_by_calls = [name for name, indices in owners.items() if len(indices) > 1]
        require(
            "execution",
            not missing_from_calls and not repeated_by_calls,
            "the launched filters assign every enumerated test to exactly one call",
            f"the launched filters leave {len(missing_from_calls)} missing and "
            f"{len(repeated_by_calls)} assigned more than once",
        )
        require(
            "execution",
            len(result_paths) == len(invocations)
            and len(set(result_paths)) == len(invocations)
            and all(Path(path).is_dir() for path in result_paths),
            "every invocation has its own result bundle path",
            f"found {len(result_paths)} result paths, {len(set(result_paths))} unique, "
            f"for {len(invocations)} invocations",
        )

    print("\ncontrols")
    required_api = all(
        hasattr(tool, name)
        for name in ("plan_target_invocations", "audit_target_invocations", "PlanError")
    )
    if not required_api:
        print("  FAIL the selection tool has no target partition audit API")
        failures.append("controls: the selection tool has no target partition audit API")
    elif plan is not None:
        def refused(label: str, candidate: object, phrase: str) -> None:
            try:
                tool.audit_target_invocations(candidate, enumeration)
            except tool.PlanError as error:
                require(
                    "controls",
                    phrase in str(error),
                    f"{label} was refused: {error}",
                    f"{label} was refused for an unrelated reason: {error}",
                )
            else:
                require("controls", False, "", f"{label} was accepted")

        refused(
            "a plan with its final invocation removed",
            replace(plan, invocations=plan.invocations[:-1]),
            "unassigned",
        )
        refused(
            "a plan with one invocation duplicated",
            replace(
                plan,
                invocations=(
                    *plan.invocations,
                    replace(plan.invocations[0], name="DuplicateFirstInvocation"),
                ),
            ),
            "more than once",
        )
        empty = tool.TargetInvocation(
            name="EmptySelection",
            filters=(f"{TARGET}/ThisSuiteDoesNotExist",),
            identifiers=(),
        )
        refused(
            "a plan containing an empty selection",
            replace(plan, invocations=(*plan.invocations, empty)),
            "selects no enumerated test",
        )

    print()
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    if failures:
        return 1
    print(
        f"the verifier partitions all {ENUMERATED_TOTAL} {TARGET} tests exactly once and "
        "refuses incomplete, overlapping, and empty plans"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
