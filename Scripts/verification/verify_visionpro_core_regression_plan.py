#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TEST_PLAN = REPOSITORY_ROOT / "VisionProCoreRegression.xctestplan"
UI_TEST_ROOT = REPOSITORY_ROOT / "Tests" / "EnchronAppUI"


def declared_test_methods() -> set[str]:
    declarations: set[str] = set()
    class_pattern = re.compile(r"\b(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b")
    method_pattern = re.compile(r"\bfunc\s+(test\w+)\s*\(")

    for source in UI_TEST_ROOT.rglob("*.swift"):
        text = source.read_text(encoding="utf-8")
        class_matches = list(class_pattern.finditer(text))
        for index, class_match in enumerate(class_matches):
            body_end = (
                class_matches[index + 1].start()
                if index + 1 < len(class_matches)
                else len(text)
            )
            class_name = class_match.group(1)
            for method in method_pattern.finditer(text, class_match.end(), body_end):
                declarations.add(f"{class_name}/{method.group(1)}()")
    return declarations


def main() -> int:
    plan = json.loads(TEST_PLAN.read_text(encoding="utf-8"))
    selected = [
        test
        for target in plan.get("testTargets", [])
        for test in target.get("selectedTests", [])
    ]
    failures: list[str] = []

    duplicates = sorted({test for test in selected if selected.count(test) > 1})
    if duplicates:
        failures.append("duplicate selected tests: " + ", ".join(duplicates))

    declared = declared_test_methods()
    missing = sorted(set(selected) - declared)
    if missing:
        failures.append("selected tests without XCTest declarations: " + ", ".join(missing))

    if not selected:
        failures.append("the core regression plan selects no tests")

    if failures:
        print("VisionProCoreRegression plan verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(
        f"VisionProCoreRegression plan selects {len(selected)} unique declared XCTest methods"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
