#!/usr/bin/env python3

"""Run several checkers in one interpreter.

Each checker is a script with a `main`, and starting an interpreter for every
one of them costs more than the check itself. This runner imports each in turn,
points its output at its own log, and reports one exit code per checker.

A checker that raises is reported as a failure of that checker alone; the
remaining checkers in the batch still run.
"""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import traceback
from pathlib import Path


def load(path: Path):
    name = "batch_" + path.stem
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def run_one(path: Path, log_path: Path) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    saved_argv = sys.argv
    saved_stdout = sys.stdout
    saved_stderr = sys.stderr
    buffer = io.StringIO()
    code = 0
    try:
        sys.argv = [str(path)]
        sys.stdout = buffer
        sys.stderr = buffer
        module = load(path)
        entry = getattr(module, "main", None)
        if entry is None:
            code = 1
            buffer.write("no main()\n")
        else:
            try:
                result = entry()
                code = 0 if result in (None, 0) else int(result)
            except SystemExit as exit_requested:
                code = int(exit_requested.code or 0)
            except BaseException:
                buffer.write(traceback.format_exc())
                code = 1
    except BaseException:
        buffer.write(traceback.format_exc())
        code = 1
    finally:
        sys.argv = saved_argv
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr
    log_path.write_text(buffer.getvalue(), encoding="utf-8")
    return code


def main() -> int:
    log_root = Path(sys.argv[1])
    report = Path(sys.argv[2])
    outcomes = {}
    for name in sys.argv[3:]:
        path = Path(name)
        log = log_root / f"{path.stem}.log"
        outcomes[path.name] = run_one(path, log)
    report.write_text(json.dumps(outcomes), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
