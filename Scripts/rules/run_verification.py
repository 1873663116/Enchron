#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import errno
import fcntl
import json
import os
from pathlib import Path
import re
import selectors
import shlex
import shutil
import signal
import subprocess
import sys
import time


if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

from enchron_artifact_paths import artifact_root, evidence_root

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASELINE_PATH = REPOSITORY_ROOT / "Config/verification_baseline.json"
DEFAULT_LOG_ROOT = artifact_root() / "Verification/runs"
PLAYBACK_CORE_SCRATCH = artifact_root() / "Verification/PlaybackCore"
TEST_FAILURE = re.compile(
    r"\bTest (?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?:\([^)]*\))? (?:recorded an issue|failed after)"
)
TEST_SUMMARY = re.compile(
    r"\bTest run with (?P<count>\d+) tests?.*? "
    r"(?P<verdict>passed|failed) after"
)
RUN_DIRECTORY = re.compile(r"^\d{8}T\d{6}Z-\d+$")
LOCK_WAIT_SECONDS = float(os.environ.get("VERIFICATION_LOCK_WAIT_SECONDS", 1800))
STEP_SILENCE_SECONDS = float(os.environ.get("VERIFICATION_STEP_SILENCE_SECONDS", 900))


@dataclass(frozen=True)
class LayerResult:
    name: str
    state: str
    detail: str
    logs: tuple[str, ...] = ()


@dataclass(frozen=True)
class TestSummary:
    count: int
    verdict: str


@dataclass(frozen=True)
class StructureCheck:
    identifier: str
    filename: str
    runs_in_quick_mode: bool = True


SCRIPT_DIRECTORIES = ("Scripts/rules", "Scripts/verification")


def structure_check_path(filename: str) -> Path:
    for directory in SCRIPT_DIRECTORIES:
        candidate = REPOSITORY_ROOT / directory / filename
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"structure check not found in any script directory: {filename}")


STRUCTURE_CHECKS = (
    StructureCheck("design-source-architecture", "verify_design_source_architecture.py"),
    StructureCheck("package-membership", "verify_package_membership.py"),
    StructureCheck("playback-surface-structure", "verify_playback_surface_structure.py"),
    StructureCheck("format-description-ownership", "verify_format_description_ownership.py"),
    StructureCheck(
        "format-description-identity",
        "verify_format_description_identity.py",
        runs_in_quick_mode=False,
    ),
    StructureCheck("media-byte-stream", "verify_media_byte_stream.py"),
    StructureCheck("demux-buffer-policy", "verify_demux_buffer_policy.py"),
    StructureCheck(
        "media-byte-stream-conformance",
        "verify_media_byte_stream_conformance.py",
    ),
    StructureCheck("media-discovery-admission", "verify_media_discovery_admission.py"),
    StructureCheck("glass-usage", "verify_glass_usage.py"),
    StructureCheck("documentation-references", "verify_documentation_references.py"),
    StructureCheck(
        "regression-core-layering",
        "verify_regression_core_layering.py",
    ),
    StructureCheck("recording-extractor", "check_recording_extractor.py"),
    StructureCheck(
        "playback-issue-ownership",
        "verify_playback_issue_ownership.py",
    ),
    StructureCheck(
        "product-source-comments",
        "verify_product_source_comments.py",
    ),
    StructureCheck(
        "release-test-channel-absent",
        "verify_release_test_channel_absent.py",
    ),
    StructureCheck(
        "regression-fact-provenance",
        "verify_regression_fact_provenance.py",
    ),
    StructureCheck(
        "playback-runtime-ownership",
        "verify_playback_runtime_ownership.py",
    ),
    StructureCheck(
        "regression-oracle-producers",
        "verify_regression_oracle_producers.py",
    ),
    StructureCheck(
        "controller-invocations",
        "verify_controller_invocations.py",
    ),
    StructureCheck(
        "regression-element-targeting",
        "verify_regression_element_targeting.py",
    ),
    StructureCheck(
        "regression-related-results-arity",
        "verify_regression_related_results_arity.py",
    ),
    StructureCheck(
        "operation-evidence-payloads",
        "verify_operation_evidence_payloads.py",
    ),
    StructureCheck("hover-region-clipping", "check_hover_region_clipping.py"),
    StructureCheck(
        "reachability-inventory",
        "generate_reachability_inventory.py",
    ),
    StructureCheck(
        "visionpro-core-regression-plan",
        "verify_visionpro_core_regression_plan.py",
    ),
    StructureCheck(
        "xcodebuild-test-selection",
        "check_xcodebuild_test_selection.py",
    ),
    StructureCheck(
        "vision-test-suite-coverage",
        "check_vision_test_suite_coverage.py",
    ),
    StructureCheck(
        "merge-evidence-tier",
        "merge_evidence_tier.py",
    ),
    StructureCheck(
        "scripts-inventory",
        "verify_scripts_inventory.py",
    ),
    StructureCheck(
        "ensure-test-services",
        "ensure_test_services.py",
        runs_in_quick_mode=False,
    ),
    StructureCheck("disc-image-format", "check_disc_image_format.py"),
    StructureCheck(
        "dolby-vision-premises",
        "check_dolby_vision_premises.py",
        runs_in_quick_mode=False,
    ),
    StructureCheck(
        "interactive-halt-wake",
        "check_interactive_halt_wake.py",
        runs_in_quick_mode=False,
    ),
    StructureCheck(
        "media-byte-stream-foundation",
        "verify_media_byte_stream_foundation.py",
    ),
    StructureCheck(
        "organic-architecture-xcode",
        "verify_organic_architecture_xcode.sh",
    ),
    StructureCheck("swiftlint", "verify_swiftlint.py"),
    StructureCheck(
        "bootstrap-freeze",
        "verify_bootstrap_freeze.py",
    ),
)


