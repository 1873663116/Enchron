"""The merge gate.

A merge into main runs three tiers and aggregates them into four states:

  green     every tier passed
  yellow    every failure is declared on main in Config/console/known-failures.md
  override  every red failure carries a human-approved record on main
  red       at least one failure is undeclared, declared on the branch, expired,
            or a build failure

Declarations and override records are read from main, never from the branch
being merged. A branch that adds a declaration or an override changes nothing
until the record itself lands on main from another merge.
"""

from __future__ import annotations

import datetime
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import known
from report import EXIT_OK, EXIT_TERMINAL, write_json


GREEN = "green"
YELLOW = "yellow"
OVERRIDE = "override"
RED = "red"

MERGES = Path("TestEvidence/console/merges")
OVERRIDES = Path("Config/console/merge-overrides")
STATUS = Path(".scratch/console/merge-gate/status.txt")
MAIN_DECLARATIONS = Path(".scratch/console/merge-gate/main-known-failures.md")
FAILED_TEST = re.compile(r'✘ Test "([^"]+)" failed')


@dataclass(frozen=True)
class Failure:
    signature: str
    detail: str = ""


@dataclass
class Verdict:
    status: str
    yellow: list[dict[str, Any]] = field(default_factory=list)
    red: list[dict[str, Any]] = field(default_factory=list)
    overridden: list[dict[str, Any]] = field(default_factory=list)


def reference_date() -> str:
    return datetime.date.today().isoformat()


def expired(record: dict[str, Any], reference: str | None = None) -> bool:
    expiry = str(record.get("expires") or "").strip()
    if not expiry:
        return False
    return expiry < (reference or reference_date())


def declaration_allows(
    declaration: dict[str, Any],
    failure: Failure,
    reference: str | None = None,
) -> bool:
    if expired(declaration, reference):
        return False
    phrase = str(declaration.get("match") or "")
    if failure.signature.startswith("ci:"):
        checker = str(declaration.get("checker") or "")
        if not checker or checker != failure.signature.split(":", 1)[1]:
            return False
        return not phrase or phrase in failure.detail
    if failure.signature.startswith("unit:"):
        test = str(declaration.get("test") or "")
        if not test or test not in failure.signature.split(":", 1)[1]:
            return False
        return not phrase or phrase in failure.detail
    return False


def override_allows(
    record: dict[str, Any],
    failure: Failure,
    reference: str | None = None,
) -> bool:
    if str(record.get("schema")) != "enchron.console.merge-override":
        return False
    if record.get("schemaVersion") != 1:
        return False
    if str(record.get("signature") or "") != failure.signature:
        return False
    if not str(record.get("reason") or "").strip():
        return False
    if not str(record.get("approvedBy") or "").strip():
        return False
    if not str(record.get("approvedAt") or "").strip():
        return False
    return not expired(record, reference)


def classify(
    failures: list[Failure],
    declarations: list[dict[str, Any]],
    overrides: list[dict[str, Any]],
    reference: str | None = None,
) -> Verdict:
    verdict = Verdict(GREEN)
    for failure in failures:
        declaration = next(
            (
                item
                for item in declarations
                if declaration_allows(item, failure, reference)
            ),
            None,
        )
        if declaration is not None:
            verdict.yellow.append(
                {
                    "signature": failure.signature,
                    "detail": failure.detail,
                    "declaration": declaration,
                }
            )
            continue
        override = next(
            (
                item
                for item in overrides
                if override_allows(item, failure, reference)
            ),
            None,
        )
        if override is not None:
            verdict.overridden.append(
                {
                    "signature": failure.signature,
                    "detail": failure.detail,
                    "override": override,
                }
            )
            continue
        verdict.red.append(
            {"signature": failure.signature, "detail": failure.detail}
        )
    if verdict.red:
        verdict.status = RED
    elif verdict.overridden:
        verdict.status = OVERRIDE
    elif verdict.yellow:
        verdict.status = YELLOW
    return verdict


def failed_tests(text: str) -> list[str]:
    seen: list[str] = []
    for name in FAILED_TEST.findall(text.replace("\r", "\n")):
        if name not in seen:
            seen.append(name)
    return seen


def _payload(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _log_text(payload: dict[str, Any] | None) -> str:
    if not payload:
        return ""
    log = str(payload.get("log") or "")
    if not log:
        return ""
    try:
        return Path(log).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def ci_failures(payload: dict[str, Any] | None) -> list[Failure]:
    if not payload:
        return [Failure("ci:infrastructure", "the static tier wrote no payload")]
    failures: list[Failure] = []
    checks = payload.get("checks") or []
    for check in checks:
        if str(check.get("state")) not in {"FAIL", "known"}:
            continue
        identifier = str(check.get("checker") or "unknown")
        detail = str(check.get("detail") or check.get("knownReason") or "")
        failures.append(Failure(f"ci:{identifier}", detail))
    if payload.get("exitCode") not in (0, None) and not failures:
        failures.append(
            Failure("ci:infrastructure", str(payload.get("stderr") or "")[-2000:])
        )
    return failures


def unit_failures(payload: dict[str, Any] | None) -> list[Failure]:
    if not payload:
        return [Failure("unit:infrastructure", "the unit tier wrote no payload")]
    if payload.get("exitCode") == 0 and payload.get("passed"):
        return []
    text = _log_text(payload)
    tests = failed_tests(text)
    if tests:
        return [
            Failure(f"unit:{name}", text[-4000:])
            for name in tests
        ]
    return [Failure("unit:infrastructure", text[-4000:])]


def build_failures(payload: dict[str, Any] | None) -> list[Failure]:
    if not payload:
        return [Failure("build", "the build tier wrote no payload")]
    if payload.get("exitCode") == 0:
        return []
    return [Failure("build", _log_text(payload)[-4000:])]


def _git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(root), *arguments],
        capture_output=True,
        text=True,
    )


