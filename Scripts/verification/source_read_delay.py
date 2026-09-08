#!/usr/bin/env python3
"""Add a fixed delay to every loopback byte-stream read on the app under test.

The delay stands in for a slow remote backend: every read the loopback server
forwards to a WebDAV, SMB or Emby source waits the given number of
milliseconds first. Omitting --ms clears the delay.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPTS_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

import playback_mode_matrix as matrix
from harness import InstrumentFault

VERB = "setSourceReadDelay"


def arguments_for(milliseconds: int | None) -> list[str]:
    return [] if milliseconds is None else ["ms=" + str(milliseconds)]


def apply(*, milliseconds: int | None, evidence_directory: Path) -> dict[str, object]:
    instruments = matrix._get_instruments()
    client = matrix._controller_client(instruments, evidence_directory)
    response = matrix.app_command_harness(instruments, client, VERB, *arguments_for(milliseconds))
    return {"passed": bool(response.get("ok")), "milliseconds": milliseconds, "response": response}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ms", type=int, default=None, help="delay per read; omit to clear")
    parser.add_argument("--evidence-dir", type=Path, default=None)
    arguments = parser.parse_args()
    evidence_directory = (arguments.evidence_dir or matrix.default_evidence_directory() / "source-read-delay").expanduser().resolve()
    evidence_directory.mkdir(parents=True, exist_ok=True)
    try:
        result = apply(milliseconds=arguments.ms, evidence_directory=evidence_directory)
    except InstrumentFault as fault:
        result = {"passed": False, "stage": "instrument", "kind": fault.kind, "evidence": fault.evidence}
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