def load_baseline(path: Path = BASELINE_PATH) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = payload.get("playbackCoreExpectedFailures")
    intermittent = payload.get("playbackCoreIntermittentTimeout")
    parity = payload.get("sourceParityKnownStatuses")
    if payload.get("version") != 1:
        raise ValueError("expected baseline version 1")
    if not isinstance(expected, list) or not all(isinstance(x, str) for x in expected):
        raise ValueError("playbackCoreExpectedFailures must be a string list")
    if len(expected) != len(set(expected)):
        raise ValueError("playbackCoreExpectedFailures contains duplicates")
    if not isinstance(intermittent, dict):
        raise ValueError("playbackCoreIntermittentTimeout must be an object")
    if not isinstance(intermittent.get("test"), str):
        raise ValueError("the intermittent timeout test name is missing")
    markers = intermittent.get("markers")
    if not isinstance(markers, list) or not markers or not all(
        isinstance(marker, str) for marker in markers
    ):
        raise ValueError("the intermittent timeout markers must be a string list")
    if not isinstance(parity, list):
        raise ValueError("sourceParityKnownStatuses must be a list")
    pairs: list[tuple[str, str]] = []
    for entry in parity:
        if not isinstance(entry, dict):
            raise ValueError("every source parity status must be an object")
        name = entry.get("name")
        decode = entry.get("decode")
        if not isinstance(name, str) or not isinstance(decode, str):
            raise ValueError("every source parity status needs name and decode strings")
        pairs.append((name, decode))
    if len(pairs) != len(set(pairs)):
        raise ValueError("sourceParityKnownStatuses contains duplicates")
    return payload


def tool_environment() -> dict[str, str]:
    completed = subprocess.run(
        ["/usr/bin/xcode-select", "-p"],
        capture_output=True,
        text=True,
        check=True,
    )
    environment = os.environ.copy()
    environment["DEVELOPER_DIR"] = completed.stdout.strip()
    return environment


def swift_tool(environment: dict[str, str]) -> str:
    completed = subprocess.run(
        ["/usr/bin/xcrun", "--find", "swift"],
        capture_output=True,
        text=True,
        check=True,
        env=environment,
    )
    return completed.stdout.strip()


def run_logged(
    title: str,
    command: list[str],
    log_path: Path,
    environment: dict[str, str],
) -> tuple[int, str]:
    print(f"\n== {title} ==")
    print("$ " + shlex.join(command))
    log_path.parent.mkdir(parents=True, exist_ok=True)
    output: list[str] = []
    with log_path.open("w", encoding="utf-8") as sink:
        sink.write("$ " + shlex.join(command) + "\n")
        sink.flush()
        try:
            process = subprocess.Popen(
                command,
                cwd=REPOSITORY_ROOT,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                bufsize=1,
                start_new_session=True,
            )
        except OSError as error:
            message = f"could not start command: {error}\n"
            print(message, end="", file=sys.stderr)
            sink.write(message)
            return 127, message
        assert process.stdout is not None
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        try:
            while True:
                if not selector.select(timeout=STEP_SILENCE_SECONDS):
                    message = (
                        f"no output for {STEP_SILENCE_SECONDS:.0f}s and still running;"
                        " terminating. A shared build directory can wedge a"
                        " subprocess on its own lock after the build completes.\n"
                    )
                    print(message, end="", file=sys.stderr)
                    sink.write(message)
                    output.append(message)
                    terminate(process)
                    return 124, "".join(output)
                line = process.stdout.readline()
                if not line:
                    break
                print(line, end="")
                sink.write(line)
                sink.flush()
                output.append(line)
        finally:
            selector.close()
            process.stdout.close()
        return process.wait(), "".join(output)


