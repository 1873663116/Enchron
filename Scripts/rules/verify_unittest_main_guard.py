#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ast
from pathlib import Path
import sys


DEFAULT_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TEST_ROOTS = (Path("Scripts/rules/tests"),)
RULE = "unittest-main-guard-last"


def is_main_guard(statement: ast.stmt) -> bool:
    if not isinstance(statement, ast.If):
        return False
    test = statement.test
    return (
        isinstance(test, ast.Compare)
        and isinstance(test.left, ast.Name)
        and test.left.id == "__name__"
        and len(test.comparators) == 1
        and isinstance(test.comparators[0], ast.Constant)
        and test.comparators[0].value == "__main__"
    )


def statements_after_main_guard(source: str) -> list[ast.stmt]:
    module = ast.parse(source)
    for index, statement in enumerate(module.body):
        if is_main_guard(statement):
            return module.body[index + 1 :]
    return []


def test_files(repository_root: Path) -> list[Path]:
    files: list[Path] = []
    for relative_root in TEST_ROOTS:
        root = repository_root / relative_root
        if root.is_dir():
            files.extend(sorted(root.glob("test_*.py")))
    return files


def audit(repository_root: Path) -> list[str]:
    diagnostics: list[str] = []
    for path in test_files(repository_root):
        late = statements_after_main_guard(path.read_text(encoding="utf-8"))
        for statement in late:
            name = getattr(statement, "name", type(statement).__name__)
            diagnostics.append(
                f"{path.relative_to(repository_root)}:{statement.lineno}: error: [{RULE}] "
                f"{name} follows the __main__ guard, so unittest.main() never sees it"
            )
    return diagnostics


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Keep every test module's __main__ guard after its last test class."
    )
    parser.add_argument("--root", type=Path, default=DEFAULT_REPOSITORY_ROOT)
    arguments = parser.parse_args(argv)
    diagnostics = audit(arguments.root.resolve())
    for line in diagnostics:
        print(line, file=sys.stderr)
    if diagnostics:
        return 1
    print("unittest main guard check passed: every test module runs all of its classes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
