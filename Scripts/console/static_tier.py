from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from report import EXIT_OK, EXIT_TERMINAL, write_json


RUN_VERIFICATION = Path("Scripts/rules/run_verification.py")


CODE_ONLY_CHECKERS = (
    "verify_product_source_comments.py",
    "verify_swiftlint.py",
    "verify_release_test_channel_absent.py",
    "verify_debug_boundary.py",
    "verify_unittest_main_guard.py",
    "harness_primitives_gate.py",
    "check_no_literal_rfc1918.py",
    "check_ats_cleartext_policy.py",
)


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


def run_static_tier(
    root: Path,
    evidence_root: Path,
    quick: bool,
    code_only: bool = False,
    full: bool = False,
) -> dict[str, Any]:
    if code_only:
        return run_code_only(root, evidence_root)
    started = time.monotonic()
    command = [sys.executable, str(root / RUN_VERIFICATION)]
    if not full:
        command.append("--text-only")
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
        "stdout": completed.stdout[-8000:],
        "stderr": completed.stderr[-8000:],
    }
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
        detail = f"failing {', '.join(failed)}" if failed else "every code checker passed"
        return f"static code-only {state} in {payload['durationMs']} ms ({detail})"
    return (
        f"static {state} in {payload['durationMs']} ms "
        f"(quick={payload['quick']}, exit {payload['exitCode']})"
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
