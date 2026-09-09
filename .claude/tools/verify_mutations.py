#!/usr/bin/env python3

"""Invert each guard and record which probe turns red.

A probe that has never seen its guard fail is not evidence that the guard
works. This repository has shipped two false greens: a regex with re.S that
matched from a `def` to the end of the file and so hit a same-named string
further down, and a hook probe that handed the gate a content block where a
transcript record belonged, leaving three of its four cases testing nothing.
Both printed PASS.

So every rule carries a mutation that disables exactly it, and this runs them:
the unmutated copy must be green first, the mutated copy must fail, and it must
fail on the named cases. A mutation that reddens some other case, or reddens
nothing, is reported as a failure of the manifest rather than a pass.

    python3 .claude/tools/verify_mutations.py            run every mutation
    python3 .claude/tools/verify_mutations.py --id gate-detach
    python3 .claude/tools/verify_mutations.py --baseline-only
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

CLAUDE = Path(__file__).resolve().parents[1]
MANIFEST = CLAUDE / "mutations.json"
FAILED_CASE = re.compile(r"^FAIL ([\w-]+)", re.M)


def probe(copy: Path, relative: str) -> tuple[int, set[str], str]:
    environment = dict(os.environ, ENCHRON_CLAUDE_DIR=str(copy))
    done = subprocess.run(
        [sys.executable, str(copy / relative)],
        capture_output=True, text=True, env=environment, cwd=str(copy.parent),
    )
    output = done.stdout + done.stderr
    return done.returncode, set(FAILED_CASE.findall(output)), output


def copy_tree(destination: Path) -> Path:
    shutil.copytree(
        CLAUDE, destination,
        ignore=shutil.ignore_patterns("state", "worktrees", "__pycache__", "*.pyc"),
    )
    (destination / "state").mkdir(exist_ok=True)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--id")
    parser.add_argument("--baseline-only", action="store_true")
    arguments = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    probes = manifest["probes"]
    mutations = [
        mutation for mutation in manifest["mutations"]
        if arguments.id is None or mutation["id"] == arguments.id
    ]

    failures: list[str] = []
    with tempfile.TemporaryDirectory() as directory:
        pristine = copy_tree(Path(directory) / "baseline/.claude")
        for name, relative in sorted(probes.items()):
            code, red, output = probe(pristine, relative)
            if code != 0 or red:
                failures.append(f"baseline {name} is not green: {sorted(red)}")
                print(output)
            else:
                print(f"BASELINE {name}: green")
    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 1
    if arguments.baseline_only:
        return 0

    for mutation in mutations:
        identifier = mutation["id"]
        expected = set(mutation["expect"])
        with tempfile.TemporaryDirectory() as directory:
            copy = copy_tree(Path(directory) / "mutant/.claude")
            target = copy / mutation["file"]
            source = target.read_text(encoding="utf-8")
            occurrences = source.count(mutation["find"])
            if occurrences != 1:
                failures.append(
                    f"{identifier}: anchor occurs {occurrences} times in {mutation['file']}"
                )
                print(f"FAIL {identifier}: anchor occurs {occurrences} times")
                continue
            target.write_text(
                source.replace(mutation["find"], mutation["replaceWith"]), encoding="utf-8"
            )
            code, red, output = probe(copy, probes[mutation["probe"]])
            if code == 0:
                failures.append(f"{identifier}: the probe stayed green")
                print(f"FAIL {identifier}: {probes[mutation['probe']]} stayed green")
                continue
            if not expected <= red:
                failures.append(f"{identifier}: expected {sorted(expected - red)} to turn red")
                print(f"FAIL {identifier}: turned red on {sorted(red)}, expected {sorted(expected)}")
                continue
            print(f"PASS {identifier}: {probes[mutation['probe']]} red on {sorted(red)}")

    print(f"mutations: {len(mutations) - len(failures)} of {len(mutations)} proven")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
