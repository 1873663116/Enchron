#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN_TOKENS = ("subprocess", "timeout=", "time.sleep", "time.monotonic", "devicectl")
EXEMPT_BASENAMES = ("interactive_visionpro_ui.py", "enchron_target.py")
EXEMPT_PREFIX = "Scripts/verification/harness"


def allowlist_path() -> Path:
    return REPOSITORY_ROOT / "Config/harness_primitives_allowlist.json"


def load_allowlist() -> set[str]:
    path = allowlist_path()
    if not path.is_file():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set()
    if isinstance(data, list):
        return {str(item) for item in data if isinstance(item, str)}
    if isinstance(data, dict):
        for key in ("allowlist", "allowed", "files", "exempt", "allow"):
            value = data.get(key)
            if isinstance(value, list):
                return {str(item) for item in value if isinstance(item, str)}
        return set()
    return set()


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
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return [f"{relative}: cannot read file"]
    found: list[str] = []
    for index, line in enumerate(lines, start=1):
        for token in FORBIDDEN_TOKENS:
            if token in line:
                found.append(f"{relative}:{index}: contains forbidden token '{token}'")
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
