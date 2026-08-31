#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EXECUTION_IDENTITY = REPO / "Scripts/regression/execution_identity.py"
RUNCTL = REPO / "Scripts/regression/runctl.py"


def body(source: str, name: str) -> str:
    """The text of one top-level definition.

    A `re.S` pattern anchored on `def name` runs to the end of the file, so it
    keeps matching after the guard inside that function is deleted: removing
    `payload["bootstrap"] = True` left every such check green while the
    behaviour probe went red.
    """
    start = source.find(f"def {name}(")
    if start < 0:
        return ""
    rest = source.find("\ndef ", start + 1)
    return source[start:] if rest < 0 else source[start:rest]


def fail(message: str) -> int:
    print(f"FAIL {message}")
    return 1

def main() -> int:
    try:
        identity_source = EXECUTION_IDENTITY.read_text(encoding="utf-8")
        runctl_source = RUNCTL.read_text(encoding="utf-8")
    except OSError as error:
        return fail(str(error))

    if "bootstrap: bool" not in identity_source and "bootstrap:bool" not in identity_source:
        return fail("FrozenExecutionInput lacks bootstrap boolean field")

    if "_bootstrap_configuration_digest" not in identity_source:
        return fail("execution_identity lacks bootstrap digest helper")

    if "bootstrap" not in body(identity_source, "freeze_execution_input"):
        return fail("freeze_execution_input does not expose bootstrap parameter")

    if "bootstrap" not in body(identity_source, "execution_input_payload"):
        return fail("execution_input_payload does not carry bootstrap marker inside the payload")

    if "bootstrap" not in body(identity_source, "load_execution_input"):
        return fail("load_execution_input does not distinguish bootstrap")

    if '"bootstrap"' not in identity_source and "'bootstrap'" not in identity_source:
        return fail("execution input JSON never contains bootstrap key, distinction only in path")

    if "--bootstrap" not in runctl_source:
        return fail("runctl freeze lacks --bootstrap option")

    if not re.search(r"freeze_execution_input\(.*bootstrap", runctl_source, re.S):
        return fail("runctl freeze does not forward bootstrap to execution_identity")

    marker_inside = re.search(
        r'"bootstrap"\s*:\s*True|payload\[.bootstrap.\]',
        body(identity_source, "execution_input_payload"),
    )
    if marker_inside is None:
        return fail("bootstrap marker is not written inside the execution input file")

    print("bootstrap freeze marker travels inside the payload and loader distinguishes it")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
