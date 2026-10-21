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


def run_static_tier(root: Path, evidence_root: Path, quick: bool) -> dict[str, Any]:
    started = time.monotonic()
    command = [sys.executable, str(root / RUN_VERIFICATION)]
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