def terminate(process: subprocess.Popen[str]) -> None:
    for escalation in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(os.getpgid(process.pid), escalation)
        except (ProcessLookupError, PermissionError):
            try:
                process.send_signal(escalation)
            except ProcessLookupError:
                return
        try:
            process.wait(timeout=10)
            return
        except subprocess.TimeoutExpired:
            continue


def relative_log(path: Path, run_directory: Path) -> str:
    return path.relative_to(run_directory).as_posix()


def structure_check_command(filename: str) -> list[str]:
    path = structure_check_path(filename)
    if path.suffix == ".swift":
        return ["swift", str(path)]
    if path.suffix in (".sh", ".zsh"):
        return ["zsh", str(path)]
    return [sys.executable, str(path)]


def discovered_test_checks() -> tuple[StructureCheck, ...]:
    discovered: list[StructureCheck] = []
    for directory in SCRIPT_DIRECTORIES:
        for path in sorted((REPOSITORY_ROOT / directory).glob("test_*.py")):
            discovered.append(StructureCheck(path.stem.replace("_", "-"), path.name))
    if not discovered:
        raise ValueError(f"no self-tests found under {', '.join(SCRIPT_DIRECTORIES)}")
    return tuple(discovered)


def run_structure_checks(
    run_directory: Path,
    environment: dict[str, str],
    quick: bool,
) -> LayerResult:
    failures: list[str] = []
    logs: list[str] = []
    checks = tuple(
        check
        for check in STRUCTURE_CHECKS + discovered_test_checks()
        if not quick or check.runs_in_quick_mode
    )
    for check in checks:
        log = run_directory / "structure" / f"{check.identifier}.log"
        code, _ = run_logged(
            f"structure: {check.identifier}",
            structure_check_command(check.filename),
            log,
            environment,
        )
        logs.append(relative_log(log, run_directory))
        if code != 0:
            failures.append(f"{check.identifier} exited {code}")
    if failures:
        return LayerResult(
            "Structure checks",
            "FAIL",
            "; ".join(failures),
            tuple(logs),
        )
    return LayerResult(
        "Structure checks",
        "PASS",
        f"all {len(checks)} {'quick ' if quick else ''}checks passed",
        tuple(logs),
    )


def failure_names(output: str) -> set[str]:
    return {match.group("name") for match in TEST_FAILURE.finditer(output)}


def test_summary(output: str) -> TestSummary | None:
    matches = list(TEST_SUMMARY.finditer(output.replace("\r", "\n")))
    if not matches:
        return None
    match = matches[-1]
    return TestSummary(int(match.group("count")), match.group("verdict"))


def test_failure_has_marker(
    output: str,
    test_name: str,
    markers: list[str],
) -> bool:
    lines = output.replace("\r", "\n").splitlines()
    for index, line in enumerate(lines):
        if f"Test {test_name}" not in line:
            continue
        context_lines = [line]
        for following in lines[index + 1 : index + 4]:
            if "Test " in following:
                break
            context_lines.append(following)
        context = "\n".join(context_lines)
        if any(marker in context for marker in markers):
            return True
    return False


def discard_playback_core_scratch() -> bool:
    """Throw away the shared build directory after a step failed to report.

    A terminated `swift test` leaves that directory wedged, and every later run
    inherits it: the suite then fails a different handful of timing-sensitive
    tests each time, which reads as a flaky product rather than as stale state.
    Rebuilding costs minutes; a poisoned directory costs every run after it.
    """
    if not PLAYBACK_CORE_SCRATCH.exists():
        return False
    shutil.rmtree(PLAYBACK_CORE_SCRATCH, ignore_errors=True)
    return not PLAYBACK_CORE_SCRATCH.exists()


