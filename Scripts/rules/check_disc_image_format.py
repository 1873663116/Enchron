#!/usr/bin/env python3
"""Check real Blu-ray ISO and directory catalogs against independent MPLS bytes."""

from pathlib import Path
import subprocess
import sys


if __name__ == "__main__":
    repository = Path(__file__).resolve().parents[2]
    raise SystemExit(subprocess.call([
        sys.executable,
        str(repository / "Scripts/verification/verify_bluray_corpus.py"),
        *sys.argv[1:],
    ]))
