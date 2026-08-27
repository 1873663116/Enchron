#!/usr/bin/env python3

"""SwiftLint runs on every Xcode build and no gate has ever read its output.

The custom architecture guards in .swiftlint.yml are already errors and already
pass. What accumulated unseen was the built-in style set. This holds the count
against a baseline the same way the design source rule does: a finding outside
the baseline fails, a baseline entry that no longer occurs fails, and the
baseline can only be rewritten smaller.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONFIGURATION = REPOSITORY_ROOT / ".swiftlint.yml"
BASELINE = REPOSITORY_ROOT / "Config/swiftlint_baseline.json"


def run(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["swiftlint", "lint", "--quiet", "--config", str(CONFIGURATION), *arguments],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
    )


def baseline_size() -> int:
    if not BASELINE.is_file():
        return 0
    return len(json.loads(BASELINE.read_text(encoding="utf-8")))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write-baseline",
        action="store_true",
        help="rewrite the baseline, refusing any rewrite that would grow it",
    )
    arguments = parser.parse_args()

    if shutil.which("swiftlint") is None:
        print("swiftlint is not installed; brew install swiftlint", file=sys.stderr)
        return 1

    recorded = baseline_size()
    occurring = len([line for line in run([]).stdout.splitlines() if line.strip()])

    if arguments.write_baseline:
        if occurring > recorded:
            print(
                f"refusing to widen the baseline from {recorded} to {occurring}; "
                "fix the code or turn the rule off with a reason",
                file=sys.stderr,
            )
            return 1
        run(["--write-baseline", str(BASELINE)])
        print(f"Wrote {occurring} baselined violation(s) to {BASELINE}")
        return 0

    arriving = [
        line
        for line in run(["--baseline", str(BASELINE)]).stdout.splitlines()
        if line.strip()
    ]
    if arriving:
        print("\n".join(arriving), file=sys.stderr)
        print(f"{len(arriving)} violation(s) outside the baseline", file=sys.stderr)
        return 1
    if occurring < recorded:
        print(
            f"baseline records {recorded} violation(s) but only {occurring} remain; "
            f"run {Path(__file__).name} --write-baseline to shrink it",
            file=sys.stderr,
        )
        return 1
    print(f"SwiftLint passed: {recorded} baselined violation(s), none new")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