def run_playback_core_tests(
    run_directory: Path,
    environment: dict[str, str],
    baseline: dict[str, object],
) -> LayerResult:
    swift = swift_tool(environment)
    command = [
        swift,
        "test",
        "--no-parallel",
        "--package-path",
        str(REPOSITORY_ROOT / "Packages/PlaybackCore"),
        "--scratch-path",
        str(PLAYBACK_CORE_SCRATCH),
    ]
    log = run_directory / "playback-core-tests.log"
    code, output = run_logged("PlaybackCore full tests", command, log, environment)
    logs = [relative_log(log, run_directory)]
    summary = test_summary(output)
    if summary is None:
        discarded = discard_playback_core_scratch()
        return LayerResult(
            "PlaybackCore tests",
            "FAIL",
            f"full test summary is missing; command exited {code}"
            + ("; discarded the shared build directory" if discarded else ""),
            tuple(logs),
        )

    failures = failure_names(output)
    intermittent = baseline["playbackCoreIntermittentTimeout"]
    assert isinstance(intermittent, dict)
    intermittent_name = intermittent["test"]
    markers = intermittent["markers"]
    assert isinstance(intermittent_name, str) and isinstance(markers, list)
    if intermittent_name in failures:
        if not test_failure_has_marker(output, intermittent_name, markers):
            return LayerResult(
                "PlaybackCore tests",
                "FAIL",
                f"{intermittent_name} failed without the accepted timeout signature",
                tuple(logs),
            )
        rerun_log = run_directory / "playback-core-intermittent-rerun.log"
        rerun_code, rerun_output = run_logged(
            f"PlaybackCore retry: {intermittent_name}",
            [*command, "--skip-build", "--filter", intermittent_name],
            rerun_log,
            environment,
        )
        logs.append(relative_log(rerun_log, run_directory))
        rerun_summary = test_summary(rerun_output)
        if (
            rerun_code != 0
            or rerun_summary is None
            or rerun_summary.verdict != "passed"
            or intermittent_name in failure_names(rerun_output)
        ):
            return LayerResult(
                "PlaybackCore tests",
                "FAIL",
                f"{intermittent_name} did not pass its isolated timeout rerun",
                tuple(logs),
            )
        failures.remove(intermittent_name)

    expected = set(baseline["playbackCoreExpectedFailures"])
    unknown = sorted(failures - expected)
    missing = sorted(expected - failures)
    if unknown or missing:
        details: list[str] = []
        if unknown:
            details.append("new failures: " + ", ".join(unknown))
        if missing:
            details.append("baseline failures now absent: " + ", ".join(missing))
        return LayerResult(
            "PlaybackCore tests",
            "FAIL",
            "; ".join(details),
            tuple(logs),
        )

    expected_verdict = "failed" if expected else "passed"
    expected_zero = not expected
    if summary.verdict != expected_verdict or (code == 0) != expected_zero:
        return LayerResult(
            "PlaybackCore tests",
            "FAIL",
            f"test summary and exit code disagree with the baseline: {summary}, exit {code}",
            tuple(logs),
        )
    return LayerResult(
        "PlaybackCore tests",
        "PASS",
        f"{summary.count} tests completed; {len(expected)} expected failure names matched",
        tuple(logs),
    )


def judge_source_parity(
    results: object,
    known_statuses: list[dict[str, str]],
) -> tuple[bool, str]:
    if not isinstance(results, list) or not results:
        return False, "parity output has no media results"
    known = {(entry["name"], entry["decode"]) for entry in known_statuses}
    differences: list[str] = []
    unknown: list[str] = []
    accepted = 0
    for entry in results:
        if not isinstance(entry, dict):
            return False, "parity output contains a non-object result"
        name = entry.get("name")
        decode = entry.get("decode")
        if not isinstance(name, str) or not isinstance(decode, str):
            return False, "parity result is missing a name or decode status"
        if not isinstance(entry.get("http"), dict) or "differences" not in entry:
            return False, f"parity result lacks its HTTP comparison: {name}"
        if entry.get("differences"):
            differences.append(name)
        if decode in ("ok", "not_video"):
            continue
        if (name, decode) in known:
            accepted += 1
        else:
            unknown.append(f"{name} ({decode})")
    if differences or unknown:
        details: list[str] = []
        if differences:
            details.append(
                f"{len(differences)} transport differences: " + ", ".join(differences)
            )
        if unknown:
            details.append("unaccepted media states: " + ", ".join(unknown))
        return False, "; ".join(details)
    return (
        True,
        f"{len(results)} media results, 0 transport differences, "
        f"{accepted} known media states",
    )