def main_declarations_text(root: Path) -> str:
    completed = _git(root, "show", f"HEAD:{known.DECLARATION.as_posix()}")
    return completed.stdout if completed.returncode == 0 else ""


def main_declarations(root: Path) -> list[dict[str, Any]]:
    return known.parse_declarations(main_declarations_text(root))


def main_overrides(root: Path) -> list[dict[str, Any]]:
    listing = _git(root, "ls-tree", "-r", "--name-only", "HEAD", "--", OVERRIDES.as_posix())
    if listing.returncode != 0:
        return []
    records: list[dict[str, Any]] = []
    for name in listing.stdout.splitlines():
        if not name.endswith(".json"):
            continue
        completed = _git(root, "show", f"HEAD:{name}")
        if completed.returncode != 0:
            continue
        try:
            records.append(json.loads(completed.stdout))
        except json.JSONDecodeError:
            continue
    return records


def _invoke(
    root: Path, environment: dict[str, str], arguments: list[str], timeout: int
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(root / "Scripts" / "console" / "cli.py"),
        "--root",
        str(root),
        *arguments,
    ]
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            cwd=str(root),
            env=environment,
            timeout=timeout,
        )
    except (subprocess.TimeoutExpired, OSError) as error:
        return subprocess.CompletedProcess(command, 1, stdout="", stderr=str(error))


def status_line(verdict: Verdict) -> str:
    if verdict.status == GREEN:
        return "green"
    if verdict.status == YELLOW:
        return f"yellow ({len(verdict.yellow)} known)"
    if verdict.status == OVERRIDE:
        return f"override ({len(verdict.overridden)} approved)"
    return f"red ({len(verdict.red)} undeclared)"


def render(verdict: Verdict, duration_ms: int) -> str:
    lines = [f"merge gate {status_line(verdict)} in {duration_ms} ms"]
    for item in verdict.yellow:
        lines.append(f"  known    {item['signature']}")
    for item in verdict.overridden:
        lines.append(f"  override {item['signature']}")
    for item in verdict.red:
        lines.append(f"  red      {item['signature']}")
    return "\n".join(lines)


def run_gate(root: Path, target: str | None, evidence_root: Path) -> tuple[int, dict[str, Any]]:
    started = time.monotonic()
    declarations = main_declarations(root)
    overrides = main_overrides(root)
    scratch = root / MAIN_DECLARATIONS.parent
    scratch.mkdir(parents=True, exist_ok=True)
    (root / MAIN_DECLARATIONS).write_text(
        main_declarations_text(root), encoding="utf-8"
    )
    branch_declarations = known.declarations(root)
    environment = dict(os.environ)
    environment[known.ENVIRONMENT] = str(root / MAIN_DECLARATIONS)
    if target:
        environment["ENCHRON_TARGET_DEVICE"] = target
    tiers: dict[str, dict[str, Any]] = {}
    for name, arguments, timeout, payload_path in (
        (
            "ci",
            ["tier", "static", "--event", "merge"],
            1800,
            evidence_root / "static" / "last-run.json",
        ),
        ("build", ["tier", "build"], 3600, evidence_root / "tiers" / "build.json"),
        ("unit", ["tier", "unit"], 3600, evidence_root / "tiers" / "unit.json"),
    ):
        completed = _invoke(root, environment, arguments, timeout)
        tiers[name] = {
            "exitCode": completed.returncode,
            "durationMs": 0,
            "stdout": completed.stdout[-4000:],
            "stderr": completed.stderr[-4000:],
        }
        payload = _payload(payload_path)
        if payload:
            tiers[name]["durationMs"] = payload.get("durationMs", 0)
            tiers[name]["payload"] = payload_path.as_posix()
    failures = (
        build_failures(_payload(evidence_root / "tiers" / "build.json"))
        + ci_failures(_payload(evidence_root / "static" / "last-run.json"))
        + unit_failures(_payload(evidence_root / "tiers" / "unit.json"))
    )
    verdict = classify(failures, declarations, overrides)
    duration_ms = int((time.monotonic() - started) * 1000)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    directory = evidence_root / "merges" / stamp
    directory.mkdir(parents=True, exist_ok=True)
    summary = {
        "schema": "enchron.console.merge-gate",
        "schemaVersion": 1,
        "status": verdict.status,
        "durationMs": duration_ms,
        "target": target or "",
        "head": _git(root, "rev-parse", "HEAD").stdout.strip(),
        "mergeHead": _git(root, "rev-parse", "MERGE_HEAD").stdout.strip(),
        "declarations": {
            "main": len(declarations),
            "branch": len(branch_declarations),
        },
        "yellow": verdict.yellow,
        "overridden": verdict.overridden,
        "red": verdict.red,
        "tiers": tiers,
    }
    write_json(directory / "summary.json", summary)
    (root / STATUS).parent.mkdir(parents=True, exist_ok=True)
    (root / STATUS).write_text(status_line(verdict), encoding="utf-8")
    print(render(verdict, duration_ms))
    return (EXIT_OK if verdict.status != RED else EXIT_TERMINAL), summary


def main(argv: list[str] | None = None) -> int:
    root = Path.cwd()
    target = os.environ.get("ENCHRON_TARGET_DEVICE", "")
    exit_code, payload = run_gate(
        root, target or None, root / "TestEvidence" / "console"
    )
    if "--json" in (argv if argv is not None else sys.argv[1:]):
        print(json.dumps(payload, indent=1))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
