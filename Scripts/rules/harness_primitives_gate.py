#!/usr/bin/env python3
from __future__ import annotations
import ast
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN_TOKENS = ("subprocess", "timeout=", "time.sleep", "time.monotonic", "devicectl")
FORBIDDEN_TIME_NAMES = frozenset({"sleep", "monotonic"})
EXEMPT_BASENAMES = ("interactive_visionpro_ui.py", "enchron_target.py")
EXEMPT_PREFIX = "Scripts/verification/harness"


def allowlist_path() -> Path:
    return REPOSITORY_ROOT / "Config/harness_primitives_allowlist.json"


def load_allowlist() -> set[str]:
    path = allowlist_path()
    if not path.is_file():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(data, list), (
        f"{path} must hold a flat JSON list of repository-relative paths"
    )
    return {str(item) for item in data}


def scan_roots() -> tuple[Path, ...]:
    return (REPOSITORY_ROOT / "Scripts/verification", REPOSITORY_ROOT / "Scripts/regression")


def is_exempt(relative: str, allowlist: set[str]) -> bool:
    if relative in allowlist:
        return True
    if relative.startswith(EXEMPT_PREFIX):
        return True
    name = relative.rsplit("/", 1)[-1]
    if name in EXEMPT_BASENAMES:
        return True
    return False


def file_violations(path: Path, relative: str) -> list[str]:
    try:
        source = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return [f"{relative}: cannot read file"]
    found: list[str] = []
    for index, line in enumerate(source.splitlines(), start=1):
        for token in FORBIDDEN_TOKENS:
            if token in line:
                found.append(f"{relative}:{index}: contains forbidden token '{token}'")
    found.extend(structural_violations(source, relative))
    return found


def structural_violations(source: str, relative: str) -> list[str]:
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        return [f"{relative}:{error.lineno}: does not parse; the gate cannot inspect it"]
    found: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "subprocess" or alias.name.startswith("subprocess."):
                    found.append(f"{relative}:{node.lineno}: imports subprocess")
                if alias.name == "time" and alias.asname not in (None, "time"):
                    found.append(f"{relative}:{node.lineno}: imports time under the alias '{alias.asname}'")
        elif isinstance(node, ast.ImportFrom):
            if node.module == "subprocess" or (node.module or "").startswith("subprocess."):
                found.append(f"{relative}:{node.lineno}: imports from subprocess")
            if node.module == "time":
                for alias in node.names:
                    if alias.name in FORBIDDEN_TIME_NAMES or alias.name == "*":
                        found.append(f"{relative}:{node.lineno}: imports time.{alias.name} by name")
        elif isinstance(node, ast.Call):
            found.extend(call_violations(node, relative))
    return found


def call_violations(node: ast.Call, relative: str) -> list[str]:
    found: list[str] = []
    func = node.func
    if isinstance(func, ast.Name) and func.id == "getattr" and node.args:
        first = node.args[0]
        if isinstance(first, ast.Name) and first.id == "time":
            found.append(f"{relative}:{node.lineno}: reaches into the time module via getattr")
        elif len(node.args) > 1:
            second = node.args[1]
            if isinstance(second, ast.Constant) and second.value in FORBIDDEN_TIME_NAMES:
                found.append(f"{relative}:{node.lineno}: fetches the attribute '{second.value}' via getattr")
    for keyword in node.keywords:
        if keyword.arg == "timeout":
            found.append(f"{relative}:{node.lineno}: passes a timeout keyword argument")
        elif keyword.arg is None and isinstance(keyword.value, ast.Dict):
            for key in keyword.value.keys:
                if isinstance(key, ast.Constant) and key.value == "timeout":
                    found.append(f"{relative}:{node.lineno}: smuggles a timeout key through ** unpacking")
    return found


def failures() -> list[str]:
    allowlist = load_allowlist()
    violations: list[str] = []
    for root in scan_roots():
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.py")):
            relative = path.relative_to(REPOSITORY_ROOT).as_posix()
            if is_exempt(relative, allowlist):
                continue
            violations.extend(file_violations(path, relative))
    return sorted(violations)


def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} forbidden primitive violations")
        return 1
    allowlist = load_allowlist()
    count = 0
    for root in scan_roots():
        if root.is_dir():
            count += sum(1 for _ in root.rglob("*.py"))
    print(f"no forbidden primitives in {count} files; {len(allowlist)} allowlisted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