def visionos_simulator_identifier(environment: dict[str, str]) -> str | None:
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        env=environment,
        capture_output=True,
        text=True,
    )
    if listing.returncode != 0:
        return None
    catalogue = json.loads(listing.stdout).get("devices", {})
    booted = None
    shutdown = None
    for runtime, devices in catalogue.items():
        if "xrOS" not in runtime and "visionOS" not in runtime:
            continue
        for device in devices:
            if device.get("state") == "Booted" and booted is None:
                booted = device["udid"]
            elif shutdown is None:
                shutdown = device["udid"]
    return booted or shutdown


def run_domain_tests(run_directory: Path, environment: dict[str, str]) -> LayerResult:
    log = run_directory / "domain-tests.log"
    identifier = visionos_simulator_identifier(environment)
    if identifier is None:
        return LayerResult(
            "Domain tests",
            "FAIL",
            "no visionOS simulator is available to run EnchronDomainTests",
        )
    command = [
        "xcodebuild",
        "test",
        "-project",
        str(REPOSITORY_ROOT / "Enchron.xcodeproj"),
        "-scheme",
        "EnchronDomainTests",
        "-testPlan",
        "EnchronDomain",
        "-destination",
        f"id={identifier}",
        "-derivedDataPath",
        str(artifact_root() / "DerivedData/DomainTests"),
    ]
    code, output = run_logged("domain tests", command, log, environment)
    summary = TEST_SUMMARY.search(output)
    logs = (relative_log(log, run_directory),)
    if summary is None:
        return LayerResult("Domain tests", "FAIL", f"no test summary; exited {code}", logs)
    if summary.group("verdict") != "passed":
        failures = sorted({match.group("name") for match in TEST_FAILURE.finditer(output)})
        detail = ", ".join(failures) if failures else "see the log"
        return LayerResult("Domain tests", "FAIL", f"failures: {detail}", logs)
    return LayerResult(
        "Domain tests", "PASS", f"{summary.group('count')} tests passed", logs
    )


def run_source_parity(
    run_directory: Path,
    environment: dict[str, str],
    baseline: dict[str, object],
) -> LayerResult:
    output_path = run_directory / "source-parity.json"
    log = run_directory / "source-parity.log"
    command = [
        sys.executable,
        str(REPOSITORY_ROOT / "Scripts/rules/verify_source_parity_matrix.py"),
        "--mode",
        "parity",
        "--scratch-path",
        str(PLAYBACK_CORE_SCRATCH),
        "--output",
        str(output_path),
    ]
    code, _ = run_logged("source parity", command, log, environment)
    logs = [relative_log(log, run_directory)]
    if output_path.is_file():
        logs.append(relative_log(output_path, run_directory))
    else:
        return LayerResult(
            "Source parity",
            "FAIL",
            f"result JSON is missing; command exited {code}",
            tuple(logs),
        )
    try:
        results = json.loads(output_path.read_text(encoding="utf-8"))
        known = baseline["sourceParityKnownStatuses"]
        assert isinstance(known, list)
        passed, detail = judge_source_parity(results, known)
    except (OSError, ValueError, json.JSONDecodeError, KeyError) as error:
        return LayerResult(
            "Source parity",
            "FAIL",
            f"could not judge parity output: {error}",
            tuple(logs),
        )
    if code not in (0, 1):
        passed = False
        detail = f"parity command exited unexpectedly with {code}; {detail}"
    return LayerResult(
        "Source parity",
        "PASS" if passed else "FAIL",
        detail,
        tuple(logs),
    )


def run_media_discovery_capability_matrix(
    run_directory: Path,
    environment: dict[str, str],
) -> LayerResult:
    log = run_directory / "media-discovery-capability-matrix.log"
    code, _ = run_logged(
        "media discovery capability matrix",
        [
            sys.executable,
            str(
                REPOSITORY_ROOT
                / "Scripts/rules/verify_media_discovery_capability_matrix.py"
            ),
            "--scratch-path",
            str(PLAYBACK_CORE_SCRATCH),
        ],
        log,
        environment,
    )
    return LayerResult(
        "Media discovery capability matrix",
        "PASS" if code == 0 else "FAIL",
        "all proven source combinations replayed" if code == 0 else f"checker exited {code}",
        (relative_log(log, run_directory),),
    )


