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


_READS: dict[tuple[str, str | None, str | None], str] = {}
_ORIGINAL_READ_TEXT = Path.read_text


def cached_read_text(self, encoding=None, errors=None):
    key = (str(self), encoding, errors)
    hit = _READS.get(key)
    if hit is None:
        hit = _ORIGINAL_READ_TEXT(self, encoding=encoding, errors=errors)
        _READS[key] = hit
    return hit


def install_read_cache() -> None:
    Path.read_text = cached_read_text


def run_test_module(path: Path, log_path: Path) -> int:
    import unittest

    log_path.parent.mkdir(parents=True, exist_ok=True)
    buffer = io.StringIO()
    saved_argv = sys.argv
    code = 0
    try:
        sys.argv = [str(path)]
        module = load(path)
        suite = unittest.TestLoader().loadTestsFromModule(module)
        result = unittest.TextTestRunner(stream=buffer, verbosity=1).run(suite)
        code = 0 if result.wasSuccessful() else 1
    except SystemExit as exit_requested:
        code = int(exit_requested.code or 0)
    except BaseException:
        buffer.write(traceback.format_exc())
        code = 1
    finally:
        sys.argv = saved_argv
    log_path.write_text(buffer.getvalue(), encoding="utf-8")
    return code


def main() -> int:
    install_read_cache()
    log_root = Path(sys.argv[1])
    report = Path(sys.argv[2])
    outcomes = {}
    for name in sys.argv[3:]:
        path = Path(name)
        log = log_root / f"{path.stem}.log"
        runner = run_test_module if path.name.startswith("test_") else run_one
        outcomes[path.name] = runner(path, log)
    report.write_text(json.dumps(outcomes), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
