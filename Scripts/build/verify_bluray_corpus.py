#!/usr/bin/env python3
"""Build or invoke BluRayDiscProbe and verify the authored Blu-ray corpus."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "Packages/PlaybackCore"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from Scripts.verification.verify_bluray_corpus import (
    DEFAULT_CORPUS,
    GOLDEN,
    assert_equal,
    sha256,
    verify_catalog,
)


def run_probe(binary: Path, source: Path) -> dict:
    completed = subprocess.run(
        [str(binary), "--json", str(source)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode:
        raise RuntimeError(f"Probe failed for {source}: {completed.stderr[-1200:]}")
    return json.loads(completed.stdout)


def build_probe(scratch: Path) -> Path:
    command = [
        "swift", "build", "--package-path", str(PACKAGE),
        "--scratch-path", str(scratch), "--product", "BluRayDiscProbe",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode:
        raise RuntimeError(f"Probe build failed: {completed.stderr[-3000:]}")
    location = subprocess.run(
        [
            "swift", "build", "--package-path", str(PACKAGE),
            "--scratch-path", str(scratch), "--show-bin-path",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    binary = Path(location.stdout.strip()) / "BluRayDiscProbe"
    if not binary.is_file():
        raise RuntimeError(f"Probe binary is missing: {binary}")
    return binary


def verify(corpus: Path, binary: Path) -> dict:
    results = {}
    for label, golden in GOLDEN.items():
        release = corpus / label
        folder = release / golden["folder"]
        bdmv = folder / "BDMV"
        image = release / f"{golden['folder']}.iso"
        assert_equal(sha256(image), golden["iso_sha256"], f"{label} ISO SHA-256")
        iso = run_probe(binary, image)
        parent = run_probe(binary, folder)
        self_root = run_probe(binary, bdmv)
        assert_equal(parent, iso, f"{label} parent-root catalog")
        assert_equal(self_root, iso, f"{label} BDMV-self catalog")
        result = verify_catalog(iso, bdmv, golden, label)
        result["isoSHA256"] = golden["iso_sha256"]
        result["selectedMPLSSHA256"] = golden["mpls_sha256"]
        results[label] = result
    return {
        "schema": "enchron.bluray.corpus-verification/v1",
        "verdict": "passed",
        "corpora": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument(
        "--scratch",
        type=Path,
        default=PACKAGE / ".build/bluray-verifier",
    )
    parser.add_argument("--probe", type=Path, help="Existing probe binary; skip building")
    arguments = parser.parse_args()
    try:
        binary = arguments.probe or build_probe(arguments.scratch)
        report = verify(arguments.corpus, binary)
    except (AssertionError, OSError, ValueError, RuntimeError) as error:
        print(json.dumps({
            "schema": "enchron.bluray.corpus-verification/v1",
            "verdict": "failed",
            "error": str(error),
        }, sort_keys=True))
        return 1
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