def feature_gap_count(output: str, code: int) -> int | None:
    if code == 0 and "every declared evidence has an owner" in output:
        return 0
    match = re.search(r"^\s*(\d+) unguarded:$", output, flags=re.MULTILINE)
    if code == 1 and match:
        return int(match.group(1))
    return None


def run_feature_coverage(
    run_directory: Path,
    environment: dict[str, str],
) -> LayerResult:
    log = run_directory / "feature-evidence-coverage.log"
    code, output = run_logged(
        "feature evidence coverage",
        [
            sys.executable,
            str(REPOSITORY_ROOT / "Scripts/rules/verify_feature_evidence_coverage.py"),
        ],
        log,
        environment,
    )
    count = feature_gap_count(output, code)
    if count is None:
        return LayerResult(
            "Feature evidence coverage",
            "FAIL",
            f"checker did not produce a valid gap count; exit {code}",
            (relative_log(log, run_directory),),
        )
    return LayerResult(
        "Feature evidence coverage",
        "PASS",
        f"counted {count} unguarded evidence promises",
        (relative_log(log, run_directory),),
    )


def run_guard_selftests(
    run_directory: Path,
    environment: dict[str, str],
) -> LayerResult:
    log = run_directory / "guard-selftests.log"
    code, _ = run_logged(
        "guard self-tests",
        [
            sys.executable,
            str(REPOSITORY_ROOT / "Scripts/rules/verify_guard_selftests.py"),
        ],
        log,
        environment,
    )
    return LayerResult(
        "Guard self-tests",
        "PASS" if code == 0 else "FAIL",
        "all known bad samples were rejected" if code == 0 else f"checker exited {code}",
        (relative_log(log, run_directory),),
    )


