#!/usr/bin/env python3

"""Every script under Scripts/ must be reachable, and its name must not lie.

A checker that nothing invokes reports nothing, and the list that decides what
runs cannot notice its own omissions. This walks the directory instead: it
classifies each file from its syntax tree, then holds the file name and the
verification's table to that classification. Unclassified is an error, so a new
file cannot arrive unnoticed.
"""

from __future__ import annotations

import argparse
import ast
from dataclasses import dataclass
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_ROOT = REPOSITORY_ROOT / "Scripts"
VERIFICATION = REPOSITORY_ROOT / "Scripts/rules/run_verification.py"
TEST_PREFIX = "test_"
RULE_PREFIXES = ("verify_", "check_")


@dataclass(frozen=True)
class Script:
    path: Path
    kind: str
    reason: str

    @property
    def relative(self) -> str:
        return str(self.path.relative_to(REPOSITORY_ROOT))


def defines_test_cases(tree: ast.Module) -> bool:
    classes = {
        node.name: node
        for node in tree.body
        if isinstance(node, ast.ClassDef)
    }
    test_cases = {
        name
        for name, node in classes.items()
        if "TestCase"
        in {getattr(base, "attr", getattr(base, "id", "")) for base in node.bases}
    }
    while True:
        derived = {
            name
            for name, node in classes.items()
            if any(
                getattr(base, "attr", getattr(base, "id", "")) in test_cases
                for base in node.bases
            )
        }
        expanded = test_cases | derived
        if expanded == test_cases:
            break
        test_cases = expanded
    for name in test_cases:
        node = classes[name]
        if any(
            isinstance(member, (ast.FunctionDef, ast.AsyncFunctionDef))
            and member.name.startswith(TEST_PREFIX)
            for member in node.body
        ):
            return True
    return False


def requires_arguments(tree: ast.Module) -> bool:
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if getattr(node.func, "attr", None) != "add_argument":
            continue
        positional = [
            argument
            for argument in node.args
            if isinstance(argument, ast.Constant)
            and isinstance(argument.value, str)
            and not argument.value.startswith("-")
        ]
        if positional:
            return True
        for keyword in node.keywords:
            if keyword.arg != "required":
                continue
            if isinstance(keyword.value, ast.Constant) and keyword.value.value is True:
                return True
    return False


def is_executable(tree: ast.Module) -> bool:
    for node in tree.body:
        if not isinstance(node, ast.If):
            continue
        test = node.test
        if not isinstance(test, ast.Compare) or not isinstance(test.left, ast.Name):
            continue
        if test.left.id != "__name__":
            continue
        if any(
            isinstance(value, ast.Constant) and value.value == "__main__"
            for value in test.comparators
        ):
            return True
    return False


def classify_non_python(path: Path) -> Script:
    if not path.name.startswith(RULE_PREFIXES):
        return Script(path, "tool", "runnable entry point")
    source = path.read_text(encoding="utf-8", errors="replace")
    if "exit 64" in source:
        return Script(path, "parameterised", "checker that takes an input")
    return Script(path, "rule", "checker that runs over the whole repository")


def classify(path: Path) -> Script:
    if path.suffix != ".py":
        return classify_non_python(path)
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError as error:
        return Script(path, "unparseable", f"{error.msg} at line {error.lineno}")
    if defines_test_cases(tree):
        return Script(path, "test", "defines unittest.TestCase methods")
    if path.name.startswith(RULE_PREFIXES):
        if requires_arguments(tree):
            return Script(path, "parameterised", "checker that takes an input")
        return Script(path, "rule", "checker that runs over the whole repository")
    if is_executable(tree):
        return Script(path, "tool", "runnable entry point")
    return Script(path, "library", "imported, no entry point")


def registered_filenames() -> set[str]:
    source = VERIFICATION.read_text(encoding="utf-8")
    if "STRUCTURE_CHECKS = (" not in source:
        raise ValueError(f"no STRUCTURE_CHECKS table in {VERIFICATION}")
    return set(re.findall(r"([A-Za-z0-9_]+\.(?:py|swift|sh|zsh))", source))


def cited(path: Path) -> bool:
    for candidate in REPOSITORY_ROOT.rglob("*"):
        if candidate == path or not candidate.is_file():
            continue
        if candidate.suffix not in (".py", ".sh", ".zsh", ".md", ".yml", ".json"):
            continue
        parts = candidate.relative_to(REPOSITORY_ROOT).parts
        if any(part.startswith(".") for part in parts):
            if ".agents" not in parts and ".github" not in parts:
                continue
        try:
            if path.name in candidate.read_text(encoding="utf-8", errors="replace"):
                return True
        except OSError:
            continue
    return False


def discover() -> list[Script]:
    paths = [
        path
        for suffix in (".py", ".swift", ".sh", ".zsh")
        for path in SCRIPTS_ROOT.rglob(f"*{suffix}")
    ]
    return [classify(path) for path in sorted(paths)]


def violations(scripts: list[Script], registered: set[str]) -> list[str]:
    found: list[str] = []
    for script in scripts:
        named_test = script.path.name.startswith(TEST_PREFIX)
        if script.kind == "unparseable":
            found.append(f"{script.relative}: does not parse: {script.reason}")
        elif script.kind == "test" and not named_test:
            found.append(
                f"{script.relative}: defines test cases but is not named "
                f"{TEST_PREFIX}*.py, so discovery skips it"
            )
        elif script.kind != "test" and named_test:
            found.append(
                f"{script.relative}: is named {TEST_PREFIX}*.py but defines no "
                "unittest.TestCase methods"
            )
        elif script.kind == "rule" and script.path.name not in registered:
            found.append(
                f"{script.relative}: is a checker that no verification layer runs; "
                "register it in STRUCTURE_CHECKS or delete it"
            )
        elif script.kind == "parameterised" and not cited(script.path):
            found.append(
                f"{script.relative}: takes an input so no layer can run it, and "
                "nothing in the repository names it; cite it or delete it"
            )
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--list",
        action="store_true",
        help="print the classification of every script instead of only failures",
    )
    arguments = parser.parse_args()

    scripts = discover()
    registered = registered_filenames()

    if arguments.list:
        for script in sorted(scripts, key=lambda item: (item.kind, item.relative)):
            print(f"{script.kind:12} {script.relative:64} {script.reason}")
        print()

    found = violations(scripts, registered)
    counts: dict[str, int] = {}
    for script in scripts:
        counts[script.kind] = counts.get(script.kind, 0) + 1
    summary = ", ".join(f"{count} {kind}" for kind, count in sorted(counts.items()))
    if found:
        for line in found:
            print(f"error: {line}", file=sys.stderr)
        print(
            f"{len(scripts)} scripts ({summary}); {len(found)} unreachable or misnamed",
            file=sys.stderr,
        )
        return 1
    print(f"{len(scripts)} scripts ({summary}); every one reachable and correctly named")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
