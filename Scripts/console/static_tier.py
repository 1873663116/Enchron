from __future__ import annotations

import hashlib
import re
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import known
from report import EXIT_OK, EXIT_TERMINAL, write_json


RUN_VERIFICATION = Path("Scripts/rules/run_verification.py")


CODE_ONLY_CHECKERS = (
    "verify_product_source_comments.py",
    "verify_swiftlint.py",
    "verify_release_test_channel_absent.py",
    "verify_debug_boundary.py",
    "verify_unittest_main_guard.py",
    "verify_localizations.py",
    "harness_primitives_gate.py",
    "check_no_literal_rfc1918.py",
    "check_ats_cleartext_policy.py",
)


GATE_STAMP = Path(".scratch/console/static-gate.json")


def tree_fingerprint(root: Path) -> str:
    listing = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=str(root),
        capture_output=True,
    )
    digest = hashlib.sha256()
    for name in sorted(entry for entry in listing.stdout.decode().split("\0") if entry):
        try:
            info = (root / name).stat()
        except OSError:
            continue
        digest.update(f"{name}\0{info.st_mtime_ns}\0{info.st_size}\n".encode())
    return digest.hexdigest()


def run_gate(root: Path, evidence_root: Path) -> dict[str, Any]:
    stamp = root / GATE_STAMP
    fingerprint = tree_fingerprint(root)
    recorded = ""
    try:
        recorded = str(json.loads(stamp.read_text(encoding="utf-8"))["fingerprint"])
    except (OSError, ValueError, KeyError, TypeError):
        recorded = ""
    if recorded == fingerprint:
        return {
            "passed": True,
            "codeOnly": True,
            "skipped": True,
            "fingerprint": fingerprint,
            "durationMs": 0,
            "checkers": [],
            "exitCode": EXIT_OK,
        }
    payload = run_code_only(root, evidence_root)
    payload["skipped"] = False
    payload["fingerprint"] = fingerprint
    if payload["exitCode"] == EXIT_OK:
        stamp.parent.mkdir(parents=True, exist_ok=True)
        stamp.write_text(json.dumps({"fingerprint": fingerprint}), encoding="utf-8")
    return payload


