#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASELINE_PATH = REPOSITORY_ROOT / "Config/verification_gauntlet_baseline.json"
DEFAULT_LOG_ROOT = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/VerificationGauntlet/runs"
)
PLAYBACK_CORE_SCRATCH = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/VerificationGauntlet/PlaybackCore"
)
STRUCTURE_CHECKS = (
    ("design-source-architecture", "verify_design_source_architecture.py"),
    ("package-membership", "verify_package_membership.py"),
    ("playback-surface-structure", "verify_playback_surface_structure.py"),
    ("format-description-ownership", "verify_format_description_ownership.py"),
    ("media-byte-stream", "verify_media_byte_stream.py"),
    ("hover-region-clipping", "check_hover_region_clipping.py"),
    ("visionpro-core-regression-plan", "verify_visionpro_core_regression_plan.py"),
)
TEST_FAILURE = re.compile(
    r"\bTest (?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?:\([^)]*\))? (?:recorded an issue|failed after)"
)
TEST_SUMMARY = re.compile(
    r"\bTest run with (?P<count>\d+) tests?.*? "
    r"(?P<verdict>passed|failed) after"
)
RUN_DIRECTORY = re.compile(r"^\d{8}T\d{6}Z-\d+$")


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
            )
        except OSError as error:
            message = f"could not start command: {error}\n"
            print(message, end="", file=sys.stderr)
            sink.write(message)
            return 127, message
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="")
            sink.write(line)
            sink.flush()
            output.append(line)
        return process.wait(), "".join(output)


def relative_log(path: Path, run_directory: Path) -> str:
    return path.relative_to(run_directory).as_posix()


def run_structure_checks(
    run_directory: Path,
    environment: dict[str, str],
) -> LayerResult:
    failures: list[str] = []
    logs: list[str] = []
    for identifier, filename in STRUCTURE_CHECKS:
        log = run_directory / "structure" / f"{identifier}.log"
        code, _ = run_logged(
            f"structure: {identifier}",
            [sys.executable, str(REPOSITORY_ROOT / "Scripts/verification" / filename)],
            log,
            environment,
        )
        logs.append(relative_log(log, run_directory))
        if code != 0:
            failures.append(f"{identifier} exited {code}")
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
        f"all {len(STRUCTURE_CHECKS)} checks passed",
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


def run_playback_core_tests(
    run_directory: Path,
    environment: dict[str, str],
    baseline: dict[str, object],
) -> LayerResult:
    swift = swift_tool(environment)
    command = [
        swift,
        "test",
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
        return LayerResult(
            "PlaybackCore tests",
            "FAIL",
            f"full test summary is missing; command exited {code}",
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


def run_source_parity(
    run_directory: Path,
    environment: dict[str, str],
    baseline: dict[str, object],
) -> LayerResult:
    output_path = run_directory / "source-parity.json"
    log = run_directory / "source-parity.log"
    command = [
        sys.executable,
        str(REPOSITORY_ROOT / "Scripts/verification/verify_source_parity_matrix.py"),
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
            str(REPOSITORY_ROOT / "Scripts/verification/verify_feature_evidence_coverage.py"),
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
            str(REPOSITORY_ROOT / "Scripts/verification/verify_guard_selftests.py"),
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
    print("\n== Verification gauntlet summary ==")
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
        help="run structure checks and PlaybackCore full tests only",
    )
    parser.add_argument("--log-root", type=Path, default=DEFAULT_LOG_ROOT)
    parser.add_argument("--retain-runs", type=int, default=14)
    arguments = parser.parse_args()
    if arguments.retain_runs < 1:
        parser.error("--retain-runs must be at least 1")
    return arguments


def main() -> int:
    arguments = parse_arguments()
    log_root = arguments.log_root.resolve()
    log_root.mkdir(parents=True, exist_ok=True)
    lock_path = log_root / ".gauntlet.lock"
    started = datetime.now(timezone.utc)
    run_id = started.strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    run_directory = log_root / run_id

    with lock_path.open("a+", encoding="utf-8") as lock:
        print(f"Acquiring verification lock: {lock_path}")
        fcntl.flock(lock, fcntl.LOCK_EX)
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
        results.append(run_structure_checks(run_directory, environment))
        try:
            results.append(
                run_playback_core_tests(run_directory, environment, baseline)
            )
        except (OSError, subprocess.SubprocessError) as error:
            results.append(LayerResult("PlaybackCore tests", "FAIL", str(error)))
        if arguments.quick:
            results.extend(
                [
                    skipped("Source parity"),
                    skipped("Feature evidence coverage"),
                    skipped("Guard self-tests"),
                ]
            )
        else:
            results.append(run_source_parity(run_directory, environment, baseline))
            results.append(run_feature_coverage(run_directory, environment))
            results.append(run_guard_selftests(run_directory, environment))

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
