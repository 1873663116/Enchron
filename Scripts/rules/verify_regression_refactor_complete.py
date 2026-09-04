#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import BinaryIO, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_ROOT = REPOSITORY_ROOT / "Scripts"
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from regression.completion import CompletionPaths, verify_completion
from regression.core.digest import canonical_bytes


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify every mechanical predicate in the autonomous refactor Definition of Done."
    )
    parser.add_argument("--json", action="store_true", required=True)
    parser.add_argument(
        "--test-repository-root",
        type=Path,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--test-final-root",
        type=Path,
        help=argparse.SUPPRESS,
    )
    return parser


def main(
    argv: Sequence[str] | None = None, *, stdout: BinaryIO | None = None
) -> int:
    arguments = _parser().parse_args(argv)
    overrides = (
        arguments.test_repository_root is not None,
        arguments.test_final_root is not None,
    )
    if overrides[0] != overrides[1]:
        _parser().error("test repository and final-root overrides must be supplied together")
    paths = (
        CompletionPaths.for_tests(
            arguments.test_repository_root,
            arguments.test_final_root,
        )
        if all(overrides)
        else CompletionPaths.for_repository(REPOSITORY_ROOT)
    )
    report = verify_completion(paths)
    output = stdout if stdout is not None else sys.stdout.buffer
    output.write(canonical_bytes(report.payload()) + b"\n")
    return 0 if report.done else 1


if __name__ == "__main__":
    raise SystemExit(main())