def install_git_hooks(environment: dict[str, str]) -> LayerResult:
    hook = REPOSITORY_ROOT / ".githooks/pre-push"
    if not hook.is_file() or not os.access(hook, os.X_OK):
        return LayerResult(
            "Git hook installation",
            "FAIL",
            f"pre-push hook is missing or not executable: {hook}",
        )
    read = subprocess.run(
        ["git", "config", "--local", "--get", "core.hooksPath"],
        cwd=REPOSITORY_ROOT,
        env=environment,
        capture_output=True,
        text=True,
    )
    current = read.stdout.strip() if read.returncode == 0 else None
    if current != ".githooks":
        configured = subprocess.run(
            ["git", "config", "--local", "core.hooksPath", ".githooks"],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if configured.returncode != 0:
            return LayerResult(
                "Git hook installation",
                "FAIL",
                configured.stderr.strip() or "git config failed",
            )
        action = f"set core.hooksPath from {current!r} to '.githooks'"
    else:
        action = "core.hooksPath already points to '.githooks'"
    return LayerResult("Git hook installation", "PASS", action)


def skipped(name: str) -> LayerResult:
    return LayerResult(name, "SKIP", "omitted by --quick")


def retain_recent_runs(log_root: Path, retain: int, current: Path) -> None:
    candidates = sorted(
        path
        for path in log_root.iterdir()
        if path.is_dir() and RUN_DIRECTORY.fullmatch(path.name)
    )
    removable = [path for path in candidates if path != current]
    while len(candidates) > retain and removable:
        target = removable.pop(0)
        if target.parent.resolve() != log_root.resolve():
            raise RuntimeError(f"refusing to remove log directory outside {log_root}: {target}")
        shutil.rmtree(target)
        candidates.remove(target)


def write_summary(
    run_directory: Path,
    started_at: str,
    quick: bool,
    environment: dict[str, str],
    results: list[LayerResult],
) -> None:
    payload = {
        "version": 1,
        "startedAt": started_at,
        "finishedAt": datetime.now(timezone.utc).isoformat(),
        "mode": "quick" if quick else "full",
        "repository": str(REPOSITORY_ROOT),
        "developerDirectory": environment["DEVELOPER_DIR"],
        "layers": [asdict(result) for result in results],
        "verdict": "failed" if any(result.state == "FAIL" for result in results) else "passed",
    }
    (run_directory / "summary.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def print_summary(results: list[LayerResult], run_directory: Path) -> bool:
    print("\n== Verification summary ==")
    for result in results:
        print(f"[{result.state}] {result.name}: {result.detail}")
    failed = any(result.state == "FAIL" for result in results)
    print(f"[{'FAIL' if failed else 'PASS'}] Overall verdict")
    print(f"Logs: {run_directory}")
    return not failed


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Enchron's layered local verification gate."
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help=(
            "run quick structure checks and PlaybackCore full tests only; "
            "the media-corpus format identity check runs only in full mode"
        ),
    )
    parser.add_argument("--log-root", type=Path, default=DEFAULT_LOG_ROOT)
    parser.add_argument("--retain-runs", type=int, default=14)
    arguments = parser.parse_args()
    if arguments.retain_runs < 1:
        parser.error("--retain-runs must be at least 1")
    return arguments


def lock_holders(lock_path: Path) -> str:
    try:
        listing = subprocess.run(
            ["/usr/sbin/lsof", "-t", str(lock_path)],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    holders = listing.stdout.split()
    return ", ".join(holders) if holders else "unknown"


def acquire_lock(lock, lock_path: Path) -> bool:
    """Take the gate's exclusive lock, naming the holder rather than hanging.

    Every worktree shares one lock and one build directory, so a wedged run
    blocks every later run and every push through the pre-push hook. Waiting
    forever in silence makes that indistinguishable from slow work.
    """
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError as error:
        if error.errno not in (errno.EACCES, errno.EAGAIN):
            raise
    print(
        f"Verification lock held by pid {lock_holders(lock_path)}:"
        f" {lock_path}\nWaiting up to {LOCK_WAIT_SECONDS:.0f}s.",
        flush=True,
    )
    deadline = time.monotonic() + LOCK_WAIT_SECONDS
    while time.monotonic() < deadline:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print("Verification lock acquired.", flush=True)
            return True
        except OSError as error:
            if error.errno not in (errno.EACCES, errno.EAGAIN):
                raise
        time.sleep(2)
    print(
        f"FAIL Verification lock still held by pid {lock_holders(lock_path)}"
        f" after {LOCK_WAIT_SECONDS:.0f}s. Inspect or kill that run, then retry.",
        file=sys.stderr,
        flush=True,
    )
    return False


def main() -> int:
    sys.stdout.reconfigure(line_buffering=True)
    arguments = parse_arguments()
    log_root = arguments.log_root.resolve()
    log_root.mkdir(parents=True, exist_ok=True)
    lock_path = log_root / ".verification.lock"
    started = datetime.now(timezone.utc)
    run_id = started.strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    run_directory = log_root / run_id

    with lock_path.open("a+", encoding="utf-8") as lock:
        if not acquire_lock(lock, lock_path):
            return 1
        run_directory.mkdir()
        print(f"Mode: {'quick' if arguments.quick else 'full'}")
        print(f"Repository: {REPOSITORY_ROOT}")
        print(f"Run logs: {run_directory}")
        try:
            environment = tool_environment()
            baseline = load_baseline()
        except (OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError) as error:
            result = LayerResult("Gate configuration", "FAIL", str(error))
            results = [result]
            write_summary(
                run_directory,
                started.isoformat(),
                arguments.quick,
                {"DEVELOPER_DIR": "unknown"},
                results,
            )
            print_summary(results, run_directory)
            return 1

        results = [install_git_hooks(environment)]
        results.append(
            run_structure_checks(run_directory, environment, arguments.quick)
        )
        try:
            results.append(
                run_playback_core_tests(run_directory, environment, baseline)
            )
        except (OSError, subprocess.SubprocessError) as error:
            results.append(LayerResult("PlaybackCore tests", "FAIL", str(error)))
        results.append(run_guard_selftests(run_directory, environment))
        if arguments.quick:
            results.extend(
                [
                    skipped("Domain tests"),
                    skipped("Source parity"),
                    skipped("Media discovery capability matrix"),
                    skipped("Feature evidence coverage"),
                ]
            )
        else:
            try:
                results.append(run_domain_tests(run_directory, environment))
            except (OSError, subprocess.SubprocessError) as error:
                results.append(LayerResult("Domain tests", "FAIL", str(error)))
            results.append(run_source_parity(run_directory, environment, baseline))
            results.append(
                run_media_discovery_capability_matrix(run_directory, environment)
            )
            results.append(run_feature_coverage(run_directory, environment))

        write_summary(
            run_directory,
            started.isoformat(),
            arguments.quick,
            environment,
            results,
        )
        retain_recent_runs(log_root, arguments.retain_runs, run_directory)
        passed = print_summary(results, run_directory)
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
