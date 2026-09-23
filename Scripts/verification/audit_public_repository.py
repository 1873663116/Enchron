#!/usr/bin/env python3

"""Scan the public HEAD lineage for secrets and archived captures.

Run from any directory after installing Gitleaks. Reports stay in the ignored
`.audit/` directory. The summary never prints a matched secret.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


REPOSITORY = Path(__file__).resolve().parents[2]
REPORT_DIRECTORY = REPOSITORY / ".audit"
GITLEAKS_REPORT = REPORT_DIRECTORY / "gitleaks-full-history.json"
SUMMARY_REPORT = REPORT_DIRECTORY / "public-repository-audit.json"
MEDIA_SUFFIXES = {".jpg", ".jpeg", ".m4a", ".mov", ".mp3", ".mp4", ".png", ".reality", ".wav"}
CAPTURE_PREFIXES = (
    "DesignPreview/.codex-screenshots/",
    "docs/archive/acceptance/evidence/",
    "docs/qa-reports/",
    "docs/ui/screenshots/",
)
CAPTURE_SUFFIXES = {".jpg", ".jpeg", ".png"}
SENSITIVE_NAME = re.compile(
    r"(?i)^(?:\.env(?:\..*)?|.*(?:credential|secret).*\.(?:env|json|txt|ya?ml)|"
    r".*\.(?:cer|key|mobileprovision|p12|p8|pem))$"
)


def git_output(*arguments: str) -> str:
    return subprocess.check_output(
        ["git", *arguments], cwd=REPOSITORY, text=True
    )


def main() -> int:
    if shutil.which("gitleaks") is None:
        print("Install Gitleaks before running this audit: brew install gitleaks", file=sys.stderr)
        return 2

    REPORT_DIRECTORY.mkdir(exist_ok=True)
    scan = subprocess.run(
        [
            "gitleaks", "git", "--no-banner", "--redact=100",
            "--report-format", "json", "--report-path", str(GITLEAKS_REPORT),
            "--log-opts=HEAD", ".",
        ],
        cwd=REPOSITORY,
        capture_output=True,
        text=True,
        check=False,
    )
    if scan.returncode not in (0, 1) or not GITLEAKS_REPORT.exists():
        print("Gitleaks failed; inspect the local report and rerun the audit.", file=sys.stderr)
        return 2

    findings = json.loads(GITLEAKS_REPORT.read_text(encoding="utf-8"))
    history_paths = sorted(set(git_output("log", "HEAD", "--name-only", "--format=").splitlines()))
    tracked_paths = git_output("ls-files").splitlines()
    sensitive_paths = sorted(
        path for path in history_paths if SENSITIVE_NAME.fullmatch(Path(path).name)
    )
    summary = {
        "head": git_output("rev-parse", "HEAD").strip(),
        "commit_count": int(git_output("rev-list", "HEAD", "--count").strip()),
        "secret_findings": [
            {
                "rule": finding.get("RuleID"),
                "path": finding.get("File"),
                "commit": finding.get("Commit"),
                "line": finding.get("StartLine"),
            }
            for finding in findings
        ],
        "sensitive_history_paths": sensitive_paths,
        "historical_capture_paths": [
            path for path in history_paths
            if path.startswith(CAPTURE_PREFIXES)
            and Path(path).suffix.lower() in CAPTURE_SUFFIXES
        ],
        "historical_media_paths": [
            path for path in history_paths if Path(path).suffix.lower() in MEDIA_SUFFIXES
        ],
        "current_media_paths": [
            path for path in tracked_paths if Path(path).suffix.lower() in MEDIA_SUFFIXES
        ],
    }
    SUMMARY_REPORT.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Checked {summary['commit_count']} reachable commits at {summary['head'][:12]}.")
    print(f"Gitleaks findings: {len(findings)}; sensitive history paths: {len(sensitive_paths)}.")
    print(f"Archived capture paths in Git history: {len(summary['historical_capture_paths'])}.")
    print(
        "Committed media paths: "
        f"{len(summary['current_media_paths'])} current, "
        f"{len(summary['historical_media_paths'])} historical paths."
    )
    print(f"Redacted local reports: {GITLEAKS_REPORT}, {SUMMARY_REPORT}")
    return 1 if findings or sensitive_paths or summary["historical_capture_paths"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