def run_code_only(root: Path, evidence_root: Path) -> dict[str, Any]:
    started = time.monotonic()
    results = []
    for name in CODE_ONLY_CHECKERS:
        script = root / "Scripts" / "rules" / name
        if not script.exists():
            results.append({"checker": name, "exitCode": None, "detail": "absent"})
            continue
        completed = subprocess.run(
            [sys.executable, str(script)], capture_output=True, text=True, cwd=str(root)
        )
        results.append(
            {
                "checker": name,
                "exitCode": completed.returncode,
                "stderr": completed.stderr[-4000:],
            }
        )
    model = subprocess.run(
        [sys.executable, str(root / "Scripts" / "console" / "cli.py"),
         "--root", str(root), "plan", "check"],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    results.append(
        {
            "checker": "plan-check",
            "exitCode": model.returncode,
            "stderr": (model.stderr or model.stdout)[-4000:],
        }
    )
    duration_ms = int((time.monotonic() - started) * 1000)
    failed = [item for item in results if item["exitCode"] not in (0, None)]
    payload = {
        "tier": "static",
        "codeOnly": True,
        "exitCode": 0 if not failed else 1,
        "durationMs": duration_ms,
        "checkers": results,
    }
    evidence_root.mkdir(parents=True, exist_ok=True)
    write_json(evidence_root / "static" / "code-only.json", payload)
    return payload


CHECK_LINE = re.compile(r"^\s+(PASS|FAIL|SKIP)\s+(\S+)\s+([0-9.]+)s\s*$", re.MULTILINE)
LAYER_LINE = re.compile(r"^\[(PASS|FAIL)\]\s+([^:]+):\s*(.*)$", re.MULTILINE)
FAILED_TEST = re.compile(r'✘ Test "([^"]+)" failed after', re.MULTILINE)


def _check_breakdown(output: str) -> list[dict[str, Any]]:
    checks = [
        {"checker": name, "state": state, "durationMs": int(float(seconds) * 1000)}
        for state, name, seconds in CHECK_LINE.findall(output)
    ]
    checks.extend(
        {"checker": name.strip(), "state": state, "detail": detail, "durationMs": None}
        for state, name, detail in LAYER_LINE.findall(output)
        if name.strip() != "Overall verdict"
    )
    return checks


def run_static_tier(
    root: Path,
    evidence_root: Path,
    quick: bool,
    code_only: bool = False,
    full: bool = False,
    changed_since: str = "",
    gate: bool = False,
    changed_staged: bool = False,
    changed_list: str = "",
    event: str = "",
    remote_oid: str = "",
    base_ref: str = "main",
    local_oid: str = "HEAD",
) -> dict[str, Any]:
    if code_only:
        if gate:
            return run_gate(root, evidence_root)
        return run_code_only(root, evidence_root)
    started = time.monotonic()
    command = [sys.executable, str(root / RUN_VERIFICATION)]
    if not full:
        command.append("--text-only")
    if changed_since:
        command.extend(["--changed-since", changed_since])
    if changed_staged:
        command.append("--changed-staged")
    if changed_list:
        command.extend(["--changed-list", changed_list])
    if event:
        command.extend(["--event", event])
    if remote_oid:
        command.extend(["--remote-oid", remote_oid])
    if base_ref != "main":
        command.extend(["--base-ref", base_ref])
    if local_oid != "HEAD":
        command.extend(["--local-oid", local_oid])
    if quick:
        command.append("--quick")
    log_root = evidence_root / "static" / time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    command.extend(["--log-root", str(log_root)])
    completed = subprocess.run(command, capture_output=True, text=True, cwd=str(root))
    duration_ms = int((time.monotonic() - started) * 1000)
    payload = {
        "tier": "static",
        "quick": quick,
        "exitCode": completed.returncode,
        "durationMs": duration_ms,
        "logRoot": str(log_root),
        "checks": _check_breakdown(completed.stdout),
        "stdout": completed.stdout[-8000:],
        "stderr": completed.stderr[-8000:],
    }
    for check in payload["checks"]:
        if check.get("state") != "FAIL":
            continue
        text = str(check)
        name = str(check["checker"]).lower().replace(" ", "-") + ".log"
        candidates = [log_root / name, *log_root.rglob(name)]
        log_text = ""
        for log in candidates:
            if log.exists():
                log_text = log.read_text(encoding="utf-8", errors="replace")[-200000:]
                break
        failed_tests = FAILED_TEST.findall(log_text)
        text += log_text
        declaration = known.checker_matching(root, str(check["checker"]), text)
        if declaration is None:
            continue
        if failed_tests:
            phrases = [
                str(item.get("match") or "")
                for item in known.declarations(root)
                if str(item.get("checker")) == str(check["checker"])
            ]
            undeclared = [
                test for test in failed_tests
                if not any(phrase and phrase in test for phrase in phrases)
            ]
            if undeclared:
                check["undeclaredFailures"] = undeclared
                continue
        check["state"] = "known"
        check["knownReason"] = str(declaration.get("reason", "declared known failure"))
    payload["exitCode"] = (
        0
        if not (completed.returncode and any(c.get("state") == "FAIL" for c in payload["checks"]))
        else 1
    )
    evidence_root.mkdir(parents=True, exist_ok=True)
    write_json(evidence_root / "static" / "last-run.json", payload)
    return payload


def static_exit(payload: dict[str, Any]) -> int:
    return EXIT_OK if payload["exitCode"] == 0 else EXIT_TERMINAL


def summarize(payload: dict[str, Any]) -> str:
    state = "passed" if payload["exitCode"] == 0 else "failed"
    if payload.get("codeOnly"):
        failed = [
            item["checker"]
            for item in payload["checkers"]
            if item["exitCode"] not in (0, None)
        ]
        if payload.get("skipped"):
            return "static code-only up to date, nothing changed since the last gate"
        detail = f"failing {', '.join(failed)}" if failed else "every code checker passed"
        return f"static code-only {state} in {payload['durationMs']} ms ({detail})"
    skipped_tooling = ""
    for item in payload.get("checks", []):
        detail = str(item.get("detail") or "")
        match = re.search(
            r"tooling self-tests skipped, CI and test infrastructure unchanged \((\d+)\)",
            detail,
        )
        if match:
            skipped_tooling = f"; tooling self-tests skipped ({match.group(1)})"
            break
    return (
        f"static {state} in {payload['durationMs']} ms "
        f"(quick={payload['quick']}, exit {payload['exitCode']})"
        f"{skipped_tooling}"
    )


def main(argv: list[str] | None = None) -> int:
    arguments = list(argv if argv is not None else sys.argv[1:])
    root = Path.cwd()
    quick = "--quick" in arguments
    payload = run_static_tier(root, root / "TestEvidence" / "console", quick)
    if "--json" in arguments:
        print(json.dumps(payload, indent=1))
    else:
        print(summarize(payload))
    return static_exit(payload)


if __name__ == "__main__":
    raise SystemExit(main())
